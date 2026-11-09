import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'slow_loop.dart';

import 'theme.dart';

/// Sonar-Motiv wie im Launcher-Icon: zwei Ringe, Punkt und ein Peilkeil, der nach oben zeigt.
/// [sweep] dreht den Keil (in Umdrehungen, 0 = nach oben).
class SonarMark extends StatelessWidget {
  const SonarMark({super.key, this.size = 164, this.sweep});

  /// Durchmesser des äußeren Rings.
  final double size;
  final Animation<double>? sweep;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter(sweep)),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.sweep) : super(repaint: sweep);

  final Animation<double>? sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final stroke = size.width * 0.04;
    final r = size.width / 2 - stroke / 2;
    final turns = sweep?.value ?? 0;

    paintBeam(canvas, c, r, turns * 2 * math.pi);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(c, r, ring..color = SonarColors.amber);
    canvas.drawCircle(
      c,
      r * 0.63,
      ring..color = SonarColors.amber.withAlpha(170),
    );
    canvas.drawCircle(c, r * 0.185, Paint()..color = SonarColors.amber);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.sweep != sweep;
}

/// Zeichnet den Peilkeil: 56 Grad breit, nach außen verblassend. [angle] dreht im Uhrzeigersinn.
void paintBeam(
  Canvas canvas,
  Offset center,
  double radius,
  double angle, {
  double maxAlpha = 0.7,
}) {
  const width = 56 * math.pi / 180;
  final rect = Rect.fromCircle(center: center, radius: radius);
  final path = Path()
    ..moveTo(center.dx, center.dy)
    ..arcTo(rect, -math.pi / 2 - width / 2 + angle, width, false)
    ..close();
  final paint = Paint()
    ..shader = RadialGradient(
      colors: [
        SonarColors.amber.withValues(alpha: maxAlpha),
        SonarColors.amber.withValues(alpha: maxAlpha * 0.1),
      ],
    ).createShader(rect);
  canvas.drawPath(path, paint);
}

/// Ringe, die vom Mittelpunkt nach außen wandern und verblassen: „Sonar lauscht“.
/// Pulsiert beim Erscheinen [_pulses]-mal mit höchstens 10 Bildern je Sekunde, danach (und ohne
/// Animation) stehen die Ringe still.
class SonarPulse extends StatefulWidget {
  const SonarPulse({super.key, this.size = 96});

  final double size;

  @override
  State<SonarPulse> createState() => _SonarPulseState();
}

const _pulses = 2;

class _SonarPulseState extends State<SonarPulse> {
  final _c = SlowLoop(period: SonarMotion.standbyRing);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop(rest: 0.3);
    } else {
      _c.start(count: _pulses);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(child: CustomPaint(painter: _PulsePainter(_c))),
    ),
  );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t) : super(repaint: t);

  final ValueListenable<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final max = size.width / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t.value + i / 3) % 1;
      canvas.drawCircle(
        c,
        max * (0.18 + 0.82 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = SonarColors.amber.withValues(alpha: 0.65 * (1 - p)),
      );
    }
    canvas.drawCircle(c, max * 0.14, Paint()..color = SonarColors.amber);
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t;
}
