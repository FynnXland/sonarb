part of 'category_symbol.dart';

/// Messstellen: Nadel mit weißem Schild im Kopf. Die Silhouette trennt die Arten auch ohne
/// Farbe: rund (fest), Portal (Tunnel), Ampelgehäuse links (Rotlicht und Tempo), Tafel
/// (Abschnitt), eckig mit Rädern (Anhänger), Stativ (mobil).
void _paintCamera(
  Canvas canvas,
  _Geo g,
  _Form form,
  AlertCategory category,
  int? speed,
  bool upright,
) {
  final color = categoryColor(category);
  final c = g.c;
  final r = g.r;
  if (upright) _shadow(canvas, g.ground, g.u);

  switch (form) {
    case _Form.pin:
      _outlined(canvas, _drop(c, r, g.tip), color, g);
      _roundFace(canvas, category, speed, c, r * 0.8);

    case _Form.tunnel:
      final bottom = g.m + r * 1.72;
      final body = _union([
        _arch(c.dx, g.m, r, bottom, r * 0.22),
        _tail(c.dx, bottom, r * 0.42, g.tip),
      ]);
      _outlined(canvas, body, color, g);
      final k = r * 0.2;
      final face = _arch(c.dx, g.m + k, r - k, bottom - k, r * 0.12);
      canvas.drawPath(face, _fill(SymbolColors.face));
      final fr = r - k;
      final center = Offset(c.dx, g.m + k + fr * 1.12);
      _faceContent(canvas, category, speed, center, fr, face);

    case _Form.lightPin:
      final housing = RRect.fromRectAndRadius(
        Rect.fromLTRB(g.m, c.dy - r * 0.94, c.dx - r * 0.6, c.dy + r * 0.94),
        Radius.circular(g.u * 0.1),
      );
      final drop = _drop(c, r, g.tip);
      _outlined(canvas, _union([drop, Path()..addRRect(housing)]), color, g);
      canvas.drawRRect(housing, _fill(SymbolColors.ink));
      canvas.drawPath(drop, _fill(color));
      final lampX = (housing.left + c.dx - r) / 2;
      final lampR = g.u * 0.065;
      for (final (i, dy) in [-0.27, 0.0, 0.27].indexed) {
        canvas.drawCircle(
          Offset(lampX, c.dy + dy * g.u),
          lampR,
          _fill(i == 0 ? SymbolColors.fixed : SymbolColors.lampOff),
        );
      }
      _roundFace(canvas, category, speed, c, r * 0.8);

    case _Form.plate:
      final plate = RRect.fromRectAndRadius(
        Rect.fromLTRB(g.m, g.m, g.box.width - g.m, g.signBottom),
        Radius.circular(g.u * 0.1),
      );
      final body = _union([
        Path()..addRRect(plate),
        _tail(c.dx, plate.bottom, g.u * 0.16, g.tip),
      ]);
      _outlined(canvas, body, color, g);
      final face = plate.deflate(g.u * 0.075);
      final facePath = Path()..addRRect(face);
      canvas.drawPath(facePath, _fill(SymbolColors.face));
      final rect = face.outerRect;
      if (speed != null) {
        _paintNumber(
          canvas,
          speed,
          rect.center,
          fontSize: rect.height * 0.84,
          maxWidth: rect.width * 0.88,
        );
      } else {
        _faceContent(
          canvas,
          category,
          null,
          rect.center,
          rect.height / 2,
          facePath,
        );
      }

    case _Form.trailer:
      final head = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: r * 2, height: r * 1.84),
        Radius.circular(r * 0.36),
      );
      final wheelR = r * 0.27;
      final wheels = [
        for (final dx in [-0.58, 0.58]) Offset(c.dx + dx * r, head.bottom),
      ];
      final body = _union([
        Path()..addRRect(head),
        _tail(c.dx, head.bottom, r * 0.34, g.tip),
        for (final w in wheels) _circle(w, wheelR),
      ]);
      _outlined(canvas, body, color, g);
      for (final w in wheels) {
        canvas.drawCircle(w, wheelR, _fill(SymbolColors.ink));
      }
      _roundFace(canvas, category, speed, c.translate(0, -r * 0.04), r * 0.74);

    case _Form.tripod:
      // Drei Beine aus einem Punkt unter dem Kopf: ein Stativ.
      final legW = g.u * 0.09;
      final foot = g.tip.dy;
      final hub = Offset(c.dx, c.dy + r * 0.7);
      final body = _union([
        _circle(c, r),
        for (final dx in [-0.34, 0.0, 0.34])
          _bar(hub, Offset(c.dx + dx * g.u, foot), legW),
      ]);
      _outlined(canvas, body, color, g);
      _roundFace(canvas, category, speed, c, r * 0.8);

    default:
      break;
  }
}

/// Rundes weißes Schild im Kopf.
void _roundFace(
  Canvas canvas,
  AlertCategory category,
  int? speed,
  Offset c,
  double fr,
) {
  canvas.drawCircle(c, fr, _fill(SymbolColors.face));
  _faceContent(canvas, category, speed, c, fr, _circle(c, fr));
}

/// Zahl oder Piktogramm im Schild. [fr]: halbe Höhe des Schilds, [clip]: seine Fläche.
void _faceContent(
  Canvas canvas,
  AlertCategory category,
  int? speed,
  Offset c,
  double fr,
  Path clip,
) {
  if (speed != null) {
    _paintNumber(canvas, speed, c, fontSize: fr * 1.15, maxWidth: fr * 1.62);
    return;
  }
  final s = fr * 2;
  switch (category) {
    case AlertCategory.sectionEnd:
      _endStripes(canvas, c, s, clip);
    case AlertCategory.fixedRedLight || AlertCategory.mobileRedLight:
      _lamp(canvas, c, s);
    case AlertCategory.mobileDistance:
      _distance(canvas, c, s);
    default:
      _camera(canvas, c, s);
  }
}

/// Tropfen: Kreis mit Tangenten zur Spitze.
Path _drop(Offset c, double r, Offset tip) {
  final d = (tip - c).distance;
  final a = math.acos(r / d);
  final base = math.atan2(tip.dy - c.dy, tip.dx - c.dx);
  final p1 = c + Offset(math.cos(base + a), math.sin(base + a)) * r;
  return Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(p1.dx, p1.dy)
    ..arcTo(
      Rect.fromCircle(center: c, radius: r),
      base + a,
      2 * math.pi - 2 * a,
      false,
    )
    ..close();
}

/// Spitze unter einer geraden Unterkante.
Path _tail(double cx, double top, double halfWidth, Offset tip) => Path()
  ..moveTo(cx - halfWidth, top - 1)
  ..lineTo(tip.dx, tip.dy)
  ..lineTo(cx + halfWidth, top - 1)
  ..close();

/// Tunnelportal: Halbkreis oben, gerade Seiten, flache Unterkante.
Path _arch(double cx, double top, double r, double bottom, double corner) =>
    Path()
      ..moveTo(cx - r, top + r)
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, top + r), radius: r),
        math.pi,
        math.pi,
        false,
      )
      ..lineTo(cx + r, bottom - corner)
      ..quadraticBezierTo(cx + r, bottom, cx + r - corner, bottom)
      ..lineTo(cx - r + corner, bottom)
      ..quadraticBezierTo(cx - r, bottom, cx - r, bottom - corner)
      ..close();

/// Kamera von vorn: Gehäuse, Objektiv, Blitz oben links. Fläche [s] × [s].
void _camera(Canvas canvas, Offset c, double s) {
  final ink = _fill(SymbolColors.ink);
  final body = Rect.fromCenter(
    center: c.translate(0, s * 0.06),
    width: s * 0.66,
    height: s * 0.42,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(body, Radius.circular(s * 0.07)),
    ink,
  );
  canvas.drawRect(
    Rect.fromLTWH(body.left + s * 0.06, body.top - s * 0.09, s * 0.2, s * 0.1),
    ink,
  );
  canvas.drawCircle(body.center, s * 0.13, _fill(SymbolColors.face));
  canvas.drawCircle(body.center, s * 0.06, ink);
}

/// Ampel: Gehäuse mit drei Lampen, die obere rot.
void _lamp(Canvas canvas, Offset c, double s) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: s * 0.36, height: s * 0.74),
      Radius.circular(s * 0.1),
    ),
    _fill(SymbolColors.ink),
  );
  for (final (i, dy) in [-0.22, 0.0, 0.22].indexed) {
    canvas.drawCircle(
      c.translate(0, dy * s),
      s * 0.085,
      _fill(i == 0 ? SymbolColors.fixed : SymbolColors.lampOff),
    );
  }
}

/// Abstand: zwei Fahrzeuge hintereinander, darüber der Doppelpfeil.
void _distance(Canvas canvas, Offset c, double s) {
  final ink = _fill(SymbolColors.ink);
  for (final dx in [-0.25, 0.25]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c.translate(dx * s, s * 0.14),
          width: s * 0.26,
          height: s * 0.2,
        ),
        Radius.circular(s * 0.05),
      ),
      ink,
    );
  }
  final y = c.dy - s * 0.14;
  final line = _stroke(SymbolColors.ink, s * 0.07);
  canvas.drawLine(Offset(c.dx - s * 0.28, y), Offset(c.dx + s * 0.28, y), line);
  for (final side in [-1.0, 1.0]) {
    final end = c.dx + side * s * 0.36;
    canvas.drawPath(
      Path()
        ..moveTo(end, y)
        ..lineTo(end - side * s * 0.14, y - s * 0.1)
        ..lineTo(end - side * s * 0.14, y + s * 0.1)
        ..close(),
      ink,
    );
  }
}

/// Ende: schräge Streifen wie auf dem Zeichen „Ende aller Streckenverbote“.
void _endStripes(Canvas canvas, Offset c, double s, Path clip) {
  canvas.save();
  canvas.clipPath(clip);
  final line = Paint()
    ..color = SymbolColors.ink
    ..strokeWidth = s * 0.09;
  for (final k in [-0.24, 0.0, 0.24]) {
    final o = c.translate(k * s, 0);
    canvas.drawLine(
      o.translate(-s * 0.4, s * 0.4),
      o.translate(s * 0.4, -s * 0.4),
      line,
    );
  }
  canvas.restore();
}
