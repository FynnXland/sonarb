import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/core/model/position_fix.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_state.dart';
import 'package:sonarb/features/cockpit/standstill_gate.dart';
import 'package:sonarb/features/warning/warning.dart';

import '../warning/drive_sim.dart';
import 'fakes.dart';

PositionFix _standing(GeoPoint at, DateTime time, {double jitter = 0}) =>
    PositionFix(
      position: jitter == 0 ? at : destinationPoint(at, 0, jitter),
      speedMps: 0.2,
      accuracyMeters: 5,
      time: time,
      headingDeg: 90,
    );

void main() {
  final t0 = DateTime.utc(2026, 11, 2, 12);

  group('StandstillGate', () {
    test('bei Fahrt kommt jeder Fix durch', () {
      final g = StandstillGate();
      for (var i = 0; i < 5; i++) {
        expect(g.admit(fixAt(52.5, 13.4 + i * 1e-4, speedKmh: 50), t0), isTrue);
      }
    });

    test('im Stand nur Tempowechsel, Bewegung oder alle 10 s', () {
      final g = StandstillGate();
      const at = GeoPoint(52.5, 13.4);
      DateTime s(int sec) => t0.add(Duration(seconds: sec));
      expect(g.admit(_standing(at, s(0)), s(0)), isTrue);
      expect(g.admit(_standing(at, s(1), jitter: 2), s(1)), isFalse);
      expect(g.admit(_standing(at, s(2)), s(2)), isFalse);
      expect(g.admit(_standing(at, s(10)), s(10)), isTrue);
      expect(g.admit(_standing(at, s(11), jitter: 4), s(11)), isTrue);
    });

    test('Anzeige läuft bis 0 km/h herunter', () {
      final g = StandstillGate();
      const at = GeoPoint(52.5, 13.4);
      for (final (i, kmh) in [(0, 2.9), (1, 1.4), (2, 0.4), (3, 0.3)].indexed) {
        final fix = PositionFix(
          position: at,
          speedMps: kmh.$2 / 3.6,
          accuracyMeters: 5,
          time: t0.add(Duration(seconds: i)),
        );
        expect(g.admit(fix, t0.add(Duration(seconds: i))), i < 3);
      }
    });
  });

  group('Fahrsimulation mit Ampelhalt', () {
    late TestRig rig;
    late ProviderContainer c;
    late DateTime now;
    late WarningEngine real;

    const camera = 1200.0;

    setUp(() async {
      rig = await TestRig.create();
      now = t0;
      final sim = DriveSim();
      rig.alerts.points = [
        AlertPoint(
          id: 'osm:node/9',
          kind: AlertKind.speedCamera,
          position: sim.at(camera),
          source: 'osm',
          travelBearings: const [90],
          maxSpeed: 50,
        ),
      ];
      real = createWarningEngine();
      rig.engine.respond = (fix, points, limit) =>
          real.update(fix, points, roadSpeedLimitKmh: limit);
      c = ProviderContainer.test(
        overrides: [
          ...rig.overrides,
          clockProvider.overrideWithValue(() => now),
        ],
      );
    });

    Future<void> feed(WidgetTester tester, List<PositionFix> fixes) async {
      for (final f in fixes) {
        now = now.add(const Duration(seconds: 1));
        rig.location.emit(f);
        await tester.pump();
        await tester.pump();
      }
    }

    /// (Stufe, Abstand gerundet) aller Ansagen.
    List<(WarningStage, int)> events() => [
      for (final e in rig.audio.announced) (e.stage, e.distanceMeters.round()),
    ];

    testWidgets('Warnungen am selben Abstand wie ohne Halt, weniger Arbeit', (
      tester,
    ) async {
      final ctl = c.read(driveControllerProvider.notifier);
      final sim = DriveSim();
      await ctl.start();
      await feed(tester, sim.drive(0, camera + 100, speed: 15));
      final straight = events();
      final straightCalls = rig.engine.calls.length;
      expect(straight, isNotEmpty);
      unawaited(ctl.stop());
      await tester.pump();

      rig.audio.announced.clear();
      rig.engine.calls.clear();
      real = createWarningEngine();
      final sim2 = DriveSim();
      await ctl.start();
      await feed(tester, sim2.drive(0, 600, speed: 15));
      final stop = sim2.at(600);
      await feed(tester, [
        for (var i = 0; i < 90; i++)
          _standing(
            stop,
            t0.add(Duration(seconds: 100 + i)),
            jitter: i.isEven ? 0 : 1.5,
          ),
      ]);
      expect(
        c.read(driveControllerProvider).motion,
        MotionState.driving,
        reason: 'Ampel ist kein Fahrtende',
      );
      await feed(tester, sim2.drive(600, camera + 100, speed: 15));

      expect(events(), straight);
      // 90 s Halt: höchstens alle 10 s ein Durchlauf statt 90.
      expect(rig.engine.calls.length - straightCalls, lessThanOrEqualTo(12));
      unawaited(ctl.stop());
      await tester.pump();
    });

    testWidgets('positionFixes liefert auch im Stand jeden Fix', (
      tester,
    ) async {
      final ctl = c.read(driveControllerProvider.notifier);
      final got = <PositionFix>[];
      // Abo endet mit dem Container; Kündigen innerhalb der Fake-Zeit hängt im Test.
      ctl.positionFixes.listen(got.add);
      await ctl.start();
      final sim = DriveSim();
      await feed(tester, sim.drive(0, 100, speed: 15));
      final moving = got.length;
      final stateFix = c.read(driveControllerProvider).fix;
      await feed(tester, [
        for (var i = 0; i < 5; i++)
          _standing(sim.at(100), t0.add(Duration(seconds: 50 + i))),
      ]);
      expect(got, hasLength(moving + 5));
      expect(
        c.read(driveControllerProvider).fix,
        isNot(same(stateFix)),
        reason: 'erster Stand-Fix zeigt das Tempo 0',
      );
      unawaited(ctl.stop());
      await tester.pump();
    });
  });
}
