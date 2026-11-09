import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/cockpit/follow_glide.dart';

final _t0 = DateTime(2026, 11, 2, 12);
DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));

/// 25 m/s (90 km/h) nach Osten: rund 0,000369° Länge je Sekunde bei 52,5° Breite.
const _lat = 52.5;
const _perSecond = 25 / 67770;
GeoPoint _east(double seconds) => GeoPoint(_lat, 13.4 + seconds * _perSecond);

bool _fix(
  FollowGlide g,
  int ms,
  GeoPoint p, {
  double? heading = 90,
  double speed = 25,
  double zoom = 16,
  bool glide = true,
}) => g.onFix(
  position: p,
  headingDeg: heading,
  speedMps: speed,
  zoom: zoom,
  now: _at(ms),
  glide: glide,
);

void main() {
  test('erster Fix springt', () {
    final g = FollowGlide();
    expect(_fix(g, 0, _east(0)), isFalse);
    expect(g.at(_at(0))!.position, _east(0));
  });

  test('Zwischenlage: gleitet zur Stelle des nächsten Fixes', () {
    final g = FollowGlide();
    _fix(g, 0, _east(0));
    _fix(g, 1000, _east(1));
    expect(_fix(g, 2000, _east(2)), isTrue);
    // Ziel: Fix plus ein Fix-Abstand Fahrt, also etwa _east(3).
    final half = g.at(_at(2500))!;
    expect(distanceMeters(half.position, _east(2.5)), lessThan(1));
    final end = g.at(_at(3000))!;
    expect(distanceMeters(end.position, _east(3)), lessThan(1));
  });

  test('nahtlos: der nächste Fix startet an der sichtbaren Lage', () {
    final g = FollowGlide();
    _fix(g, 0, _east(0));
    _fix(g, 1000, _east(1));
    final before = g.at(_at(1700))!;
    _fix(g, 1700, _east(1.7));
    final after = g.at(_at(1700))!;
    expect(distanceMeters(before.position, after.position), lessThan(0.01));
  });

  test(
    'bleibt ein Fix aus: höchstens einen Fix-Abstand raten, dann stehen',
    () {
      final g = FollowGlide();
      _fix(g, 0, _east(0));
      _fix(g, 1000, _east(1));
      final end = g.at(_at(2000))!;
      final later = g.at(_at(6000))!;
      expect(later.position, end.position);
      expect(g.active(_at(2500)), isFalse);
    },
  );

  test('Kurs dreht über den kürzeren Winkel', () {
    expect(lerpHeading(359, 1, 0.5), closeTo(0, 1e-9));
    expect(lerpHeading(1, 359, 0.25), closeTo(0.5, 1e-9));
    expect(lerpHeading(350, 10, 0.75), closeTo(5, 1e-9));
    expect(lerpHeading(10, 170, 0.5), closeTo(90, 1e-9));
    expect(lerpHeading(null, 40, 0.5), 40);
    expect(lerpHeading(40, null, 0.5), 40);

    final g = FollowGlide();
    _fix(g, 0, _east(0), heading: 358);
    _fix(g, 1000, _east(1), heading: 4);
    expect(g.at(_at(1500))!.headingDeg, closeTo(1, 1e-6));
  });

  test('große Lücke springt (Tunnel)', () {
    final g = FollowGlide();
    _fix(g, 0, _east(0));
    _fix(g, 1000, _east(1));
    expect(_fix(g, 9000, _east(9)), isFalse);
    expect(g.at(_at(9000))!.position, _east(9));
  });

  test('großer Sprung springt (Ausreißer)', () {
    final g = FollowGlide();
    _fix(g, 0, _east(0));
    _fix(g, 1000, _east(1));
    expect(_fix(g, 2000, _east(30)), isFalse);
    expect(g.at(_at(2000))!.position, _east(30));
  });

  test('ohne Gleiten (Stand, Hintergrund) springt', () {
    final g = FollowGlide();
    _fix(g, 0, _east(0));
    expect(_fix(g, 1000, _east(1), glide: false), isFalse);
    expect(g.at(_at(1200))!.position, _east(1));
  });

  test('Dauer folgt dem gemessenen Fix-Abstand', () {
    final g = FollowGlide();
    for (var i = 0; i <= 12; i++) {
      _fix(g, i * 2000, _east(i * 2.0));
    }
    expect(g.interval.inMilliseconds, closeTo(2000, 30));
    expect(
      g.endsAt!.difference(_at(24000)).inMicroseconds,
      g.interval.inMicroseconds,
    );
  });

  test('Bildtakt nach Tempo und Abbiegen', () {
    int fps(Duration d) => (1000000 / d.inMicroseconds).round();
    expect(fps(glideFrameInterval(50)), GlideRates.fps);
    expect(fps(glideFrameInterval(130)), GlideRates.fastFps);
    expect(
      fps(glideFrameInterval(50, turnDegPerSec: 25)),
      GlideRates.turningFps,
    );
    expect(fps(glideFrameInterval(50, turnDegPerSec: 5)), GlideRates.fps);
  });

  test('Kursdrehung je Sekunde aus zwei Fixes', () {
    final g = FollowGlide();
    _fix(g, 0, _east(0), heading: 350);
    _fix(g, 1000, _east(1), heading: 10);
    expect(g.turnDegPerSec, closeTo(20, 1e-9));
    _fix(g, 2000, _east(2), heading: 12);
    expect(g.turnDegPerSec, closeTo(2, 1e-9));
  });

  test('Bildtakt bremst, wenn das Zeichnen langsam ist', () {
    expect(
      glideFrameInterval(50, raster: const Duration(milliseconds: 35)),
      const Duration(milliseconds: 35) * GlideRates.rasterGuard,
    );
    expect(
      glideFrameInterval(50, raster: const Duration(milliseconds: 2)),
      glideFrameInterval(50),
    );
    final avg = RasterAverage();
    for (var i = 0; i < 50; i++) {
      avg.add(const Duration(milliseconds: 30));
    }
    expect(avg.value.inMilliseconds, 30);
  });
}
