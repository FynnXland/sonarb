import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../core/model/alert_point.dart';

/// Blitzer-Hotspots, aus denselben vergangenen Beobachtungen und mit denselben Schwellen wie die
/// Ansage „Blitzer-Hotspot“. Kommt von außen (`AppServices.heatSpots`), weil die Karte die
/// Warnlogik nicht importiert.
typedef HeatSpotFinder = List<AlertPoint> Function(
  List<AlertPoint> points,
  DateTime now,
);

/// Außenradius des Rings in Bildpunkten, vor der Neigung. Liegt flach auf der Karte und wird
/// mit ihr gestaucht: ein Oval auf der Straße, kein aufrechtes Zeichen wie ein Blitzer.
const heatSpotRingRadius = 18.0;

/// Wo die Ansage „Blitzer-Hotspot“ herkommt: ein roter Ring mit Punkt, flach auf der Straße.
/// Für die geneigte Fahrtansicht, in der die einzelnen roten Punkte ausgeblendet sind. Zeichnet
/// nur neu, wenn sich Karte oder Hotspots ändern; keine eigene Animation.
class HeatSpotLayer extends StatelessWidget {
  const HeatSpotLayer({super.key, required this.spots});

  final List<AlertPoint> spots;

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    final view = (Offset.zero & camera.size).inflate(heatSpotRingRadius * 2);
    final centers = [
      for (final s in spots)
        if (camera.latLngToScreenOffset(LatLng(s.position.lat, s.position.lon))
            case final at when view.contains(at))
          at,
    ];
    if (centers.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(painter: HeatSpotPainter(centers)),
      ),
    );
  }
}

class HeatSpotPainter extends CustomPainter {
  HeatSpotPainter(this.centers);

  final List<Offset> centers;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = SonarColors.red.withValues(alpha: 0.18);
    // Dunkler Rand außen trennt den Ring von der roten Wärme darunter.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = SonarColors.bg.withValues(alpha: 0.55);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = SonarColors.red;
    final dot = Paint()..color = SonarColors.red;
    for (final c in centers) {
      canvas.drawCircle(c, heatSpotRingRadius, fill);
      canvas.drawCircle(c, heatSpotRingRadius, edge);
      canvas.drawCircle(c, heatSpotRingRadius, ring);
      canvas.drawCircle(c, 4, dot);
    }
  }

  @override
  bool shouldRepaint(HeatSpotPainter old) => !_same(old.centers, centers);

  static bool _same(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
