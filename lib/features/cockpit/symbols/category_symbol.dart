import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/model/alert_point.dart';

part 'symbol_paint.dart';
part 'camera_symbols.dart';
part 'hazard_symbols.dart';
part 'other_symbols.dart';

/// Kartensymbol einer [AlertCategory]. Die Grundform sagt die Gruppe, das Piktogramm die Art,
/// die Farbe kommt nur dazu:
/// - Messstellen: Nadel mit der Spitze am Ort und einem Schild im Kopf. Fest rund, mobil auf
///   einem Stativ, Anhänger eckig mit Rädern, Tunnel als Portal, Abschnitt als Tafel.
/// - Gefahrenstellen: Dreieck wie ein Gefahrzeichen, Bernstein wie gelbe Baustellenschilder.
/// - Weitere: rundes Verbotszeichen mit weißem Piktogramm.
/// - Ampel: kleines dunkles Gehäuse ohne Rand, damit sie hinter den Warnpunkten zurücktritt.
///
/// [size] ist der Durchmesser des Nadelkopfs bzw. des runden Zeichens; breite Formen sind breiter.
/// Die Fläche und den Bodenpunkt liefert [categorySymbolLayout].
/// [upright]: Nadel mit Schatten, Dreieck und Kreis auf einem Pfosten (geneigte Karte).
class CategorySymbol extends StatelessWidget {
  const CategorySymbol(
    this.category, {
    super.key,
    this.speed,
    this.size = 22,
    this.upright = false,
  });

  final AlertCategory category;

  /// Tempolimit in km/h. Erscheint nur bei Arten mit [AlertCategory.showsSpeed].
  final int? speed;
  final double size;
  final bool upright;

  @override
  Widget build(BuildContext context) {
    final layout = categorySymbolLayout(category, size: size, upright: upright);
    final shown = shownSpeed(category, speed);
    return Semantics(
      label: shown == null ? category.label : '${category.label}, $shown',
      excludeSemantics: true,
      child: CustomPaint(
        size: layout.box,
        painter: _SymbolPainter(category, shown, size, upright),
      ),
    );
  }
}

/// Zahl, die das Symbol trägt, oder null (dann zeigt es ein Piktogramm).
int? shownSpeed(AlertCategory category, int? speed) =>
    category.showsSpeed && speed != null && speed > 0 && speed < 1000
    ? speed
    : null;

/// Fläche eines Symbols und der Punkt darin, der auf dem Ort liegt.
class SymbolLayout {
  const SymbolLayout(this.box, this.ground);

  final Size box;

  /// Ort in Symbolkoordinaten: Spitze der Nadel, Fuß des Pfostens, sonst die Mitte.
  final Offset ground;

  /// Ausrichtung für `Marker.alignment` in flutter_map, damit [ground] auf dem Punkt liegt.
  Alignment get markerAlignment =>
      Alignment(1 - 2 * ground.dx / box.width, 1 - 2 * ground.dy / box.height);
}

SymbolLayout categorySymbolLayout(
  AlertCategory category, {
  double size = 22,
  bool upright = false,
}) => _geometry(_formOf(category), size, upright).layout;

enum _Form {
  pin,
  tunnel,
  lightPin,
  plate,
  trailer,
  tripod,
  triangle,
  disc,
  signal,
}

_Form _formOf(AlertCategory c) => switch (c) {
  AlertCategory.fixedSpeed || AlertCategory.fixedRedLight => _Form.pin,
  AlertCategory.tunnelSpeed => _Form.tunnel,
  AlertCategory.fixedRedLightSpeed => _Form.lightPin,
  AlertCategory.sectionStart || AlertCategory.sectionEnd => _Form.plate,
  AlertCategory.semiStationary => _Form.trailer,
  AlertCategory.mobileSpeed ||
  AlertCategory.mobileRedLight ||
  AlertCategory.mobileDistance => _Form.tripod,
  AlertCategory.accessControl ||
  AlertCategory.heightControl ||
  AlertCategory.weightControl ||
  AlertCategory.busLane ||
  AlertCategory.noOvertaking ||
  AlertCategory.closure => _Form.disc,
  AlertCategory.trafficSignal => _Form.signal,
  _ => _Form.triangle,
};

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.category, this.speed, this.unit, this.upright);

  final AlertCategory category;
  final int? speed;
  final double unit;
  final bool upright;

  @override
  void paint(Canvas canvas, Size size) {
    final form = _formOf(category);
    final g = _geometry(form, unit, upright);
    switch (form) {
      case _Form.triangle:
        _paintHazard(canvas, g, category, upright);
      case _Form.disc:
        _paintOther(canvas, g, category, upright);
      case _Form.signal:
        _paintSignal(canvas, g, upright);
      default:
        _paintCamera(canvas, g, form, category, speed, upright);
    }
  }

  @override
  bool shouldRepaint(_SymbolPainter old) =>
      old.category != category ||
      old.speed != speed ||
      old.unit != unit ||
      old.upright != upright;
}
