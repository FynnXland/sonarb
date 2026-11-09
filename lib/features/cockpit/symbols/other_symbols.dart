part of 'category_symbol.dart';

/// Weitere: rundes rotes Zeichen mit weißem Piktogramm. Die Sperrung folgt dem Zeichen
/// „Verbot für Fahrzeuge aller Art“: weiße Fläche im roten Ring.
void _paintOther(Canvas canvas, _Geo g, AlertCategory category, bool upright) {
  final c = g.c;
  final r = g.r;
  if (upright) {
    _shadow(canvas, g.ground, g.u);
    _post(canvas, g.ground.dx, c.dy + r, g.box.height, g);
  }
  _outlined(canvas, _circle(c, r), SymbolColors.fixed, g);

  final white = _fill(SymbolColors.face);
  final red = _fill(SymbolColors.fixed);
  switch (category) {
    case AlertCategory.accessControl:
      canvas.drawRect(
        Rect.fromCenter(center: c, width: r * 1.36, height: r * 0.4),
        white,
      );
    case AlertCategory.heightControl:
      for (final side in [-1.0, 1.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - r * 0.38, c.dy + side * r * 0.72)
            ..lineTo(c.dx + r * 0.38, c.dy + side * r * 0.72)
            ..lineTo(c.dx, c.dy + side * r * 0.16)
            ..close(),
          white,
        );
      }
    case AlertCategory.weightControl:
      // Gewicht mit Griff.
      canvas.drawCircle(
        c.translate(0, -r * 0.4),
        r * 0.2,
        _stroke(SymbolColors.face, r * 0.14),
      );
      canvas.drawPath(
        _roundedPolygon([
          c.translate(-r * 0.34, -r * 0.2),
          c.translate(r * 0.34, -r * 0.2),
          c.translate(r * 0.54, r * 0.56),
          c.translate(-r * 0.54, r * 0.56),
        ], r * 0.1),
        white,
      );
    case AlertCategory.busLane:
      final body = Rect.fromCenter(
        center: c.translate(0, -r * 0.06),
        width: r * 1.0,
        height: r * 1.1,
      );
      for (final dx in [-0.3, 0.3]) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(c.dx + dx * r, body.bottom + r * 0.06),
            width: r * 0.2,
            height: r * 0.2,
          ),
          white,
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(r * 0.18)),
        white,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            body.left + r * 0.12,
            body.top + r * 0.14,
            body.right - r * 0.12,
            body.top + r * 0.58,
          ),
          Radius.circular(r * 0.06),
        ),
        red,
      );
      for (final dx in [-0.28, 0.28]) {
        canvas.drawCircle(
          Offset(c.dx + dx * r, body.bottom - r * 0.22),
          r * 0.09,
          red,
        );
      }
    case AlertCategory.noOvertaking:
      for (final dx in [-0.36, 0.36]) {
        _carFront(canvas, c.translate(dx * r, r * 0.08), r * 0.6);
      }
    default:
      canvas.drawCircle(c, r * 0.7, white);
  }
}

/// Auto von vorn: Dach, Karosserie, Räder, Scheibe in Rot.
void _carFront(Canvas canvas, Offset c, double w) {
  final white = _fill(SymbolColors.face);
  final body = Rect.fromCenter(center: c, width: w, height: w * 0.46);
  for (final dx in [-0.32, 0.32]) {
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(c.dx + dx * w, body.bottom + w * 0.06),
        width: w * 0.2,
        height: w * 0.2,
      ),
      white,
    );
  }
  final roof = Rect.fromLTRB(
    c.dx - w * 0.34,
    body.top - w * 0.36,
    c.dx + w * 0.34,
    body.top + 1,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(roof, Radius.circular(w * 0.14)),
    white,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(body, Radius.circular(w * 0.1)),
    white,
  );
  canvas.drawRect(roof.deflate(w * 0.09), _fill(SymbolColors.fixed));
}

/// Ampel: kleines dunkles Gehäuse mit grauen Lampen, ohne weißen Rand. Sie steht nur als
/// Orientierung auf der Karte und soll die Warnpunkte nicht überdecken.
void _paintSignal(Canvas canvas, _Geo g, bool upright) {
  final w = g.box.width;
  final halo = g.halo;
  final body = RRect.fromRectAndRadius(
    Rect.fromLTRB(halo, halo, w - halo, g.signBottom - halo),
    Radius.circular(w * 0.36),
  );
  if (upright) {
    _shadow(canvas, g.ground, g.u * 0.6);
    _post(canvas, g.ground.dx, body.bottom, g.box.height, g);
  }
  canvas.drawRRect(body.inflate(halo), _fill(SymbolColors.ink));
  canvas.drawRRect(body, _fill(SonarColors.surfaceHigh));
  canvas.drawRRect(
    body.deflate(0.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = SonarColors.textMuted,
  );
  final lampR = body.width * 0.17;
  for (final f in [0.24, 0.5, 0.76]) {
    canvas.drawCircle(
      Offset(w / 2, body.top + body.height * f),
      lampR,
      _fill(SonarColors.textMuted),
    );
  }
}
