import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

/// Kachel 52,0–52,1 N / 8,0–8,1 O (0,1°-Gitter).
const testTile = TileId(80, 520);

const testArea = GeoBounds(south: 52.02, west: 8.02, north: 52.08, east: 8.08);

Map<String, dynamic> node(
  int id,
  double lat,
  double lon, [
  Map<String, String>? tags,
]) => {'type': 'node', 'id': id, 'lat': lat, 'lon': lon, 'tags': ?tags};

Map<String, dynamic> way(
  int id,
  List<List<double>> geom,
  Map<String, String> tags, {
  List<int>? nodes,
}) => {
  'type': 'way',
  'id': id,
  'nodes': nodes ?? [for (var i = 0; i < geom.length; i++) id * 100 + i],
  'tags': tags,
  'geometry': [
    for (final g in geom) {'lat': g[0], 'lon': g[1]},
  ],
};

Map<String, dynamic> member(
  String type,
  int ref,
  String role, {
  double? lat,
  double? lon,
}) => {'type': type, 'ref': ref, 'role': role, 'lat': ?lat, 'lon': ?lon};

Map<String, dynamic> relation(
  int id,
  Map<String, String> tags,
  List<Map<String, dynamic>> members,
) => {'type': 'relation', 'id': id, 'tags': tags, 'members': members};

String overpassBody(List<Map<String, dynamic>> elements) =>
    jsonEncode({'version': 0.6, 'elements': elements});

/// Eine Kamera mit Richtung 90 und ein Weg mit 50 km/h, beides in [testTile].
String simpleTileBody() => overpassBody([
  node(1, 52.05, 8.05, {'highway': 'speed_camera', 'direction': '90'}),
  way(
    10,
    [
      [52.05, 8.04],
      [52.05, 8.06],
    ],
    {'highway': 'primary', 'maxspeed': '50'},
  ),
]);

/// Westkante des letzten Rechtecks „(S,W,N,O)“ der Abfrage, um die Zelle zu erkennen.
String westOf(http.Request req) {
  final m = RegExp(r'\((-?[\d.]+),(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)\)')
      .allMatches(req.bodyFields['data']!)
      .last;
  return m.group(2)!;
}

/// Südkante des letzten Rechtecks der Abfrage.
String southOf(http.Request req) {
  final m = RegExp(r'\((-?[\d.]+),(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)\)')
      .allMatches(req.bodyFields['data']!)
      .last;
  return m.group(1)!;
}

/// Schicht, zu der die Overpass-Abfrage gehört.
OsmLayer layerOf(http.Request req) {
  final q = req.bodyFields['data']!;
  if (q.contains('speed_camera')) return OsmLayer.cameras;
  if (q.contains('traffic_signals')) return OsmLayer.signals;
  return q.contains('residential') ? OsmLayer.minorLimits : OsmLayer.limits;
}

/// Antwort je Schicht: Blitzer (Richtung 90) und Ampel in [testTile], ein 50er-Weg bei 52,05 N.
String layerBody(OsmLayer layer) => switch (layer) {
  OsmLayer.cameras => overpassBody([
    node(1, 52.05, 8.05, {'highway': 'speed_camera', 'direction': '90'}),
  ]),
  OsmLayer.signals => overpassBody([
    node(2, 52.06, 8.06, {'highway': 'traffic_signals'}),
  ]),
  OsmLayer.limits => overpassBody([
    way(
      10,
      [
        [52.05, 8.04],
        [52.05, 8.06],
      ],
      {'highway': 'primary', 'maxspeed': '50'},
    ),
  ]),
  OsmLayer.minorLimits => overpassBody([]),
};
