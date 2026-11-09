import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/map_layer_settings.dart';
import '../../core/model/alert_point.dart';
import 'map_clusters.dart';
import 'map_heat.dart';
import 'map_layers.dart';
import 'map_pins.dart';
import 'map_point_layers.dart' show heatMinRadiusPx;
import 'map_tilt.dart';
import 'symbols/category_symbol.dart';

/// Kleinste Tippfläche um einen Punkt, auch wenn sein Symbol kleiner gezeichnet ist.
const minTapSize = 48.0;

/// Fläche [drawn], mindestens [minTapSize] groß, um dieselbe Mitte.
Rect atLeastTapSize(Rect drawn) => Rect.fromCenter(
  center: drawn.center,
  width: math.max(drawn.width, minTapSize),
  height: math.max(drawn.height, minTapSize),
);

/// Punkte unter dem Finger auf der flachen Karte, nächstes Bündel zuerst. [tap] liegt in
/// Kartenkoordinaten. Getroffen ist, wer sein Symbol (Spitze am Ort, Fläche darüber) unter dem
/// Finger hat; ein Bündel liefert alle seine Punkte.
List<AlertPoint> flatHits({
  required List<AlertPoint> points,
  required Set<MapLayer> layers,
  required MapCamera camera,
  required Offset tap,
}) {
  final size = markerSizeForZoom(camera.zoom);
  final hits = <(MarkerGroup, double)>[];
  for (final g in clusterPoints(points, layers, camera.zoom)) {
    final at = camera.latLngToScreenOffset(
      LatLng(g.lead.position.lat, g.lead.position.lon),
    );
    final l = categorySymbolLayout(g.lead.effectiveCategory, size: size);
    final drawn = Rect.fromLTWH(
      at.dx - l.ground.dx + g.spread * l.box.width * 1.05,
      at.dy - l.ground.dy,
      l.box.width,
      l.box.height,
    );
    if (atLeastTapSize(drawn).contains(tap)) {
      hits.add((g, (drawn.center - tap).distance));
    }
  }
  hits.sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final h in hits) ...h.$1.members];
}

/// Fläche eines aufrechten Symbols im Ausschnitt, mindestens [minTapSize] groß.
Rect pinTapRect(AlertPoint point, Offset tip, double scale) =>
    atLeastTapSize(uprightRect(point, tip, scale));

/// Punkte unter dem Finger auf der geneigten Karte. [tap] liegt im Ausschnitt. Vordere Bündel
/// (weiter unten im Bild) zuerst, denn sie liegen oben. Dieselben Bündel wie [placePins].
List<AlertPoint> tiltedHits({
  required List<AlertPoint> points,
  required Set<MapLayer> layers,
  required MapCamera camera,
  required TiltGeometry tilt,
  required Offset tap,
}) {
  final pins = placePins(
    points: points,
    layers: layers,
    camera: camera,
    tilt: tilt,
  ).reversed;
  return [
    for (final pin in pins)
      if (pinTapRect(pin.point, pin.tip, pin.scale).contains(tap))
        ...pin.group.members,
  ];
}

/// Wärmezelle unter dem Finger auf der flachen Karte: die nächste, deren Mitte näher liegt als
/// gut die Hälfte ihres gemalten Radius (dort ist der Fleck sichtbar), sonst null.
HeatCell? heatCellAt({
  required List<HeatCell> cells,
  required MapCamera camera,
  required Offset tap,
}) {
  HeatCell? best;
  var bestDistance = double.infinity;
  for (final c in cells) {
    final radius = (heatSpotMeters / metersPerPixel(c.center.lat, camera.zoom))
        .clamp(heatMinRadiusPx, heatMaxRadiusPx);
    final at = camera.latLngToScreenOffset(LatLng(c.center.lat, c.center.lon));
    final d = (at - tap).distance;
    if (d <= math.max(radius * 0.6, minTapSize / 2) && d < bestDistance) {
      best = c;
      bestDistance = d;
    }
  }
  return best;
}
