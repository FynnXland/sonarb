part of 'category_symbol.dart';

/// Gefahrenstellen: Dreieck mit der Spitze nach oben wie ein Gefahrzeichen, dunkles
/// Piktogramm. Amtliche Meldungen blau mit weißem Ausrufezeichen, eigene Meldungen türkis mit
/// dem Sonar-Ring der App.
void _paintHazard(Canvas canvas, _Geo g, AlertCategory category, bool upright) {
  final w = g.box.width;
  final top = g.m;
  final bottom = g.signBottom - g.m;
  if (upright) {
    _shadow(canvas, g.ground, g.u);
    _post(canvas, g.ground.dx, bottom, g.box.height, g);
  }
  final triangle = _roundedPolygon([
    Offset(w / 2, top),
    Offset(w - g.m, bottom),
    Offset(g.m, bottom),
  ], g.u * 0.1);
  _outlined(canvas, triangle, categoryColor(category), g);

  final s = (bottom - top) * 0.6;
  final p = Offset(w / 2, top + (bottom - top) * 0.65);
  final ink = SymbolColors.ink;
  switch (category) {
    case AlertCategory.longTermRoadworks:
      _barrier(canvas, p, s);
    case AlertCategory.dayRoadworks:
      _cone(canvas, p, s);
    case AlertCategory.trafficJamEnd:
      _queue(canvas, p, s);
    case AlertCategory.obstacle:
      _rock(canvas, p, s);
    case AlertCategory.accident:
      _crash(canvas, p, s);
    case AlertCategory.slipperyRoad:
      _snowflake(canvas, p, s);
    case AlertCategory.poorVisibility:
      for (final (y, x0, x1) in [
        (-0.3, -0.44, 0.28),
        (0.0, -0.28, 0.44),
        (0.3, -0.44, 0.44),
      ]) {
        canvas.drawLine(
          p.translate(x0 * s, y * s),
          p.translate(x1 * s, y * s),
          _stroke(ink, s * 0.12),
        );
      }
    case AlertCategory.breakdown:
      // Aufgestelltes Warndreieck.
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy - s * 0.4)
          ..lineTo(p.dx + s * 0.4, p.dy + s * 0.28)
          ..lineTo(p.dx - s * 0.4, p.dy + s * 0.28)
          ..close(),
        _stroke(ink, s * 0.12),
      );
      canvas.drawLine(
        p.translate(-s * 0.2, s * 0.46),
        p.translate(s * 0.2, s * 0.46),
        _stroke(ink, s * 0.1),
      );
    case AlertCategory.officialNotice:
      final white = _fill(SymbolColors.face);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            p.dx - s * 0.085,
            p.dy - s * 0.46,
            p.dx + s * 0.085,
            p.dy + s * 0.14,
          ),
          Radius.circular(s * 0.08),
        ),
        white,
      );
      canvas.drawCircle(p.translate(0, s * 0.34), s * 0.1, white);
    default:
      // Gemeldete Stelle: Ring und Punkt aus dem Sonar-Zeichen.
      canvas.drawCircle(p, s * 0.32, _stroke(ink, s * 0.11));
      canvas.drawCircle(p, s * 0.12, _fill(ink));
  }
}

/// Absperrschranke: gestreifte Latte auf zwei Füßen.
void _barrier(Canvas canvas, Offset p, double s) {
  final ink = _fill(SymbolColors.ink);
  final plank = Rect.fromCenter(
    center: p.translate(0, -s * 0.12),
    width: s * 1.04,
    height: s * 0.36,
  );
  for (final dx in [-0.32, 0.32]) {
    canvas.drawRect(
      Rect.fromLTRB(
        p.dx + dx * s - s * 0.06,
        plank.bottom - 1,
        p.dx + dx * s + s * 0.06,
        p.dy + s * 0.46,
      ),
      ink,
    );
  }
  final rr = RRect.fromRectAndRadius(plank, Radius.circular(s * 0.05));
  canvas.drawRRect(rr, ink);
  canvas.save();
  canvas.clipRRect(rr.deflate(s * 0.05));
  final gap = Paint()
    ..color = SymbolColors.hazard
    ..strokeWidth = s * 0.13;
  for (final k in [-0.34, 0.0, 0.34]) {
    canvas.drawLine(
      Offset(p.dx + k * s - s * 0.12, plank.bottom),
      Offset(p.dx + k * s + s * 0.12, plank.top),
      gap,
    );
  }
  canvas.restore();
}

/// Leitkegel mit hellem Band und Fuß.
void _cone(Canvas canvas, Offset p, double s) {
  final cone = Path()
    ..moveTo(p.dx - s * 0.1, p.dy - s * 0.5)
    ..lineTo(p.dx + s * 0.1, p.dy - s * 0.5)
    ..lineTo(p.dx + s * 0.3, p.dy + s * 0.32)
    ..lineTo(p.dx - s * 0.3, p.dy + s * 0.32)
    ..close();
  final ink = _fill(SymbolColors.ink);
  canvas.drawPath(cone, ink);
  canvas.save();
  canvas.clipPath(cone);
  canvas.drawRect(
    Rect.fromLTRB(p.dx - s, p.dy - s * 0.14, p.dx + s, p.dy + s * 0.02),
    _fill(SymbolColors.hazard),
  );
  canvas.restore();
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(
        p.dx - s * 0.48,
        p.dy + s * 0.3,
        p.dx + s * 0.48,
        p.dy + s * 0.46,
      ),
      Radius.circular(s * 0.04),
    ),
    ink,
  );
}

/// Stauende: zwei Autos von hinten, das hintere kleiner.
void _queue(Canvas canvas, Offset p, double s) {
  _carRear(canvas, p.translate(0, -s * 0.26), s * 0.52, s);
  _carRear(canvas, p.translate(0, s * 0.2), s * 0.84, s);
}

void _carRear(Canvas canvas, Offset c, double w, double s) {
  final body = RRect.fromRectAndRadius(
    Rect.fromCenter(center: c, width: w, height: w * 0.5),
    Radius.circular(w * 0.14),
  );
  // Schmale Fuge in Grundfarbe trennt das vordere Auto vom hinteren.
  canvas.drawRRect(body.inflate(s * 0.05), _fill(SymbolColors.hazard));
  final ink = _fill(SymbolColors.ink);
  for (final dx in [-0.3, 0.3]) {
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(c.dx + dx * w, body.bottom + w * 0.05),
        width: w * 0.18,
        height: w * 0.16,
      ),
      ink,
    );
  }
  canvas.drawRRect(body, ink);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(c.dx - w * 0.32, body.top + w * 0.08, w * 0.64, w * 0.16),
      Radius.circular(w * 0.04),
    ),
    _fill(SymbolColors.hazard),
  );
}

/// Hindernis: Brocken auf der Fahrbahn.
void _rock(Canvas canvas, Offset p, double s) {
  final ink = _fill(SymbolColors.ink);
  canvas.drawPath(
    _roundedPolygon([
      for (final (x, y) in [
        (-0.44, 0.32),
        (-0.36, 0.02),
        (-0.16, -0.06),
        (-0.04, -0.3),
        (0.14, -0.14),
        (0.3, -0.2),
        (0.44, 0.32),
      ])
        p.translate(x * s, y * s),
    ], s * 0.06),
    ink,
  );
  canvas.drawRect(
    Rect.fromLTRB(
      p.dx - s * 0.5,
      p.dy + s * 0.36,
      p.dx + s * 0.5,
      p.dy + s * 0.46,
    ),
    ink,
  );
}

/// Unfall: zwei Autos von der Seite, Front an Front und angehoben, darüber Stoßstriche.
void _crash(Canvas canvas, Offset p, double s) {
  final ink = _fill(SymbolColors.ink);
  final w = s * 0.46;
  for (final side in [-1.0, 1.0]) {
    canvas.save();
    canvas.translate(p.dx + side * s * 0.03, p.dy + s * 0.3);
    if (side > 0) canvas.scale(-1, 1);
    canvas.rotate(-0.32);
    // Front liegt bei x = 0, das Heck bei -w.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-w, -s * 0.19, 0, 0),
        Radius.circular(s * 0.05),
      ),
      ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-w * 0.82, -s * 0.33, -w * 0.3, -s * 0.17),
        Radius.circular(s * 0.05),
      ),
      ink,
    );
    for (final x in [-0.76, -0.24]) {
      canvas.drawCircle(Offset(x * w, 0), s * 0.075, ink);
    }
    canvas.restore();
  }
  final burst = _stroke(SymbolColors.ink, s * 0.08);
  final hub = p.translate(0, -s * 0.02);
  for (final a in [-math.pi / 2, -math.pi * 0.22, -math.pi * 0.78]) {
    final d = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(hub + d * (s * 0.16), hub + d * (s * 0.34), burst);
  }
}

/// Glätte: Schneeflocke mit drei Achsen.
void _snowflake(Canvas canvas, Offset p, double s) {
  final line = _stroke(SymbolColors.ink, s * 0.09);
  for (var k = 0; k < 6; k++) {
    final a = -math.pi / 2 + k * math.pi / 3;
    final dir = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(p, p + dir * (s * 0.46), line);
    final fork = p + dir * (s * 0.28);
    for (final turn in [-0.75, 0.75]) {
      final b = a + turn;
      canvas.drawLine(
        fork,
        fork + Offset(math.cos(b), math.sin(b)) * (s * 0.15),
        line,
      );
    }
  }
}
