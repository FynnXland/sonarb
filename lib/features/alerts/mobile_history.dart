import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';

/// So lange bleibt eine gesehene Stelle gespeichert. Danach zählt sie in der Wärme ohnehin nur noch
/// ein Viertel (Halbwertszeit ein Jahr).
const Duration mobileHistoryKeep = Duration(days: 730);

/// Obergrenze für die Zahl der Einträge. Bei Überschuss gehen die ältesten zuerst.
const int mobileHistoryMax = 20000;

/// Dieselbe Stelle am selben Tag zählt einmal, auch aus verschiedenen Quellen.
const double mobileHistoryDedupeMeters = 50;

/// Quelle der Punkte, die der Verlauf liefert.
const String mobileHistorySource = 'own_history';

/// Arten, die der Verlauf aufnimmt. Gespeichert wird der Platz in dieser Liste: neue Arten nur anhängen.
const _recorded = [
  AlertCategory.mobileSpeed,
  AlertCategory.mobileRedLight,
  AlertCategory.mobileDistance,
  AlertCategory.semiStationary,
];

/// Nimmt der Verlauf diesen Punkt auf? Mobile und halbfeste Blitzer, die ein Plugin gerade meldet.
/// Nicht: vergangene Beobachtungen (kommen schon als Verlauf), eigene Meldungen, Gefahren, Baustellen.
bool isRecordedMobile(AlertPoint p) =>
    !p.historical &&
    p.kind != AlertKind.hotspot &&
    _recorded.contains(p.effectiveCategory);

int _floorDiv(int a, int b) => (a / b).floor();

int _epochDay(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 86400000;

DateTime _noonOf(int epochDay) {
  final d = DateTime.utc(1970).add(Duration(days: epochDay));
  return DateTime(d.year, d.month, d.day, 12);
}

/// Ein Blitzer an einer Stelle an einem Tag. Position auf 1 m gerundet (0,00001°).
class MobileSighting {
  MobileSighting({
    required this.latE5,
    required this.lonE5,
    required this.category,
    required this.bearing,
    required this.day,
  });

  final int latE5, lonE5;

  /// Platz der Art in [_recorded].
  final int category;

  /// Fahrtrichtung in Grad, -1 wenn unbekannt.
  final int bearing;

  /// Tag der Beobachtung als Tage seit 1.1.1970 (Ortszeit).
  final int day;

  GeoPoint get position => GeoPoint(latE5 / 1e5, lonE5 / 1e5);

  /// Der Eintrag als vergangene Beobachtung für Wärme und Hotspots.
  late final AlertPoint point = AlertPoint(
    id: 'own:mobile:$latE5:$lonE5:$day',
    kind: AlertKind.live,
    position: position,
    source: mobileHistorySource,
    category: _recorded[category],
    travelBearings: bearing < 0 ? const [] : [bearing.toDouble()],
    label: 'Eigener Verlauf',
    observedAt: _noonOf(day),
    historical: true,
  );

  List<int> toJson() => [latE5, lonE5, category, bearing, day];

  static MobileSighting? fromJson(Object? raw) {
    if (raw is! List || raw.length != 5 || raw.any((e) => e is! int)) {
      return null;
    }
    final [lat, lon, cat, bearing, day] = raw.cast<int>();
    if (lat.abs() > 9000000 ||
        lon.abs() > 18000000 ||
        cat < 0 ||
        cat >= _recorded.length ||
        bearing < -1 ||
        bearing > 359) {
      return null;
    }
    return MobileSighting(
      latE5: lat,
      lonE5: lon,
      category: cat,
      bearing: bearing,
      day: day,
    );
  }
}

/// Ablage des Verlaufs, nur auf dem Gerät.
abstract interface class MobileHistoryStore {
  Future<List<MobileSighting>> load();

  /// Ersetzt den ganzen Bestand.
  Future<void> save(List<MobileSighting> items);
}

/// JSON-Datei `mobile_history.json` im Ordner [directory]. Atomar geschrieben (erst `.tmp`, dann
/// umbenannt). Eine unlesbare Datei wird als `.bad` beiseitegelegt, nicht überschrieben.
class FileMobileHistoryStore implements MobileHistoryStore {
  FileMobileHistoryStore(this.directory);

  final Directory directory;

  static const _version = 1;

  File get file =>
      File('${directory.path}${Platform.pathSeparator}mobile_history.json');

  @override
  Future<List<MobileSighting>> load() async {
    final f = file;
    if (!await f.exists()) return const [];
    try {
      final raw = jsonDecode(await f.readAsString());
      final list = raw is Map ? raw['items'] : null;
      if (list is! List) throw const FormatException('items fehlt');
      return [for (final e in list) ?MobileSighting.fromJson(e)];
    } on FormatException {
      try {
        await f.rename('${f.path}.bad');
      } on FileSystemException {
        // Dann bleibt sie liegen und wird beim nächsten Speichern überschrieben.
      }
      return const [];
    }
  }

  @override
  Future<void> save(List<MobileSighting> items) async {
    await directory.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': _version,
        'items': [for (final s in items) s.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}

/// Für Tests.
class MemoryMobileHistoryStore implements MobileHistoryStore {
  MemoryMobileHistoryStore([List<MobileSighting> items = const []])
    : items = List.of(items);

  List<MobileSighting> items;
  int saves = 0;

  @override
  Future<List<MobileSighting>> load() async => List.of(items);

  @override
  Future<void> save(List<MobileSighting> items) async {
    saves++;
    this.items = List.of(items);
  }
}

/// Eigener, dauerhafter Verlauf mobiler Blitzer: jeder mobile oder halbfeste Blitzer, den irgendein
/// Plugin meldet, wird mit Ort, Art, Richtung und Tag gespeichert, unabhängig davon, ob das Plugin
/// selbst Verlauf führt. Daraus entstehen vergangene Beobachtungen für die Wärme-Ebene und die
/// Hotspots, über Wochen und App-Neustarts hinweg. Nichts verlässt das Gerät.
///
/// Dieselbe Stelle (höchstens [mobileHistoryDedupeMeters]) am selben Tag zählt einmal. Es bleiben
/// höchstens [mobileHistoryKeep] und [mobileHistoryMax] Einträge.
class MobileHistory {
  MobileHistory(
    this._store, {
    DateTime Function()? clock,
    this.saveDelay = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now;

  final MobileHistoryStore _store;
  final DateTime Function() _clock;

  /// Wartezeit bis zum Schreiben nach der letzten Änderung (bündelt viele Meldungen einer Fahrt).
  final Duration saveDelay;

  final List<MobileSighting> _items = [];

  /// Raster zum Finden von Nachbarn: 0,001° Breite (111 m) × 0,0015° Länge (rund 100 m).
  final Map<(int, int), List<MobileSighting>> _grid = {};
  bool _loaded = false;
  bool _dirty = false;
  bool _disposed = false;
  Timer? _timer;
  Future<void> _writes = Future.value();

  /// Zahl der gespeicherten Einträge.
  int get length => _items.length;

  /// Alle Einträge, ältester zuerst nicht garantiert.
  List<MobileSighting> get items => List.unmodifiable(_items);

  /// Hat [load] den gespeicherten Bestand schon übernommen?
  bool get loaded => _loaded;

  (int, int) _cell(int latE5, int lonE5) =>
      (_floorDiv(latE5, 100), _floorDiv(lonE5, 150));

  /// Liest die Datei und fügt Einträge hinzu, die inzwischen schon gemeldet wurden. Ein
  /// unlesbarer Speicher bleibt ohne Folgen: der Verlauf beginnt dann leer.
  Future<void> load() async {
    if (_loaded || _disposed) return;
    List<MobileSighting> stored;
    try {
      stored = await _store.load();
    } catch (_) {
      stored = const [];
    }
    if (_disposed) return;
    final fresh = List.of(_items);
    _items.clear();
    _grid.clear();
    for (final s in [...stored, ...fresh]) {
      _add(s);
    }
    _loaded = true;
    final pruned = _prune();
    if (pruned || fresh.isNotEmpty) _schedule();
  }

  bool _hasNear(MobileSighting s) {
    final (cy, cx) = _cell(s.latE5, s.lonE5);
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        for (final o in _grid[(cy + dy, cx + dx)] ?? const <MobileSighting>[]) {
          if (o.day == s.day &&
              distanceMeters(o.position, s.position) <=
                  mobileHistoryDedupeMeters) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _add(MobileSighting s) {
    if (_hasNear(s)) return false;
    _items.add(s);
    (_grid[_cell(s.latE5, s.lonE5)] ??= []).add(s);
    return true;
  }

  /// Übernimmt die Punkte, die ein Plugin eben geliefert hat; was nicht in den Verlauf gehört, wird
  /// übergangen. True, wenn etwas Neues dazukam.
  bool record(Iterable<AlertPoint> points) {
    if (_disposed) return false;
    final now = _clock();
    final today = _epochDay(now);
    final oldest = _epochDay(now.subtract(mobileHistoryKeep));
    var added = false;
    for (final p in points) {
      if (!isRecordedMobile(p)) continue;
      final day = p.observedAt == null ? today : _epochDay(p.observedAt!);
      if (day < oldest || day > today + 1) continue;
      final bearing = p.travelBearings.isEmpty
          ? -1
          : ((p.travelBearings.first % 360).round() % 360);
      added |= _add(
        MobileSighting(
          latE5: (p.position.lat * 1e5).round(),
          lonE5: (p.position.lon * 1e5).round(),
          category: _recorded.indexOf(p.effectiveCategory),
          bearing: bearing,
          day: day,
        ),
      );
    }
    if (!added) return false;
    _prune();
    _schedule();
    return true;
  }

  /// Einträge in [radiusMeters] um [center] als vergangene Beobachtungen.
  List<AlertPoint> around(GeoPoint center, double radiusMeters) {
    if (_items.isEmpty) return const [];
    final dLat = radiusMeters / 111195;
    final dLon = dLat / math.max(0.2, math.cos(center.lat * math.pi / 180));
    final minLat = ((center.lat - dLat) * 1e5).floor();
    final maxLat = ((center.lat + dLat) * 1e5).ceil();
    final minLon = ((center.lon - dLon) * 1e5).floor();
    final maxLon = ((center.lon + dLon) * 1e5).ceil();
    final out = <AlertPoint>[];
    for (var cy = _floorDiv(minLat, 100); cy <= _floorDiv(maxLat, 100); cy++) {
      for (
        var cx = _floorDiv(minLon, 150);
        cx <= _floorDiv(maxLon, 150);
        cx++
      ) {
        for (final s in _grid[(cy, cx)] ?? const <MobileSighting>[]) {
          if (s.latE5 < minLat ||
              s.latE5 > maxLat ||
              s.lonE5 < minLon ||
              s.lonE5 > maxLon) {
            continue;
          }
          if (distanceMeters(center, s.position) <= radiusMeters) {
            out.add(s.point);
          }
        }
      }
    }
    return out;
  }

  /// Entfernt zu alte Einträge und, über der Obergrenze, die ältesten. True, wenn etwas wegfiel.
  bool _prune() {
    final oldest = _epochDay(_clock().subtract(mobileHistoryKeep));
    var drop = _items.where((s) => s.day < oldest).toSet();
    final rest = _items.length - drop.length;
    if (rest > mobileHistoryMax) {
      // Auf 95 % kürzen, damit nicht jede neue Meldung wieder kürzt.
      final keep = (mobileHistoryMax * 0.95).floor();
      final byAge = _items.where((s) => !drop.contains(s)).toList()
        ..sort((a, b) => a.day.compareTo(b.day));
      drop = {...drop, ...byAge.take(rest - keep)};
    }
    if (drop.isEmpty) return false;
    _items.removeWhere(drop.contains);
    for (final s in drop) {
      _grid[_cell(s.latE5, s.lonE5)]?.remove(s);
    }
    return true;
  }

  void _schedule() {
    _dirty = true;
    if (!_loaded || _timer != null) return;
    _timer = Timer(saveDelay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// Schreibt den Bestand sofort, wenn er sich geändert hat (und der gespeicherte Stand schon
  /// gelesen wurde, sonst würde er überschrieben).
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (!_dirty || !_loaded) return _writes;
    _dirty = false;
    final snapshot = List.of(_items);
    return _writes = _writes.then((_) async {
      try {
        await _store.save(snapshot);
      } catch (_) {
        _dirty = true;
      }
    });
  }

  /// Schreibt noch offene Änderungen und stellt den Betrieb ein.
  Future<void> dispose() async {
    if (_disposed) return;
    await flush();
    _disposed = true;
    _timer?.cancel();
  }
}

/// Findet unter vergangenen Beobachtungen (etwa dem Verlauf eines Plugins) solche, die der eigene
/// Verlauf schon hat: dieselbe Stelle (höchstens [mobileHistoryDedupeMeters]) am selben Tag.
/// Sonst zählte dieselbe Sichtung in der Wärme doppelt.
class ObservationIndex {
  ObservationIndex(Iterable<AlertPoint> points) {
    for (final p in points) {
      final at = p.observedAt;
      if (at == null) continue;
      (_cells[_key(_epochDay(at), p.position, 0, 0)] ??= []).add(p.position);
    }
  }

  final Map<(int, int, int), List<GeoPoint>> _cells = {};

  (int, int, int) _key(int day, GeoPoint p, int dy, int dx) =>
      (day, (p.lat * 1000).floor() + dy, (p.lon * 1000 / 1.5).floor() + dx);

  bool get isEmpty => _cells.isEmpty;

  /// Steht eine Beobachtung desselben Tages im Umkreis von [mobileHistoryDedupeMeters] um [p]?
  bool covers(AlertPoint p) {
    final at = p.observedAt;
    if (at == null) return false;
    final day = _epochDay(at);
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        for (final q in _cells[_key(day, p.position, dy, dx)] ?? const []) {
          if (distanceMeters(q, p.position) <= mobileHistoryDedupeMeters) {
            return true;
          }
        }
      }
    }
    return false;
  }
}
