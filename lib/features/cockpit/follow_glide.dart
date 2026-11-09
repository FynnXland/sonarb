import 'dart:math' as math;

import '../../core/geo/geo.dart';

/// Lage der Karte beim Mitführen: Position, Kurs (null: keiner bekannt) und Zoom.
class GlidePose {
  const GlidePose(this.position, this.headingDeg, this.zoom);

  final GeoPoint position;
  final double? headingDeg;
  final double zoom;

  @override
  String toString() => 'GlidePose($position, $headingDeg, $zoom)';
}

/// Lässt die Karte zwischen zwei GPS-Fixes gleiten statt springen.
///
/// Mit jedem Fix startet ein neuer Abschnitt: von der Lage, die gerade zu sehen ist, zu der
/// Stelle, an der das Auto beim nächsten Fix voraussichtlich ist (Fix plus Tempo mal
/// Fix-Abstand). Der Abschnitt dauert so lange wie der gemessene Fix-Abstand. Bleibt der
/// nächste Fix aus, steht die Karte am Ende des Abschnitts still; geraten wird also höchstens
/// einen Fix-Abstand weit.
class FollowGlide {
  FollowGlide({
    this.jumpMeters = 150,
    this.maxGap = const Duration(seconds: 5),
  });

  /// Mindestabstand zwischen sichtbarer Lage und neuem Fix, ab dem die Karte springt.
  final double jumpMeters;

  /// Längere Pause zwischen zwei Fixes (Tunnel, Neustart): springen statt gleiten.
  final Duration maxGap;

  /// Fix-Abstand, solange noch keiner gemessen ist.
  static const _initialInterval = Duration(seconds: 1);
  static const _minInterval = Duration(milliseconds: 200);
  static const _maxInterval = Duration(seconds: 3);

  /// Gewicht des neuesten Abstands im gleitenden Mittel.
  static const _smoothing = 0.3;

  GlidePose? _from;
  GlidePose? _to;
  DateTime? _start;
  DateTime? _lastFixAt;
  Duration _interval = _initialInterval;

  /// Gemessener Fix-Abstand, gleitend gemittelt.
  Duration get interval => _interval;

  /// Wie schnell sich der Kurs zuletzt gedreht hat, in Grad je Sekunde.
  double get turnDegPerSec => _turn;
  double _turn = 0;
  double? _lastHeading;

  /// Gerade unterwegs: [at] liefert bis [endsAt] noch neue Lagen.
  bool active(DateTime now) {
    final end = endsAt;
    return end != null && now.isBefore(end);
  }

  DateTime? get endsAt => _start?.add(_interval);

  /// Neuer Fix. Mit [glide] false (Stand, Hintergrund, Animationen aus) springt die Karte.
  /// [viewHeadingDeg] ist der Kurs, nach dem die Karte ausgerichtet wird (geglättet, siehe
  /// [HeadingSmoother]); ohne ihn gilt [headingDeg].
  /// Gibt true zurück, wenn ein Gleitabschnitt beginnt.
  bool onFix({
    required GeoPoint position,
    required double? headingDeg,
    required double speedMps,
    required double zoom,
    required DateTime now,
    bool glide = true,
    double? viewHeadingDeg,
  }) {
    final last = _lastFixAt;
    final gap = last == null ? null : now.difference(last);
    _lastFixAt = now;
    final prevHeading = _lastHeading;
    if (headingDeg != null) _lastHeading = headingDeg;
    _turn =
        prevHeading != null &&
            headingDeg != null &&
            gap != null &&
            gap > Duration.zero
        ? angleDifference(prevHeading, headingDeg) / _seconds(gap)
        : 0;
    // Erst die sichtbare Lage, dann den Takt neu messen: sonst springt sie um den Unterschied.
    final current = at(now);
    if (gap != null && gap <= maxGap) _measure(gap);
    // Die Karte dreht nach dem geglätteten Kurs; vorhergesagt wird mit dem gemessenen.
    final heading = viewHeadingDeg ?? headingDeg ?? current?.headingDeg;
    final fixPose = GlidePose(position, heading, zoom);
    final jump =
        !glide ||
        current == null ||
        gap == null ||
        gap > maxGap ||
        distanceMeters(current.position, position) >
            math.max(jumpMeters, speedMps * _seconds(_interval) * 3);
    if (jump) {
      jumpTo(fixPose);
      return false;
    }
    final ahead = headingDeg == null || speedMps <= 0
        ? position
        : destinationPoint(
            position,
            headingDeg,
            speedMps * _seconds(_interval),
          );
    _from = current;
    _to = GlidePose(ahead, heading, zoom);
    _start = now;
    return true;
  }

  /// Ohne Gleiten auf [pose] setzen.
  void jumpTo(GlidePose pose) {
    _from = pose;
    _to = pose;
    _start = null;
  }

  /// Zoom sofort ändern, Ort und Kurs gleiten weiter.
  void setZoom(double zoom) {
    if (_from case final f?) _from = GlidePose(f.position, f.headingDeg, zoom);
    if (_to case final t?) _to = GlidePose(t.position, t.headingDeg, zoom);
  }

  /// Vergisst alles; der nächste Fix springt.
  void reset() {
    _from = null;
    _to = null;
    _start = null;
    _lastFixAt = null;
    _lastHeading = null;
    _turn = 0;
  }

  /// Sichtbare Lage zum Zeitpunkt [now]; null vor dem ersten Fix.
  GlidePose? at(DateTime now) {
    final from = _from, to = _to, start = _start;
    if (from == null || to == null) return null;
    if (start == null) return to;
    final t = (now.difference(start).inMicroseconds / _interval.inMicroseconds)
        .clamp(0.0, 1.0);
    return GlidePose(
      GeoPoint(
        _lerp(from.position.lat, to.position.lat, t),
        _lerp(from.position.lon, to.position.lon, t),
      ),
      lerpHeading(from.headingDeg, to.headingDeg, t),
      _lerp(from.zoom, to.zoom, t),
    );
  }

  void _measure(Duration gap) {
    final clamped = gap < _minInterval
        ? _minInterval
        : gap > _maxInterval
        ? _maxInterval
        : gap;
    final us =
        _interval.inMicroseconds * (1 - _smoothing) +
        clamped.inMicroseconds * _smoothing;
    _interval = Duration(microseconds: us.round());
  }
}

/// Bildraten fürs Gleiten der Karte, an einer Stelle zum Nachstellen nach der Probefahrt.
abstract final class GlideRates {
  /// Darunter gilt man als stehend: kein Gleiten, die Karte springt zum Fix.
  static const minKmh = 3.0;

  /// Bilder je Sekunde von [minKmh] bis [fastKmh].
  static const fps = 20;

  /// Beim Abbiegen, wenn sich der Kurs schneller als [turnDegPerSec] dreht. Vorerst wie [fps]:
  /// höchstens 20, bis die Probefahrt zeigt, ob es beim Drehen mehr braucht.
  static const turningFps = 20;
  static const turnDegPerSec = 10.0;

  /// Über [fastKmh]: lange Geraden, etwas weniger reicht.
  static const fastFps = 15;
  static const fastKmh = 100.0;

  /// Nie schneller als dieses Vielfache der gemessenen Zeichenzeit: kommt das Zeichnen nicht
  /// hinterher, stockt die Karte sonst ganz (im Emulator ab etwa 30 ms je Bild gesehen).
  static const rasterGuard = 3;
}

/// Ruhiger Kurs für die Ausrichtung der Karte nach Fahrtrichtung.
abstract final class HeadingRules {
  /// Darunter ist der GPS-Kurs unzuverlässig: die Karte behält ihre Richtung.
  static const holdBelowKmh = 8.0;

  /// Kleinere Änderungen sind meist Rauschen und drehen die Karte nicht.
  static const deadbandDeg = 3.0;

  /// Anteil einer Änderung, den ein Fix übernimmt. Eine Kurve von 90° steht nach etwa drei
  /// Fixes, ohne dass einzelne Ausreißer die Karte herumreißen.
  static const smoothing = 0.5;
}

/// Glättet den GPS-Kurs für die Ausrichtung der Karte: hält ihn bei langsamer Fahrt und im
/// Stand, übergeht kleines Rauschen und folgt Kurven über den kürzeren Winkel.
class HeadingSmoother {
  double? _value;

  /// Geglätteter Kurs, null solange keiner bekannt ist.
  double? get value => _value;

  /// Neuer Fix mit gemessenem Kurs [headingDeg] bei [speedKmh]; gibt den geglätteten Kurs zurück.
  double? update(double? headingDeg, double speedKmh) {
    final last = _value;
    if (headingDeg == null || speedKmh < HeadingRules.holdBelowKmh) return last;
    if (last == null) return _value = normalizeDegrees(headingDeg);
    final delta = ((headingDeg - last + 540) % 360) - 180;
    if (delta.abs() < HeadingRules.deadbandDeg) return last;
    return _value = normalizeDegrees(last + delta * HeadingRules.smoothing);
  }

  void reset() => _value = null;
}

/// Takt, in dem die Karte zwischen zwei Fixes weitergleitet, nach [GlideRates].
Duration glideFrameInterval(
  double speedKmh, {
  double turnDegPerSec = 0,
  Duration raster = Duration.zero,
}) {
  final fps = turnDegPerSec > GlideRates.turnDegPerSec
      ? GlideRates.turningFps
      : speedKmh > GlideRates.fastKmh
      ? GlideRates.fastFps
      : GlideRates.fps;
  final base = Duration(microseconds: 1000000 ~/ fps);
  final guard = raster * GlideRates.rasterGuard;
  return guard > base ? guard : base;
}

/// Gleitender Mittelwert der Zeichenzeit je Bild.
class RasterAverage {
  Duration _value = Duration.zero;

  Duration get value => _value;

  void add(Duration d) {
    _value = _value == Duration.zero
        ? d
        : Duration(
            microseconds: (_value.inMicroseconds * 0.9 + d.inMicroseconds * 0.1)
                .round(),
          );
  }
}

/// Kurs zwischen [a] und [b] über den kürzeren Winkel (359° → 1° dreht 2°, nicht 358°).
double? lerpHeading(double? a, double? b, double t) {
  if (a == null) return b;
  if (b == null) return a;
  final delta = ((b - a + 540) % 360) - 180;
  return normalizeDegrees(a + delta * t);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _seconds(Duration d) => d.inMicroseconds / 1e6;
