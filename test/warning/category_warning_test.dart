import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/warning/warning.dart';

import 'drive_sim.dart';

const announce = WarningStage.announce;
const reminder = WarningStage.reminder;
const imminent = WarningStage.imminent;

void main() {
  late DriveSim sim;
  late WarningEngine engine;

  setUp(() {
    sim = DriveSim();
    engine = createWarningEngine();
  });

  AlertPoint at(
    double along,
    AlertCategory c, {
    AlertKind kind = AlertKind.construction,
    String id = 'p',
    int? maxSpeed,
  }) => cam(
    sim.at(along),
    id: id,
    kind: kind,
    maxSpeed: maxSpeed,
  ).copyWith(category: c);

  test('Kontrollen und Gefahrenstellen: nur die erste Ansage, auch wenn zu schnell', () {
    for (final c in [
      AlertCategory.heightControl,
      AlertCategory.weightControl,
      AlertCategory.accessControl,
      AlertCategory.noOvertaking,
      AlertCategory.closure,
      AlertCategory.busLane,
      AlertCategory.trafficJamEnd,
      AlertCategory.accident,
      AlertCategory.officialNotice,
      AlertCategory.dayRoadworks,
    ]) {
      engine.reset();
      final r = run(engine, sim.drive(0, 2300), [at(2000, c)], road: 30);
      expect(r.stages(), [announce], reason: '$c');
    }
  });

  test('Stauende und Unfall früher: 1 km oder 40 s, Baustelle wie üblich', () {
    final jam = at(3000, AlertCategory.trafficJamEnd, id: 'jam');
    final works = at(3000, AlertCategory.dayRoadworks, id: 'works');
    final city = run(engine, sim.drive(0, 3300), [jam, works]); // 20 m/s
    expect(city.distanceAt(announce, 'jam'), inInclusiveRange(979, 1000));
    expect(city.distanceAt(announce, 'works'), inInclusiveRange(579, 600));

    engine.reset();
    final fast = run(engine, sim.drive(0, 3300, speed: 36.1), [jam]);
    expect(fast.distanceAt(announce), inInclusiveRange(1444 - 36.1, 1444.5));
  });

  group('Abschnittskontrolle', () {
    test(
      'Ende: eine Ansage unmittelbar davor, keine Stufen, auch wenn zu schnell',
      () {
        final end = at(
          2000,
          AlertCategory.sectionEnd,
          kind: AlertKind.sectionControl,
          maxSpeed: 50,
        );
        final r = run(engine, sim.drive(0, 2300), [
          end,
        ]); // 72 km/h bei Limit 50
        expect(r.stages(), [announce]);
        expect(r.distanceAt(announce), inInclusiveRange(30, 50));
        final shown = r.updates.where((u) => u.primary != null);
        expect(
          shown.every((u) => u.primary!.level == WarningLevel.pre),
          isTrue,
        );
        expect(shown.every((u) => u.speedLimitKmh == null), isTrue);
      },
    );

    test('Ende auf der Autobahn: Zone wächst mit dem Tempo, mindestens ein Fix darin', () {
      final end = at(
        3000,
        AlertCategory.sectionEnd,
        kind: AlertKind.sectionControl,
      );
      final r = run(engine, sim.drive(0, 3300, speed: 36.1), [end]);
      expect(r.stages(), [announce]);
      expect(r.distanceAt(announce), lessThan(2.5 * 36.1));
    });

    test('Anfang gestuft, Ende nur angesagt', () {
      final start = at(
        1000,
        AlertCategory.sectionStart,
        kind: AlertKind.sectionControl,
        id: 'start',
        maxSpeed: 50,
      );
      final end = at(
        3000,
        AlertCategory.sectionEnd,
        kind: AlertKind.sectionControl,
        id: 'end',
        maxSpeed: 50,
      );
      final r = run(engine, sim.drive(0, 3300), [start, end]);
      expect(r.stages('start'), [announce, reminder, imminent]);
      expect(r.stages('end'), [announce]);
    });
  });

  test('Blitzeranhänger und mobiler Rotlichtblitzer: alle Stufen', () {
    for (final c in [
      AlertCategory.semiStationary,
      AlertCategory.mobileRedLight,
    ]) {
      engine.reset();
      final r = run(engine, sim.drive(0, 2300), [
        at(2000, c, kind: AlertKind.live, maxSpeed: 50),
      ]);
      expect(r.stages(), [announce, reminder, imminent], reason: '$c');
    }
  });
}
