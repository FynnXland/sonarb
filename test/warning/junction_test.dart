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

/// Endpunkt einer Folge von Abschnitten (Kurs, Länge) ab [start].
GeoPoint walk(GeoPoint start, List<(double, double)> legs) {
  var p = start;
  for (final (course, length) in legs) {
    p = destinationPoint(p, course, length);
  }
  return p;
}

/// Kreisbogen als 20-m-Abschnitte: [length] Meter mit Radius [radius], Kurs wächst
/// (Rechtskurve), mit [left] fällt er.
List<(double, double)> arc(
  double course,
  double radius,
  double length, {
  bool left = false,
}) => [
  for (var s = 0.0; s < length; s += 20)
    (course + (left ? -1 : 1) * (s + 10) / radius * 180 / math.pi, 20.0),
];

void main() {
  late DriveSim sim; // Strecke nach Osten (Kurs 90)
  late WarningEngine engine;

  setUp(() {
    sim = DriveSim();
    engine = createWarningEngine();
  });

  AlertPoint site(GeoPoint p, {String id = 'site'}) => cam(
    p,
    id: id,
    kind: AlertKind.construction,
  ).copyWith(category: AlertCategory.dayRoadworks);

  group('Blitzer je Fahrtrichtung', () {
    test('gegenläufiges Paar: genau eine Warnung, die für meine Richtung', () {
      final mine = cam(sim.at(1200, lateral: 8), id: 'east', bearings: [90]);
      final other = cam(sim.at(1200, lateral: -8), id: 'west', bearings: [270]);
      final r = run(engine, sim.drive(0, 1500), [mine, other]);
      expect(r.stages('east'), [announce]);
      expect(r.stages('west'), isEmpty);
      expect(r.events, hasLength(1));

      engine.reset();
      final back = run(engine, sim.drive(1500, 0), [mine, other]);
      expect(back.stages('west'), [announce]);
      expect(back.stages('east'), isEmpty);
    });

    test(
      'Paar, bei dem einem die Richtung fehlt: trotzdem nur eine Warnung',
      () {
        final mine = cam(sim.at(1200, lateral: 8), id: 'east', bearings: [90]);
        final unknown = cam(sim.at(1200, lateral: -8), id: 'any');
        final r = run(engine, sim.drive(0, 1500), [unknown, mine]);
        expect(r.events, hasLength(1));
        expect(
          r.updates.every((u) => u.active.length <= 1),
          isTrue,
          reason: 'eine Stelle, eine Anzeige',
        );
      },
    );

    test('derselbe Blitzer aus zwei Quellen: eine Stufenfolge', () {
      final a = cam(sim.at(1200), id: 'osm', maxSpeed: 30);
      final b = cam(
        sim.at(1225, lateral: 5),
        id: 'plugin',
        kind: AlertKind.live,
        maxSpeed: 30,
      );
      final r = run(engine, sim.drive(0, 1500), [a, b]);
      expect(r.stages(), [announce, reminder, imminent]);
      expect(r.events.map((e) => e.point.id).toSet(), hasLength(1));
    });

    test('Punkt ohne Richtung warnt weiter, in beiden Richtungen', () {
      final any = cam(sim.at(1200), id: 'any');
      expect(run(engine, sim.drive(0, 1500), [any]).stages(), [announce]);
      engine.reset();
      expect(run(engine, sim.drive(1500, 0), [any]).stages(), [announce]);
    });

    test('zwei Blitzer 300 m auseinander bleiben zwei Stellen', () {
      final a = cam(sim.at(1200), id: 'a');
      final b = cam(sim.at(1500), id: 'b');
      final r = run(engine, sim.drive(0, 1800), [a, b]);
      expect(r.stages('a'), [announce]);
      expect(r.stages('b'), [announce]);
    });
  });

  group('Kreuzung', () {
    // Kreuzung bei 1000 m; rechts = Süden (Kurs 180), links = Norden (Kurs 0).
    late GeoPoint junction;
    setUp(() => junction = sim.at(1000));

    test('Baustelle 60 m rechts in der Querstraße, links abgebogen: still', () {
      final works = site(destinationPoint(junction, 180, 60));
      final r = run(engine, sim.route(0, [(90, 1000), (0, 600)]), [works]);
      expect(r.events, isEmpty);
      expect(r.updates.every((u) => u.active.isEmpty), isTrue);
    });

    test('Baustelle geradeaus hinter der Kreuzung, links abgebogen: angesagt, endet still', () {
      final works = site(sim.at(1200));
      final fixes = sim.route(0, [(90, 1000), (0, 600)]);
      final r = run(engine, fixes, [works]);
      expect(r.stages(), [announce]);
      expect(r.distanceAt(announce), greaterThan(540));

      final turned = fixes.indexWhere((f) => f.headingDeg == 0);
      for (final u in r.updates.skip(turned + 3)) {
        expect(u.active, isEmpty);
        expect(u.events, isEmpty);
      }
    });

    test('Baustelle 150 m in der Querstraße: gar keine Ansage', () {
      final works = site(destinationPoint(junction, 180, 150));
      final r = run(engine, sim.route(0, [(90, 1000), (0, 600)]), [works]);
      expect(r.events, isEmpty);
      expect(r.updates.every((u) => u.active.isEmpty), isTrue);
    });

    test('rechts in die Baustellenstraße abgebogen: Ansage kommt dann', () {
      final works = site(destinationPoint(junction, 180, 200));
      final fixes = sim.route(0, [(90, 1000), (180, 400)]);
      final r = run(engine, fixes, [works]);
      expect(r.stages(), [announce]);
      final turned = fixes.indexWhere((f) => f.headingDeg == 180);
      expect(r.indexOfStage(announce), greaterThanOrEqualTo(turned));
      expect(r.distanceAt(announce), lessThanOrEqualTo(200));
    });

    test('geradeaus auf die Baustelle zu: Warnung bleibt bis davor', () {
      final works = site(sim.at(1300));
      final r = run(engine, sim.route(0, [(90, 1500)]), [works]);
      expect(r.stages(), [announce]);
      final from = r.indexOfStage(announce);
      for (final (i, u) in r.updates.indexed.skip(from)) {
        final f = r.fixes[i];
        final d = distanceMeters(f.position, works.position);
        final ahead = f.position.lon < works.position.lon;
        if (ahead && d > 30) expect(u.primary?.point.id, 'site', reason: '$d');
      }
    });

    test(
      'geradeaus über die Kreuzung, Baustelle 60 m rechts daneben: still',
      () {
        final works = site(destinationPoint(junction, 180, 60));
        final r = run(engine, sim.route(0, [(90, 1600)]), [works]);
        expect(r.events, isEmpty);
      },
    );

    test('Blitzer ohne Richtung in der Querstraße, links abgebogen: nur die Ansage', () {
      final camera = cam(destinationPoint(junction, 180, 120));
      final fixes = sim.route(0, [(90, 1000), (0, 600)]);
      final r = run(engine, fixes, [camera]);
      expect(r.stages(), [announce]);
      final turned = fixes.indexWhere((f) => f.headingDeg == 0);
      for (final u in r.updates.skip(turned + 2)) {
        expect(u.active, isEmpty);
      }
    });
  });

  test('Autobahnkurve (Radius 1 km): Blitzer kommt mit voller Vorwarnung', () {
    final legs = [(90.0, 200.0), ...arc(90, 1000, 1400)];
    final camera = cam(walk(sim.at(0), legs), maxSpeed: 100);
    final r = run(
      engine,
      sim.route(0, [...legs, (180.0, 300.0)], speed: 36.1),
      [camera],
    );
    expect(r.stages(), [announce, reminder, imminent]);
    expect(r.distanceAt(announce), greaterThan(1000));
  });

  group('Baustellen nach Straßenverlauf', () {
    test('Baustelle auf der Parallelstraße 80 m daneben: still', () {
      final works = site(sim.at(1500, lateral: 80));
      final r = run(engine, sim.drive(0, 1800), [works]);
      expect(r.events, isEmpty);
    });

    test('Linkskurve in der Stadt, Baustelle auf der Tangente: still', () {
      final before = [(90.0, 600.0), ...arc(90, 150, 118, left: true)];
      final middle = walk(sim.at(0), before);
      final works = site(destinationPoint(middle, 45, 450));
      final legs = [
        (90.0, 600.0),
        ...arc(90, 150, 236, left: true),
        (0.0, 800.0),
      ];
      final r = run(engine, sim.route(0, legs, speed: 13.9), [works]);
      expect(r.events, isEmpty);
    });

    test('sanfte Landstraßenkurve (Radius 1 km), Baustelle auf der Tangente: still', () {
      final before = [(90.0, 300.0), ...arc(90, 1000, 300)];
      final tangent = 90 + 300 / 1000 * 180 / math.pi;
      final works = site(
        destinationPoint(walk(sim.at(0), before), tangent, 800),
      );
      final legs = [(90.0, 300.0), ...arc(90, 1000, 900)];
      final r = run(engine, sim.route(0, legs, speed: 27.8), [works]);
      expect(r.events, isEmpty);
    });

    test('Autobahnkurve (Radius 1 km), Baustelle auf der eigenen Fahrbahn: frühe Ansage', () {
      final legs = [(90.0, 300.0), ...arc(90, 1000, 1500)];
      final works = site(walk(sim.at(0), legs));
      final r = run(
        engine,
        sim.route(0, [...legs, (176.0, 300.0)], speed: 36.1),
        [works],
      );
      expect(r.stages(), [announce]);
      expect(r.distanceAt(announce), greaterThan(900));
    });

    test('gerade Autobahn: Baustelle mit voller Vorwarnung', () {
      final works = site(sim.at(3000));
      final r = run(engine, sim.drive(0, 3300, speed: 36.1), [works]);
      expect(r.distanceAt(announce), inInclusiveRange(1083 - 36.1, 1083.5));
    });

    test('Baustelle kommt erst nach drei Fixes auf der Linie', () {
      // Direkter Eintritt 300 m davor: kein Vorlauf zum Beobachten.
      final works = site(sim.at(1300));
      final r = run(engine, sim.drive(1000, 1400), [works]);
      expect(r.indexOfStage(announce), 2);
    });
  });
}
