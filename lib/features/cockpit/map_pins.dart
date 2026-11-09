import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/map_layer_settings.dart';
import '../../app/theme.dart';
import '../../core/model/alert_point.dart';
import 'map_clusters.dart';
import 'map_point_layers.dart';
import 'map_tilt.dart';
import 'symbols/category_symbol.dart';

/// Durchmesser des Nadelkopfs am Drehpunkt der geneigten Karte. Breite Formen werden breiter,
/// die Fläche liefert [uprightLayout].
const pinUnit = 26.0;

/// Nadeln hinten werden kleiner, aber nicht unleserlich; vorn nicht größer als am Drehpunkt.
const _minPinScale = 0.55;
const _maxPinScale = 1.0;

/// Fläche und Bodenpunkt eines aufrechten Symbols bei [pinUnit].
SymbolLayout uprightLayout(AlertPoint p) =>
    categorySymbolLayout(p.effectiveCategory, size: pinUnit, upright: true);

/// Höhe der höchsten Nadel, für den Rand unter dem Dunst.
final double _tallest = categorySymbolLayout(
  AlertCategory.fixedSpeed,
  size: pinUnit,
  upright: true,
).box.height;

/// Maßstab einer Nadel am Kartenpunkt [inMap] der gerenderten Karte.
double pinScaleAt(TiltGeometry tilt, Offset inMap) =>
    tilt.scaleAt(inMap).clamp(_minPinScale, _maxPinScale);

/// Nadeln dicht unter dem Dunst oder am oberen Rand würden angeschnitten: darüber keine.
double pinMinY(TiltGeometry tilt) => tilt.horizonY + _tallest * 0.6;

/// Fläche eines aufrechten Symbols im Ausschnitt: Bodenpunkt bei [tip], Maßstab [scale].
Rect uprightRect(AlertPoint p, Offset tip, double scale) {
  final l = uprightLayout(p);
  return Rect.fromLTWH(
    tip.dx - l.ground.dx * scale,
    tip.dy - l.ground.dy * scale,
    l.box.width * scale,
    l.box.height * scale,
  );
}

/// Ein aufrechtes Bündel im Ausschnitt: Bodenpunkt bei [tip], Maßstab [scale].
class PlacedPin {
  const PlacedPin(this.group, this.tip, this.scale);

  final MarkerGroup group;
  final Offset tip;
  final double scale;

  AlertPoint get point => group.lead;
}

/// Setzt die Bündel ([clusterPoints], dasselbe Raster wie flach) als aufrechte Symbole in den
/// Ausschnitt der geneigten Karte: nur sichtbare unterhalb des Dunsts, hintere zuerst (vordere
/// liegen oben). Bündel derselben Zelle stehen nebeneinander.
List<PlacedPin> placePins({
  required List<AlertPoint> points,
  required Set<MapLayer> layers,
  required MapCamera camera,
  required TiltGeometry tilt,
}) {
  final view = Offset.zero & tilt.viewport;
  final minY = pinMinY(tilt);
  final placed = <PlacedPin>[];
  for (final g in clusterPoints(points, layers, camera.zoom)) {
    final inMap = camera.latLngToScreenOffset(
      LatLng(g.lead.position.lat, g.lead.position.lon),
    );
    final scale = pinScaleAt(tilt, inMap);
    final width = uprightLayout(g.lead).box.width * scale;
    final tip = tilt.project(inMap) + Offset(g.spread * width * 1.05, 0);
    if (tip.dy < minY || !view.inflate(pinUnit * 1.5).contains(tip)) continue;
    placed.add(PlacedPin(g, tip, scale));
  }
  return placed..sort((a, b) => a.tip.dy.compareTo(b.tip.dy));
}

/// Aufrechte Symbole über der geneigten Karte, Spitze bzw. Pfosten am Bodenpunkt. Fängt keine
/// Berührungen ab: das Antippen läuft über die Karte (`point_hits.dart`).
class PinOverlay extends StatelessWidget {
  const PinOverlay({super.key, required this.pins});

  final List<PlacedPin> pins;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        for (final pin in pins)
          if (uprightLayout(pin.point) case final l)
            Positioned(
              key: ValueKey(pin.point.id),
              left: pin.tip.dx - l.ground.dx,
              top: pin.tip.dy - l.ground.dy,
              width: l.box.width,
              height: l.box.height,
              child: Transform.scale(
                scale: pin.scale,
                // Um den Bodenpunkt, damit die Spitze beim Verkleinern am Ort bleibt.
                alignment: -l.markerAlignment,
                child: GroupSymbol(
                  group: pin.group,
                  size: pinUnit,
                  upright: true,
                ),
              ),
            ),
      ],
    ),
  );
}

/// Dunst am Horizont: verdeckt das Ende der gerenderten Karte und lässt die Ferne auslaufen.
class TiltHaze extends StatelessWidget {
  const TiltHaze({super.key, required this.geometry});

  final TiltGeometry geometry;

  @override
  Widget build(BuildContext context) {
    final edge = geometry.horizonY.clamp(0.0, geometry.viewport.height);
    // Kurzer Auslauf: auf der höheren Karte soll vorn möglichst viel Strecke sichtbar bleiben.
    final height = edge + geometry.viewport.height * 0.1;
    final solid = SonarColors.bg.withValues(alpha: geometry.t);
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [solid, solid, SonarColors.bg.withValues(alpha: 0)],
              stops: [0, edge / height, 1],
            ),
          ),
        ),
      ),
    );
  }
}
