import 'dart:math' as math;

import '../../core/geo/geo.dart';
import 'osm_tile.dart';

/// So weit voraus folgt die Linie der Straße: etwas mehr als die größte erste Ansage bei Tempo
/// (2 km) plus Rand.
const double roadAheadMeters = 2500;

/// Eigener Weg: höchstens so weit neben der Position und so weit vom Kurs abweichend.
const double _matchMeters = 25;
const double _matchDeg = 45;

/// Zwei Wege hängen zusammen, wenn ein Eckpunkt des einen so nah am Ende des anderen liegt
/// (in OSM derselbe Knoten, hier nur die Koordinaten).
const double _joinMeters = 3;

/// Weiter als so stark abknicken (fast umdrehen) führt keine Fortsetzung.
const double _maxTurnDeg = 110;

/// Höchstens so viele Wege hintereinander.
const int _maxWays = 40;

/// Die Strecke, der man wahrscheinlich folgt: ab der Position entlang des eigenen Wegs, an jedem
/// Wegende weiter auf den Anschluss mit demselben Namen oder derselben Nummer (`ref`), sonst
/// derselben Straßenart, sonst der wichtigeren, sonst dem kleinsten Knick. So folgt die Linie
/// einer abknickenden Vorfahrtsstraße und nach einer Abfahrt der Rampe.
///
/// Null, wenn kein eigener Weg passt oder seine Art unbekannt ist (alter Cache): Dann bleibt die
/// Warnlogik bei der geraden Linie. Die Linie beginnt an der Position.
List<GeoPoint>? roadAhead(
  List<SpeedWay> ways,
  GeoPoint position,
  double headingDeg, {
  double meters = roadAheadMeters,
}) {
  final start = _match(ways, position, headingDeg);
  if (start == null) return null;
  final line = <GeoPoint>[position];
  var length = 0.0;
  var way = start.way;
  var index = start.index;
  var forward = start.forward;
  final used = <SpeedWay>{way};
  for (var n = 0; n < _maxWays; n++) {
    final pts = way.points;
    var i = forward ? index + 1 : index;
    while (i >= 0 && i < pts.length) {
      length += distanceMeters(line.last, pts[i]);
      line.add(pts[i]);
      if (length >= meters) return line;
      i += forward ? 1 : -1;
    }
    final end = line.last;
    final before = line[line.length - 2];
    final next = _continuation(
      ways,
      used,
      way,
      end,
      bearingDegrees(before, end),
    );
    if (next == null) break;
    way = next.way;
    index = next.index;
    forward = next.forward;
    used.add(way);
  }
  return line.length >= 2 ? line : null;
}

/// Ein Weg mit Abschnitt [index] (von Punkt index nach index+1) und Fahrtrichtung.
class _Spot {
  const _Spot(this.way, this.index, this.forward);

  final SpeedWay way;
  final int index;
  final bool forward;
}

bool _near(SpeedWay w, GeoPoint p, double meters) {
  final dLat = meters / 111320.0;
  final dLon =
      dLat / math.cos(p.lat * math.pi / 180).abs().clamp(0.01, 1.0).toDouble();
  return p.lat >= w.minLat - dLat &&
      p.lat <= w.maxLat + dLat &&
      p.lon >= w.minLon - dLon &&
      p.lon <= w.maxLon + dLon;
}

/// Eigener Weg wie beim Tempolimit: nächstes Segment, dessen Richtung zum Kurs passt.
/// Einbahnstraßen nur in ihrer Richtung. Ohne bekannte Art: null.
_Spot? _match(List<SpeedWay> ways, GeoPoint p, double heading) {
  _Spot? best;
  var bestScore = double.infinity;
  for (final w in ways) {
    if (!_near(w, p, _matchMeters)) continue;
    final pts = w.points;
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      if (distanceMeters(a, b) < 1) continue;
      final d = distanceToSegmentMeters(p, a, b);
      if (d > _matchMeters) continue;
      final bearing = bearingDegrees(a, b);
      final diffF = w.oneway != -1 ? angleDifference(heading, bearing) : 360.0;
      final diffB = w.oneway != 1
          ? angleDifference(heading, bearing + 180)
          : 360.0;
      final forward = diffF <= diffB;
      final diff = forward ? diffF : diffB;
      if (diff > _matchDeg) continue;
      final score = d + diff * 0.2;
      if (score < bestScore) {
        bestScore = score;
        best = _Spot(w, i, forward);
      }
    }
  }
  if (best == null || !best.way.classKnown) return null;
  return best;
}

/// Anschluss am Ende [end] des Wegs [from], wenn man mit Kurs [bearing] ankommt.
_Spot? _continuation(
  List<SpeedWay> ways,
  Set<SpeedWay> used,
  SpeedWay from,
  GeoPoint end,
  double bearing,
) {
  _Spot? best;
  (int, int, int, double)? bestKey;
  for (final w in ways) {
    if (used.contains(w) || !_near(w, end, _joinMeters)) continue;
    final pts = w.points;
    for (var k = 0; k < pts.length; k++) {
      if (distanceMeters(pts[k], end) > _joinMeters) continue;
      for (final forward in const [true, false]) {
        if (forward && (k + 1 >= pts.length || w.oneway == -1)) continue;
        if (!forward && (k == 0 || w.oneway == 1)) continue;
        final out = bearingDegrees(pts[k], pts[forward ? k + 1 : k - 1]);
        final turn = angleDifference(bearing, out);
        if (turn > _maxTurnDeg) continue;
        final key = (
          _sameRoad(from, w) ? 0 : 1,
          _sameClass(from, w) ? 0 : 1,
          w.rank ?? (w.minor == true ? 50 : 40),
          turn,
        );
        if (bestKey == null || _less(key, bestKey)) {
          bestKey = key;
          // Eckpunkt k liegt schon auf der Linie. [roadAhead] hängt vorwärts ab index + 1 an,
          // rückwärts ab index: also k bzw. k - 1.
          best = _Spot(w, forward ? k : k - 1, forward);
        }
      }
    }
  }
  return best;
}

bool _sameRoad(SpeedWay a, SpeedWay b) =>
    (a.ref != null && a.ref == b.ref) || (a.name != null && a.name == b.name);

bool _sameClass(SpeedWay a, SpeedWay b) {
  if (a.rank != null && b.rank != null) return a.rank == b.rank;
  return a.minor != null && a.minor == b.minor;
}

bool _less((int, int, int, double) a, (int, int, int, double) b) {
  if (a.$1 != b.$1) return a.$1 < b.$1;
  if (a.$2 != b.$2) return a.$2 < b.$2;
  if (a.$3 != b.$3) return a.$3 < b.$3;
  return a.$4 < b.$4;
}
