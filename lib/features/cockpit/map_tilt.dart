import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/widgets.dart' show Matrix4;

/// Neigung der Karte bei voller Fahrtansicht.
const tiltPitchDeg = 50.0;

/// Höhe der eigenen Position im Bild (Anteil von oben) bei voller Neigung: unten im Bild, damit
/// vorn mehr Strecke zu sehen ist; darunter bleibt ein Rest der Straße hinter dem Auto.
const tiltPivotFraction = 0.8;

/// Höhe der eigenen Position in der flachen Karte beim Mitführen mit Fahrtrichtung oben: unter
/// der Mitte, damit mehr Strecke voraus zu sehen ist.
const followPivotFraction = 0.65;

/// Brennweite der Perspektive im Verhältnis zur Bildhöhe. Kleiner = stärkere Verkürzung.
const _focalPerHeight = 1.5;

/// So weit (in Bildhöhen der flachen Karte) reicht die gerenderte Karte nach vorn. Was darüber
/// läge, deckt der Dunst am Horizont ab; so bleibt die Zahl der Kacheln begrenzt.
const _maxAheadPerHeight = 3.4;

/// Geometrie der geneigten Karte für einen Ausschnitt [viewport] und eine Neigung [t]
/// (0 = flach, 1 = volle Fahrtansicht).
///
/// Die Karte wird größer gerendert ([mapRect], im Ausschnitt-Koordinatensystem) und dann um den
/// Drehpunkt [pivot] perspektivisch gekippt ([matrix], relativ zur linken oberen Ecke von
/// [mapRect]). Die Kamera der Karte sitzt in der Mitte von [mapRect]; die eigene Position liegt
/// [cameraOffset] Bildpunkte darunter, also genau am Drehpunkt.
class TiltGeometry {
  /// [flatPivot] ist die Höhe der eigenen Position im flachen Bild (Anteil von oben); mit der
  /// Neigung wandert sie zu [tiltPivotFraction].
  factory TiltGeometry(Size viewport, double t, {double flatPivot = 0.5}) {
    final tilt = t.clamp(0.0, 1.0);
    final w = viewport.width;
    final h = viewport.height;
    // Vor dem ersten Layout ist der Ausschnitt leer: dann flach.
    final pitch = h > 0 ? tiltPitchDeg * tilt * math.pi / 180 : 0.0;
    final cosP = math.cos(pitch);
    final k = pitch == 0 ? 0.0 : math.sin(pitch) / (_focalPerHeight * h);
    final py = h * (flatPivot + (tiltPivotFraction - flatPivot) * tilt);
    final above = py;
    final below = h - py;

    // Wie weit die Karte nach oben reichen muss, damit sie den Ausschnitt bis zum oberen Rand
    // füllt, höchstens bis zur Sichtweite.
    final denom = cosP - k * above;
    final maxAhead = math.max(above, _maxAheadPerHeight * h);
    final ahead = denom <= 0 ? maxAhead : math.min(above / denom, maxAhead);
    final behind = below / (cosP + k * below);
    // Oben ist die Karte am stärksten verkleinert: so breit muss sie dort sein. Ein Bildpunkt
    // Reserve gegen Rundung an den Ecken.
    final width = w * (1 + k * ahead) + 2;
    final rect = Rect.fromLTWH(
      (w - width) / 2,
      py - ahead,
      width,
      ahead + behind,
    );
    return TiltGeometry._(
      viewport: viewport,
      t: tilt,
      pitch: pitch,
      k: k,
      pivot: Offset(w / 2, py),
      mapRect: rect,
      ahead: ahead,
      behind: behind,
    );
  }

  TiltGeometry._({
    required this.viewport,
    required this.t,
    required this.pitch,
    required this.k,
    required this.pivot,
    required this.mapRect,
    required this.ahead,
    required this.behind,
  });

  final Size viewport;
  final double t;

  /// Neigung in Bogenmaß.
  final double pitch;

  /// Perspektivfaktor: ein Punkt y Bildpunkte über dem Drehpunkt wird um 1 + k·y verkleinert.
  final double k;

  /// Drehpunkt im Ausschnitt; dort liegt die eigene Position.
  final Offset pivot;

  /// Lage und Größe der gerenderten Karte vor dem Kippen.
  final Rect mapRect;

  /// Gerenderte Strecke über und unter dem Drehpunkt (Kartenbildpunkte).
  final double ahead;
  final double behind;

  bool get isFlat => pitch == 0;

  /// Abstand der eigenen Position unter der Kartenmitte, für `MapController.move(offset:)`.
  Offset get cameraOffset => Offset(0, (ahead - behind) / 2);

  /// Drehpunkt in Koordinaten der gerenderten Karte.
  Offset get pivotInMap => Offset(mapRect.width / 2, ahead);

  /// Kipp-Matrix für ein `Transform` um die linke obere Ecke der Karte.
  Matrix4 get matrix {
    final o = pivotInMap;
    final m = Matrix4.identity()
      ..setEntry(1, 1, math.cos(pitch))
      ..setEntry(3, 1, -k);
    return Matrix4.translationValues(o.dx, o.dy, 0)
      ..multiply(m)
      ..multiply(Matrix4.translationValues(-o.dx, -o.dy, 0));
  }

  /// Ein Punkt der gerenderten Karte (Kartenkoordinaten) im Ausschnitt.
  Offset project(Offset inMap) {
    final rel = inMap - pivotInMap;
    final d = 1 - k * rel.dy;
    return pivot + Offset(rel.dx / d, rel.dy * math.cos(pitch) / d);
  }

  /// Maßstab an einem Kartenpunkt: 1 am Drehpunkt, kleiner nach hinten.
  double scaleAt(Offset inMap) => 1 / (1 - k * (inMap.dy - pivotInMap.dy));

  /// Oberkante der gerenderten Karte im Ausschnitt. Darüber liegt nur noch Dunst.
  double get horizonY => project(Offset(mapRect.width / 2, 0)).dy;
}
