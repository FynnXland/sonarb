import 'dart:math' as math;

import '../../core/model/alert_point.dart';
import 'osm_category.dart';
import 'osm_parser.dart';
import 'osm_tile.dart';

/// Grober Umriss Deutschlands (Breite, Länge), reihum von der Emsmündung aus. Er dient nur dazu,
/// die Kacheln des Landes aufzuzählen und Randkacheln zu erkennen; die Blitzer selbst kommen aus der
/// Overpass-Fläche `ISO3166-1=DE`. Abweichungen von einigen Kilometern schaden nicht.
const List<(double, double)> germanyOutline = [
  (53.60, 6.65),
  (53.75, 7.00),
  (53.80, 7.60),
  (53.90, 8.30),
  (53.90, 8.60),
  (54.15, 8.80),
  (54.30, 8.55),
  (54.65, 8.30),
  (55.05, 8.35),
  (55.06, 8.65),
  (54.90, 8.75),
  (54.90, 9.70),
  (54.80, 10.00),
  (54.60, 10.30),
  (54.60, 11.25),
  (54.15, 11.05),
  (53.96, 10.87),
  (53.90, 11.45),
  (54.18, 12.10),
  (54.45, 12.45),
  (54.65, 13.00),
  (54.70, 13.45),
  (54.45, 13.75),
  (54.00, 14.25),
  (53.55, 14.28),
  (53.20, 14.38),
  (52.35, 14.58),
  (51.95, 14.75),
  (51.15, 15.05),
  (50.85, 14.80),
  (50.85, 14.45),
  (50.90, 14.25),
  (50.40, 13.00),
  (50.30, 12.10),
  (50.10, 12.20),
  (49.90, 12.40),
  (49.50, 12.65),
  (49.30, 12.85),
  (49.00, 13.80),
  (48.75, 13.85),
  (48.55, 13.45),
  (48.30, 13.00),
  (47.80, 13.00),
  (47.55, 13.05),
  (47.58, 12.20),
  (47.60, 11.50),
  (47.45, 11.00),
  (47.40, 10.45),
  (47.55, 10.20),
  (47.55, 9.65),
  (47.65, 9.18),
  (47.80, 8.65),
  (47.58, 7.58),
  (48.03, 7.58),
  (48.58, 7.81),
  (48.97, 8.18),
  (49.04, 7.95),
  (49.15, 7.05),
  (49.47, 6.37),
  (49.80, 6.42),
  (49.93, 6.20),
  (50.35, 6.30),
  (50.77, 6.05),
  (50.90, 5.95),
  (51.20, 6.05),
  (51.78, 6.10),
  (52.20, 6.90),
  (52.50, 7.05),
  (52.90, 7.10),
  (53.20, 7.15),
  (53.35, 7.20),
];

/// Abstand zum Umriss in Grad, ab dem eine Kachel als „sicher im Land“ gilt (rund 8–13 km).
const double borderMarginDeg = 0.12;

bool _inside(double lat, double lon) {
  var in_ = false;
  final n = germanyOutline.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final (yi, xi) = germanyOutline[i];
    final (yj, xj) = germanyOutline[j];
    if ((yi > lat) != (yj > lat) &&
        lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
      in_ = !in_;
    }
  }
  return in_;
}

/// Kleinster Abstand von (lat, lon) zum Umriss in Grad (Länge nach Breite gestreckt).
double _edgeDistance(double lat, double lon) {
  final k = math.cos(lat * math.pi / 180);
  var best = double.infinity;
  final n = germanyOutline.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final (ay, ax) = germanyOutline[j];
    final (by, bx) = germanyOutline[i];
    final dx = (bx - ax) * k, dy = by - ay;
    final px = (lon - ax) * k, py = lat - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : ((px * dx + py * dy) / len2).clamp(0.0, 1.0);
    final ex = px - t * dx, ey = py - t * dy;
    best = math.min(best, math.sqrt(ex * ex + ey * ey));
  }
  return best;
}

/// Alle Kacheln (0,1°), deren Mitte in Deutschland liegt.
List<TileId> germanyTiles() {
  final lats = germanyOutline.map((p) => p.$1),
      lons = germanyOutline.map((p) => p.$2);
  final out = <TileId>[];
  for (
    var iy = (lats.reduce(math.min) * tilesPerDegree).floor();
    iy <= (lats.reduce(math.max) * tilesPerDegree).floor();
    iy++
  ) {
    for (
      var ix = (lons.reduce(math.min) * tilesPerDegree).floor();
      ix <= (lons.reduce(math.max) * tilesPerDegree).floor();
      ix++
    ) {
      final t = TileId(ix, iy);
      final c = t.center;
      if (_inside(c.lat, c.lon)) out.add(t);
    }
  }
  return out;
}

/// True, wenn die Kachel ganz im Land liegt (mit Sicherheitsabstand zum groben Umriss): Dort sind die
/// Blitzer der Länderabfrage vollständig. Randkacheln können Blitzer jenseits der Grenze vermissen.
bool isInteriorTile(TileId t) {
  final c = t.center;
  return _inside(c.lat, c.lon) &&
      _edgeDistance(c.lat, c.lon) >= borderMarginDeg;
}

/// Overpass-QL: alle Blitzer in Deutschland wie in der Blitzer-Schicht (Knoten, Relationen, Wege für
/// die Richtung), samt Höhen-, Gewichts-, Einfahrts- und Überholkontrollen.
String buildCountryQuery() {
  final roads = motorRoadTypes.join('|');
  return '[out:json][timeout:240][maxsize:536870912];\n'
      'area["ISO3166-1"="DE"][admin_level=2]->.de;\n'
      'node["highway"="speed_camera"](area.de)->.cams;\n'
      'rel(bn.cams)["type"="enforcement"]'
      '["enforcement"~"maxspeed|traffic_signals|average_speed|section_control"]'
      '->.enfCams;\n'
      'rel["type"="enforcement"]["enforcement"~"$otherEnforcementPattern"](area.de)'
      '->.enfOther;\n'
      '(.enfCams; .enfOther;)->.enf;\n'
      'way(bn.cams)["highway"~"^($roads)\$"]->.camways;\n'
      '.cams out meta;\n'
      '.enf out geom meta;\n'
      '.camways out geom;\n';
}

/// Die Blitzer Deutschlands, nach Kacheln geordnet.
class CountryData {
  const CountryData(this.fetchedAt, this.byTile);

  factory CountryData.fromParsed(ParsedOsm parsed, DateTime fetchedAt) {
    final by = <TileId, List<AlertPoint>>{};
    for (final p in parsed.points) {
      (by[TileId.of(p.position.lat, p.position.lon)] ??= []).add(p);
    }
    return CountryData(fetchedAt, by);
  }

  final DateTime fetchedAt;
  final Map<TileId, List<AlertPoint>> byTile;

  int get pointCount => byTile.values.fold(0, (a, l) => a + l.length);
}
