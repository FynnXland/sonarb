import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/position_fix.dart';
import 'package:sonarb/features/cockpit/heading_estimator.dart';

final _t0 = DateTime.utc(2026, 10, 29, 12);

/// Fix ohne Kurs; Tempo 0 heißt "nicht gemeldet".
PositionFix fix(
  double lat,
  double lon,
  int seconds, {
  double speed = 0,
  double? heading,
  double accuracy = 5,
}) => PositionFix(
  position: GeoPoint(lat, lon),
  speedMps: speed,
  accuracyMeters: accuracy,
  time: _t0.add(Duration(seconds: seconds)),
  headingDeg: heading,
);

void main() {
  const lat = 52.51262;

  test('gemeldeter Kurs bleibt unverändert', () {
    final e = HeadingEstimator();
    final out = e.apply(fix(lat, 13.47, 0, speed: 10, heading: 123));
    expect(out.headingDeg, 123);
  });

  test('Fahrt nach Osten ohne Kurs und ohne Tempo ergibt etwa 90 Grad', () {
    final e = HeadingEstimator();
    expect(e.apply(fix(lat, 13.47, 0)).headingDeg, isNull);
    // 0.00035 Grad Länge sind hier rund 23 m pro Sekunde.
    final out = e.apply(fix(lat, 13.47035, 1));
    expect(out.headingDeg, closeTo(90, 1));
  });

  test('Fahrt nach Norden mit gemeldetem Tempo', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, speed: 12));
    final out = e.apply(fix(lat + 0.00018, 13.47, 1, speed: 12));
    expect(out.headingDeg, closeTo(0, 1));
  });

  test('Abstand unter 15 m ergibt keinen neuen Kurs', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, speed: 5));
    final out = e.apply(fix(lat, 13.47012, 1, speed: 5));
    expect(out.headingDeg, isNull);
  });

  test('Kurs sammelt sich über mehrere kurze Schritte', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, speed: 5));
    expect(e.apply(fix(lat, 13.47012, 1, speed: 5)).headingDeg, isNull);
    final out = e.apply(fix(lat, 13.47024, 2, speed: 5));
    expect(out.headingDeg, closeTo(90, 1));
  });

  test('Abstand muss auch die doppelte Genauigkeit übertreffen', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, speed: 10, accuracy: 30));
    // rund 23 m: über 15 m, aber unter 2 x 30 m
    final out = e.apply(fix(lat, 13.47035, 1, speed: 10, accuracy: 30));
    expect(out.headingDeg, isNull);
  });

  test('zu langsam: kein neuer Kurs', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, speed: 1));
    final out = e.apply(fix(lat, 13.47035, 1, speed: 1));
    expect(out.headingDeg, isNull);
  });

  test('Tempo aus Abstand und Zeit, wenn es fehlt', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0));
    // rund 23 m in 10 s: 2,3 m/s, schnell genug für einen Kurs
    final out = e.apply(fix(lat, 13.47035, 10));
    expect(out.headingDeg, closeTo(90, 1));
    // rund 7 m in 10 s: 0,7 m/s
    final slow = HeadingEstimator()..apply(fix(lat, 13.47, 0));
    expect(slow.apply(fix(lat, 13.47010, 10)).headingDeg, isNull);
  });

  test('Stillstand hält den Kurs höchstens 10 Sekunden', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, speed: 10));
    e.apply(fix(lat, 13.47035, 1, speed: 10));
    expect(e.apply(fix(lat, 13.47035, 5)).headingDeg, closeTo(90, 1));
    expect(e.apply(fix(lat, 13.47035, 11)).headingDeg, closeTo(90, 1));
    expect(e.apply(fix(lat, 13.47035, 12)).headingDeg, isNull);
  });

  test('Kurs folgt einer Kurve', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, speed: 10));
    expect(
      e.apply(fix(lat, 13.47035, 1, speed: 10)).headingDeg,
      closeTo(90, 1),
    );
    final north = e.apply(fix(lat + 0.00025, 13.47035, 2, speed: 10));
    expect(north.headingDeg, closeTo(0, 1));
  });

  test('Winziges gemeldetes Tempo (5e-16) zählt als fehlend', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, speed: 5e-16));
    final out = e.apply(fix(lat, 13.47035, 1, speed: 5e-16));
    expect(out.headingDeg, closeTo(90, 1));
  });

  test('geschätztes Tempo steht im Ergebnis, wenn es fehlt', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0));
    final out = e.apply(fix(lat, 13.47035, 1));
    // rund 23 m in 1 s
    expect(out.speedMps, closeTo(23.5, 1));
    expect(out.position, const GeoPoint(lat, 13.47035));
    expect(out.accuracyMeters, 5);
  });

  test('winziges gemeldetes Tempo wird durch das geschätzte ersetzt', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, speed: 5e-16));
    final out = e.apply(fix(lat, 13.47035, 1, speed: 5e-16));
    expect(out.speedMps, closeTo(23.5, 1));
  });

  test('gemeldetes Tempo bleibt unverändert', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, speed: 10));
    final out = e.apply(fix(lat, 13.47035, 1, speed: 10));
    expect(out.speedMps, 10);
  });

  test('GPS-Rauschen unter der Genauigkeit ergibt kein Tempo', () {
    final e = HeadingEstimator();
    e.apply(fix(lat, 13.47, 0, accuracy: 10));
    // rund 6,7 m in 1 s bei 10 m Genauigkeit
    final out = e.apply(fix(lat, 13.47010, 1, accuracy: 10));
    expect(out.speedMps, 0);
    expect(out.headingDeg, isNull);
  });
}
