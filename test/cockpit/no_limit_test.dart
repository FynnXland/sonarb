import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_state.dart';
import 'package:sonarb/features/cockpit/instruments.dart';
import 'package:sonarb/features/warning/warning.dart';

import 'fakes.dart';

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Widget _row(DriveState drive) => MaterialApp(
  theme: buildSonarTheme(),
  home: Scaffold(
    body: SizedBox(width: 360, height: 120, child: SpeedRow(drive: drive)),
  ),
);

void main() {
  group('Durchreichen bis zum Zustand', () {
    late TestRig rig;
    late ProviderContainer c;

    setUp(() async {
      rig = await TestRig.create();
      c = rig.container();
      rig.engine.respond = (_, _, limit) => WarningUpdate(
        active: const [],
        sounds: const [],
        speedLimitKmh: limit,
      );
    });

    Future<DriveState> drive({int? limit, bool noLimit = false}) async {
      rig.alerts
        ..limit = limit
        ..noLimit = noLimit;
      await c.read(driveControllerProvider.notifier).start();
      rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 180));
      await _settle();
      return c.read(driveControllerProvider);
    }

    test(
      'kein Limit: Zustand sagt es, die Warnlogik bekommt keine Zahl',
      () async {
        final s = await drive(noLimit: true);
        expect(s.speedLimitKmh, isNull);
        expect(s.noSpeedLimit, isTrue);
        expect(rig.engine.calls.single.$3, isNull);
      },
    );

    test('Zahl: kein „kein Limit“', () async {
      final s = await drive(limit: 120);
      expect(s.speedLimitKmh, 120);
      expect(s.noSpeedLimit, isFalse);
    });

    test('fehlend: unbekannt', () async {
      final s = await drive();
      expect(s.speedLimitKmh, isNull);
      expect(s.noSpeedLimit, isFalse);
    });

    test('Limit der Messstelle voraus geht vor', () async {
      rig.engine.respond = (_, _, _) =>
          const WarningUpdate(active: [], sounds: [], speedLimitKmh: 100);
      final s = await drive(noLimit: true);
      expect(s.speedLimitKmh, 100);
      expect(s.noSpeedLimit, isFalse);
    });
  });

  test('ohne Limit löst „zu schnell“ nicht aus, auch bei 210 km/h', () {
    final engine = createWarningEngine();
    final update = engine.update(
      fixAt(52.5, 13.4, speedKmh: 210),
      const [],
      roadSpeedLimitKmh: null,
    );
    expect(update.overspeed, isFalse);
    expect(update.speedLimitKmh, isNull);
  });

  group('Anzeige', () {
    testWidgets('kein Limit: Zeichen 282', (tester) async {
      await tester.pumpWidget(
        _row(DriveState(fix: fixAt(52.5, 13.4), noSpeedLimit: true)),
      );
      expect(find.byType(NoSpeedLimitSign), findsOneWidget);
      expect(find.bySemanticsLabel('Kein Tempolimit'), findsOneWidget);
      expect(find.text('Limit\nunbekannt'), findsNothing);
    });

    testWidgets('unbekannt: Text', (tester) async {
      await tester.pumpWidget(_row(DriveState(fix: fixAt(52.5, 13.4))));
      expect(find.text('Limit\nunbekannt'), findsOneWidget);
      expect(find.byType(NoSpeedLimitSign), findsNothing);
    });

    testWidgets('Zahl: rundes Schild', (tester) async {
      await tester.pumpWidget(
        _row(
          DriveState(
            fix: fixAt(52.5, 13.4),
            speedLimitKmh: 120,
            noSpeedLimit: true,
          ),
        ),
      );
      expect(find.byType(SpeedLimitSign), findsOneWidget);
      expect(find.byType(NoSpeedLimitSign), findsNothing);
    });
  });
}
