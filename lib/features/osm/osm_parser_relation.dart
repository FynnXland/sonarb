part of 'osm_parser.dart';

class _RelationResult {
  _RelationResult(this.points, this.deviceNodeIds);

  /// Anfang der Kontrolle, bei Abschnittskontrollen mit bekanntem Ende dazu ein zweiter Punkt.
  final List<AlertPoint> points;
  final Set<int> deviceNodeIds;
}

/// Mitte einer Geometrie (Wegmitglied) bzw. die Knotenposition.
GeoPoint? _memberPosition(Map<String, dynamic> m) {
  final p = _latLon(m);
  if (p != null) return p;
  final g = m['geometry'];
  if (g is List && g.isNotEmpty) {
    final mid = g[g.length ~/ 2];
    if (mid is Map<String, dynamic>) return _latLon(mid);
  }
  return null;
}

_RelationResult? _relationPoint(
  Map<String, dynamic> rel,
  Map<int, Map<String, dynamic>> camNodes,
  Map<int, List<_Way>> camWays,
) {
  final tags = _tags(rel);

  GeoPoint? devicePos, fromPos, toPos;
  int? deviceNodeId;
  final deviceNodeIds = <int>{};
  for (final m in (rel['members'] as List? ?? const [])) {
    if (m is! Map<String, dynamic>) continue;
    final pos = _memberPosition(m);
    switch (m['role']) {
      case 'device':
        if (m['type'] == 'node' && m['ref'] is int) {
          deviceNodeIds.add(m['ref'] as int);
        }
        if (devicePos == null && pos != null) {
          devicePos = pos;
          if (m['type'] == 'node') deviceNodeId = m['ref'] as int?;
        }
      case 'from':
        fromPos ??= pos;
      case 'to':
        toPos ??= pos;
    }
  }

  final deviceNode = deviceNodeId == null ? null : camNodes[deviceNodeId];
  // Angaben der Relation gehen vor, der Geräteknoten ergänzt sie.
  final allTags = {...?deviceNode == null ? null : _tags(deviceNode), ...tags};
  final cls = classifyEnforcement(
    enforcement: enforcementValues(tags['enforcement']),
    tags: allTags,
    tunnel:
        (deviceNodeId != null && _inTunnel(deviceNodeId, camWays)) ||
        allTags['tunnel'] == 'yes',
  );
  if (cls == null) return null;

  final isSection = cls.kind == AlertKind.sectionControl;
  final position = isSection ? (fromPos ?? devicePos) : (devicePos ?? fromPos);
  if (position == null) return null;

  // Messstelle: von „from“ zum Gerät; Abschnittskontrolle: von „from“ nach „to“.
  var bearings = bearingFromTo(
    fromPos,
    isSection ? (toPos ?? devicePos) : (devicePos ?? toPos),
  );
  if (bearings.isEmpty && deviceNode != null) {
    bearings = _nodeBearings(deviceNodeId!, deviceNode, camWays);
  }
  final maxSpeed = cls.category.showsSpeed
      ? parseMaxspeed(allTags['maxspeed'])
      : null;
  final stamps = [
    _timestamp(rel),
    _timestamp(deviceNode),
  ].whereType<DateTime>();
  final source = osmSource(
    'relation',
    rel['id'],
    stamps.isEmpty ? null : stamps.reduce((a, b) => a.isAfter(b) ? a : b),
  );
  final details = buildOsmDetails(
    tags: allTags,
    bearings: bearings,
    maxSpeed: maxSpeed,
    road: deviceNodeId == null ? null : _road(deviceNodeId, camWays),
  );

  final start = AlertPoint(
    id: 'osm:relation/${rel['id']}',
    kind: cls.kind,
    category: cls.category,
    position: position,
    source: 'osm',
    travelBearings: bearings,
    maxSpeed: maxSpeed,
    label: tags['name'] ?? tags['ref'],
    details: details,
    sources: [source],
  );
  return _RelationResult([
    start,
    // Das Ende einer Abschnittskontrolle ist eine eigene Stelle auf der Karte.
    if (isSection && toPos != null)
      start.copyWith(
        id: '${start.id}#end',
        category: AlertCategory.sectionEnd,
        position: toPos,
      ),
  ], deviceNodeIds);
}
