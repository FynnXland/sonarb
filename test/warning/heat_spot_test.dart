import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/core/model/heat_spot.dart';
import 'package:sonarb/features/warning/heat_spots.dart';
import 'package:sonarb/features/warning/warning.dart';

import 'drive_sim.dart';

/// Uhrzeit der simulierten Fahrten (siehe [DriveSim]).
final t0 = DateTime.utc(2026, 1, 1, 12);

/// Vergangener mobiler Blitzer, [ageDays] Tage vor der Fahrt.
AlertPoint seen(GeoPoint pos, String id, {double? ageDays = 10}) => AlertPoint(
  id: id,
  kind: AlertKind.live,
  position: pos,
  source: 'verlauf',
  category: AlertCategory.mobileSpeed,
  observedAt: ageDays == null
      ? null
      : t0.subtract(Duration(hours: (ageDays * 24).round())),
  historical: true,
);

/// [days] Beobachtungen an verschiedenen Tagen, 20 m auseinander entlang Ost.
List<AlertPoint> cluster(
  GeoPoint pos, {
  int days = 3,
  double ageDays = 10,
  String prefix = 'o',
}) => [
  for (var i = 0; i < days; i++)
    seen(
      destinationPoint(pos, 90, i * 20.0),
      '$prefix$i',
      ageDays: ageDays + i,
    ),
];

GeoPoint walk(GeoPoint start, List<(double, double)> legs) {
  var p = start;
  for (final (course, length) in legs) {
    p = destinationPoint(p, course, length);
  }
  return p;
}

/// Linkskurve als 20-m-Abschnitte mit Radius [radius].
List<(double, double)> leftArc(double course, double radius, double length) => [
  for (var s = 0.0; s < length; s += 20)
    (course - (s + 10) / radius * 180 / math.pi, 20.0),
];

bool heat(WarningEvent e) => isHeatSpot(e.point);

void main() {
  late DriveSim sim; // Strecke nach Osten (Kurs 90)
  late WarningEngine engine;

  setUp(() {
    sim = DriveSim();
    engine = createWarningEngine();
  });

  group('Erkennung', () {
    test(
      'Standard: jede gemeldete Stelle, auch eine einzelne alte Meldung',
      () {
        expect(defaultHeatSpotReports, 1);
        final old = findHeatSpots([seen(sim.at(0), 'a', ageDays: 1000)], t0);
        expect(old, hasLength(1));
        final s = old.single;
        expect(isHeatSpot(s), isTrue);
        expect(s.historical, isTrue);
        expect(s.id, startsWith(heatSpotIdPrefix));
        // Der Hotspot steht an einer echten Meldung, also auf der Straße.
        expect(s.position, sim.at(0));
      },
    );

    for (final n in heatSpotReportChoices) {
      test('Stufe ab $n: zählt Meldungen im Umkreis, nicht Tage', () {
        // Alle am selben Tag, wie bei groben Datumsangaben in den Verlaufsdaten.
        List<AlertPoint> reports(int count) => [
          for (var i = 0; i < count; i++)
            seen(
              destinationPoint(sim.at(0), 90, i * 20.0),
              'r$i',
              ageDays: 365,
            ),
        ];
        expect(findHeatSpots(reports(n), t0, minReports: n), hasLength(1));
        if (n > 1) {
          expect(findHeatSpots(reports(n - 1), t0, minReports: n), isEmpty);
        }
      });
    }

    test('dieselbe Meldung aus zwei Quellen zählt einmal', () {
      final a = seen(sim.at(0), 'a');
      final b = a.copyWith(id: 'b', source: 'andere');
      expect(findHeatSpots([a, b], t0, minReports: 2), isEmpty);
      final c = seen(sim.at(0), 'c', ageDays: 40);
      expect(findHeatSpots([a, b, c], t0, minReports: 2), hasLength(1));
    });

    test('Meldungen 400 m auseinander zählen getrennt', () {
      final spread = [
        for (var i = 0; i < 6; i++) seen(sim.at(i * 400.0), 'v$i'),
      ];
      expect(findHeatSpots(spread, t0, minReports: 2), isEmpty);
      expect(findHeatSpots(spread, t0), hasLength(6));
    });

    test('dichte Häufung über Zellgrenzen: ein Hotspot', () {
      final dense = [
        for (var i = 0; i < 20; i++)
          seen(sim.at(i * 12.0), 'd$i', ageDays: i + 1.0),
      ];
      expect(findHeatSpots(dense, t0), hasLength(1));
      expect(findHeatSpots(dense, t0, minReports: 5), hasLength(1));
    });

    test('Meldungen alle 100 m: Hotspots mindestens 300 m auseinander', () {
      final road = [
        for (var i = 0; i < 30; i++) seen(sim.at(i * 100.0), 'k$i'),
      ];
      final spots = findHeatSpots(road, t0);
      expect(spots.length, inInclusiveRange(7, 10));
      for (final a in spots) {
        for (final b in spots) {
          if (identical(a, b)) continue;
          expect(
            distanceMeters(a.position, b.position),
            greaterThanOrEqualTo(heatSpotRadiusMeters),
          );
        }
      }
    });

    test('ohne Kategorie oder allgemein: zählt mit', () {
      AlertPoint plain(AlertKind kind, AlertCategory? c, String id) =>
          AlertPoint(
            id: id,
            kind: kind,
            position: sim.at(0),
            source: 'verlauf',
            category: c,
            observedAt: t0.subtract(const Duration(days: 30)),
            historical: true,
          );
      for (final p in [
        plain(AlertKind.live, null, 'live'),
        plain(AlertKind.speedCamera, null, 'kamera'),
        plain(AlertKind.live, AlertCategory.otherReport, 'sonstiges'),
        plain(AlertKind.live, AlertCategory.mobileDistance, 'abstand'),
        plain(AlertKind.live, AlertCategory.semiStationary, 'anhaenger'),
      ]) {
        expect(countsForHeatSpot(p), isTrue, reason: p.id);
        expect(findHeatSpots([p], t0), hasLength(1), reason: p.id);
      }
    });

    test('eindeutig keine Tempokontrolle: zählt nicht', () {
      for (final c in [
        AlertCategory.longTermRoadworks,
        AlertCategory.dayRoadworks,
        AlertCategory.accident,
        AlertCategory.trafficSignal,
        AlertCategory.mobileRedLight,
        AlertCategory.fixedRedLight,
        AlertCategory.closure,
        AlertCategory.heightControl,
      ]) {
        final p = seen(sim.at(0), 'x').copyWith(category: c);
        expect(countsForHeatSpot(p), isFalse, reason: '$c');
      }
      final works = AlertPoint(
        id: 'bau',
        kind: AlertKind.construction,
        position: sim.at(0),
        source: 'verlauf',
        historical: true,
      );
      expect(countsForHeatSpot(works), isFalse);
    });

    test('eigene Meldungen und aktuelle Blitzer zählen nicht mit', () {
      final own = [
        for (final p in cluster(sim.at(0))) p.copyWith(kind: AlertKind.hotspot),
      ];
      final current = [
        for (final p in cluster(sim.at(0))) p.copyWith(historical: false),
      ];
      expect(findHeatSpots(own, t0), isEmpty);
      expect(findHeatSpots(current, t0), isEmpty);
    });
  });

  group('Warnung auf der Fahrtlinie', () {
    test('Hotspot voraus: eine Ansage, keine Erinnerung, keine Anzeige', () {
      final points = cluster(sim.at(1200));
      // 72 km/h bei Tempo 30: ein Blitzer bekäme Erinnerung und schnelle Folge.
      final r = run(engine, sim.drive(0, 1600), points, road: 30);
      expect(r.stages(), [WarningStage.announce]);
      expect(r.events.every(heat), isTrue);
      expect(r.distanceAt(WarningStage.announce), greaterThan(540));
      expect(r.updates.every((u) => u.active.isEmpty), isTrue);
    });

    test('einmal je Durchfahrt, nach weiter Entfernung wieder', () {
      final points = cluster(sim.at(1200));
      expect(run(engine, sim.drive(0, 1600), points).events, hasLength(1));
      expect(run(engine, sim.drive(1600, 5000), points).events, isEmpty);
      expect(run(engine, sim.drive(5000, 0), points).events, hasLength(1));
    });

    test('Hotspot auf der Parallelstraße 80 m daneben: still', () {
      final points = cluster(sim.at(1200, lateral: 80));
      expect(run(engine, sim.drive(0, 1600), points).events, isEmpty);
    });

    test('Linkskurve in der Stadt, Hotspot auf der Tangente: still', () {
      final before = [(90.0, 600.0), ...leftArc(90, 150, 118)];
      final middle = walk(sim.at(0), before);
      final points = cluster(destinationPoint(middle, 45, 450));
      final legs = [(90.0, 600.0), ...leftArc(90, 150, 236), (0.0, 800.0)];
      final r = run(engine, sim.route(0, legs, speed: 13.9), points);
      expect(r.events, isEmpty);
    });

    test('aktueller Blitzer an derselben Stelle: nur dessen Warnung', () {
      final points = [
        ...cluster(sim.at(1200)),
        cam(sim.at(1250), maxSpeed: 50),
      ];
      final r = run(engine, sim.drive(0, 1600), points);
      expect(r.stages('cam'), isNotEmpty);
      expect(r.events.where(heat), isEmpty);
    });

    test('Blitzer nur für die Gegenrichtung: Hotspot warnt trotzdem', () {
      final points = [
        ...cluster(sim.at(1200)),
        cam(sim.at(1250), maxSpeed: 50, bearings: [270]),
      ];
      final r = run(engine, sim.drive(0, 1600), points);
      expect(r.stages('cam'), isEmpty);
      expect(r.events.where(heat), hasLength(1));
    });

    test('ausgeschaltet: keine Ansage', () {
      engine.settings = engine.settings.copyWith(heatSpotsEnabled: false);
      final points = cluster(sim.at(1200));
      expect(run(engine, sim.drive(0, 1600), points).events, isEmpty);
    });

    test('einzelne alte Meldung auf der Linie: angesagt, ab Stufe 2 still', () {
      final points = [seen(sim.at(1200), 'x', ageDays: 700)];
      expect(run(engine, sim.drive(0, 1600), points).events, hasLength(1));
      engine.reset();
      engine.settings = engine.settings.copyWith(heatSpotMinReports: 2);
      expect(run(engine, sim.drive(0, 1600), points).events, isEmpty);
    });

    for (final (kmh, speed) in [(50, 13.9), (100, 27.8), (130, 36.1)]) {
      test(
        'Meldung alle 100 m über 5 km bei $kmh km/h: höchstens alle 20 s',
        () {
          final points = [
            for (var i = 0; i < 50; i++) seen(sim.at(500 + i * 100.0), 'k$i'),
          ];
          final r = run(engine, sim.drive(0, 6000, speed: speed), points);
          final at = [
            for (var i = 0; i < r.updates.length; i++)
              if (r.updates[i].events.any(heat)) r.fixes[i].time,
          ];
          expect(at, isNotEmpty);
          for (var i = 1; i < at.length; i++) {
            expect(
              at[i].difference(at[i - 1]).inSeconds,
              greaterThanOrEqualTo(20),
            );
          }
          // Höchstens eine Ansage je 20 s Fahrt.
          final seconds = r.fixes.last.time.difference(r.fixes.first.time);
          expect(at.length, lessThanOrEqualTo(seconds.inSeconds ~/ 20 + 1));
        },
      );
    }
  });
}
