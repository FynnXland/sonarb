import 'package:flutter/material.dart';

import '../../app/map_layer_settings.dart';
import '../../app/theme.dart';
import '../../core/model/alert_point.dart';
import 'loaded_area_layer.dart';
import 'map_point_layers.dart';
import 'symbols/category_symbol.dart';

/// Das Kartensymbol einer Ebene. Aus: blass und durchgestrichen.
class LayerSymbol extends StatelessWidget {
  const LayerSymbol({
    super.key,
    required this.layer,
    required this.on,
    this.size = 22,
  });

  final MapLayer layer;
  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Je Ebene ein festes Symbol der Karte. Nicht quadratische Formen passen per FittedBox.
    Widget category(AlertCategory c) =>
        FittedBox(child: CategorySymbol(c, size: size));
    final symbol = switch (layer) {
      MapLayer.fixedCameras => category(AlertCategory.fixedSpeed),
      MapLayer.mobile => CustomPaint(
        size: Size.square(size),
        painter: _GlowSymbolPainter(),
      ),
      MapLayer.construction => category(AlertCategory.longTermRoadworks),
      MapLayer.danger => category(AlertCategory.obstacle),
      MapLayer.signals => category(AlertCategory.trafficSignal),
      MapLayer.loadedAreas => CustomPaint(
        size: Size.square(size),
        painter: LoadedAreaSymbolPainter(),
      ),
    };
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: on
            ? symbol
            : Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(opacity: 0.4, child: symbol),
                  CustomPaint(painter: _StrikePainter()),
                ],
              ),
      ),
    );
  }
}

/// Der Fleck der mobilen Blitzer: rot, weich auslaufend.
class _GlowSymbolPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            heatColor,
            heatColor.withValues(alpha: 0.75),
            heatColor.withValues(alpha: 0),
          ],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_GlowSymbolPainter old) => false;
}

class _StrikePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.drawLine(
      Offset(w * 0.08, w * 0.92),
      Offset(w * 0.92, w * 0.08),
      Paint()
        ..color = SonarColors.text
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_StrikePainter old) => false;
}
