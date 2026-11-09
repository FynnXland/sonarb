import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/services.dart';
import 'package:sonarb/features/background/background.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_state.dart';

import 'fakes.dart';

class FakeMonitor implements BackgroundMonitor {
  int starts = 0;
  int stops = 0;
  int leaves = 0;
  final shown = <MonitorSnapshot>[];
  final stopButton = StreamController<void>.broadcast();

  @override
  Future<void> start(MonitorSnapshot snapshot) async => starts++;

  @override
  void show(MonitorSnapshot snapshot) => shown.add(snapshot);

  @override
  Future<void> stop() async => stops++;

  @override
  Stream<void> get stopRequests => stopButton.stream;

  @override
  Future<void> leaveForeground() async => leaves++;
}

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  Future<void> lifecycle(
    WidgetTester tester,
    List<AppLifecycleState> states,
  ) async {
    for (final s in states) {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
    }
  }

  const hide = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const show = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  testWidgets('stop() wartet auf den Dienst und hinterlässt keine Abos', (
    tester,
  ) async {
    final c = rig.container();
    final ctl = c.read(driveControllerProvider.notifier);
    await ctl.start();
    await tester.pump();
    rig.location.emitDriving(fixAt(52.5, 13.4));
    await tester.pump();
    expect(rig.location.controller.hasListener, isTrue);
    expect(rig.carLink.controller.hasListener, isTrue);

    final gate = rig.companion.stopGate = Completer<void>();
    var done = false;
    unawaited(ctl.stop().then((_) => done = true));
    await tester.pump();
    expect(done, isFalse, reason: 'Dienst noch nicht beendet');
    gate.complete();
    await tester.pump();
    expect(done, isTrue);

    expect(rig.companion.stopsByUser, [true]);
    expect(rig.location.controller.hasListener, isFalse);
    expect(rig.carLink.controller.hasListener, isFalse);
    expect(rig.alerts.statusController.hasListener, isFalse);

    final modes = rig.location.modes.length;
    await tester.pump(const Duration(minutes: 10));
    expect(c.read(driveControllerProvider).phase, DrivePhase.idle);
    expect(rig.location.modes, hasLength(modes), reason: 'kein neues Abo');
    expect(rig.companion.starts, hasLength(1), reason: 'kein Neustart');
  });

  group('BackgroundCompanion', () {
    late FakeMonitor monitor;
    late ProviderContainer c;

    setUp(() {
      monitor = FakeMonitor();
      c = ProviderContainer.test(
        overrides: rig.overridesWithCompanion(
          driveCompanionProvider.overrideWith((ref) {
            final companion = BackgroundCompanion(ref, monitor);
            ref.onDispose(companion.dispose);
            return companion;
          }),
        ),
      );
    });

    DriveController ctl() => c.read(driveControllerProvider.notifier);
    DrivePhase phase() => c.read(driveControllerProvider).phase;

    testWidgets(
      'Beenden im Cockpit: nichts startet von selbst, erst das Öffnen',
      (tester) async {
        await lifecycle(tester, [AppLifecycleState.resumed]);
        await ctl().start();
        await tester.pump();
        expect(monitor.starts, 1);

        await ctl().stop();
        expect(monitor.stops, 1);
        expect(phase(), DrivePhase.idle);

        // Benachrichtigungsleiste auf und zu: kein Öffnen der App.
        await lifecycle(tester, [
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]);
        await tester.pump(const Duration(minutes: 5));
        expect(phase(), DrivePhase.idle);
        expect(monitor.starts, 1);

        await lifecycle(tester, hide);
        await tester.pump(const Duration(minutes: 5));
        expect(phase(), DrivePhase.idle);

        await lifecycle(tester, show);
        expect(phase(), DrivePhase.running);
        expect(monitor.starts, 2);
        await ctl().stop();
      },
    );

    testWidgets(
      'Beenden in der Benachrichtigung: stoppt, App geht nach hinten',
      (tester) async {
        await lifecycle(tester, [AppLifecycleState.resumed]);
        await ctl().start();
        await tester.pump();
        monitor.stopButton.add(null);
        await tester.pump();
        await tester.pump();
        expect(phase(), DrivePhase.idle);
        expect(monitor.stops, 1);
        expect(monitor.leaves, 1);

        await lifecycle(tester, hide);
        await tester.pump(const Duration(minutes: 5));
        expect(phase(), DrivePhase.idle);
        await lifecycle(tester, show);
        expect(phase(), DrivePhase.running);
        await ctl().stop();
      },
    );
  });
}
