import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/sonar_mark.dart';
import '../../app/theme.dart';

/// Eigene Position: Pfeil in Kursrichtung mit schwachem Peilkeil davor, ohne Kurs ein Punkt,
/// darum ein ruhiger Ring. Ohne Animation: ein dauernd wandernder Ring ließ die ganze Karte mit
/// voller Bildrate neu zeichnen, auch im Stand.
/// [rotationDeg] ist die Drehung relativ zur Bildschirmoberkante.
class OwnPositionMarker extends StatelessWidget {
  const OwnPositionMarker({
    super.key,
    required this.rotationDeg,
    this.size = 76,
  });

  final double? rotationDeg;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Eigene Position',
    child: CustomPaint(
      size: Size.square(size),
      painter: _OwnPainter(rotationDeg),
    ),
  );
}

class _OwnPainter extends CustomPainter {
  const _OwnPainter(this.rotationDeg);

  final double? rotationDeg;

  /// Stand des Rings zwischen innen (0) und außen (1).
  static const _ring = 0.4;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final c = Offset(w / 2, w / 2);

    const p = _ring;
    canvas.drawCircle(
      c,
      w * 0.12 + w * 0.38 * p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = SonarColors.amber.withValues(alpha: 0.5 * (1 - p)),
    );

    final r = rotationDeg;
    // Pfeil und Punkt bleiben so groß wie im Entwurf mit 34 dp, auch wenn die Fläche größer ist.
    const u = 34.0;
    final fill = Paint()..color = SonarColors.text;
    final edge = Paint()
      ..color = SonarColors.bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    if (r == null) {
      canvas.drawCircle(c, u * 0.26, edge);
      canvas.drawCircle(c, u * 0.26, fill);
      return;
    }
    final angle = r * math.pi / 180;
    paintBeam(canvas, c, w * 0.48, angle, maxAlpha: 0.35);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final arrow = Path()
      ..moveTo(0, -u * 0.46)
      ..lineTo(u * 0.34, u * 0.36)
      ..lineTo(0, u * 0.18)
      ..lineTo(-u * 0.34, u * 0.36)
      ..close();
    canvas.drawPath(arrow, edge);
    canvas.drawPath(arrow, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OwnPainter old) => old.rotationDeg != rotationDeg;
}
