import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../core/model/alert_point.dart';
import 'map_clusters.dart';
import 'map_point_layers.dart' show heatColor;
import 'point_hits.dart' show minTapSize;

/// Ab diesem Zoom stehen die genauen Stellen vergangener mobiler Blitzer als Punkte über der
/// Wärme. Weiter draußen lägen sie in der Stadt so dicht, dass sie zu einer roten Fläche
/// verklumpen; dort zeigt die Wärme allein, wo es sich häuft. Einen halben Zoom davor blenden
/// sie ein, statt aufzuspringen.
const heatDotMinZoom = 14.0;
const _fadeZoom = 0.5;

/// Gezeichneter Radius: klein und ohne Symbol, damit ihn niemand für einen aktuellen Blitzer
/// hält (die haben Form, Farbe und Rand). Bei Fahrt kleiner und blasser.
const heatDotRadius = 3.5;
const heatDotRadiusDriving = 2.5;

/// Deckkraft der Füllung: leicht durchsichtig, Straßen bleiben erkennbar.
const heatDotAlpha = 0.75;
const heatDotAlphaDriving = 0.5;

/// Stellen, die näher als so viele Bildpunkte beieinander liegen, zeigen einen Punkt. Das
/// Raster hängt an der Welt, nicht am Bildschirm: beim Verschieben springt nichts.
const _mergePx = 8.0;

/// Ein Punkt im Ausschnitt: Bildschirmlage und die Beobachtung dahinter.
class HeatDot {
  const HeatDot(this.center, this.point);

  final Offset center;
  final AlertPoint point;
}

/// Wie sichtbar die Punkte bei [zoom] sind: 0 unter [heatDotMinZoom] − [_fadeZoom], dann
/// ansteigend bis 1.
double heatDotFade(double zoom) =>
    ((zoom - (heatDotMinZoom - _fadeZoom)) / _fadeZoom).clamp(0.0, 1.0);

/// Genaue Stellen vergangener Beobachtungen im Ausschnitt. Aktuelle mobile Blitzer haben ihr
/// eigenes Symbol und fehlen hier.
List<HeatDot> heatDots(List<AlertPoint> heat, MapCamera camera) {
  if (heatDotFade(camera.zoom) <= 0) return const [];
  final view = (Offset.zero & camera.size).inflate(heatDotRadius * 2);
  final z = camera.zoom.floor();
  final taken = <(int, int)>{};
  final dots = <HeatDot>[];
  for (final p in heat) {
    if (!p.historical) continue;
    final w = worldPixel(p.position, z);
    if (!taken.add(((w.dx / _mergePx).floor(), (w.dy / _mergePx).floor()))) {
      continue;
    }
    final at = camera.latLngToScreenOffset(
      LatLng(p.position.lat, p.position.lon),
    );
    if (view.contains(at)) dots.add(HeatDot(at, p));
  }
  return dots;
}

/// Nächster Punkt unter dem Finger, innerhalb einer Tippfläche von [minTapSize]; sonst null.
HeatDot? heatDotAt(List<HeatDot> dots, Offset tap) {
  HeatDot? best;
  var bestDistance = minTapSize / 2;
  for (final d in dots) {
    final distance = (d.center - tap).distance;
    if (distance <= bestDistance) {
      best = d;
      bestDistance = distance;
    }
  }
  return best;
}

/// Kleine rote Punkte an den Stellen, an denen früher mobil geblitzt wurde, über der Wärme und
/// unter den Symbolen. Angetippt wird über die Karte ([heatDotAt]).
class HeatDotLayer extends StatelessWidget {
  const HeatDotLayer({super.key, required this.heat, this.driving = false});

  /// Punkte der Wärme-Ebene ([heatPoints]).
  final List<AlertPoint> heat;
  final bool driving;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final fade = heatDotFade(camera.zoom);
    if (heat.isEmpty || fade <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: HeatDotPainter(
            [for (final d in heatDots(heat, camera)) d.center],
            radius: driving ? heatDotRadiusDriving : heatDotRadius,
            alpha: (driving ? heatDotAlphaDriving : heatDotAlpha) * fade,
          ),
        ),
      ),
    );
  }
}

class HeatDotPainter extends CustomPainter {
  HeatDotPainter(this.centers, {required this.radius, required this.alpha});

  final List<Offset> centers;
  final double radius;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    // Dunkler Rand trennt den Punkt vom roten Fleck darunter.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = SonarColors.bg.withValues(alpha: alpha * 0.8);
    final fill = Paint()..color = heatColor.withValues(alpha: alpha);
    for (final c in centers) {
      canvas.drawCircle(c, radius, fill);
      canvas.drawCircle(c, radius + 0.75, rim);
    }
  }

  @override
  bool shouldRepaint(HeatDotPainter old) =>
      old.centers != centers || old.radius != radius || old.alpha != alpha;
}
