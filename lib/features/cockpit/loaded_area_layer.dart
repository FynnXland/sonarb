import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/geo/geo.dart';
import 'map_layers.dart';

/// Blau des Datenumkreises. Eigene Farbe, weil keine Warnstufe gemeint ist: Blau kommt sonst
/// nirgends vor und liest sich als neutrale Auskunft. 7,6:1 gegen den App-Grund.
const loadedAreaColor = Color(0xFF6CB4FF);

/// Strichlänge und Lücke des Kreises, solange der Umkreis noch lädt.
const _dash = 10.0;
const _gap = 8.0;

/// Mehr Striche malt der Kreis nicht: bei 50 km und nahem Zoom liegt ohnehin nur ein kurzes
/// Stück im Bild, die übrigen werden vorher verworfen.
const _maxDashes = 20000;

/// Der Umkreis, in dem alle Daten vorliegen: ein Kreis um die eigene Position mit dem Radius aus
/// den Einstellungen. Er wandert beim Fahren mit. Solange geladen wird, ist er gestrichelt.
class DataRadiusLayer extends StatelessWidget {
  const DataRadiusLayer({
    super.key,
    required this.center,
    required this.radiusMeters,
    this.loading = false,
  });

  final GeoPoint center;
  final double radiusMeters;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final at = camera.latLngToScreenOffset(LatLng(center.lat, center.lon));
    final radius = radiusMeters / metersPerPixel(center.lat, camera.zoom);
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: DataRadiusPainter(
            center: at,
            radius: radius,
            loading: loading,
          ),
        ),
      ),
    );
  }
}

class DataRadiusPainter extends CustomPainter {
  DataRadiusPainter({
    required this.center,
    required this.radius,
    required this.loading,
  });

  final Offset center;
  final double radius;
  final bool loading;

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0 || !radius.isFinite) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = loadedAreaColor.withValues(alpha: 0.06),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = loadedAreaColor.withValues(alpha: loading ? 0.6 : 0.8);
    if (!loading) {
      canvas.drawCircle(center, radius, stroke);
      return;
    }
    for (final (a, b) in dashSegments(center, radius, Offset.zero & size)) {
      canvas.drawLine(a, b, stroke);
    }
  }

  @override
  bool shouldRepaint(DataRadiusPainter old) =>
      old.center != center || old.radius != radius || old.loading != loading;
}

/// Striche des gestrichelten Kreises, nur die im Bild [view]. Bei sehr großen Kreisen wird der
/// Abstand der Striche so gestreckt, dass höchstens [_maxDashes] durchgerechnet werden.
List<(Offset, Offset)> dashSegments(Offset center, double radius, Rect view) {
  final circumference = 2 * math.pi * radius;
  final count = math.min(_maxDashes, (circumference / (_dash + _gap)).floor());
  if (count < 2) return const [];
  final step = 2 * math.pi / count;
  final dashAngle = step * _dash / (_dash + _gap);
  final visible = view.inflate(_dash);
  Offset onCircle(double a) =>
      center + Offset(math.cos(a) * radius, math.sin(a) * radius);
  return [
    for (var i = 0; i < count; i++)
      if (onCircle(i * step) case final a when visible.contains(a))
        (a, onCircle(i * step + dashAngle)),
  ];
}

/// Symbol der Ebene in den Einstellungen: blauer Kreis um einen Punkt.
class LoadedAreaSymbolPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.4;
    canvas.drawCircle(
      c,
      r,
      Paint()..color = loadedAreaColor.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = loadedAreaColor,
    );
    canvas.drawCircle(c, size.width * 0.09, Paint()..color = loadedAreaColor);
  }

  @override
  bool shouldRepaint(LoadedAreaSymbolPainter old) => false;
}
