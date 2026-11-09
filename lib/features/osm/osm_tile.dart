import 'dart:math' as math;

import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import 'osm_details.dart';

/// Kacheln pro Grad im groben Gitter (0,1° × 0,1°) für Blitzer und Ampeln.
const int tilesPerDegree = 10;

/// Kacheln pro Grad im feinen Gitter (0,05° × 0,05°) für Tempolimit-Wege.
const int fineTilesPerDegree = 20;

/// Kachel in einem Gitter mit [perDegree] Zellen je Grad. [ix] = Längen-, [iy] = Breitenindex.
class TileId {
  const TileId(this.ix, this.iy, [this.perDegree = tilesPerDegree]);

  factory TileId.of(double lat, double lon, [int perDegree = tilesPerDegree]) =>
      TileId((lon * perDegree).floor(), (lat * perDegree).floor(), perDegree);

  final int ix;
  final int iy;
  final int perDegree;

  String get key => '${iy}_$ix';

  GeoBounds get bounds => GeoBounds(
    south: iy / perDegree,
    west: ix / perDegree,
    north: (iy + 1) / perDegree,
    east: (ix + 1) / perDegree,
  );

  GeoPoint get center => bounds.center;

  /// Abstand von [p] zur Kachel in Metern; 0, wenn [p] darin liegt.
  double distanceTo(GeoPoint p) {
    final b = bounds;
    return distanceMeters(
      p,
      GeoPoint(
        p.lat.clamp(b.south, b.north).toDouble(),
        p.lon.clamp(b.west, b.east).toDouble(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TileId &&
      other.ix == ix &&
      other.iy == iy &&
      other.perDegree == perDegree;

  @override
  int get hashCode => Object.hash(ix, iy, perDegree);

  @override
  String toString() => 'TileId($key/$perDegree)';
}

/// Alle Kacheln, die [area] überdecken, die nächste zur Mitte zuerst (höchstens [maxTiles]).
List<TileId> tilesCovering(
  GeoBounds area, {
  int perDegree = tilesPerDegree,
  int maxTiles = 64,
}) {
  final south = math.min(area.south, area.north);
  final north = math.max(area.south, area.north);
  final west = math.min(area.west, area.east);
  final east = math.max(area.west, area.east);
  final tiles = <TileId>[
    for (
      var iy = (south * perDegree).floor();
      iy <= (north * perDegree).floor();
      iy++
    )
      for (
        var ix = (west * perDegree).floor();
        ix <= (east * perDegree).floor();
        ix++
      )
        TileId(ix, iy, perDegree),
  ];
  final c = area.center;
  final dist = {for (final t in tiles) t: t.distanceTo(c)};
  tiles.sort((a, b) {
    final byEdge = dist[a]!.compareTo(dist[b]!);
    return byEdge != 0
        ? byEdge
        : distanceMeters(c, a.center).compareTo(distanceMeters(c, b.center));
  });
  return tiles.length <= maxTiles ? tiles : tiles.sublist(0, maxTiles);
}

/// Straßenabschnitt mit Tempolimit. Richtungen beziehen sich auf die Geometrie-Reihenfolge.
class SpeedWay {
  SpeedWay({
    required this.points,
    this.forward,
    this.backward,
    this.oneway = 0,
    this.rank,
    this.minor,
    this.name,
    this.ref,
    this.limitTagged = true,
  }) : minLat = points.map((p) => p.lat).reduce(math.min),
       maxLat = points.map((p) => p.lat).reduce(math.max),
       minLon = points.map((p) => p.lon).reduce(math.min),
       maxLon = points.map((p) => p.lon).reduce(math.max);

  factory SpeedWay.fromJson(Map<String, dynamic> j) {
    final g = (j['g'] as List).cast<num>();
    return SpeedWay(
      points: [
        for (var i = 0; i + 1 < g.length; i += 2)
          GeoPoint(g[i].toDouble(), g[i + 1].toDouble()),
      ],
      forward: (j['f'] as num?)?.toInt(),
      backward: (j['b'] as num?)?.toInt(),
      oneway: (j['o'] as num?)?.toInt() ?? 0,
      // Ohne Klasse (Cache vor wayDetailVersion 5): bleibt unbekannt, keine Linie voraus.
      rank: (j['h'] as num?)?.toInt(),
      minor: j['h'] == null ? null : j['mi'] == 1,
      name: j['n'] as String?,
      ref: j['r'] as String?,
      limitTagged: j['u'] != 1,
    );
  }

  final List<GeoPoint> points;

  /// Limit in km/h in bzw. gegen die Wegrichtung; null = unbekannt, `speedWayNoLimit` (−1) =
  /// ausdrücklich keines (`maxspeed=none`).
  final int? forward;
  final int? backward;

  /// 0 = beidseitig, 1 = nur in Wegrichtung, -1 = nur dagegen.
  final int oneway;

  /// Rang der Straßenart (Index in `motorRoadTypes`, 0 = Autobahn), null = unbekannt (Paket,
  /// alter Cache).
  final int? rank;

  /// Nebenstraße (`minorRoadTypes`)? Null = unbekannt (alter Cache). Pakete kennen nur das.
  final bool? minor;

  /// `name` und `ref` aus OSM, für die Fortsetzung an Kreuzungen.
  final String? name;
  final String? ref;

  /// Trägt der Weg ein Tempolimit? Rampen ohne `maxspeed` sind nur für die Linie voraus geladen
  /// und zählen beim Tempolimit nie.
  final bool limitTagged;

  /// Klasse bekannt (genau oder nur Haupt- und Nebenstraße): Daraus lässt sich die Linie voraus
  /// bilden.
  bool get classKnown => rank != null || minor != null;

  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  Map<String, dynamic> toJson() => {
    'g': [
      for (final p in points) ...[p.lat, p.lon],
    ],
    if (forward != null) 'f': forward,
    if (backward != null) 'b': backward,
    if (oneway != 0) 'o': oneway,
    if (rank != null) 'h': rank,
    if (minor == true) 'mi': 1,
    if (name != null) 'n': name,
    if (ref != null) 'r': ref,
    if (!limitTagged) 'u': 1,
  };
}

/// Geparster Inhalt einer Kachel, so wird er auch im Cache abgelegt.
class TileData {
  const TileData({
    required this.fetchedAt,
    required this.points,
    required this.ways,
    this.detailVersion = 0,
    this.partial = false,
  });

  static const int formatVersion = 1;

  final DateTime fetchedAt;
  final List<AlertPoint> points;
  final List<SpeedWay> ways;

  /// 0 = Kachel aus einer Fassung ohne Punkt-Details, sonst [pointDetailVersion].
  final int detailVersion;

  /// Aus einer Länderabfrage an der Landesgrenze: Punkte jenseits der Grenze fehlen vielleicht.
  /// Die Kachel zeigt, was da ist, gilt aber als veraltet und wird beim nächsten Besuch ergänzt.
  final bool partial;

  Map<String, dynamic> toJson() => {
    'v': formatVersion,
    if (detailVersion > 0) 'x': detailVersion,
    if (partial) 'pt': 1,
    't': fetchedAt.millisecondsSinceEpoch,
    'p': [for (final p in points) _pointToJson(p)],
    'w': [for (final w in ways) w.toJson()],
  };

  /// Wirft bei falscher Version oder kaputtem Inhalt; der Aufrufer wertet das als „fehlt“.
  factory TileData.fromJson(Map<String, dynamic> j) {
    if (j['v'] != formatVersion) {
      throw const FormatException('Kachelformat unbekannt');
    }
    return TileData(
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        j['t'] as int,
        isUtc: true,
      ),
      points: [
        for (final p in (j['p'] as List))
          _pointFromJson(p as Map<String, dynamic>),
      ],
      ways: [
        for (final w in (j['w'] as List))
          SpeedWay.fromJson(w as Map<String, dynamic>),
      ],
      detailVersion: (j['x'] as num?)?.toInt() ?? 0,
      partial: j['pt'] == 1,
    );
  }
}

Map<String, dynamic> _pointToJson(AlertPoint p) => {
  'i': p.id,
  'k': p.kind.name,
  'la': p.position.lat,
  'lo': p.position.lon,
  if (p.travelBearings.isNotEmpty) 'b': p.travelBearings,
  if (p.maxSpeed != null) 'm': p.maxSpeed,
  if (p.label != null) 'l': p.label,
  if (p.category != null) 'c': p.category!.name,
  if (p.details.isNotEmpty)
    'd': [
      for (final d in p.details) [d.label, d.value],
    ],
  if (p.sources.isNotEmpty)
    'q': [
      for (final q in p.sources)
        {
          if (q.updatedAt != null) 't': q.updatedAt!.millisecondsSinceEpoch,
          if (q.url != null) 'u': q.url,
        },
    ],
};

AlertPoint _pointFromJson(Map<String, dynamic> j) => AlertPoint(
  id: j['i'] as String,
  kind: AlertKind.values.byName(j['k'] as String),
  position: GeoPoint((j['la'] as num).toDouble(), (j['lo'] as num).toDouble()),
  source: 'osm',
  travelBearings: [
    for (final b in (j['b'] as List? ?? const [])) (b as num).toDouble(),
  ],
  maxSpeed: (j['m'] as num?)?.toInt(),
  label: j['l'] as String?,
  category: AlertCategory.values.asNameMap()[j['c']],
  details: [
    for (final d in (j['d'] as List? ?? const []))
      PointDetail((d as List)[0] as String, d[1] as String),
  ],
  sources: [
    for (final q in (j['q'] as List? ?? const []))
      osmSourceAt(
        (q as Map)['u'] as String?,
        q['t'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(q['t'] as int, isUtc: true),
      ),
  ],
);
