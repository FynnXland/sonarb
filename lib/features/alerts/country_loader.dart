import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../osm/country_cameras.dart';

/// Zustand des Länderlaufs für die Anzeige.
enum CountryState { off, idle, loading, ok, error }

/// Holt einmalig alle festen Messstellen Deutschlands in den Kachel-Cache und frischt sie danach
/// wöchentlich auf. Gemessen: eine Anfrage, rund 1,2 MB übertragen (6,5 MB Text), 80 s Wartezeit
/// beim öffentlichen Server; deshalb weder WLAN-Pflicht noch Blöcke nötig.
///
/// [poke] ist billig und wird regelmäßig gerufen (jede Positionsabfrage): ein Lauf startet nur,
/// wenn das Land eingeschaltet ist, kein Lauf läuft, der Stand älter als [interval] ist, [canRun]
/// zustimmt (die Fahrt hat nichts Dringendes) und die Pause nach einem Fehlschlag um ist.
class CountryLoader {
  CountryLoader({
    required this.source,
    required this.prefs,
    required this.clock,
    required this.onChanged,
    this.canRun,
    this.interval = const Duration(days: 7),
    this.retryAfter = const [
      Duration(minutes: 30),
      Duration(hours: 2),
      Duration(hours: 12),
    ],
    this._enabled = true,
  }) {
    final ms = prefs.getInt(_atKey);
    _at = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    _points = prefs.getInt(_pointsKey) ?? 0;
  }

  static const String _atKey = 'country.cameras.at';
  static const String _pointsKey = 'country.cameras.points';

  /// Null, wenn die Quelle das nicht kann (andere `FixedPointSource`).
  final CountryCameraSource? source;
  final SharedPreferences prefs;
  final DateTime Function() clock;

  /// Zustand oder Fortschritt hat sich geändert (Statuszeile).
  final void Function() onChanged;

  /// Zusätzliche Bedingung, z. B. „Umgebung ist fertig geladen“.
  final bool Function()? canRun;
  final Duration interval;

  /// Pausen nach dem 1., 2., 3. … aufeinanderfolgenden Fehlschlag (das letzte Maß bleibt).
  final List<Duration> retryAfter;

  bool _enabled;
  bool _running = false;
  bool _disposed = false;
  DateTime? _at;
  int _points = 0;
  int _failures = 0;
  DateTime? _retryAt;
  String? _error;

  bool get enabled => _enabled;

  /// Stand der letzten vollständigen Aktualisierung.
  DateTime? get updatedAt => _at;
  int get pointCount => _points;
  String? get message => _error;

  CountryState get state {
    if (!_enabled || source == null) return CountryState.off;
    if (_running) return CountryState.loading;
    if (_error != null && _at == null) return CountryState.error;
    return _at == null ? CountryState.idle : CountryState.ok;
  }

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    onChanged();
    if (value) poke();
  }

  bool get _due {
    final at = _at;
    return at == null || clock().difference(at) >= interval;
  }

  /// Startet einen Lauf, falls fällig. Gibt ihn zurück (zum Abwarten in Tests), sonst null.
  Future<void>? poke() {
    if (_disposed || !_enabled || _running || source == null) return null;
    if (!_due) return null;
    final retry = _retryAt;
    if (retry != null && clock().isBefore(retry)) return null;
    if (canRun != null && !canRun!()) return null;
    return _run();
  }

  Future<void> _run() async {
    _running = true;
    onChanged();
    CountryLoadResult r;
    try {
      r = await source!.loadCountryCameras();
    } catch (_) {
      r = const CountryLoadResult(error: 'Abruf gescheitert');
    }
    _running = false;
    if (_disposed) return;
    if (r.ok) {
      _at = r.fetchedAt ?? clock();
      _points = r.points;
      _failures = 0;
      _retryAt = null;
      _error = null;
      unawaited(prefs.setInt(_atKey, _at!.millisecondsSinceEpoch));
      unawaited(prefs.setInt(_pointsKey, _points));
    } else {
      _failures++;
      _retryAt = clock().add(
        retryAfter[(_failures - 1).clamp(0, retryAfter.length - 1)],
      );
      _error = r.error;
    }
    onChanged();
  }

  void dispose() => _disposed = true;
}
