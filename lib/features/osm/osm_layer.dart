import '../../core/geo/geo.dart';
import 'osm_category.dart';
import 'osm_parser.dart';
import 'osm_tile.dart';
import 'osm_way_limits.dart';

/// Rangniedrige Straßen, die nur in der zweiten Tempolimit-Schicht geladen werden.
final List<String> _minorRoads = minorRoadTypes.toList();

/// Dringlichkeit der Blitzer-Abfrage für die Kartenübersicht: nach allem, was die Fahrt braucht
/// (Blitzer, Tempolimits, Ampeln um die Position).
const int overviewPriority = 3;

/// Eine Datenschicht mit eigener Abfrage, eigenem Kachelgitter und eigener Dringlichkeit.
/// Die Reihenfolge der Werte ist die Abruf-Reihenfolge: Blitzer vor Ampeln vor Tempolimits.
///
/// Die Server sind oft überlastet. Darum ist die Blitzer-Abfrage klein (nur Knoten im Index und
/// das, was an ihnen hängt) und das Gitter grob (wenige Anfragen); die schweren Wegabfragen
/// laufen in feinen Kacheln und in zwei Stufen.
enum OsmLayer {
  /// Messstellen, ihre Enforcement-Relationen und die Wege, auf denen sie liegen (für die Richtung).
  cameras(
    perDegree: tilesPerDegree,
    queryTimeout: 60,
    httpTimeout: Duration(seconds: 75),
    maxTilesPerLoad: 400,
  ),

  /// Ampelknoten.
  signals(
    perDegree: tilesPerDegree,
    queryTimeout: 60,
    httpTimeout: Duration(seconds: 75),
    maxTilesPerLoad: 16,
  ),

  /// Tempolimit-Wege der Hauptstraßen samt Geometrie.
  limits(
    perDegree: fineTilesPerDegree,
    queryTimeout: 90,
    httpTimeout: Duration(seconds: 120),
    maxTilesPerLoad: 20,
  ),

  /// Tempolimit-Wege der Nebenstraßen (Wohnstraßen, Tempo-30-Zonen).
  minorLimits(
    perDegree: fineTilesPerDegree,
    queryTimeout: 90,
    httpTimeout: Duration(seconds: 120),
    maxTilesPerLoad: 20,
  );

  const OsmLayer({
    required this.perDegree,
    required this.queryTimeout,
    required this.httpTimeout,
    required this.maxTilesPerLoad,
  });

  final int perDegree;

  /// `[timeout:…]` der Overpass-Abfrage in Sekunden.
  final int queryTimeout;

  /// Wartezeit auf die HTTP-Antwort, danach folgt der Ausweich-Endpunkt.
  final Duration httpTimeout;

  /// So viele Kacheln fordert ein `load` höchstens an, die nächsten zuerst. Ein großer Umkreis lädt so
  /// nicht Hunderte schwerer Wegabfragen auf einmal; der Rest folgt, wenn man näher kommt.
  final int maxTilesPerLoad;

  /// Kleinere Zahl = dringender: Blitzer, dann die Tempolimits der eigenen Straße (beide Schichten
  /// gleich, damit die Zelle unter der Position vollständig zuerst kommt), dann Ampeln, dann
  /// [overviewPriority] für die Übersicht.
  int get priority => switch (this) {
    cameras => 0,
    limits || minorLimits => 1,
    signals => 2,
  };

  /// Schichten mit Tempolimit-Wegen für `speedLimitAt`.
  bool get hasWays => this == limits || this == minorLimits;
}

/// Overpass-QL für ein Rechteck (mit kleinem Rand gegen Rundungsfehler an der Kante).
/// Für mehrere benachbarte Kacheln ist das ihre gemeinsame Hülle.
String buildLayerQuery(OsmLayer layer, GeoBounds b) {
  const margin = 0.00002;
  String c(double v) => v.toStringAsFixed(5);
  final box =
      '(${c(b.south - margin)},${c(b.west - margin)},'
      '${c(b.north + margin)},${c(b.east + margin)})';
  String hw(Iterable<String> roads) => '["highway"~"^(${roads.join('|')})\$"]';
  final head = '[out:json][timeout:${layer.queryTimeout}];\n';
  switch (layer) {
    case OsmLayer.cameras:
      return '${head}node["highway"="speed_camera"]$box->.cams;\n'
          'rel(bn.cams)["type"="enforcement"]'
          '["enforcement"~"maxspeed|traffic_signals|average_speed|section_control"]'
          '->.enfCams;\n'
          // Höhen-, Gewichts-, Einfahrts- und Überholkontrollen haben keinen Blitzerknoten.
          'rel["type"="enforcement"]["enforcement"~"$otherEnforcementPattern"]'
          '$box->.enfOther;\n'
          '(.enfCams; .enfOther;)->.enf;\n'
          'way(bn.cams)${hw(motorRoadTypes)}->.camways;\n'
          '.cams out meta;\n'
          '.enf out geom meta;\n'
          '.camways out geom;\n';
    case OsmLayer.signals:
      return '${head}node["highway"="traffic_signals"]$box;\nout;\n';
    case OsmLayer.limits || OsmLayer.minorLimits:
      final minor = layer == OsmLayer.minorLimits;
      final roads = hw(
        minor
            ? _minorRoads
            : motorRoadTypes.where((r) => !_minorRoads.contains(r)),
      );
      return '$head(\n'
          '  way$roads["maxspeed"]$box;\n'
          '  way$roads["maxspeed:forward"]$box;\n'
          '  way$roads["maxspeed:backward"]$box;\n'
          // Verkehrsberuhigte Bereiche haben meist kein maxspeed: dort gilt Schrittgeschwindigkeit.
          '${minor ? '  way["highway"="living_street"]$box;\n' : ''}'
          // Rampen auch ohne Limit: für die Linie voraus, nie fürs Tempolimit.
          '${minor ? '' : '  way${hw(rampRoadTypes)}$box;\n'}'
          ');\n'
          // Nur die Angaben, die speedLimitAt und die Linie voraus brauchen, statt aller Tags
          // und Knoten-IDs. Fehlende Tags kommen als leerer Text zurück (siehe parseAll).
          'convert item ::id=id(), highway=t["highway"], maxspeed=t["maxspeed"], '
          '"maxspeed:forward"=t["maxspeed:forward"], '
          '"maxspeed:backward"=t["maxspeed:backward"], oneway=t["oneway"], '
          'junction=t["junction"], name=t["name"], ref=t["ref"], '
          '::geom=geom();\n'
          'out geom;\n';
  }
}
