import '../../core/contracts/data_source_plugin.dart';
import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';

/// Laufzeitzustand eines Plugins im Repository.
class PluginSlot {
  PluginSlot(this.plugin, {required this.enabled});

  final DataSourcePlugin plugin;
  bool enabled;
  bool initialized = false;
  bool loading = false;

  /// Wird beim Ausschalten erhöht; laufende Abrufe verwerfen ihr Ergebnis dann.
  int generation = 0;

  /// Gültige bekannte Punkte, auch aus früheren Gegenden (siehe [absorb]).
  List<AlertPoint> points = const [];

  /// Punkt und Zeitpunkt, zu dem ihn das Plugin zuletzt geliefert hat.
  final Map<String, (AlertPoint, DateTime)> _known = {};
  DateTime? lastSuccessAt;

  /// Mittelpunkt des letzten erfolgreichen Abrufs.
  GeoPoint? successCenter;
  DateTime? lastFetchAt;
  GeoPoint? lastCenter;
  bool failed = false;
  String? message;

  PluginStatus get status {
    if (!enabled) return PluginStatus.disabled;
    if (loading) return PluginStatus.loading;
    if (failed) return PluginStatus.error;
    return lastSuccessAt != null ? PluginStatus.ok : PluginStatus.idle;
  }

  /// Obergrenze für gemerkte aktuelle Punkte je Plugin.
  static const int maxKnown = 5000;

  /// Obergrenze für vergangene Beobachtungen je Plugin. Plugins können Jahre an Historie liefern;
  /// bei Überschuss gehen die ältesten zuerst.
  static const int maxHistorical = 15000;

  /// Vergangene Beobachtungen ändern sich nicht schnell und bleiben mindestens so lange gemerkt.
  static const Duration historicalValidity = Duration(hours: 24);

  /// Übernimmt die Antwort eines Abrufs für [area]. Punkte innerhalb von [area] ersetzt die Antwort
  /// (was dort nicht mehr kommt, ist weg); Punkte außerhalb bleiben, bis [expire] sie entfernt. So
  /// verschwinden Baustellen nicht, wenn man weiterfährt oder die Karte verschiebt.
  void absorb(Iterable<AlertPoint> fresh, GeoBounds area, DateTime now) {
    _known.removeWhere((_, e) => area.contains(e.$1.position));
    for (final p in fresh) {
      _known[p.id] = (p, now);
    }
    _trim();
    points = [for (final e in _known.values) e.$1];
  }

  void _trim() {
    var current = _known.values.where((e) => !e.$1.historical).length;
    var past = _known.length - current;
    for (final id in _known.keys.toList()) {
      if (current <= maxKnown) break;
      if (!_known[id]!.$1.historical) {
        _known.remove(id);
        current--;
      }
    }
    if (past <= maxHistorical) return;
    // Älteste Beobachtung zuerst; ohne Zeitangabe gilt ein Punkt als ältester.
    final byAge = _known.entries.where((e) => e.value.$1.historical).toList()
      ..sort(
        (a, b) =>
            (a.value.$1.observedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  b.value.$1.observedAt ??
                      DateTime.fromMillisecondsSinceEpoch(0),
                ),
      );
    for (final e in byAge) {
      if (past <= maxHistorical) break;
      _known.remove(e.key);
      past--;
    }
  }

  /// Entfernt Punkte, die vor mehr als [validity] geliefert wurden. True, wenn sich etwas änderte.
  bool expire(DateTime now, Duration validity) {
    final before = _known.length;
    _known.removeWhere((_, e) {
      final limit = e.$1.historical && validity < historicalValidity
          ? historicalValidity
          : validity;
      return now.difference(e.$2) > limit;
    });
    if (_known.length == before) return false;
    points = [for (final e in _known.values) e.$1];
    return true;
  }

  /// Zurück in den Zustand „nie benutzt“ (beim Ausschalten).
  void reset() {
    generation++;
    initialized = false;
    loading = false;
    points = const [];
    _known.clear();
    lastSuccessAt = null;
    successCenter = null;
    lastFetchAt = null;
    lastCenter = null;
    failed = false;
    message = null;
  }
}
