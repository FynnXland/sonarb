import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/core/model/position_fix.dart';
import 'package:sonarb/core/model/road_limit.dart';
import 'package:sonarb/features/cockpit/speed_filter.dart';
import 'package:sonarb/features/stats/trip_recorder.dart';
import 'package:sonarb/features/stats/trip_summary.dart';

import 'trip_sim.dart';

/// Spielt [fixes] ein; [road] und [update] je Fix, sonst unbekannt bzw. leer.
TripSummary? record(
  List<PositionFix> fixes, {
  RoadLimit Function(int i)? road,
  WarningUpdate Function(int i, PositionFix f)? update,
  bool filtered = false,
}) {
  final r = TripRecorder();
  final filter = SpeedFilter();
  for (var i = 0; i < fixes.length; i++) {
    final f = filtered ? filter.apply(fixes[i]) : fixes[i];
    final roadLimit = road?.call(i) ?? const RoadLimit.unknown();
    r.add(
      f,
      road: roadLimit,
      update:
          update?.call(i, f) ??
          WarningUpdate(active: const [], speedLimitKmh: roadLimit.kmh),
    );
  }
  return r.finish('t');
}

DriveFigures figuresOf(
  TripSim sim, {
  RoadLimit Function(int i)? road,
  WarningUpdate Function(int i, PositionFix f)? update,
  bool filtered = false,
}) =>
    record(sim.fixes, road: road, update: update, filtered: filtered)!.figures;

void main() {
  group('Strecke und Zeit', () {
    test('Strecke aus dem Tempo, Dauer und Fahrzeit', () {
      final sim = TripSim()
        ..begin(kmh: 50)
        ..hold(50, 600);
      final trip = record(sim.fixes)!;
      expect(trip.figures.distanceMeters, closeTo(50 / 3.6 * 600, 1));
      expect(trip.figures.movingSeconds, 600);
      expect(trip.duration, const Duration(seconds: 600));
      expect(trip.figures.averageKmh, closeTo(50, 0.1));
    });

    test('Positionsrauschen im Stand ergibt keine Strecke', () {
      final sim = TripSim()
        ..begin(kmh: 50)
        ..hold(50, 120);
      final noisy = [
        ...sim.fixes,
        for (var i = 1; i <= 60; i++)
          PositionFix(
            position: destinationPoint(sim.fixes.last.position, i * 37.0, 8),
            speedMps: 0,
            accuracyMeters: 8,
            time: sim.time.add(Duration(seconds: i)),
          ),
      ];
      final f = record(noisy)!.figures;
      // Der Schritt von 50 auf 0 zählt mit dem Mittel; danach kommt nichts dazu.
      expect(f.distanceMeters, closeTo(50 / 3.6 * 120.5, 1));
    });

    test('Standzeit und Halte, der Stand am Ende zählt nicht', () {
      final sim = TripSim()
        ..begin(kmh: 40)
        ..hold(40, 120)
        ..stand(60)
        ..hold(40, 120)
        ..stand(3)
        ..hold(40, 60)
        ..stand(300);
      final trip = record(sim.fixes)!;
      // Der Schritt von 40 auf 0 zählt noch als Bewegung (Mittel 20 km/h).
      expect(trip.figures.standSeconds, closeTo(59 + 2, 0.01));
      expect(trip.figures.stops, 1);
      expect(trip.end, sim.fixes[120 + 60 + 120 + 3 + 60 + 1].time);
      expect(trip.duration.inSeconds, 364);
    });

    test('kurze Fahrten werden nicht gespeichert', () {
      final sim = TripSim()
        ..begin(kmh: 30)
        ..hold(30, 50);
      expect(record(sim.fixes), isNull);
    });

    test('ungenaue Fixes fallen heraus, Lücken zählen als Luftlinie', () {
      final sim = TripSim()
        ..begin(kmh: 72)
        ..hold(72, 60)
        ..poor()
        ..hold(72, 60)
        ..gap(20)
        ..hold(72, 60);
      final f = record(sim.fixes)!.figures;
      expect(f.distanceMeters, closeTo(20.0 * 201, 2));
      expect(f.movingSeconds, closeTo(201, 0.5));
      expect(f.roadSeconds[RoadClass.unknown.index], closeTo(201, 0.5));
    });
  });

  group('Tempo', () {
    test('Verteilung, häufigstes, Höchsttempo ohne Ausreißer', () {
      final sim = TripSim()
        ..begin(kmh: 50)
        ..hold(50, 300)
        ..ramp(100, 3)
        ..hold(100, 120)
        ..hold(160, 1)
        ..hold(100, 10);
      final f = figuresOf(sim);
      expect(f.mostFrequentKmh, 50);
      expect(f.speedSeconds[5], closeTo(300, 1));
      expect(f.speedSeconds[10], greaterThanOrEqualTo(120));
      expect(f.maxKmh, closeTo(100, 0.5));
    });

    test('über 3 Fixes gehaltenes Höchsttempo zählt', () {
      final sim = TripSim()
        ..begin(kmh: 80)
        ..hold(80, 100)
        ..hold(130, 3)
        ..hold(80, 20);
      expect(figuresOf(sim).maxKmh, closeTo(130, 0.5));
    });
  });

  group('Tempolimit', () {
    test('Stufen über dem Limit innerorts', () {
      final sim = TripSim()..begin(kmh: 52);
      for (final kmh in [52.0, 58.0, 65.0, 75.0]) {
        sim.hold(kmh, 60);
      }
      final f = figuresOf(sim, road: (_) => const RoadLimit.kmh(50));
      final urban = f.overLimitSeconds[RoadClass.urban]!;
      expect(urban[OverLimit.within.index], closeTo(60, 1));
      expect(urban[OverLimit.upTo10.index], closeTo(60, 1));
      expect(urban[OverLimit.upTo20.index], closeTo(60, 1));
      expect(urban[OverLimit.above20.index], closeTo(60, 1));
      expect(f.over10Share, closeTo(0.5, 0.01));
      expect(f.urbanShare, 1);
    });

    test('Straßenart aus dem Limit, ohne Limit kein Vergleich', () {
      final sim = TripSim()
        ..begin(kmh: 90)
        ..hold(90, 100)
        ..hold(140, 100)
        ..hold(30, 100);
      final f = figuresOf(
        sim,
        road: (i) => i <= 100
            ? const RoadLimit.kmh(100)
            : i <= 200
            ? const RoadLimit.none()
            : const RoadLimit.unknown(),
      );
      expect(f.roadSeconds[RoadClass.rural.index], closeTo(100, 1));
      expect(f.roadSeconds[RoadClass.motorway.index], closeTo(100, 1));
      expect(f.roadSeconds[RoadClass.unknown.index], closeTo(100, 1));
      expect(f.limitKnownSeconds, closeTo(100, 1));
      expect(f.urbanShare, 0);
      expect(roadClassOf(const RoadLimit.kmh(30)), RoadClass.urban);
      expect(roadClassOf(const RoadLimit.kmh(120)), RoadClass.motorway);
    });

    test('Grenzen der Stufen', () {
      expect(overLimitOf(3.4), OverLimit.within);
      expect(overLimitOf(-20), OverLimit.within);
      expect(overLimitOf(4), OverLimit.upTo10);
      expect(overLimitOf(10.4), OverLimit.upTo10);
      expect(overLimitOf(11), OverLimit.upTo20);
      expect(overLimitOf(20), OverLimit.upTo20);
      expect(overLimitOf(21), OverLimit.above20);
    });
  });

  group('Bremsen', () {
    test('harte Bremsung, auch durch den Tempofilter', () {
      final sim = TripSim()
        ..begin(kmh: 100)
        ..hold(100, 60)
        ..ramp(0, 6)
        ..stand(10)
        ..ramp(50, 1.5)
        ..hold(50, 60);
      final f = figuresOf(sim, filtered: true);
      expect(f.decelerations, 1);
      expect(f.brakes, 1);
      expect(f.hardBrakes, 1);
      expect(f.gentleShare, 0);
    });

    test('normale Bremsung ist nicht hart', () {
      final sim = TripSim()
        ..begin(kmh: 70)
        ..hold(70, 60)
        ..ramp(20, 2)
        ..hold(20, 30)
        ..ramp(70, 1.5)
        ..hold(70, 30);
      final f = figuresOf(sim, filtered: true);
      expect(f.brakes, 1);
      expect(f.hardBrakes, 0);
    });

    test('langes sanftes Verzögern zählt als Motorbremse (geschätzt)', () {
      final sim = TripSim()
        ..begin(kmh: 100)
        ..hold(100, 60)
        ..ramp(50, 0.8)
        ..hold(50, 60)
        ..ramp(0, 5)
        ..stand(5)
        ..ramp(50, 1.5)
        ..hold(50, 60);
      final f = figuresOf(sim);
      expect(f.decelerations, 2);
      expect(f.brakes, 1);
      expect(f.gentleShare, closeTo(0.5, 0.05));
    });

    test('GPS-Rauschen um ein festes Tempo ergibt keine Bremsung', () {
      final sim = TripSim()
        ..begin(kmh: 80)
        ..hold(80, 300);
      final noisy = [
        for (var i = 0; i < sim.fixes.length; i++)
          PositionFix(
            position: sim.fixes[i].position,
            speedMps: sim.fixes[i].speedMps + ((i * 7919) % 7 - 3) * 0.1,
            accuracyMeters: 5,
            time: sim.fixes[i].time,
            headingDeg: sim.fixes[i].headingDeg,
          ),
      ];
      final f = record(noisy)!.figures;
      expect(f.decelerations, 0);
      expect(f.accelerations, 0);
    });
  });

  group('Anfahren und Beschleunigen', () {
    test('ruhiges und kräftiges Anfahren', () {
      final sim = TripSim()
        ..begin()
        ..ramp(50, 1.5)
        ..hold(50, 60)
        ..ramp(0, 2)
        ..stand(20)
        ..ramp(50, 3.5)
        ..hold(50, 60)
        ..ramp(90, 1)
        ..hold(90, 30);
      final f = figuresOf(sim);
      expect(f.accelerations, 3);
      expect(f.starts, 2);
      expect(f.strongAccelerations, 1);
    });
  });

  group('Kurven', () {
    test('zügige Kurve aus Kursänderung mal Tempo', () {
      final sim = TripSim()
        ..begin(kmh: 50)
        ..hold(50, 60)
        ..hold(50, 5, turnDegPerSecond: 20)
        ..hold(50, 60)
        ..hold(50, 10, turnDegPerSecond: 5)
        ..hold(50, 30);
      final f = figuresOf(sim);
      expect(f.sharpCurves, 1);
      // 13,9 m/s × 20°/s = 4,85 m/s²
      expect(f.maxLateralMps2, closeTo(50 / 3.6 * 20 * 3.14159 / 180, 0.1));
    });

    test('Kurssprung ist keine Kurve', () {
      final sim = TripSim()
        ..begin(kmh: 50)
        ..hold(50, 60)
        ..hold(50, 1, turnDegPerSecond: 90)
        ..hold(50, 60);
      expect(figuresOf(sim).sharpCurves, 0);
    });
  });

  group('Umfeld', () {
    test('Nachtfahrt im Winter, Tagfahrt im Sommer', () {
      final night = TripSim(start: DateTime.utc(2026, 12, 15, 21))
        ..begin(kmh: 60)
        ..hold(60, 300);
      final day = TripSim(start: DateTime.utc(2026, 6, 15, 11))
        ..begin(kmh: 60)
        ..hold(60, 300);
      expect(figuresOf(night).nightShare, 1);
      expect(figuresOf(day).nightShare, 0);
    });
  });

  group('Warnungen', () {
    const fixed = AlertPoint(
      id: 'osm:node/1',
      kind: AlertKind.speedCamera,
      position: GeoPoint(0, 0),
      source: 'osm',
      maxSpeed: 50,
    );
    const mobile = AlertPoint(
      id: 'hotspot:1',
      kind: AlertKind.hotspot,
      reportKind: HotspotKind.mobileCamera,
      position: GeoPoint(0, 0),
      source: 'hotspot',
    );
    const danger = AlertPoint(
      id: 'hotspot:2',
      kind: AlertKind.hotspot,
      reportKind: HotspotKind.danger,
      position: GeoPoint(0, 0),
      source: 'hotspot',
    );

    test('passierte Blitzer, davon zu schnell, erste Ansagen', () {
      final sim = TripSim()
        ..begin(kmh: 70)
        ..hold(70, 120);
      final f = figuresOf(
        sim,
        update: (i, f) {
          final active = <ActiveWarning>[];
          final events = <WarningEvent>[];
          // Fester Blitzer mit 50: Fix 10 bis 30, kommt bis 15 m nahe (70 km/h, zu schnell).
          if (i >= 10 && i <= 30) {
            active.add(
              ActiveWarning(
                point: fixed,
                distanceMeters: (30 - i) * 19.4 + 15,
                level: WarningLevel.main,
              ),
            );
          }
          if (i == 10) {
            events.add(
              const WarningEvent(
                point: fixed,
                stage: WarningStage.announce,
                distanceMeters: 400,
              ),
            );
          }
          // Mobiler Blitzer an einer Straße mit 100: passiert, nicht zu schnell.
          if (i >= 50 && i <= 60) {
            active.add(
              ActiveWarning(
                point: mobile,
                distanceMeters: (60 - i) * 19.4 + 5,
                level: WarningLevel.main,
              ),
            );
          }
          // Gefahrenstelle zählt nicht als Blitzer; abgebogen vor einem Blitzer auch nicht.
          if (i >= 70 && i <= 80) {
            active.add(
              ActiveWarning(
                point: danger,
                distanceMeters: 10,
                level: WarningLevel.main,
              ),
            );
            active.add(
              ActiveWarning(
                point: const AlertPoint(
                  id: 'osm:node/3',
                  kind: AlertKind.speedCamera,
                  position: GeoPoint(0, 0),
                  source: 'osm',
                ),
                distanceMeters: 400.0 - i,
                level: WarningLevel.pre,
              ),
            );
          }
          return WarningUpdate(
            active: active,
            events: events,
            speedLimitKmh: i >= 50 && i <= 60 ? 100 : null,
          );
        },
      );
      expect(f.warnings, 1);
      expect(f.camerasPassed, 2);
      expect(f.camerasTooFast, 1);
    });
  });
}
