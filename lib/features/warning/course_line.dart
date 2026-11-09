import 'dart:math' as math;

import '../../core/geo/geo.dart';
import 'point_class.dart';

/// Erste Ansage nur nahe der Fahrtlinie, gemessen an der geraden Verlängerung des Kurses.
/// Blitzer: seitlich höchstens max(30 m, d × tan 20°), ab [_fastMps] 30°, damit sie in weiten
/// Autobahnkurven die volle Vorwarnung bekommen.
const double _lineMinMeters = 30;
const double _cameraLineDeg = 20;
const double _fastMps = 25;
const double _fastExtraDeg = 10;

/// Hinweise (Baustellen, Gefahrenstellen, weitere Kontrollen): eng, weil sie oft in Querstraßen
/// oder auf Parallelstraßen liegen und eine späte Ansage weniger schadet als eine falsche.
/// Seitlich höchstens max(25 m, d × tan 3°), ab [_fastMps] 6°. Bei 600 m sind das 31 m.
const double _hintLineMinMeters = 25;
const double _hintLineDeg = 3;
const double _hintFastLineDeg = 6;

/// Krümmung der Fahrt aus den letzten [trailFixes] Fixes. In einer Kurve misst die Linie für
/// Hinweise am Bogen statt an der Geraden: Eine Baustelle auf der Tangente liegt dann auf einer
/// anderen Straße, eine auf dem Bogen auf der eigenen. Unter [_curveMinDeg] Kursänderung, oder
/// wenn die letzten drei Fixes geradeaus gehen (nach dem Abbiegen), gilt die Gerade.
const int trailFixes = 5;
const double _curveMinDeg = 5;
const double _straightRecentDeg = 3;
const double _minCurveRadius = 80;

/// Schon angesagt, aber gerade weit neben der Linie: Anzeige ruht, bis der Punkt wieder
/// vor einem liegt (z. B. nach dem Abbiegen in seine Straße).
const double _hideMinMeters = 60;
const double _cameraHideDeg = 45;
const double _hintHideDeg = 25;

/// Ab diesem Tempo gelten die weiteren Toleranzen für weite Kurven.
bool isFast(double speedMps) => speedMps >= _fastMps;

/// Seitlicher Abstand zur Fahrtlinie, ab dem ein Punkt nicht als „voraus“ gilt.
double lineTolerance(
  Tracking tracking,
  double d, {
  required bool fast,
  bool hide = false,
}) {
  final camera = tracking != Tracking.announceOnly;
  if (!camera && !hide) {
    final deg = fast ? _hintFastLineDeg : _hintLineDeg;
    return math.max(_hintLineMinMeters, d * math.tan(deg * math.pi / 180));
  }
  var deg = hide ? (camera ? _cameraHideDeg : _hintHideDeg) : _cameraLineDeg;
  if (fast && !hide) deg += _fastExtraDeg;
  final min = hide ? _hideMinMeters : _lineMinMeters;
  return math.max(min, d * math.tan(deg * math.pi / 180));
}

/// Krümmung in 1/m, positiv nach rechts; 0 auf gerader Strecke und kurz nach dem Abbiegen.
double curvatureOf(List<(GeoPoint, double)> trail) {
  if (trail.length < trailFixes) return 0;
  final turn = signedTurn(trail.first.$2, trail.last.$2);
  final recent = signedTurn(trail[trail.length - 3].$2, trail.last.$2);
  if (turn.abs() < _curveMinDeg || recent.abs() < _straightRecentDeg) {
    return 0;
  }
  var meters = 0.0;
  for (var i = 1; i < trail.length; i++) {
    meters += distanceMeters(trail[i - 1].$1, trail[i].$1);
  }
  if (meters < 30) return 0;
  final k = turn * math.pi / 180 / meters;
  return k.clamp(-1 / _minCurveRadius, 1 / _minCurveRadius);
}

/// Kursänderung von [from] nach [to] in Grad, −180 bis 180, positiv nach rechts.
double signedTurn(double from, double to) => (to - from + 540) % 360 - 180;

/// Seitlicher Abstand eines Punkts (Abstand [d], Peilung [bearing]) zur voraussichtlichen
/// Fahrlinie: bei [curvature] 0 die Gerade in Richtung [heading], sonst der Bogen mit dieser
/// Krümmung (positiv nach rechts).
double offCourse(double d, double bearing, double heading, double curvature) {
  final a = signedTurn(heading, bearing) * math.pi / 180;
  final x = d * math.cos(a);
  final y = d * math.sin(a);
  if (curvature == 0) return y.abs();
  final r = 1 / curvature;
  final dy = y - r;
  return (math.sqrt(x * x + dy * dy) - r.abs()).abs();
}
