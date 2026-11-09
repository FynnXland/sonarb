import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sonarb/core/contracts/alert_audio.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_state.dart';
import 'package:sonarb/features/cockpit/format.dart';
import 'package:sonarb/features/cockpit/location_service.dart';

import 'fakes.dart';

Future<void> settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late TestRig rig;
  late ProviderContainer c;

  setUp(() async {
    rig = await TestRig.create();
    c = rig.container();
  });

  DriveController ctrl() => c.read(driveControllerProvider.notifier);
  DriveState state() => c.read(driveControllerProvider);

  test('vergangene Beobachtungen nur, wenn Hotspots gemeldet werden', () async {
    await ctrl().start();
    rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 58));
    await settle();
    rig.engine.settings = rig.engine.settings.copyWith(heatSpotsEnabled: false);
    rig.location.emitDriving(fixAt(52.501, 13.4, speedKmh: 58));
    await settle();
    expect(rig.alerts.historyCalls.first, isTrue);
    expect(rig.alerts.historyCalls.skip(1), everyElement(isFalse));
  });

  test('Strecke voraus geht an die Warnlogik', () async {
    const line = [GeoPoint(52.5, 13.4), GeoPoint(52.5, 13.41)];
    rig.alerts.ahead = line;
    await ctrl().start();
    rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 58));
    await settle();
    expect(rig.engine.aheadCalls.last, line);
    rig.alerts.ahead = null;
    rig.location.emitDriving(fixAt(52.501, 13.4, speedKmh: 58));
    await settle();
    expect(rig.engine.aheadCalls.last, isNull);
  });

  test('Fix läuft durch Punkte, Tempolimit, Engine und Ton', () async {
    rig.alerts.points = [camera];
    rig.alerts.limit = 50;
    rig.engine.respond = (fix, points, limit) => WarningUpdate(
      active: [
        ActiveWarning(
          point: points.first,
          distanceMeters: 420,
          level: WarningLevel.pre,
        ),
      ],
      sounds: const [WarningSound.overspeed],
      speedLimitKmh: limit,
      overspeed: true,
    );

    await ctrl().start();
    expect(state().phase, DrivePhase.running);

    final fix = fixAt(52.5, 13.4, speedKmh: 58);
    rig.location.emitDriving(fix);
    await settle();
    expect(state().motion, MotionState.driving);

    expect(rig.alerts.pointCalls.single, fix.position);
    final (engineFix, candidates, limit) = rig.engine.calls.single;
    expect(engineFix, same(fix));
    expect(candidates, [camera]);
    expect(limit, 50);
    expect(rig.audio.played, [WarningSound.overspeed]);

    final s = state();
    expect(s.fix, same(fix));
    expect(s.speedLimitKmh, 50);
    expect(s.overspeed, isTrue);
    expect(s.primary?.distanceMeters, 420);
    expect(s.gpsQuality, GpsQuality.good);
  });

  test('jedes Signal wird abgespielt', () async {
    rig.engine.respond = (_, _, _) => const WarningUpdate(
      active: [],
      sounds: [WarningSound.testTone, WarningSound.overspeed],
    );
    await ctrl().start();
    rig.location.emitDriving(fixAt(52.5, 13.4));
    await settle();
    expect(rig.audio.played, [WarningSound.testTone, WarningSound.overspeed]);
  });

  test('alerts.changes löst keine Neuberechnung aus', () async {
    await ctrl().start();
    rig.location.emitDriving(fixAt(52.5, 13.4));
    await settle();
    rig.alerts.changesController.add(null);
    await settle();
    expect(rig.engine.calls, hasLength(1));
  });

  test('Beenden setzt die Engine zurück und ignoriert weitere Fixes', () async {
    await ctrl().start();
    rig.location.emitDriving(fixAt(52.5, 13.4));
    await settle();
    ctrl().stop();
    expect(rig.engine.resets, 1);
    expect(rig.companion.stops, 1);
    expect(state().phase, DrivePhase.idle);
    expect(state().fix, isNull);

    rig.location.emit(fixAt(52.6, 13.4));
    await settle();
    expect(rig.engine.calls, hasLength(1));
  });

  for (final access in [
    LocationAccess.denied,
    LocationAccess.deniedForever,
    LocationAccess.serviceOff,
  ]) {
    test('ohne Zugriff ($access) blockiert', () async {
      rig.location.access = access;
      await ctrl().start();
      expect(state().phase, DrivePhase.blocked);
      expect(state().access, access);
      expect(state().usableFix, isNull);
    });
  }

  test('GPS im Betrieb ausgeschaltet: blockiert mit Grund', () async {
    await ctrl().start();
    rig.location.controller.addError(
      const LocationAccessError(LocationAccess.serviceOff),
    );
    await settle();
    expect(state().phase, DrivePhase.blocked);
    expect(state().access, LocationAccess.serviceOff);
    expect(rig.engine.resets, 1);
  });

  testWidgets('nach 5 s ohne Fix gilt das Signal als verloren', (tester) async {
    var now = DateTime(2026, 10, 29, 12);
    final container = ProviderContainer.test(
      overrides: [...rig.overrides, clockProvider.overrideWithValue(() => now)],
    );
    final ctl = container.read(driveControllerProvider.notifier);
    await ctl.start();
    rig.location.emit(fixAt(52.5, 13.4));
    await tester.pump();
    await tester.pump();
    expect(container.read(driveControllerProvider).stale, isFalse);

    now = now.add(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    final s = container.read(driveControllerProvider);
    expect(s.stale, isTrue);
    expect(s.gpsQuality, GpsQuality.none);
    expect(s.usableFix, isNull);
    ctl.stop();
  });

  group('fixFromPosition', () {
    Position pos({
      double speed = 10,
      double heading = 123,
      bool hasHeading = true,
      bool hasHeadingAccuracy = true,
      double headingAccuracy = 10,
    }) => Position(
      latitude: 52.5,
      longitude: 13.4,
      timestamp: DateTime.utc(2026),
      accuracy: 4,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading,
      headingAccuracy: headingAccuracy,
      speed: speed,
      speedAccuracy: 0,
      hasHeading: hasHeading,
      hasHeadingAccuracy: hasHeadingAccuracy,
      hasSpeed: true,
    );

    test('Kurs bei Fahrt mit brauchbarer Genauigkeit', () {
      expect(fixFromPosition(pos()).headingDeg, 123);
    });
    test('kein Kurs unter 2 m/s', () {
      expect(fixFromPosition(pos(speed: 1.5)).headingDeg, isNull);
    });
    test('kein Kurs bei großer Unsicherheit', () {
      expect(fixFromPosition(pos(headingAccuracy: 90)).headingDeg, isNull);
    });
    test('kein Kurs, wenn das Gerät keinen meldet', () {
      expect(fixFromPosition(pos(hasHeading: false)).headingDeg, isNull);
    });
    test('fehlende Kursgenauigkeit reicht nicht zum Verwerfen', () {
      expect(fixFromPosition(pos(hasHeadingAccuracy: false)).headingDeg, 123);
    });
  });

  test('Distanzformat', () {
    expect(formatDistance(347), '350 m');
    expect(formatDistance(4), '0 m');
    expect(formatDistance(996), '1,0 km');
    expect(formatDistance(1234), '1,2 km');
  });
}
