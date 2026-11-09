import 'dart:math' as math;

import '../../core/geo/geo.dart';
import '../../core/model/road_limit.dart';
import 'osm_tile.dart';

const double _mphToKmh = 1.609344;

/// Rechnet ein OSM-`maxspeed` in km/h um. Null bei `none`, `signals`, Autobahn-Kürzeln
/// und allem Unverständlichen. Bei Listen (`50;30`) zählt der erste Wert.
int? parseMaxspeed(String? raw) {
  if (raw == null) return null;
  var v = raw.trim().toLowerCase();
  if (v.isEmpty) return null;
  final semi = v.indexOf(';');
  if (semi > 0) v = v.substring(0, semi).trim();

  if (v == 'walk') return 7;
  if (v == 'none' || v == 'signals' || v == 'variable') return null;

  final mph = RegExp(r'^(\d+(?:[.,]\d+)?)\s*mph$').firstMatch(v);
  if (mph != null) {
    final n = double.parse(mph.group(1)!.replaceAll(',', '.'));
    return _plausible((n * _mphToKmh).round());
  }
  final plain = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(?:km/h|kmh|kph)?$')
      .firstMatch(v);
  if (plain != null) {
    return _plausible(
      double.parse(plain.group(1)!.replaceAll(',', '.')).round(),
    );
  }

  final coded = RegExp(r'^([a-z]{2}):(.+)$').firstMatch(v);
  if (coded == null) return null;
  final country = coded.group(1)!;
  final name = coded.group(2)!;
  final zone = RegExp(r'^zone:?(\d+)$').firstMatch(name);
  if (zone != null) return _plausible(int.parse(zone.group(1)!));
  switch (name) {
    case 'living_street':
      return 7;
    case 'urban':
      return const {'de', 'at', 'ch', 'fr'}.contains(country) ? 50 : null;
    case 'rural':
      return switch (country) {
        'de' || 'at' => 100,
        'ch' || 'fr' => 80,
        _ => null,
      };
    default:
      return null;
  }
}

int? _plausible(int kmh) => kmh >= 5 && kmh <= 250 ? kmh : null;

/// Steht in einem [SpeedWay] statt einer Zahl, wenn dort ausdrücklich kein Limit gilt. Bleibt
/// innerhalb von `features/osm`; nach außen geht daraus [RoadLimit.none].
const int speedWayNoLimit = -1;

/// Wert aus [pickSpeedLimit] (nach dem Halten über Lücken) für die anderen Bereiche.
RoadLimit roadLimitOf(int? picked) => switch (picked) {
  null => const RoadLimit.unknown(),
  speedWayNoLimit => const RoadLimit.none(),
  final kmh => RoadLimit.kmh(kmh),
};

/// Sagt ein OSM-`maxspeed`, dass hier kein Limit gilt? `none` und `DE:motorway` (Autobahn mit
/// Richtgeschwindigkeit). Nicht `signals` und `variable`: Dort zeigen Schilderbrücken mal 80,
/// mal nichts, und ohne aktuellen Wert wäre „kein Limit“ eine falsche Sicherheit.
/// [parseMaxspeed] bleibt dabei unverändert (Abgleich mit dem Paket-Generator).
bool isNoSpeedLimit(String? raw) {
  if (raw == null) return false;
  var v = raw.trim().toLowerCase();
  final semi = v.indexOf(';');
  if (semi > 0) v = v.substring(0, semi).trim();
  return v == 'none' || v == 'de:motorway';
}

/// Limit der Straße bei [position] für Kurs [headingDeg] aus bereits geladenen [ways].
/// Nächstes Segment innerhalb [maxDistance] Metern; Segmente, deren Richtung zum Kurs passt,
/// werden bevorzugt, Einbahnstraßen nur in ihrer Richtung berücksichtigt.
int? pickSpeedLimit(
  Iterable<SpeedWay> ways,
  GeoPoint position,
  double? headingDeg, {
  double maxDistance = 30,
}) {
  final dLat = maxDistance * 1.5 / 111320.0;
  final cosLat = math.cos(position.lat * math.pi / 180).abs().clamp(0.01, 1.0);
  final dLon = dLat / cosLat;

  double bestScore = double.infinity;
  int? bestLimit;
  var found = false;

  for (final way in ways) {
    // Rampen ohne Limit sind nur für die Linie voraus geladen.
    if (!way.limitTagged) continue;
    if (position.lat < way.minLat - dLat ||
        position.lat > way.maxLat + dLat ||
        position.lon < way.minLon - dLon ||
        position.lon > way.maxLon + dLon) {
      continue;
    }
    final pts = way.points;
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final d = distanceToSegmentMeters(position, a, b);
      if (d > maxDistance) continue;

      final canForward = way.oneway != -1;
      final canBackward = way.oneway != 1;
      final hasBearing = headingDeg != null && distanceMeters(a, b) > 1.0;

      bool? forward; // null = Richtung unbestimmt
      var penalty = 0.0;
      if (hasBearing) {
        final bearing = bearingDegrees(a, b);
        final diffF = canForward ? angleDifference(headingDeg, bearing) : 360.0;
        final diffB = canBackward
            ? angleDifference(headingDeg, bearing + 180)
            : 360.0;
        forward = diffF <= diffB;
        final diff = forward ? diffF : diffB;
        penalty = diff > 60 ? 1000 : diff * 0.2;
      } else if (!canBackward) {
        forward = true;
      } else if (!canForward) {
        forward = false;
      }

      final score = d + penalty;
      if (score >= bestScore) continue;
      bestScore = score;
      found = true;
      bestLimit = switch (forward) {
        true => way.forward,
        false => way.backward,
        null => _undirected(way.forward, way.backward),
      };
    }
  }
  return found ? bestLimit : null;
}

/// Richtung unklar: das strengere Limit. „Kein Limit“ ist das schwächste, eine Zahl geht vor.
int? _undirected(int? f, int? b) {
  if (f == null || f == speedWayNoLimit) return b ?? f;
  if (b == null || b == speedWayNoLimit) return f;
  return math.min(f, b);
}
