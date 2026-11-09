import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/core/model/position_fix.dart';
import 'package:sonarb/features/warning/road_course.dart';
import 'package:sonarb/features/warning/warning.dart';

import 'drive_sim.dart';

const announce = WarningStage.announce;

/// Baustelle als Startpunkt, ohne Richtung.
AlertPoint site(GeoPoint pos, {String id = 'bau'}) => AlertPoint(
  id: id,
  kind: AlertKind.construction,
  position: pos,
  source: 'test',
);

/// Strecke als dichte Linie (alle 10 m) über Abschnitte (Kurs, Länge) ab [start].
List<GeoPoint> lineOf(GeoPoint start, List<(double, double)> legs) {
  final pts = [start];
  var p = start;
  for (final (course, length) in legs) {
    for (var s = 10.0; s <= length; s += 10) {
      pts.add(destinationPoint(p, course, s));
    }
    p = destinationPoint(p, course, length);
    if (pts.last != p) pts.add(p);
  }
  return pts;
}

/// Was `roadAheadAt` liefern würde: ab der Position der Rest von [line], bis 2,5 km.
List<GeoPoint> aheadOn(List<GeoPoint> line, GeoPoint pos) {
  var best = 0;
  for (var i = 1; i < line.length; i++) {
    if (distanceMeters(line[i], pos) < distanceMeters(line[best], pos)) {
      best = i;
    }
  }
  final out = [pos];
  var m = 0.0;
  for (var i = best + 1; i < line.length && m < 2500; i++) {
    m += distanceMeters(out.last, line[i]);
    out.add(line[i]);
  }
  return out;
}

Run drive(
  WarningEngine engine,
  List<PositionFix> fixes,
  List<AlertPoint> points,
  List<GeoPoint>? Function(int i, PositionFix f) ahead,
) => Run(fixes, [
  for (var i = 0; i < fixes.length; i++)
    engine.update(fixes[i], points, roadAhead: ahead(i, fixes[i])),
]);

void main() {
  late DriveSim sim; // Start nach Osten (Kurs 90)
  late WarningEngine engine;

  setUp(() {
    sim = DriveSim();
    engine = createWarningEngine();
  });

  group(
    'abknickende Vorfahrt nach 1 km nach Norden, geradeaus eine Nebenstraße',
    () {
      final legs = [(90.0, 1000.0), (0.0, 1000.0)];

      test('Baustelle auf der geraden Nebenstraße: still', () {
        final route = lineOf(sim.at(0), legs);
        final works = site(sim.at(1300));
        final r = drive(engine, sim.route(0, legs, speed: 13.9), [
          works,
        ], (_, f) => aheadOn(route, f.position));
        expect(r.events, isEmpty);
        expect(r.updates.every((u) => u.active.isEmpty), isTrue);
      });

      test('Gegenprobe ohne Straßendaten: die gerade Linie sagt sie an', () {
        final works = site(sim.at(1300));
        final r = drive(engine, sim.route(0, legs, speed: 13.9), [
          works,
        ], (_, _) => null);
        expect(r.stages(), [announce]);
      });

      test('Baustelle auf der eigenen Straße hinter der Kreuzung: warnt rechtzeitig und weiter', () {
        final route = lineOf(sim.at(0), legs);
        final works = site(destinationPoint(sim.at(1000), 0, 400));
        final r = drive(engine, sim.route(0, legs, speed: 13.9), [
          works,
        ], (_, f) => aheadOn(route, f.position));
        expect(r.stages(), [announce]);
        expect(r.distanceAt(announce), greaterThan(540));
        // Noch vor der Kreuzung angesagt, die Anzeige bleibt bis kurz davor.
        final at = r.indexOfStage(announce);
        expect(r.fixes[at].headingDeg, 90);
        final near = r.updates.indexWhere(
          (u) => u.active.any((w) => w.distanceMeters < 100),
        );
        expect(near, greaterThan(at));
        for (final u in r.updates.sublist(at, near)) {
          expect(u.active.map((w) => w.point.id), contains('bau'));
        }
      });

      test('Blitzer geradeaus bleiben wie bisher', () {
        final route = lineOf(sim.at(0), legs);
        final r = drive(engine, sim.route(0, legs, speed: 13.9), [
          cam(sim.at(1300), maxSpeed: 30),
        ], (_, f) => aheadOn(route, f.position));
        expect(r.stages('cam'), contains(announce));
      });
    },
  );

  group('Autobahn, Abfahrt nach 3 km', () {
    final legs = [(90.0, 3000.0), (105.0, 600.0), (150.0, 800.0)];
    late List<GeoPoint> motorway;
    late List<GeoPoint> route;

    setUp(() {
      motorway = lineOf(sim.at(0), [(90.0, 8000.0)]);
      route = lineOf(sim.at(0), legs);
    });

    /// Bis zur Abfahrt die Autobahn voraus, danach die Rampe.
    List<GeoPoint> Function(int, PositionFix) aheadFor(
      List<PositionFix> fixes,
    ) {
      final exit = fixes.indexWhere((f) => f.headingDeg != 90);
      return (i, f) =>
          i < exit ? aheadOn(motorway, f.position) : aheadOn(route, f.position);
    }

    test(
      'Baustelle auf der Autobahn hinter der Abfahrt: nach der Abfahrt still',
      () {
        final fixes = sim.route(0, legs, speed: 33);
        final works = site(sim.at(4800));
        final r = drive(engine, fixes, [works], aheadFor(fixes));
        expect(r.events, isEmpty);
      },
    );

    test('schon angesagt, dann abgefahren: die Warnung endet still', () {
      final fixes = sim.route(0, legs, speed: 33);
      final works = site(sim.at(3700));
      final r = drive(engine, fixes, [works], aheadFor(fixes));
      expect(r.stages(), [announce]);
      final exit = fixes.indexWhere((f) => f.headingDeg != 90);
      expect(r.indexOfStage(announce), lessThan(exit));
      expect(r.updates[exit - 1].active, isNotEmpty);
      for (final u in r.updates.skip(exit + 2)) {
        expect(u.active, isEmpty);
        expect(u.events, isEmpty);
      }
    });

    test('Verteilerfahrbahn 40 m daneben ohne Straßendaten: Baustelle der Autobahn schweigt', () {
      final parallel = [(90.0, 2000.0), (100.0, 230.0), (90.0, 2000.0)];
      final fixes = sim.route(0, parallel, speed: 33);
      final works = site(sim.at(3200));
      final shift = fixes.indexWhere((f) => f.headingDeg != 90);
      final r = drive(engine, fixes, [
        works,
      ], (i, f) => i < shift ? aheadOn(motorway, f.position) : null);
      expect(r.events, isEmpty);

      // Gegenprobe ganz ohne Straßendaten: die gerade Linie sagt sie an.
      engine.reset();
      final again = sim.route(0, parallel, speed: 33);
      expect(drive(engine, again, [works], (_, _) => null).stages(), [
        announce,
      ]);
    });
  });

  test('ohne Straßendaten: gerade Strecke wie bisher', () {
    final works = site(sim.at(1200));
    final r = drive(engine, sim.drive(0, 1500), [works], (_, _) => null);
    expect(r.stages(), [announce]);
  });

  group('RoadCourse', () {
    test('ein Punkt hinter einem liegt nicht auf der Strecke voraus', () {
      final c = RoadCourse()
        ..update(sim.at(500), lineOf(sim.at(500), [(90.0, 1000.0)]));
      expect(c.verdict(sim.at(800), 300), RoadVerdict.onRoad);
      expect(c.verdict(sim.at(800, lateral: 50), 300), RoadVerdict.offRoad);
      expect(c.verdict(sim.at(480), 20), RoadVerdict.offRoad);
      // Weiter als die Linie reicht: unbekannt.
      expect(c.verdict(sim.at(2000), 1500), RoadVerdict.unknown);
    });
  });
}
