part of 'category_symbol.dart';

/// Farben des Zeichensatzes. Gegen den Kartengrund trennt sie der weiße Rand mit dunklem Saum,
/// deshalb tragen sie auch auf heller Karte. Kontrast gegen [SonarColors.bg]: fest 4,2:1,
/// mobil 6,5:1, Anhänger 4,6:1, amtlich 4,5:1; Weiß auf Rot 4,5:1, Dunkel auf Bernstein 10,4:1.
abstract final class SymbolColors {
  /// Feste Messstellen und Verbotszeichen: das Rot der Verkehrszeichen, aufgehellt für die
  /// dunkle Karte.
  static const fixed = Color(0xFFE8202A);

  /// Mobile Messungen.
  static const mobile = Color(0xFFF2711C);

  /// Blitzeranhänger: steht tagelang, ist aber nicht fest verbaut.
  static const trailer = Color(0xFF9B5CE6);

  /// Gefahrenstellen, wie gelbe Schilder an Baustellen.
  static const hazard = SonarColors.amber;

  /// Amtliche Meldung, Blau der Hinweiszeichen.
  static const official = Color(0xFF2B7BE0);

  /// Selbst gemeldete Stelle: Türkis wie „Melden“.
  static const report = SonarColors.hotspot;

  static const face = SonarColors.signWhite;
  static const ink = SonarColors.bg;

  /// Unbeleuchtete Lampen in Ampel-Piktogrammen.
  static const lampOff = Color(0xFF7D8792);
}

/// Hauptfarbe einer Art, etwa für eine Kante im Hinweisfeld.
Color categoryColor(AlertCategory c) => switch (c) {
  AlertCategory.semiStationary => SymbolColors.trailer,
  AlertCategory.officialNotice => SymbolColors.official,
  AlertCategory.otherReport => SymbolColors.report,
  AlertCategory.trafficSignal => SonarColors.textMuted,
  _ when c.isMobile => SymbolColors.mobile,
  _ when c.group == CategoryGroup.hazard => SymbolColors.hazard,
  _ => SymbolColors.fixed,
};

/// Maße eines Symbols bei Einheit [u] (Durchmesser des Nadelkopfs).
class _Geo {
  _Geo(
    this.u,
    this.box,
    this.ground, {
    required this.c,
    required this.r,
    required this.tip,
    required this.signBottom,
  });

  final double u;
  final Size box;
  final Offset ground;

  /// Mitte und Radius des Kopfs bzw. des runden Zeichens.
  final Offset c;
  final double r;

  /// Spitze der Nadel.
  final Offset tip;

  /// Unterkante des Schilds (ohne Pfosten).
  final double signBottom;

  double get white => _white(u);
  double get halo => _halo(u);
  double get m => white + halo;

  SymbolLayout get layout => SymbolLayout(box, ground);
}

double _white(double u) => math.max(1.0, u * 0.07);
double _halo(double u) => math.max(0.75, u * 0.035);

_Geo _geometry(_Form form, double u, bool upright) {
  final m = _white(u) + _halo(u);
  final r = u / 2 - m;
  final post = upright ? u * 0.5 : 0.0;

  _Geo pin(double w, double h, double cx) => _Geo(
    u,
    Size(w, h),
    Offset(cx, h),
    c: Offset(cx, m + r),
    r: r,
    tip: Offset(cx, h - m),
    signBottom: h,
  );

  _Geo sign(double w, double signH) {
    final h = signH + post;
    return _Geo(
      u,
      Size(w, h),
      upright ? Offset(w / 2, h) : Offset(w / 2, h / 2),
      c: Offset(w / 2, signH / 2),
      r: math.min(w, signH) / 2 - m,
      tip: Offset(w / 2, h),
      signBottom: signH,
    );
  }

  switch (form) {
    case _Form.pin || _Form.tunnel || _Form.trailer:
      return pin(u, u * 1.36, u / 2);
    case _Form.tripod:
      return pin(u, u * 1.42, u / 2);
    case _Form.lightPin:
      // Ampelgehäuse links, das Schild greift über seinen rechten Rand.
      final cx = m + u * 0.30 + r;
      return pin(cx + r + m, u * 1.36, cx);
    case _Form.plate:
      final w = u * 1.36;
      final plateH = u * 0.84 - m;
      final h = u * 1.22;
      return _Geo(
        u,
        Size(w, h),
        Offset(w / 2, h),
        c: Offset(w / 2, m + plateH / 2),
        r: plateH / 2,
        tip: Offset(w / 2, h - m),
        signBottom: m + plateH,
      );
    case _Form.triangle:
      return sign(u * 1.3, u * 1.15);
    case _Form.disc:
      return sign(u, u);
    case _Form.signal:
      final w = u * 0.46;
      final h = u * 0.78 + (upright ? u * 0.32 : 0);
      return _Geo(
        u,
        Size(w, h),
        upright ? Offset(w / 2, h) : Offset(w / 2, h / 2),
        c: Offset(w / 2, u * 0.39),
        r: w / 2,
        tip: Offset(w / 2, h),
        signBottom: u * 0.78,
      );
  }
}

/// Fläche mit dunklem Saum und weißem Rand, beide außerhalb von [path].
void _outlined(Canvas canvas, Path path, Color fill, _Geo g) {
  final edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(
    path,
    edge
      ..color = SymbolColors.ink
      ..strokeWidth = g.m * 2,
  );
  canvas.drawPath(
    path,
    edge
      ..color = SymbolColors.face
      ..strokeWidth = g.white * 2,
  );
  canvas.drawPath(path, Paint()..color = fill);
}

/// Flacher Schatten am Bodenpunkt: das Symbol steht auf der Karte, statt zu schweben.
void _shadow(Canvas canvas, Offset at, double u) => canvas.drawOval(
  Rect.fromCenter(center: at, width: u * 0.56, height: u * 0.16),
  Paint()..color = const Color(0x8C000000),
);

/// Pfosten eines aufrechten Schilds.
void _post(Canvas canvas, double x, double from, double to, _Geo g) {
  final w = math.max(1.5, g.u * 0.09);
  final line = Paint()..strokeCap = StrokeCap.butt;
  canvas.drawLine(
    Offset(x, from),
    Offset(x, to),
    line
      ..color = SymbolColors.ink
      ..strokeWidth = w + g.halo * 2,
  );
  canvas.drawLine(
    Offset(x, from),
    Offset(x, to - g.halo),
    line
      ..color = SonarColors.textMuted
      ..strokeWidth = w,
  );
}

/// Vieleck mit abgerundeten Ecken.
Path _roundedPolygon(List<Offset> pts, double radius) {
  final path = Path();
  for (var i = 0; i < pts.length; i++) {
    final v = pts[i];
    final prev = pts[(i - 1 + pts.length) % pts.length];
    final next = pts[(i + 1) % pts.length];
    final a = v + _towards(v, prev, radius);
    final b = v + _towards(v, next, radius);
    if (i == 0) {
      path.moveTo(a.dx, a.dy);
    } else {
      path.lineTo(a.dx, a.dy);
    }
    path.quadraticBezierTo(v.dx, v.dy, b.dx, b.dy);
  }
  return path..close();
}

Offset _towards(Offset from, Offset to, double len) {
  final d = to - from;
  final l = math.min(len, d.distance / 2);
  return d / d.distance * l;
}

/// Balken der Breite [w] von [a] nach [b].
Path _bar(Offset a, Offset b, double w) {
  final d = b - a;
  final n = Offset(-d.dy, d.dx) / d.distance * (w / 2);
  return Path()
    ..moveTo(a.dx + n.dx, a.dy + n.dy)
    ..lineTo(b.dx + n.dx, b.dy + n.dy)
    ..lineTo(b.dx - n.dx, b.dy - n.dy)
    ..lineTo(a.dx - n.dx, a.dy - n.dy)
    ..close();
}

Path _union(Iterable<Path> paths) =>
    paths.reduce((a, b) => Path.combine(PathOperation.union, a, b));

Path _circle(Offset c, double r) =>
    Path()..addOval(Rect.fromCircle(center: c, radius: r));

Paint _fill(Color color) => Paint()..color = color;

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// Tempolimit wie auf dem Schild, mittig bei [center]. Wird es zu breit, rückt die Schrift
/// zusammen (bis 80 %), danach wird sie kleiner.
void _paintNumber(
  Canvas canvas,
  int n,
  Offset center, {
  required double fontSize,
  required double maxWidth,
}) {
  TextPainter layout(double f) => TextPainter(
    text: TextSpan(
      text: '$n',
      // Wie Material-Text auf Android. Ohne Angabe nähme der Painter die Ersatzschrift der
      // Engine, in Tests eine Platzhalterschrift.
      style: SonarText.signNumber.copyWith(
        fontFamily: 'Roboto',
        fontSize: f,
        letterSpacing: -0.04 * f,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  var f = fontSize;
  var tp = layout(f);
  var sx = 1.0;
  if (tp.width > maxWidth) {
    sx = maxWidth / tp.width;
    if (sx < 0.8) {
      f = f * sx / 0.8;
      tp.dispose();
      tp = layout(f);
      sx = math.min(1.0, maxWidth / tp.width);
    }
  }
  // Ziffern mittig über ihre Versalhöhe, nicht über die Zeilenhöhe.
  final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(sx, 1);
  tp.paint(canvas, Offset(-tp.width / 2, f * 0.36 - baseline));
  canvas.restore();
  tp.dispose();
}
