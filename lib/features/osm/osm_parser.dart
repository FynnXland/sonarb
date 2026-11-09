import 'dart:convert';

import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import 'osm_category.dart';
import 'osm_details.dart';
import 'osm_direction.dart';
import 'osm_log.dart';
import 'osm_speed.dart';
import 'osm_tile.dart';
import 'osm_way_limits.dart';

part 'osm_parser_relation.dart';

/// Straßentypen für Kfz, geordnet nach Bedeutung (Index = Rang).
const List<String> motorRoadTypes = [
  'motorway',
  'motorway_link',
  'trunk',
  'trunk_link',
  'primary',
  'primary_link',
  'secondary',
  'secondary_link',
  'tertiary',
  'tertiary_link',
  'unclassified',
  'residential',
  'living_street',
];

/// Wertet die Antwort einer Kachel-Abfrage aus und liefert nur Punkte, die in [tile] liegen.
/// [withWays] = false lässt Tempolimit-Wege weg (die Blitzer-Abfrage liefert Wege nur für die Richtung).
TileData parseOverpassJson(
  String body,
  TileId tile,
  DateTime fetchedAt, {
  bool withWays = true,
}) {
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Overpass-Antwort ist kein Objekt');
  }
  return parseOverpass(json, tile, fetchedAt, withWays: withWays);
}

TileData parseOverpass(
  Map<String, dynamic> json,
  TileId tile,
  DateTime fetchedAt, {
  bool withWays = true,
}) => tileDataOf(parseAll(json, withWays: withWays), tile, fetchedAt);

/// Alles, was eine Antwort enthält, ohne Zuordnung zu Kacheln.
class ParsedOsm {
  const ParsedOsm(this.points, this.ways);

  final List<AlertPoint> points;
  final List<SpeedWay> ways;
}

/// Die Punkte von [parsed] in [tile] (und alle Wege, sie überspannen Kachelkanten).
TileData tileDataOf(
  ParsedOsm parsed,
  TileId tile,
  DateTime fetchedAt, {
  bool partial = false,
  int detailVersion = pointDetailVersion,
}) => TileData(
  fetchedAt: fetchedAt,
  points: [
    for (final p in parsed.points)
      if (TileId.of(p.position.lat, p.position.lon, tile.perDegree) == tile) p,
  ],
  ways: parsed.ways,
  detailVersion: detailVersion,
  partial: partial,
);

/// Wertet alle Elemente einer Antwort einmal aus.
ParsedOsm parseAll(Map<String, dynamic> json, {bool withWays = true}) {
  final elements = (json['elements'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();

  final camNodes = <int, Map<String, dynamic>>{};
  final signalNodes = <Map<String, dynamic>>[];
  final relations = <Map<String, dynamic>>[];
  final wayElements = <Map<String, dynamic>>[];
  for (final e in elements) {
    _guard(e, () {
      final tags = _tags(e);
      switch (e['type']) {
        case 'node':
          if (e['lat'] == null || e['lon'] == null) break;
          if (tags['highway'] == 'speed_camera') camNodes[e['id'] as int] = e;
          if (tags['highway'] == 'traffic_signals') signalNodes.add(e);
        case 'relation':
          if (tags['type'] == 'enforcement') relations.add(e);
        case 'way':
          if (e['geometry'] is List) wayElements.add(e);
        case 'item':
          final w = _itemAsWay(e);
          if (w != null) wayElements.add(w);
      }
    });
  }

  // Wege, auf denen Blitzerknoten liegen, nach Knoten-ID.
  final camWays = <int, List<_Way>>{};
  final speedWays = <SpeedWay>[];
  for (final e in wayElements) {
    _guard(e, () {
      final way = _Way.from(e);
      if (way == null) return;
      if (withWays && keepsWay(way.tags)) speedWays.add(way.toSpeedWay());
      for (final id in way.nodeIds) {
        if (camNodes.containsKey(id)) (camWays[id] ??= []).add(way);
      }
    });
  }

  final points = <AlertPoint>[];

  // Relationen zuerst: ihre Geräte-Knoten werden nicht noch einmal einzeln ausgegeben.
  final deviceIds = <int>{};
  for (final rel in relations) {
    _guard(rel, () {
      final p = _relationPoint(rel, camNodes, camWays);
      if (p == null) return;
      points.addAll(p.points);
      deviceIds.addAll(p.deviceNodeIds);
    });
  }

  for (final entry in camNodes.entries) {
    _guard(entry.value, () {
      if (deviceIds.contains(entry.key)) return;
      final n = entry.value;
      final tags = _tags(n);
      final bearings = _nodeBearings(entry.key, n, camWays);
      final cls =
          classifyEnforcement(
            enforcement: enforcementValues(tags['enforcement']),
            tags: tags,
            tunnel: _inTunnel(entry.key, camWays) || tags['tunnel'] == 'yes',
            speedByDefault: true,
          ) ??
          const OsmClass(AlertKind.speedCamera, AlertCategory.fixedSpeed);
      final maxSpeed = cls.category.showsSpeed
          ? parseMaxspeed(tags['maxspeed'])
          : null;
      points.add(
        AlertPoint(
          id: 'osm:node/${entry.key}',
          kind: cls.kind,
          category: cls.category,
          position: GeoPoint(
            (n['lat'] as num).toDouble(),
            (n['lon'] as num).toDouble(),
          ),
          source: 'osm',
          travelBearings: bearings,
          maxSpeed: maxSpeed,
          label: tags['name'] ?? tags['ref'],
          details: buildOsmDetails(
            tags: tags,
            bearings: bearings,
            maxSpeed: maxSpeed,
            road: _road(entry.key, camWays),
          ),
          sources: [osmSource('node', entry.key, _timestamp(n))],
        ),
      );
    });
  }
  for (final n in signalNodes) {
    _guard(n, () {
      points.add(
        AlertPoint(
          id: 'osm:node/${n['id']}',
          kind: AlertKind.trafficSignal,
          position: GeoPoint(
            (n['lat'] as num).toDouble(),
            (n['lon'] as num).toDouble(),
          ),
          source: 'osm',
        ),
      );
    });
  }

  return ParsedOsm(points, speedWays);
}

/// Ein Weg aus der schlanken Abfrage (`convert item …`): Geometrie als GeoJSON (Länge, Breite),
/// Tags ohne die leeren Werte, die `convert` für fehlende Tags schreibt. Wird zum üblichen Weg-Element.
Map<String, dynamic>? _itemAsWay(Map<String, dynamic> e) {
  final g = e['geometry'];
  if (g is! Map) return null;
  var coords = g['coordinates'];
  // Geschlossene Wege (Kreisverkehr) können als Fläche kommen: dann der äußere Ring.
  if (g['type'] == 'Polygon' && coords is List && coords.isNotEmpty) {
    coords = coords.first;
  }
  if (coords is! List) return null;
  final tags = {
    for (final en in (e['tags'] as Map? ?? const {}).entries)
      if ('${en.value}'.isNotEmpty) '${en.key}': '${en.value}',
  };
  return {
    'type': 'way',
    'id': e['id'],
    'tags': tags,
    'geometry': [
      for (final c in coords)
        if (c is List && c.length >= 2) {'lat': c[1], 'lon': c[0]} else null,
    ],
  };
}

/// Führt die Auswertung eines Elements aus. Ein ungewöhnliches Element (fehlende Felder, falsche
/// Typen) wird übersprungen und gemeldet, statt die ganze Kachel zu verwerfen.
void _guard(Map<String, dynamic> element, void Function() body) {
  try {
    body();
  } catch (e) {
    osmLog('Element ${element['type']}/${element['id']} übersprungen: $e');
  }
}

Map<String, String> _tags(Map<String, dynamic> e) {
  final t = e['tags'];
  if (t is! Map) return const {};
  return {for (final en in t.entries) '${en.key}': '${en.value}'};
}

/// True, wenn der wichtigste Weg am Knoten ein Tunnel ist.
bool _inTunnel(int nodeId, Map<int, List<_Way>> camWays) =>
    (camWays[nodeId] ?? const []).any((w) => w.tags['tunnel'] == 'yes');

/// Zeitpunkt der letzten Bearbeitung (`out meta`), sonst null.
DateTime? _timestamp(Map<String, dynamic>? e) {
  final t = e?['timestamp'];
  return t is String ? DateTime.tryParse(t) : null;
}

/// Straße, an der der Knoten liegt: Name oder Kennung des wichtigsten Wegs, der eines hat.
String? _road(int nodeId, Map<int, List<_Way>> camWays) {
  final ways = [...?camWays[nodeId]]..sort((a, b) => a.rank.compareTo(b.rank));
  for (final w in ways) {
    final label = roadLabel(w.tags);
    if (label != null) return label;
  }
  return null;
}

GeoPoint? _latLon(Map<String, dynamic> m) {
  final lat = m['lat'], lon = m['lon'];
  if (lat is num && lon is num) return GeoPoint(lat.toDouble(), lon.toDouble());
  return null;
}

/// Weg mit Geometrie aus der Overpass-Antwort (`out geom`).
class _Way {
  _Way(this.id, this.tags, this.nodeIds, this.geometry);

  static _Way? from(Map<String, dynamic> e) {
    final tags = _tags(e);
    if (!motorRoadTypes.contains(tags['highway'])) return null;
    final geometry = <GeoPoint>[];
    for (final g in (e['geometry'] as List)) {
      // Lücken (null) kommen bei Ausschnitten vor; die Kette dann unvollständig lassen.
      final p = g is Map<String, dynamic> ? _latLon(g) : null;
      if (p == null) return null;
      geometry.add(p);
    }
    if (geometry.length < 2) return null;
    final nodeIds = [
      for (final n in (e['nodes'] as List? ?? const [])) n as int,
    ];
    return _Way(e['id'] as int, tags, nodeIds, geometry);
  }

  final int id;
  final Map<String, String> tags;
  final List<int> nodeIds;
  final List<GeoPoint> geometry;

  int get rank => motorRoadTypes.indexOf(tags['highway']!);

  /// 1 = Einbahn in Wegrichtung, -1 = dagegen, 0 = beidseitig.
  int get oneway => onewayOf(tags);

  SpeedWay toSpeedWay() => speedWayOf(tags, geometry, rank: rank);

  /// Index des Knotens in der Geometrie, sonst der Eckpunkt in höchstens 2 m Nähe.
  int? vertexIndex(int nodeId, GeoPoint pos) {
    final i = nodeIds.indexOf(nodeId);
    if (i >= 0 && i < geometry.length) return i;
    for (var k = 0; k < geometry.length; k++) {
      if (distanceMeters(geometry[k], pos) <= 2) return k;
    }
    return null;
  }

  /// Peilung in Wegrichtung am Eckpunkt [i].
  double bearingAt(int i) {
    final a = i + 1 < geometry.length ? geometry[i] : geometry[i - 1];
    final b = i + 1 < geometry.length ? geometry[i + 1] : geometry[i];
    return bearingDegrees(a, b);
  }
}

WayContext? _wayContext(
  int nodeId,
  GeoPoint pos,
  Map<int, List<_Way>> camWays,
) {
  final ways = camWays[nodeId];
  if (ways == null || ways.isEmpty) return null;
  final sorted = [...ways]..sort((a, b) => a.rank.compareTo(b.rank));
  for (final way in sorted) {
    final i = way.vertexIndex(nodeId, pos);
    if (i != null) {
      return WayContext(bearing: way.bearingAt(i), oneway: way.oneway);
    }
  }
  return null;
}

List<double> _nodeBearings(
  int id,
  Map<String, dynamic> node,
  Map<int, List<_Way>> camWays,
) {
  final tags = _tags(node);
  final pos = _latLon(node)!;
  return resolveNodeBearings(
    direction: tags['direction'],
    cameraDirection: tags['camera:direction'],
    way: _wayContext(id, pos, camWays),
  );
}
