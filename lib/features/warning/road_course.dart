import 'dart:math' as math;

import '../../core/geo/geo.dart';

/// Liegt ein Hinweis auf der Strecke, der man folgt?
enum RoadVerdict {
  /// Auf der Linie voraus: warnen, auch hinter einer Kurve oder Kreuzung.
  onRoad,

  /// Daneben, oder auf der Strecke, die man gerade verlassen hat: nicht warnen.
  offRoad,

  /// Keine Straßendaten: Die Warnlogik prüft wie bisher an der geraden Linie.
  unknown,
}

/// Höchstens so weit neben der Linie gilt ein Hinweis als auf der Strecke. Baustellen stehen als
/// Startpunkt am Rand oder auf der Gegenfahrbahn.
const double roadOnMeters = 30;

/// Eine laufende Warnung gilt erst ab diesem Abstand als daneben (gegen Flattern).
const double roadOffMeters = 40;

/// Weiter als so neben der letzten Linie, ohne neue: abgebogen oder abgefahren.
const double _leftMeters = 30;

/// Die verlassene Strecke schweigt bis so weit nach dem Verlassen.
const double _leftForgetMeters = 3000;

const double _metersPerDegree = earthRadiusMeters * math.pi / 180;

/// Linie voraus aus den Straßendaten ([update] je Fix) und die Strecke, die man zuletzt
/// verlassen hat.
class RoadCourse {
  List<GeoPoint>? _line;
  double _length = 0;
  GeoPoint? _lineFrom;
  List<GeoPoint>? _left;
  GeoPoint? _leftAt;

  bool get hasLine => _line != null;
  bool get hasLeft => _left != null;

  void reset() {
    _line = null;
    _left = null;
  }

  /// Neue Linie ab [pos] oder null (keine Daten). Ohne neue bleibt die letzte, solange man auf
  /// ihr ist; liegt [pos] mehr als 30 m daneben, gilt sie als verlassen.
  void update(GeoPoint pos, List<GeoPoint>? line) {
    if (line != null && line.length >= 2) {
      _line = line;
      _lineFrom = pos;
      _length = _lengthOf(line);
      _left = null;
      return;
    }
    final last = _line;
    if (last != null && distanceToLine(pos, last) > _leftMeters) {
      _left = last;
      _leftAt = pos;
      _line = null;
    }
    final at = _leftAt;
    if (_left != null &&
        at != null &&
        distanceMeters(pos, at) > _leftForgetMeters) {
      _left = null;
    }
  }

  /// Urteil für einen Hinweis bei [p] im Abstand [d]; [tracked] mit der weiteren Grenze.
  RoadVerdict verdict(GeoPoint p, double d, {bool tracked = false}) {
    final line = _line;
    if (line != null) {
      final from = _lineFrom;
      final moved = from == null ? 0.0 : distanceMeters(from, line.first);
      // Weiter als die Linie reicht: dort weiß sie nichts.
      if (d > _length - moved + roadOnMeters) return RoadVerdict.unknown;
      final off = distanceToLine(p, line, skipBehind: true);
      return off <= (tracked ? roadOffMeters : roadOnMeters)
          ? RoadVerdict.onRoad
          : RoadVerdict.offRoad;
    }
    final left = _left;
    if (left != null &&
        distanceToLine(p, left, skipBehind: true) <= roadOnMeters) {
      return RoadVerdict.offRoad;
    }
    return RoadVerdict.unknown;
  }

  static double _lengthOf(List<GeoPoint> line) {
    var m = 0.0;
    for (var i = 1; i < line.length; i++) {
      m += distanceMeters(line[i - 1], line[i]);
    }
    return m;
  }
}

/// Kürzester Abstand von [p] zur Linie [line]. Mit [skipBehind] zählt der Teil vor dem Anfang
/// nicht: Ein Punkt hinter einem liegt nicht auf der Strecke voraus.
double distanceToLine(
  GeoPoint p,
  List<GeoPoint> line, {
  bool skipBehind = false,
}) {
  var best = double.infinity;
  for (var i = 0; i + 1 < line.length; i++) {
    final a = line[i], b = line[i + 1];
    if (i == 0 && skipBehind && _behind(p, a, b)) continue;
    final d = distanceToSegmentMeters(p, a, b);
    if (d < best) best = d;
  }
  return best;
}

/// Liegt [p] vor dem Anfang [a] des Abschnitts a–b (Projektion vor a)?
bool _behind(GeoPoint p, GeoPoint a, GeoPoint b) {
  final cos = math.cos(a.lat * math.pi / 180);
  final bx = (b.lon - a.lon) * cos * _metersPerDegree;
  final by = (b.lat - a.lat) * _metersPerDegree;
  final px = (p.lon - a.lon) * cos * _metersPerDegree;
  final py = (p.lat - a.lat) * _metersPerDegree;
  return bx * px + by * py < 0;
}
