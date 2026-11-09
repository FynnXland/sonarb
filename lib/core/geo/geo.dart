import 'dart:math' as math;

/// WGS84-Koordinate. Bewusst eigener Typ, damit der Core nicht an flutter_map hängt.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'GeoPoint($lat, $lon)';
}

/// Achsenparalleles Rechteck (Overpass-Reihenfolge: süd, west, nord, ost).
class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  /// Quadrat mit [radiusMeters] Abstand vom Mittelpunkt zu jeder Kante.
  factory GeoBounds.around(GeoPoint center, double radiusMeters) {
    final dLat = radiusMeters / _metersPerDegreeLat;
    final cosLat = math.cos(center.lat * math.pi / 180).abs().clamp(0.01, 1.0);
    final dLon = radiusMeters / (_metersPerDegreeLat * cosLat);
    return GeoBounds(
      south: center.lat - dLat,
      west: center.lon - dLon,
      north: center.lat + dLat,
      east: center.lon + dLon,
    );
  }

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(GeoPoint p) =>
      p.lat >= south && p.lat <= north && p.lon >= west && p.lon <= east;

  GeoPoint get center => GeoPoint((south + north) / 2, (west + east) / 2);

  @override
  String toString() => 'GeoBounds($south,$west,$north,$east)';
}

const double earthRadiusMeters = 6371008.8;
const double _metersPerDegreeLat = 111320.0;

double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;

/// Großkreisdistanz in Metern (Haversine).
double distanceMeters(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) *
          math.cos(_rad(b.lat)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
}

/// Anfangskurs von [from] nach [to] in Grad, 0 = Nord, im Uhrzeigersinn, [0, 360).
double bearingDegrees(GeoPoint from, GeoPoint to) {
  final p1 = _rad(from.lat);
  final p2 = _rad(to.lat);
  final dl = _rad(to.lon - from.lon);
  final y = math.sin(dl) * math.cos(p2);
  final x =
      math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return normalizeDegrees(_deg(math.atan2(y, x)));
}

/// Winkel auf [0, 360) bringen.
double normalizeDegrees(double deg) {
  final r = deg % 360;
  return r < 0 ? r + 360 : r;
}

/// Kleinster Winkel zwischen zwei Kursen, [0, 180].
double angleDifference(double a, double b) {
  final d = (normalizeDegrees(a) - normalizeDegrees(b)).abs();
  return d > 180 ? 360 - d : d;
}

/// Punkt in [distance] Metern Entfernung auf Kurs [bearingDeg].
GeoPoint destinationPoint(GeoPoint start, double bearingDeg, double distance) {
  final d = distance / earthRadiusMeters;
  final b = _rad(bearingDeg);
  final p1 = _rad(start.lat);
  final l1 = _rad(start.lon);
  final p2 = math.asin(
    math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(b),
  );
  final l2 =
      l1 +
      math.atan2(
        math.sin(b) * math.sin(d) * math.cos(p1),
        math.cos(d) - math.sin(p1) * math.sin(p2),
      );
  return GeoPoint(_deg(p2), ((_deg(l2) + 540) % 360) - 180);
}

/// Abstand von [p] zur Strecke [a]–[b] in Metern (lokal eben gerechnet, genügt für < 5 km).
double distanceToSegmentMeters(GeoPoint p, GeoPoint a, GeoPoint b) {
  final cosLat = math.cos(_rad(p.lat));
  double x(GeoPoint q) => (q.lon - p.lon) * _metersPerDegreeLat * cosLat;
  double y(GeoPoint q) => (q.lat - p.lat) * _metersPerDegreeLat;
  final ax = x(a), ay = y(a), bx = x(b), by = y(b);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt(cx * cx + cy * cy);
}
