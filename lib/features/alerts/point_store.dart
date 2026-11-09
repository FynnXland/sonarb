import 'dart:collection';

import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';

/// Gedächtnis für feste Messstellen, nach Zellen von 0,1° × 0,1° geordnet. Was einmal geladen
/// wurde, kommt in jeder Zoomstufe zurück; erst das Speicherbudget ([maxCells], zuletzt
/// benutzte Zellen bleiben) verdrängt alte Zellen. Eine Zelle ist ein Eintrag, auch wenn sie leer ist
/// („hier ist nichts“ ist eine Auskunft).
class PointStore {
  PointStore({this.maxCells = 6000});

  /// Zellen, die höchstens im Speicher bleiben.
  final int maxCells;

  /// Zuletzt benutzte Zelle hinten.
  final LinkedHashMap<(int, int), Map<String, AlertPoint>> _cells =
      LinkedHashMap();

  static const double _cellDeg = 0.1;

  static (int, int) _cellOf(GeoPoint p) =>
      ((p.lat / _cellDeg).floor(), (p.lon / _cellDeg).floor());

  int get cellCount => _cells.length;

  /// Nimmt [points] auf. Mit [authoritative] ist die Antwort für [area] vollständig: Zellen, die
  /// ganz in [area] liegen, werden ersetzt (Punkte, die es nicht mehr gibt, verschwinden, leere
  /// Zellen werden vermerkt). Sonst (Cache-Lesen, Teilantwort, Fehler) werden Punkte nur ergänzt
  /// oder aktualisiert. Gibt zurück, ob sich etwas geändert hat.
  bool ingest(
    GeoBounds area,
    Iterable<AlertPoint> points, {
    required bool authoritative,
  }) {
    var changed = false;
    final byCell = <(int, int), Map<String, AlertPoint>>{};
    for (final p in points) {
      (byCell[_cellOf(p.position)] ??= {})[p.id] = p;
    }
    if (authoritative) {
      final s = (area.south / _cellDeg).ceil();
      final n = (area.north / _cellDeg).floor() - 1;
      final w = (area.west / _cellDeg).ceil();
      final e = (area.east / _cellDeg).floor() - 1;
      for (var iy = s; iy <= n; iy++) {
        for (var ix = w; ix <= e; ix++) {
          changed |= _replace((iy, ix), byCell.remove((iy, ix)) ?? const {});
        }
      }
    }
    for (final entry in byCell.entries) {
      final cell = _cells.remove(entry.key) ?? <String, AlertPoint>{};
      for (final p in entry.value.values) {
        final old = cell[p.id];
        if (old == null || !_same(old, p)) changed = true;
        cell[p.id] = p;
      }
      _cells[entry.key] = cell;
    }
    _evict();
    return changed;
  }

  bool _replace((int, int) key, Map<String, AlertPoint> next) {
    final old = _cells.remove(key);
    _cells[key] = Map.of(next);
    if (old == null) return next.isNotEmpty;
    if (old.length != next.length) return true;
    for (final p in next.values) {
      final o = old[p.id];
      if (o == null || !_same(o, p)) return true;
    }
    return false;
  }

  /// Gleiche ID und gleiche Stelle: Aktualisierungen wie neue Details zählen nicht als „neu“,
  /// sonst meldet jede Auffrischung eine Änderung.
  static bool _same(AlertPoint a, AlertPoint b) =>
      a.position.lat == b.position.lat &&
      a.position.lon == b.position.lon &&
      a.effectiveCategory == b.effectiveCategory;

  /// Bekannte Punkte im Ausschnitt. Die berührten Zellen zählen als benutzt.
  List<AlertPoint> pointsIn(GeoBounds view) {
    final out = <AlertPoint>[];
    final touched = <(int, int)>[];
    for (final entry in _cells.entries) {
      final (iy, ix) = entry.key;
      if ((iy + 1) * _cellDeg < view.south ||
          iy * _cellDeg > view.north ||
          (ix + 1) * _cellDeg < view.west ||
          ix * _cellDeg > view.east) {
        continue;
      }
      touched.add(entry.key);
      for (final p in entry.value.values) {
        if (view.contains(p.position)) out.add(p);
      }
    }
    for (final k in touched) {
      _cells[k] = _cells.remove(k)!;
    }
    return out;
  }

  /// Alle bekannten Punkte, ohne die Zellen als benutzt zu zählen.
  Iterable<AlertPoint> get all sync* {
    for (final cell in _cells.values) {
      yield* cell.values;
    }
  }

  bool covers(GeoPoint p) => _cells.containsKey(_cellOf(p));

  void clear() => _cells.clear();

  void _evict() {
    while (_cells.length > maxCells) {
      _cells.remove(_cells.keys.first);
    }
  }
}
