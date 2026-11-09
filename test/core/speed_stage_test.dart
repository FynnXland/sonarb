import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/model/speed_stage.dart';

SpeedStage _at(
  int kmh, {
  int? limit = 50,
  bool? overspeed,
  int tolerance = 3,
}) => speedStageOf(
  speedKmh: kmh,
  limitKmh: limit,
  // Wie die Warnlogik: zu schnell erst über Limit plus Toleranz.
  overspeed: overspeed ?? (limit != null && kmh > limit + tolerance),
);

void main() {
  test('bis zum Limit normal', () {
    expect(_at(30), SpeedStage.normal);
    expect(_at(50), SpeedStage.normal);
  });

  test('über dem Limit bis zur Toleranz: Toleranz', () {
    expect(_at(51), SpeedStage.tolerance);
    expect(_at(53), SpeedStage.tolerance);
  });

  test('über der Toleranz bis +10: erste Stufe', () {
    expect(_at(54), SpeedStage.over);
    expect(_at(60), SpeedStage.over);
  });

  test('+11 bis +20: zweite Stufe', () {
    expect(_at(61), SpeedStage.high);
    expect(_at(70), SpeedStage.high);
  });

  test('ab +21 Punkt, ohne Toleranzabzug', () {
    expect(_at(71), SpeedStage.points);
    expect(_at(150), SpeedStage.points);
    expect(_at(121, limit: 100), SpeedStage.points);
    expect(_at(120, limit: 100), SpeedStage.high);
  });

  test('Farbe schaltet mit dem Piep, auch bei anderer Toleranz', () {
    expect(_at(51, tolerance: 0), SpeedStage.over);
    expect(_at(60, tolerance: 10), SpeedStage.tolerance);
    expect(_at(61, tolerance: 10), SpeedStage.high);
    // Gerundet zeigt die Anzeige 50, gepiept wird schon (50,4 > 50 + 0).
    expect(_at(50, overspeed: true), SpeedStage.over);
  });

  test('ab +21 rot, auch wenn die Warnlogik nicht piept', () {
    expect(_at(71, overspeed: false), SpeedStage.points);
  });

  test('ohne Limit immer normal', () {
    expect(_at(250, limit: null), SpeedStage.normal);
    expect(_at(250, limit: null, overspeed: true), SpeedStage.normal);
  });
}
