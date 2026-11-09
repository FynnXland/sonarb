import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'stats_format.dart';
import 'stats_widgets.dart';
import 'trip_summary.dart';
import 'trip_trace.dart';

/// Farbe der Tempolinie: nach Stufe über dem Limit, weiß ohne bekanntes Limit.
Color traceColor(int kmh, int? limit) =>
    limit == null || limit == TraceLimit.none
    ? SonarColors.text
    : overLimitColor(overLimitOf((kmh - limit).toDouble()));

/// Bremsung oder Beschleunigung, die im Diagramm markiert wird, mit ihrer Farbe. Null: keine
/// Markierung (zügiges, aber nicht kräftiges Beschleunigen).
Color? eventColor(TraceEvent e) => switch (e.kind) {
  TraceEventKind.decel =>
    e.peakMps2 >= StatsLimits.hardPeakMps2
        ? SonarColors.red
        : SonarColors.amber,
  TraceEventKind.accel =>
    e.peakMps2 >= StatsLimits.hardPeakMps2 ? SonarColors.hotspot : null,
};

/// Ablesewert an einer Sekunde.
String traceReadout(TripTrace trace, DateTime start, int second) {
  final kmh = trace.speedAt(second);
  final limit = trace.limitAt(second);
  final parts = [
    formatClock(start.add(Duration(seconds: second))),
    kmh == null ? 'kein GPS' : '$kmh km/h',
    switch (limit) {
      null => 'Limit unbekannt',
      TraceLimit.none => 'kein Limit',
      final l => 'Limit $l',
    },
  ];
  return parts.join(' · ');
}

/// Tempo über die Fahrzeit mit Limit, Stufen über dem Limit und Brems-/Beschleunigungsmarken.
/// Ziehen oder Tippen zeigt den Wert an dieser Stelle.
class SpeedChart extends StatefulWidget {
  const SpeedChart({super.key, required this.trace, required this.start});

  final TripTrace trace;
  final DateTime start;

  @override
  State<SpeedChart> createState() => _SpeedChartState();
}

class _SpeedChartState extends State<SpeedChart> {
  int? _selected;

  static const _height = 190.0;

  void _pick(Offset local, double width) {
    final n = widget.trace.length;
    if (n < 2) return;
    final plot = width - _ChartPainter.left;
    final x = (local.dx - _ChartPainter.left).clamp(0.0, plot);
    setState(() => _selected = (x / plot * (n - 1)).round());
  }

  String _summary() {
    final t = widget.trace;
    final brakes = t.events.where((e) => e.kind == TraceEventKind.decel).length;
    return 'Tempoverlauf über ${formatSeconds(t.length.toDouble())}, '
        'höchstens ${t.peakKmh} km/h, $brakes Bremsungen markiert.';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 20,
            child: Text(
              selected == null
                  ? 'Finger über das Diagramm ziehen zum Ablesen'
                  : traceReadout(widget.trace, widget.start, selected),
              style: selected == null
                  ? SonarText.small
                  : SonarText.small.copyWith(
                      color: SonarColors.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
            ),
          ),
          const SizedBox(height: SonarSpace.xs),
          Semantics(
            label: _summary(),
            excludeSemantics: true,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _pick(d.localPosition, box.maxWidth),
                onHorizontalDragStart: (d) =>
                    _pick(d.localPosition, box.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _pick(d.localPosition, box.maxWidth),
                child: CustomPaint(
                  size: Size(box.maxWidth, _height),
                  painter: _ChartPainter(
                    trace: widget.trace,
                    start: widget.start,
                    selected: selected,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: SonarSpace.s),
          const _Legend(),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: SonarSpace.m,
    runSpacing: SonarSpace.xs,
    children: const [
      _Key(SonarColors.hotspot, 'im Limit'),
      _Key(SonarColors.amber, 'ab +4'),
      _Key(SonarColors.red, 'ab +11'),
      _Key(SonarColors.signRim, 'ab +21'),
      _Key(SonarColors.text, 'Limit unbekannt'),
      _Key(SonarColors.textMuted, 'Limit', dashed: true),
    ],
  );
}

class _Key extends StatelessWidget {
  const _Key(this.color, this.label, {this.dashed = false});

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 14,
        height: 10,
        child: CustomPaint(painter: _KeyPainter(color, dashed)),
      ),
      const SizedBox(width: SonarSpace.xs),
      Text(label, style: SonarText.small),
    ],
  );
}

class _KeyPainter extends CustomPainter {
  _KeyPainter(this.color, this.dashed);

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), p);
      return;
    }
    canvas.drawLine(Offset(1, y), Offset(5, y), p);
    canvas.drawLine(Offset(9, y), Offset(size.width - 1, y), p);
  }

  @override
  bool shouldRepaint(_KeyPainter old) =>
      old.color != color || old.dashed != dashed;
}

/// Schritt der Tempo-Gitterlinien für [top] km/h.
int gridStep(int top) => top <= 60
    ? 10
    : top <= 140
    ? 20
    : 40;

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.trace,
    required this.start,
    required this.selected,
  });

  final TripTrace trace;
  final DateTime start;
  final int? selected;

  /// Platz für die Tempo-Beschriftung links und die Zeiten unten.
  static const left = 30.0;
  static const bottom = 18.0;

  /// Leiste für Brems- und Beschleunigungsmarken unter der Kurve.
  static const marks = 14.0;

  static const _small = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 11,
    color: SonarColors.textMuted,
  );

  void _text(
    Canvas c,
    String s,
    Offset at, {
    TextAlign align = TextAlign.left,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: _small),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = trace.length;
    if (n < 2) return;
    final plotW = size.width - left;
    final plotH = size.height - bottom - marks;
    var maxLimit = 0;
    for (final l in trace.limits) {
      if ((l.kmh ?? 0) > maxLimit) maxLimit = l.kmh!;
    }
    final peak = math.max(trace.peakKmh, maxLimit);
    final step = gridStep(peak);
    final top = math.max(step, ((peak + 5) / step).ceil() * step);
    double x(num i) => left + i / (n - 1) * plotW;
    double y(num kmh) => plotH - kmh / top * plotH;

    // Gitter und Tempo-Beschriftung.
    final grid = Paint()
      ..color = SonarColors.surfaceHigh
      ..strokeWidth = 1;
    for (var v = 0; v <= top; v += step) {
      canvas.drawLine(Offset(left, y(v)), Offset(size.width, y(v)), grid);
      _text(canvas, '$v', Offset(left - 6, y(v)), align: TextAlign.right);
    }

    // Zeiten unten: Start, Ende und runde Zwischenzeiten.
    final minutes = n / 60;
    final tick = [
      5,
      10,
      15,
      30,
      60,
      120,
    ].firstWhere((m) => minutes / m <= 4, orElse: () => 240);
    final labelY = size.height - bottom / 2;
    _text(canvas, formatClock(start), Offset(left, labelY));
    _text(
      canvas,
      formatClock(start.add(Duration(seconds: n - 1))),
      Offset(size.width, labelY),
      align: TextAlign.right,
    );
    final tickPaint = Paint()
      ..color = SonarColors.outline
      ..strokeWidth = 1;
    final local = start.toLocal();
    final offset = local.minute * 60 + local.second;
    final first = (offset / (tick * 60)).ceil() * tick * 60 - offset;
    for (var s = first; s < n; s += tick * 60) {
      final px = x(s);
      if (px - left < 44 || size.width - px < 44) continue;
      canvas.drawLine(Offset(px, plotH), Offset(px, plotH + 3), tickPaint);
      _text(
        canvas,
        formatClock(start.add(Duration(seconds: s))),
        Offset(px, labelY),
        align: TextAlign.center,
      );
    }

    // Tempolimit als gestrichelte Stufenlinie.
    final limitPaint = Paint()
      ..color = SonarColors.textMuted
      ..strokeWidth = 1.5;
    for (var k = 0; k < trace.limits.length; k++) {
      final l = trace.limits[k];
      final kmh = l.kmh;
      if (kmh == null || kmh == TraceLimit.none) continue;
      final end = k + 1 < trace.limits.length
          ? trace.limits[k + 1].second
          : n - 1;
      _dashed(
        canvas,
        Offset(x(l.second), y(kmh)),
        Offset(x(end), y(kmh)),
        limitPaint,
      );
    }

    // Tempo: zusammenhängende Stücke gleicher Farbe als ein Pfad.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final gapPaint = Paint()
      ..color = SonarColors.textMuted
      ..strokeWidth = 1.5;
    var limitIndex = 0;
    int? limit;
    Path? path;
    Color? color;
    int? lastKnown;
    void flush() {
      if (path != null) canvas.drawPath(path!, line..color = color!);
      path = null;
    }

    for (var i = 0; i < n; i++) {
      while (limitIndex < trace.limits.length &&
          trace.limits[limitIndex].second <= i) {
        limit = trace.limits[limitIndex].kmh;
        limitIndex++;
      }
      final v = trace.speedAt(i);
      if (v == null) {
        flush();
        continue;
      }
      final p = Offset(x(i), y(v));
      final c = traceColor(v, limit);
      final prev = lastKnown;
      if (prev != null && prev < i - 1) {
        _dotted(canvas, Offset(x(prev), y(trace.speedAt(prev)!)), p, gapPaint);
      }
      if (path == null || c != color || prev != i - 1) {
        final from = prev == i - 1
            ? Offset(x(prev!), y(trace.speedAt(prev)!))
            : p;
        flush();
        path = Path()..moveTo(from.dx, from.dy);
        color = c;
      }
      path!.lineTo(p.dx, p.dy);
      lastKnown = i;
    }
    flush();

    // Marken für Bremsungen (nach unten) und kräftiges Beschleunigen (nach oben).
    final markY = plotH + marks / 2 + 1;
    for (final e in trace.events) {
      final c = eventColor(e);
      if (c == null) continue;
      final px = x(e.second + e.seconds / 2);
      final down = e.kind == TraceEventKind.decel;
      final tri = Path()
        ..moveTo(px - 4, down ? markY - 3 : markY + 3)
        ..lineTo(px + 4, down ? markY - 3 : markY + 3)
        ..lineTo(px, down ? markY + 4 : markY - 4)
        ..close();
      canvas.drawPath(tri, Paint()..color = c);
    }

    // Auswahl.
    final s = selected;
    if (s != null && s >= 0 && s < n) {
      final px = x(s);
      canvas.drawLine(
        Offset(px, 0),
        Offset(px, plotH),
        Paint()
          ..color = SonarColors.text.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      final v = trace.speedAt(s);
      if (v != null) {
        canvas.drawCircle(
          Offset(px, y(v)),
          4,
          Paint()..color = SonarColors.text,
        );
      }
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    const dash = 5.0;
    const gap = 4.0;
    final len = (b - a).distance;
    if (len <= 0) return;
    final dir = (b - a) / len;
    for (var d = 0.0; d < len; d += dash + gap) {
      c.drawLine(a + dir * d, a + dir * math.min(d + dash, len), p);
    }
  }

  void _dotted(Canvas c, Offset a, Offset b, Paint p) {
    final len = (b - a).distance;
    if (len <= 0) return;
    final dir = (b - a) / len;
    final dot = Paint()..color = p.color;
    for (var d = 0.0; d <= len; d += 5) {
      c.drawCircle(a + dir * d, 0.9, dot);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.trace != trace || old.selected != selected || old.start != start;
}
