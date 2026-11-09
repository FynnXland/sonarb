import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/warning/warning.dart';

import 'drive_sim.dart';

const announce = WarningStage.announce;
const reminder = WarningStage.reminder;
const imminent = WarningStage.imminent;
const allStages = [announce, reminder, imminent];

double kmh(double v) => v / 3.6;

void main() {
  late DriveSim sim;
  late WarningEngine engine;

  setUp(() {
    sim = DriveSim();
    engine = createWarningEngine();
  });

  group('eigene Meldungen und Live-Punkte', () {
    test(
      'mobiler Blitzer und Abstandsmessung: alle Stufen bei Überschreitung',
      () {
        for (final kind in [
          HotspotKind.mobileCamera,
          HotspotKind.distanceCheck,
        ]) {
          engine.reset();
          final r = run(engine, sim.drive(0, 1500), [
            report(sim.at(1200), kind),
          ], road: 50);
          expect(r.stages(), allStages, reason: '$kind');
        }
      },
    );

    test('Baustelle, Gefahrenstelle, Sonstiges: nur die Ansage, auch wenn zu schnell', () {
      final points = [
        report(sim.at(1200), HotspotKind.construction, id: 'c'),
        report(sim.at(1250), HotspotKind.danger, id: 'd'),
        report(sim.at(1300), HotspotKind.other, id: 'o'),
        cam(sim.at(1350), kind: AlertKind.construction, id: 'p'),
      ];
      final r = run(engine, sim.drive(0, 1600), points, road: 30);
      for (final id in ['c', 'd', 'o', 'p']) {
        expect(r.stages(id), [announce], reason: id);
      }
      expect(r.distanceAt(announce, 'c'), inInclusiveRange(579, 600));

      // Die Anzeige läuft mit der Entfernung mit, ohne neue Meldung.
      final at = r.updates[57]; // 1140 m, 60 m vor der Baustelle
      final site = at.active.firstWhere((w) => w.point.id == 'c');
      expect(site.stage, imminent);
      expect(r.updates.last.active, isEmpty);
    });

    test('eigener Radius macht die erste Ansage früher, nie später', () {
      final wide = report(
        sim.at(2000),
        HotspotKind.mobileCamera,
        id: 'w',
        radius: 1300,
      );
      // 400 m weiter: an derselben Stelle wären beide eine einzige Warnung.
      final small = report(
        sim.at(2400),
        HotspotKind.mobileCamera,
        id: 's',
        radius: 300,
      );
      final r = run(engine, sim.drive(0, 2700), [wide, small]);
      expect(r.distanceAt(announce, 'w'), inInclusiveRange(1280, 1300));
      expect(r.distanceAt(announce, 's'), inInclusiveRange(579, 600));
    });

    test('Hotspots aus: stumm, Live-Punkte bleiben', () {
      engine = createWarningEngine(
        settings: const WarningSettings(hotspotsEnabled: false),
      );
      final hs = report(sim.at(1200), HotspotKind.mobileCamera);
      final live = cam(sim.at(1200), id: 'plugin:x:1', kind: AlertKind.live);
      final r = run(engine, sim.drive(0, 1500), [hs, live], road: 50);
      expect(r.stages('hs'), isEmpty);
      expect(r.stages('plugin:x:1'), allStages);
    });

    test('Meldung filtert nach Fahrtrichtung', () {
      final wrong = report(
        sim.at(1200),
        HotspotKind.mobileCamera,
        bearings: [270],
      );
      expect(run(engine, sim.drive(0, 1500), [wrong]).events, isEmpty);
      engine.reset();
      final right = report(sim.at(1200), HotspotKind.danger, bearings: [80]);
      expect(run(engine, sim.drive(0, 1500), [right]).stages(), [announce]);
    });
  });

  group('Stillstand und GPS-Qualität', () {
    test('Halt an der Ampel kurz vor dem Blitzer: keine Erinnerung danach', () {
      final camera = cam(sim.at(1200), maxSpeed: 50);
      final v = kmh(50);
      final r = run(
        engine,
        [
          ...sim.drive(0, 1000, speed: v),
          ...sim.stand(1000, 40),
          ...sim.drive(1000, 1400, speed: v),
        ],
        [camera],
      );
      expect(r.stages(), [announce]);
      final held = r.updates[r.updates.length - 50];
      expect(held.primary!.stage, reminder);
      expect(held.primary!.level, WarningLevel.main);
      expect(held.events, isEmpty);
    });

    test('Stillstand ohne vorherige Warnung löst nichts aus', () {
      final r = run(engine, sim.stand(1000, 30), [cam(sim.at(1200))]);
      expect(r.events, isEmpty);
      expect(r.updates.every((u) => u.active.isEmpty), isTrue);
    });

    test('Kurs unbekannt bei Fahrt: keine Meldungen', () {
      final r = run(engine, sim.drive(0, 1500, withHeading: false), [
        cam(sim.at(1200), maxSpeed: 30),
      ]);
      expect(r.events, isEmpty);
      expect(r.updates.every((u) => u.active.isEmpty), isTrue);
    });

    test('GPS-Lücke: lieber eine Erinnerung zu viel', () {
      final camera = cam(sim.at(3000), maxSpeed: 100);
      final f = sim.drive(0, 3300, speed: kmh(100));
      // Keine Fixes zwischen 700 m und 300 m vor dem Blitzer.
      final gap = [...f.take(83), ...f.skip(97)];
      final r = run(engine, gap, [camera]);
      expect(r.stages(), [announce, reminder]);
    });

    test('Tempo ungenau (40 m): Erinnerung kommt trotz passendem Tempo', () {
      final camera = cam(sim.at(3000), maxSpeed: 100);
      final v = kmh(100);
      final r = run(
        engine,
        [
          ...sim.drive(0, 2500, speed: v),
          ...sim.drive(2500, 3300, speed: v, accuracy: 40),
        ],
        [camera],
      );
      expect(r.stages(), allStages);
    });

    test(
      'sehr ungenaues GPS: Anzeige bleibt, danach nur die nächste Stufe',
      () {
        final camera = cam(sim.at(1200), maxSpeed: 30);
        final good = run(engine, sim.drive(0, 880), [camera]);
        expect(good.stages(), [announce]);

        final bad = run(engine, sim.drive(880, 1150, accuracy: 80), [camera]);
        expect(bad.events, isEmpty);
        expect(bad.updates.every((u) => u.primary?.point.id == 'cam'), isTrue);

        final again = run(engine, sim.drive(1150, 1190), [camera]);
        expect(again.stages(), [imminent]);
      },
    );
  });

  group('Tempolimit-Anzeige', () {
    test(
      'ab der Erinnerung gilt das Limit der Messstelle, sonst das der Straße',
      () {
        final camera = cam(sim.at(1200), maxSpeed: 50);
        final r = run(engine, sim.drive(0, 1500), [
          camera,
        ], road: 70); // 72 km/h
        expect(r.stages(), allStages);
        expect(r.sounds, isEmpty);

        final atReminder = r.updates[r.indexOfStage(reminder)];
        expect(atReminder.speedLimitKmh, 50);
        expect(atReminder.overspeed, isTrue);

        final atAnnounce = r.updates[r.indexOfStage(announce)];
        expect(atAnnounce.speedLimitKmh, 70);
        expect(atAnnounce.overspeed, isFalse);
        expect(r.updates.last.speedLimitKmh, 70);
      },
    );

    test('ohne Messstelle nur Straßenlimit und Überschreitungsflag', () {
      final r = run(engine, sim.drive(0, 200), [], road: 30);
      expect(r.updates.last.speedLimitKmh, 30);
      expect(r.updates.last.overspeed, isTrue);
      expect(r.events, isEmpty);
    });

    test('kein Limit bekannt: kein Überschreiten', () {
      final u = engine.update(sim.drive(0, 20).first, []);
      expect(u.speedLimitKmh, isNull);
      expect(u.overspeed, isFalse);
    });
  });

  group('Leistung', () {
    test('2000 Kandidaten pro Update unter 2 ms', () {
      final rnd = math.Random(3);
      final points = <AlertPoint>[
        for (var i = 0; i < 2000; i++)
          cam(
            destinationPoint(
              sim.at(1000),
              rnd.nextDouble() * 360,
              rnd.nextDouble() * 3000,
            ),
            id: 'p$i',
            kind: AlertKind.values[rnd.nextInt(AlertKind.values.length)],
            report: HotspotKind.values[rnd.nextInt(HotspotKind.values.length)],
            maxSpeed: rnd.nextBool() ? 50 : null,
          ),
      ];
      final fixes = sim.drive(0, 2000, speed: 15);
      for (final f in fixes.take(30)) {
        engine.update(f, points, roadSpeedLimitKmh: 50); // Warmlauf
      }
      engine.reset();

      final times = <int>[];
      for (final f in fixes) {
        final sw = Stopwatch()..start();
        engine.update(f, points, roadSpeedLimitKmh: 50);
        times.add(sw.elapsedMicroseconds);
      }
      times.sort();
      final median = times[times.length ~/ 2];
      expect(median, lessThan(2000), reason: 'Median $median µs');
    });
  });
}
