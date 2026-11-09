import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/alert_audio.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/position_fix.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_state.dart';
import 'package:sonarb/features/cockpit/location_service.dart';

import 'fakes.dart';

/// Überwachung mit steuerbarer Uhr. Der Ticker läuft in Sekunden-Schritten mit.
class Clocked {
  Clocked(this.rig, this.tester) {
    container = ProviderContainer.test(
      overrides: [...rig.overrides, clockProvider.overrideWithValue(() => now)],
    );
  }

  final TestRig rig;
  final WidgetTester tester;
  DateTime now = DateTime(2026, 10, 29, 12);
  late final ProviderContainer container;

  DriveController get ctl => container.read(driveControllerProvider.notifier);
  DriveState get state => container.read(driveControllerProvider);

  /// Verbindungsmeldungen; „Position gefunden“ prüft eine eigene Gruppe.
  List<StatusMessage> get statuses => [
    for (final m in rig.audio.statuses)
      if (m != StatusMessage.positionFound) m,
  ];

  int get positionFound =>
      rig.audio.statuses.where((m) => m == StatusMessage.positionFound).length;

  Future<void> start() async {
    await ctl.start();
    await tester.pump();
  }

  Future<void> wait(Duration d) async {
    for (var i = 0; i < d.inSeconds; i++) {
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> fix(PositionFix f) async {
    rig.location.emit(f);
    await tester.pump();
    await tester.pump();
  }

  /// Fährt los: so viele schnelle Fixes im Sekundentakt, bis die Fahrt bestätigt ist.
  Future<void> drive({double kmh = 50}) async {
    for (var i = 0; i < 3; i++) {
      await fix(fixAt(52.5, 13.4, speedKmh: kmh));
      await wait(const Duration(seconds: 1));
    }
  }

  /// Fixes im Sekundentakt über [d].
  Future<void> keepDriving(Duration d, {double kmh = 50}) async {
    for (var i = 0; i < d.inSeconds; i++) {
      await fix(fixAt(52.5, 13.4, speedKmh: kmh));
      await wait(const Duration(seconds: 1));
    }
  }

  void sources(PluginStatus osm) => rig.alerts.statusController.add([
    SourceStatus(id: 'osm', name: 'OpenStreetMap', status: osm),
  ]);
}

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  group('Fahrterkennung', () {
    testWidgets(
      'Start misst genau; langsam: keine Warnlogik, kein Tempolimit',
      (tester) async {
        final c = Clocked(rig, tester);
        await c.start();
        expect(c.state.motion, MotionState.unknown);
        expect(rig.location.modes, [LocationMode.precise]);

        await c.fix(fixAt(52.5, 13.4, speedKmh: 4));
        expect(c.state.fix, isNotNull);
        expect(rig.engine.calls, isEmpty);
        expect(rig.alerts.pointCalls, isEmpty);
        c.ctl.stop();
      },
    );

    testWidgets('drei schnelle Fixes: Fahrt, Warnlogik läuft', (tester) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.drive();
      expect(c.state.motion, MotionState.driving);
      expect(c.state.driving, isTrue);
      expect(rig.engine.calls, hasLength(1));
      expect(rig.location.modes, [LocationMode.precise]);
      c.ctl.stop();
    });

    testWidgets('ein einzelner schneller Ausreißer reicht nicht', (
      tester,
    ) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.fix(fixAt(52.5, 13.4, speedKmh: 40));
      await c.fix(fixAt(52.5, 13.4, speedKmh: 40));
      await c.fix(fixAt(52.5, 13.4, speedKmh: 3));
      await c.fix(fixAt(52.5, 13.4, speedKmh: 40));
      expect(c.state.motion, isNot(MotionState.driving));
      expect(rig.engine.calls, isEmpty);
      c.ctl.stop();
    });

    testWidgets('ohne Fahrt nach 30 s Sparmodus, schnelle Sparmessung prüft '
        'wieder genau', (tester) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.fix(fixAt(52.5, 13.4, speedKmh: 0));
      await c.wait(const Duration(seconds: 31));
      expect(c.state.motion, MotionState.stationary);
      expect(rig.location.modes, [LocationMode.precise, LocationMode.economy]);

      await c.fix(fixAt(52.5, 13.4, speedKmh: 30));
      expect(rig.location.modes.last, LocationMode.precise);
      expect(c.state.motion, MotionState.stationary);

      await c.drive(kmh: 30);
      expect(c.state.motion, MotionState.driving);
      c.ctl.stop();
    });

    testWidgets('deutlicher Ortswechsel ohne Tempo prüft genau', (
      tester,
    ) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.wait(const Duration(seconds: 31));
      expect(rig.location.modes.last, LocationMode.economy);

      await c.fix(fixAt(52.5, 13.4, speedKmh: 0, accuracy: 60));
      await c.fix(fixAt(52.5, 13.41, speedKmh: 0, accuracy: 60)); // ~680 m
      expect(rig.location.modes.last, LocationMode.precise);
      c.ctl.stop();
    });

    for (final (name, stand, kmh, stillDriving) in [
      ('Ampelhalt 90 s', const Duration(seconds: 90), 0.0, true),
      ('Stau 4 min, stehend', const Duration(minutes: 4), 0.0, true),
      ('Stau 4 min, im Schritt', const Duration(minutes: 4), 6.0, true),
      ('Parken 10 min', const Duration(minutes: 10), 0.0, false),
      ('Parken, dann 10 min zu Fuß', const Duration(minutes: 10), 5.5, false),
    ]) {
      testWidgets('$name: ${stillDriving ? 'bleibt Fahrt' : 'Fahrt endet'}', (
        tester,
      ) async {
        final c = Clocked(rig, tester);
        await c.start();
        await c.drive();
        await c.keepDriving(stand, kmh: kmh);
        expect(
          c.state.motion,
          stillDriving ? MotionState.driving : MotionState.stationary,
        );
        c.ctl.stop();
      });
    }

    testWidgets('Bluetooth-Audio verbunden: Stau 7 min bleibt Fahrt', (
      tester,
    ) async {
      rig.carLink.initial = true;
      final c = Clocked(rig, tester);
      await c.start();
      await c.drive();
      await c.keepDriving(const Duration(minutes: 7), kmh: 0);
      expect(c.state.motion, MotionState.driving);

      rig.carLink.controller.add(false); // Auto aus
      await c.keepDriving(const Duration(seconds: 2), kmh: 0);
      expect(c.state.motion, MotionState.stationary);
      c.ctl.stop();
    });

    testWidgets(
      'Bluetooth-Audio neu verbunden: 2 min genau messen, auch im Stand',
      (tester) async {
        final c = Clocked(rig, tester);
        await c.start();
        await c.wait(const Duration(seconds: 31));
        expect(rig.location.modes.last, LocationMode.economy);

        rig.carLink.controller.add(true);
        await c.wait(const Duration(seconds: 1));
        expect(rig.location.modes.last, LocationMode.precise);
        await c.keepDriving(const Duration(seconds: 90), kmh: 0);
        expect(rig.location.modes.last, LocationMode.precise);
        expect(c.state.motion, isNot(MotionState.driving));
        await c.drive();
        expect(c.state.motion, MotionState.driving);
        c.ctl.stop();
      },
    );

    testWidgets('rote Ampel (2 min Stand) bleibt Fahrt', (tester) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.drive();
      await c.keepDriving(const Duration(minutes: 2), kmh: 0);
      await c.keepDriving(const Duration(seconds: 2));
      expect(c.state.motion, MotionState.driving);
      expect(rig.engine.resets, 0);
      c.ctl.stop();
    });

    testWidgets('5 min unter 8 km/h: Fahrt endet, Warnungen weg, Sparmodus', (
      tester,
    ) async {
      final c = Clocked(rig, tester);
      rig.alerts.points = [camera];
      rig.engine.respond = (_, points, _) => WarningUpdate(
        active: [
          ActiveWarning(
            point: points.first,
            distanceMeters: 300,
            level: WarningLevel.pre,
          ),
        ],
        sounds: const [],
        speedLimitKmh: 50,
      );
      await c.start();
      await c.drive();
      expect(c.state.primary, isNotNull);

      await c.keepDriving(const Duration(minutes: 5, seconds: 2), kmh: 2);
      expect(c.state.motion, MotionState.stationary);
      expect(c.state.primary, isNull);
      expect(c.state.upcoming, isEmpty);
      expect(c.state.speedLimitKmh, isNull);
      expect(rig.engine.resets, 1);
      expect(rig.location.modes.last, LocationMode.economy);

      final calls = rig.engine.calls.length;
      await c.fix(fixAt(52.5, 13.4, speedKmh: 3));
      expect(rig.engine.calls, hasLength(calls));
      c.ctl.stop();
    });
    testWidgets(
      'ohne Netz-Ortung: Sparmodus hängt fest, GPS-Prüfung erkennt die '
      'Fahrt',
      (tester) async {
        final c = Clocked(rig, tester);
        final old = PositionFix(
          position: const GeoPoint(52.5, 13.4),
          speedMps: 0,
          accuracyMeters: 100,
          time: DateTime.utc(2026, 10, 29, 8),
        );
        await c.start();
        await c.wait(const Duration(seconds: 31));
        expect(rig.location.modes, [
          LocationMode.precise,
          LocationMode.economy,
        ]);

        // Der Anbieter wiederholt die alte Position; GPS-Punkte kommen im Sparmodus nicht an.
        for (var i = 0; i < 20; i++) {
          await c.fix(old);
          await c.wait(const Duration(seconds: 20));
          if (rig.location.modes.last == LocationMode.precise) break;
        }
        expect(rig.location.modes.last, LocationMode.precise);
        expect(c.state.motion, MotionState.stationary);
        expect(c.state.stale, isFalse);

        await c.drive(kmh: 70);
        expect(c.state.motion, MotionState.driving);
        c.ctl.stop();
      },
    );
  });

  group('Verbindungsverlust', () {
    testWidgets('GPS weg während der Fahrt: eine Ansage, Rückkehr ebenso', (
      tester,
    ) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.drive();
      await c.wait(const Duration(seconds: 6));
      expect(c.state.stale, isTrue);
      expect(c.statuses, isEmpty);

      await c.wait(const Duration(seconds: 6));
      expect(c.statuses, [StatusMessage.gpsLost]);
      expect(c.state.gpsLost, isTrue);

      await c.wait(const Duration(seconds: 30));
      expect(c.statuses, [StatusMessage.gpsLost]);

      await c.keepDriving(const Duration(seconds: 2));
      expect(c.statuses, [StatusMessage.gpsLost]);
      await c.keepDriving(const Duration(seconds: 3));
      expect(c.statuses, [StatusMessage.gpsLost, StatusMessage.gpsRestored]);
      expect(c.state.gpsLost, isFalse);
      c.ctl.stop();
    });

    testWidgets('kurze Unterführung (8 s) bleibt stumm', (tester) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.drive();
      await c.wait(const Duration(seconds: 8));
      expect(c.state.stale, isTrue);
      await c.keepDriving(const Duration(seconds: 10));
      expect(c.statuses, isEmpty);
      c.ctl.stop();
    });

    testWidgets('im Stand sind lange Pausen normal', (tester) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.fix(fixAt(52.5, 13.4, speedKmh: 0));
      await c.wait(const Duration(minutes: 2));
      expect(c.state.motion, MotionState.stationary);
      expect(c.state.stale, isFalse);
      expect(c.statuses, isEmpty);
      c.ctl.stop();
    });

    testWidgets(
      'Daten weg: Ansage nach 2 min, Laden zählt nicht als Rückkehr',
      (tester) async {
        final c = Clocked(rig, tester);
        await c.start();
        await c.drive();
        c.sources(PluginStatus.error);
        await c.keepDriving(const Duration(seconds: 60));
        c.sources(PluginStatus.loading);
        await c.keepDriving(const Duration(seconds: 50));
        expect(c.statuses, isEmpty, reason: 'unter 2 min');
        await c.keepDriving(const Duration(seconds: 15));
        expect(c.statuses, [StatusMessage.dataUnavailable]);
        expect(c.state.dataUnavailable, isTrue);

        c.sources(PluginStatus.ok);
        await c.keepDriving(const Duration(seconds: 15));
        expect(c.statuses, [StatusMessage.dataUnavailable]);
        await c.keepDriving(const Duration(seconds: 10));
        expect(c.statuses, [
          StatusMessage.dataUnavailable,
          StatusMessage.dataRestored,
        ]);
        c.ctl.stop();
      },
    );

    testWidgets('flatternde Daten bleiben stumm, auch Minuten lang', (
      tester,
    ) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.drive();
      for (var i = 0; i < 8; i++) {
        c.sources(PluginStatus.error);
        await c.keepDriving(const Duration(seconds: 100));
        c.sources(PluginStatus.ok);
        await c.keepDriving(const Duration(seconds: 3));
      }
      expect(c.statuses, isEmpty);
      c.ctl.stop();
    });

    testWidgets('Daten schon beim Losfahren weg: Ansage bei Fahrtbeginn', (
      tester,
    ) async {
      final c = Clocked(rig, tester);
      await c.start();
      c.sources(PluginStatus.error);
      await c.fix(fixAt(52.5, 13.4, speedKmh: 0));
      await c.wait(const Duration(seconds: 130));
      expect(c.state.dataUnavailable, isTrue);
      expect(c.statuses, isEmpty, reason: 'im Stand bleibt es stumm');
      expect(rig.location.modes.last, LocationMode.economy);

      // Die erste schnelle Sparmessung prüft genau, danach bestätigt sich die Fahrt.
      await c.fix(fixAt(52.5, 13.4, speedKmh: 30));
      await c.drive();
      expect(c.state.motion, MotionState.driving);
      expect(c.statuses, [StatusMessage.dataUnavailable]);

      // Rückkehr während der Fahrt wird danach wieder angesagt.
      c.sources(PluginStatus.ok);
      await c.keepDriving(const Duration(seconds: 25));
      expect(c.statuses, [
        StatusMessage.dataUnavailable,
        StatusMessage.dataRestored,
      ]);
      c.ctl.stop();
    });

    testWidgets('höchstens ein Wechselpaar je 5 min', (tester) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.drive();
      Future<void> outage() async {
        c.sources(PluginStatus.error);
        await c.keepDriving(const Duration(seconds: 125));
        c.sources(PluginStatus.ok);
        await c.keepDriving(const Duration(seconds: 25));
      }

      await outage();
      expect(c.statuses, [
        StatusMessage.dataUnavailable,
        StatusMessage.dataRestored,
      ]);

      // Zweiter Ausfall nach rund 2,5 min: zu früh, bleibt stumm (auch das „wieder da“).
      await outage();
      expect(c.state.dataUnavailable, isFalse);
      expect(c.statuses, hasLength(2));

      // Nach 5 min seit der ersten Ansage wird wieder angesagt.
      await c.keepDriving(const Duration(minutes: 3));
      await outage();
      expect(c.statuses, [
        StatusMessage.dataUnavailable,
        StatusMessage.dataRestored,
        StatusMessage.dataUnavailable,
        StatusMessage.dataRestored,
      ]);
      c.ctl.stop();
    });
  });

  group('Position gefunden', () {
    testWidgets('einmal beim ersten brauchbaren Fix', (tester) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.wait(const Duration(seconds: 3));
      expect(c.positionFound, 0);

      await c.fix(fixAt(52.5, 13.4, speedKmh: 0, accuracy: 1500));
      expect(c.positionFound, 0, reason: 'Funkzelle ist noch keine Position');

      await c.fix(fixAt(52.5, 13.4, speedKmh: 0, accuracy: 12));
      expect(c.positionFound, 1);
      await c.fix(fixAt(52.5, 13.4, speedKmh: 0, accuracy: 8));
      expect(c.positionFound, 1);
      c.ctl.stop();
    });

    testWidgets(
      'nicht erneut bei Moduswechsel oder Rückkehr nach GPS-Verlust',
      (tester) async {
        final c = Clocked(rig, tester);
        await c.start();
        await c.fix(fixAt(52.5, 13.4, speedKmh: 0));
        await c.wait(const Duration(seconds: 31)); // Sparmodus
        await c.fix(fixAt(52.5, 13.4, speedKmh: 40)); // wieder genau
        await c.drive();
        await c.wait(const Duration(seconds: 12)); // GPS weg
        await c.keepDriving(const Duration(seconds: 5)); // GPS zurück
        expect(c.statuses, [StatusMessage.gpsLost, StatusMessage.gpsRestored]);
        expect(c.positionFound, 1);
        c.ctl.stop();
      },
    );

    testWidgets('neuer Überwachungsstart sagt es wieder an', (tester) async {
      final c = Clocked(rig, tester);
      await c.start();
      await c.fix(fixAt(52.5, 13.4, speedKmh: 0));
      c.ctl.stop();
      await c.start();
      await c.fix(fixAt(52.5, 13.4, speedKmh: 0));
      expect(c.positionFound, 2);
      c.ctl.stop();
    });

    testWidgets('kommt vor der ersten Warnung beim Losfahren', (tester) async {
      final c = Clocked(rig, tester);
      rig.alerts.points = [camera];
      rig.engine.respond = (fix, points, _) => WarningUpdate(
        active: const [],
        sounds: const [],
        events: [
          WarningEvent(
            point: points.first,
            stage: WarningStage.announce,
            distanceMeters: 900,
          ),
        ],
      );
      await c.start();
      await c.drive();
      expect(rig.audio.statuses, [StatusMessage.positionFound]);
      expect(rig.audio.announced, hasLength(1));
      c.ctl.stop();
    });
  });

  group('Hintergrunddienst', () {
    testWidgets(
      'startet mit der Überwachung, bekommt Änderungen, endet mit ihr',
      (tester) async {
        final c = Clocked(rig, tester);
        await c.start();
        expect(rig.companion.starts.single.phase, DrivePhase.running);

        await c.drive();
        expect(rig.companion.changes.last.motion, MotionState.driving);

        c.ctl.stop();
        await tester.pump();
        expect(rig.companion.stops, 1);
      },
    );

    testWidgets('ohne Standortrecht kein Dienst', (tester) async {
      rig.location.access = LocationAccess.denied;
      final c = Clocked(rig, tester);
      await c.start();
      expect(rig.companion.starts, isEmpty);
    });

    testWidgets('GPS im Betrieb abgeschaltet beendet den Dienst', (
      tester,
    ) async {
      final c = Clocked(rig, tester);
      await c.start();
      rig.location.controller.addError(
        const LocationAccessError(LocationAccess.serviceOff),
      );
      await tester.pump();
      expect(c.state.phase, DrivePhase.blocked);
      expect(rig.companion.stops, 1);
    });
  });
}
