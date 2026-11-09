import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/warning/warning.dart';
import 'package:sonarb/features/warning/warning_engine_impl.dart';

import 'drive_sim.dart';

const announce = WarningStage.announce;
const reminder = WarningStage.reminder;
const imminent = WarningStage.imminent;

double kmh(double v) => v / 3.6;

void main() {
  late DriveSim sim;
  late WarningEngine engine;

  setUp(() {
    sim = DriveSim();
    engine = createWarningEngine();
  });

  /// Fahrt mit festem Tempo an einem Blitzer bei 3000 m vorbei.
  Run pass(double speedKmh, {int? limit, int? road, AlertPoint? point}) {
    final camera = point ?? cam(sim.at(3000), maxSpeed: limit);
    return run(engine, sim.drive(0, 3300, speed: kmh(speedKmh)), [
      camera,
    ], road: road);
  }

  group('Stufen nach Tempo, passend gefahren: nur die erste Ansage', () {
    for (final (speed, limit) in [(50.0, 50), (100.0, 100), (130.0, 130)]) {
      test('$speed km/h bei Limit $limit', () {
        final r = pass(speed, limit: limit);
        expect(r.stages(), [announce]);
        // Die Anzeige läuft trotzdem mit bis zur Messstelle.
        final stages = {for (final u in r.updates) u.primary?.stage};
        expect(stages, containsAll([announce, reminder, imminent]));
      });
    }
  });

  group(
    'Stufen nach Tempo, zu schnell: Ansage, Erinnerung, schnelle Folge',
    () {
      test('50 km/h in der 30er-Zone: 600 / 250 / 60 m', () {
        final v = kmh(50);
        final r = pass(50, limit: 30);
        expect(r.stages(), [announce, reminder, imminent]);
        expect(r.distanceAt(announce), inInclusiveRange(600 - v, 600));
        expect(r.distanceAt(reminder), inInclusiveRange(250 - v, 250));
        expect(r.distanceAt(imminent), inInclusiveRange(60 - v, 60));
      });

      test('100 km/h bei 70: 30 s / 15 s / 4 s vorher', () {
        final v = kmh(100);
        final r = pass(100, limit: 70);
        expect(r.stages(), [announce, reminder, imminent]);
        expect(r.distanceAt(announce), inInclusiveRange(30 * v - v, 30 * v));
        expect(r.distanceAt(reminder), inInclusiveRange(15 * v - v, 15 * v));
        expect(r.distanceAt(imminent), inInclusiveRange(4 * v - v, 4 * v));
      });

      test('130 km/h bei 100: Erinnerung 15 s vorher reicht zum Ausrollen', () {
        final v = kmh(130);
        final r = pass(130, limit: 100);
        expect(r.stages(), [announce, reminder, imminent]);
        expect(r.distanceAt(reminder), inInclusiveRange(15 * v - v, 15 * v));
        final coast = coastMeters(const WarningSettings(), v, 100);
        expect(r.distanceAt(reminder), greaterThan(coast));
      });

      test('130 km/h bei 80: Ausrollweg bestimmt die Erinnerung', () {
        const s = WarningSettings();
        final v = kmh(130);
        final coast = coastMeters(s, v, 80);
        expect(coast, greaterThan(15 * v));
        final r = pass(130, limit: 80);
        expect(r.distanceAt(reminder), inInclusiveRange(coast - v, coast));
      });

      test('Tempolimit der Straße gilt, wenn der Blitzer keins hat', () {
        final r = pass(72, road: 50);
        expect(r.stages(), [announce, reminder, imminent]);
      });

      test('innerhalb der Toleranz still', () {
        final r = pass(52.9, limit: 50); // Toleranz 3 km/h
        expect(r.stages(), [announce]);
      });
    },
  );

  group('Tempo ändert sich', () {
    test('nach der Ansage abgebremst: keine Erinnerung', () {
      final camera = cam(sim.at(3000), maxSpeed: 100);
      final r = run(
        engine,
        [
          ...sim.drive(0, 2300, speed: kmh(130)), // Ansage bei ~1080 m
          ...sim.drive(2300, 3300, speed: kmh(98)),
        ],
        [camera],
      );
      expect(r.stages(), [announce]);
    });

    test(
      'in der Erinnerungszone beschleunigt: Erinnerung kommt nachträglich',
      () {
        final camera = cam(sim.at(3000), maxSpeed: 50);
        final r = run(
          engine,
          [
            ...sim.drive(0, 2850, speed: kmh(50)),
            ...sim.drive(2850, 3300, speed: kmh(70)),
          ],
          [camera],
        );
        expect(r.stages(), [announce, reminder, imminent]);
        expect(r.distanceAt(reminder), lessThan(160));
      },
    );

    test('Stufe läuft nie zurück, nichts doppelt', () {
      final camera = cam(sim.at(3000), maxSpeed: 30);
      final r = run(
        engine,
        [
          ...sim.drive(0, 2000, speed: kmh(130)),
          ...sim.drive(2000, 3300, speed: kmh(40)),
        ],
        [camera],
      );
      expect(r.stages(), [announce, reminder, imminent]);
      final seen = [
        for (final u in r.updates)
          if (u.primary != null) u.primary!.stage!.index,
      ];
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
    });
  });

  group('Einstellungen', () {
    test('Nur bei Überschreitung aus: alle Stufen, auch ohne Limit', () {
      engine = createWarningEngine(
        settings: const WarningSettings(onlyWhenSpeeding: false),
      );
      expect(pass(50).stages(), [announce, reminder, imminent]);
    });

    test('ohne bekanntes Limit: nur die erste Ansage', () {
      expect(pass(130).stages(), [announce]);
    });

    test('Erinnerung aus: Ansage und schnelle Folge bleiben', () {
      engine = createWarningEngine(
        settings: const WarningSettings(reminderEnabled: false),
      );
      expect(pass(100, limit: 70).stages(), [announce, imminent]);
    });

    test('Erinnerung frühestens 500 m', () {
      engine = createWarningEngine(
        settings: const WarningSettings(reminderMeters: 500),
      );
      final r = pass(50, limit: 30);
      expect(r.distanceAt(reminder), inInclusiveRange(500 - kmh(50), 500));
    });

    test('erste Ansage bei 5 km', () {
      const s = WarningSettings(announceMeters: 5000);
      engine = createWarningEngine(settings: s);
      expect(s.lookAheadMeters, greaterThan(5000));
      final camera = cam(sim.at(6000));
      final r = run(engine, sim.drive(0, 6300, speed: kmh(100)), [camera]);
      expect(r.distanceAt(announce), inInclusiveRange(5000 - kmh(100), 5000));
    });

    test('Zonen werden nach innen nie größer', () {
      final z = stageZones(
        const WarningSettings(announceMeters: 300, reminderMeters: 1000),
        kmh(50),
        limitKmh: 30,
      );
      expect(z.announce, closeTo(30 * kmh(50), 0.01)); // Zeit schlägt 300 m
      expect(z.reminder, z.announce);
      expect(z.imminent, lessThanOrEqualTo(z.reminder!));
    });

    test('Zeitanteil der ersten Ansage hat eine Obergrenze', () {
      final z = stageZones(const WarningSettings(), kmh(250));
      expect(z.announce, WarningSettings.maxTimedAnnounceMeters);
    });
  });

  group('Richtung und Lage', () {
    test('Gegenrichtung bleibt stumm', () {
      final camera = cam(sim.at(1200), bearings: [270], maxSpeed: 30);
      final r = run(engine, sim.drive(0, 1500), [camera]);
      expect(r.events, isEmpty);
      expect(r.updates.every((u) => u.active.isEmpty), isTrue);
    });

    test('Richtung in der Toleranz, leere oder beide Richtungen warnen', () {
      for (final bearings in <List<double>>[
        [90.0 + 40],
        <double>[],
        [270.0, 90],
      ]) {
        engine.reset();
        final c = cam(sim.at(1200), bearings: bearings, maxSpeed: 30);
        expect(run(engine, sim.drive(0, 1500), [c]).stages(), [
          announce,
          reminder,
          imminent,
        ], reason: '$bearings');
      }
    });

    test('Punkt seitlich oder hinter dem Fahrzeug bleibt stumm', () {
      final beside = cam(sim.at(1000, lateral: 150));
      expect(run(engine, sim.drive(1000, 1400), [beside]).events, isEmpty);
      engine.reset();
      final behind = cam(sim.at(-300));
      expect(run(engine, sim.drive(0, 400), [behind]).events, isEmpty);
    });

    test('direkter Eintritt nah am Punkt: zuerst die Ansage, dann nur die nächste Stufe', () {
      final camera = cam(sim.at(1200), maxSpeed: 30);
      final r = run(engine, sim.drive(1000, 1400), [camera]); // 200 m davor
      expect(r.stages(), [announce, imminent]);
      expect(r.updates.first.primary!.stage, reminder);
      expect(r.updates.first.primary!.level, WarningLevel.main);
    });

    test(
      'Rückfahrt außer Reichweite warnt erneut, Wenden kurz danach nicht',
      () {
        final camera = cam(sim.at(1200));
        final d = engine as DefaultWarningEngine;
        expect(run(engine, sim.drive(0, 4000), [camera]).stages(), [announce]);
        expect(d.trackedPointCount, 0);
        expect(run(engine, sim.drive(4000, 0), [camera]).stages(), [announce]);

        engine.reset();
        run(engine, sim.drive(0, 1700), [camera]);
        final back = run(engine, sim.drive(1700, 0), [camera]);
        expect(back.events, isEmpty);
      },
    );

    test('Zustand nur für Punkte in der Nähe', () {
      final d = engine as DefaultWarningEngine;
      final far = cam(sim.at(5000), id: 'far');
      final close = cam(sim.at(1200), id: 'near');
      run(engine, sim.drive(0, 900), [far, close]);
      expect(d.trackedPointCount, 1);
      run(engine, sim.drive(900, 4000), [far, close]);
      expect(d.trackedPointCount, 0);
    });
  });

  group('Arten', () {
    test('Ampeln lösen nie etwas aus', () {
      final light = cam(sim.at(1200), kind: AlertKind.trafficSignal);
      final r = run(engine, sim.drive(0, 1500), [light], road: 30);
      expect(r.events, isEmpty);
      expect(r.updates.every((u) => u.active.isEmpty), isTrue);
    });

    test(
      'Rotlicht, Abschnittskontrolle, Live: alle Stufen bei Überschreitung',
      () {
        for (final kind in [
          AlertKind.redLightCamera,
          AlertKind.sectionControl,
          AlertKind.live,
        ]) {
          engine.reset();
          final c = cam(sim.at(1200), kind: kind, maxSpeed: 50);
          expect(run(engine, sim.drive(0, 1500), [c]).stages(), [
            announce,
            reminder,
            imminent,
          ], reason: '$kind');
        }
      },
    );
  });

  group('mehrere Punkte', () {
    test(
      'gleicher Schritt: nähere Stufe zuerst, dann Messstelle vor Hinweis',
      () {
        // 20 m/s: imminent-Zone 80 m, Ansage-Zone 600 m, beide erreicht bei 1000 m Strecke.
        final close = cam(sim.at(1070), id: 'a', maxSpeed: 30);
        final ahead = cam(sim.at(1590), id: 'b');
        final site = report(sim.at(1590), HotspotKind.construction, id: 'c');
        final r = run(engine, sim.drive(0, 1100), [site, ahead, close]);
        final both = r.updates.firstWhere((u) => u.events.length == 3);
        expect(both.events.map((e) => (e.point.id, e.stage)), [
          ('a', imminent),
          ('b', announce),
          ('c', announce),
        ]);
      },
    );

    test('Messstelle in Erinnerung steht vor näheren Hinweisen', () {
      final camera = cam(sim.at(1200), id: 'a');
      final site = report(sim.at(1180), HotspotKind.construction, id: 'h');
      final r = run(engine, sim.drive(1000, 1100), [site, camera]);
      final last = r.updates.last;
      expect(last.active.map((w) => w.point.id), ['a', 'h']);
      expect(last.primary!.level, WarningLevel.main);
    });
  });
}
