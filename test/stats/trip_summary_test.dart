import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/features/stats/trip_store.dart';
import 'package:sonarb/features/stats/trip_summary.dart';

import 'trip_recorder_test.dart' show record;
import 'trip_sim.dart';

DriveFigures figures({
  double km = 100,
  int hard = 0,
  int curves = 0,
  double lost = 0,
  double gentle = 0,
  double limitSeconds = 0,
  double over10Seconds = 0,
}) => DriveFigures(
  distanceMeters: km * 1000,
  movingSeconds: 3600,
  hardBrakes: hard,
  sharpCurves: curves,
  speedLostMps: lost,
  gentleSpeedLostMps: gentle,
  overLimitSeconds: {
    RoadClass.rural: [limitSeconds - over10Seconds, 0, over10Seconds, 0],
  },
);

void main() {
  group('Vorausschauend', () {
    test('gewichtetes Mittel der vier Teile', () {
      final f = figures(
        lost: 10,
        gentle: 6,
        limitSeconds: 1000,
        over10Seconds: 100,
      );
      // 35 × 0,6 + 25 × 1 + 20 × 1 + 20 × (1 − 0,1 / 0,2)
      expect(f.anticipationScore, 76);
    });

    test('fehlende Teile zählen nicht, harte Bremsungen kosten', () {
      expect(figures().anticipationScore, 100);
      // 10 harte je 100 km: Teil 0, bleiben die Kurven (20 von 45).
      expect(figures(hard: 10).anticipationScore, 44);
      // 5 Kurven je 100 km: halber Teil, (25 + 10) von 45.
      expect(figures(curves: 5).anticipationScore, 78);
    });

    test('kurze Strecke rechnet mit 10 km, unter 1 km kein Wert', () {
      // 1 harte Bremsung auf 2 km = 10 je 100 km.
      expect(figures(km: 2, hard: 1).anticipationScore, 44);
      expect(figures(km: 0.5).anticipationScore, isNull);
    });
  });

  test('Summe mehrerer Fahrten, Höchstwerte als Maximum', () {
    final a = DriveFigures(
      distanceMeters: 1000,
      movingSeconds: 100,
      maxKmh: 80,
      maxLateralMps2: 2,
      brakes: 2,
      speedSeconds: [0, 0, 0, 0, 0, 100],
    );
    final b = DriveFigures(
      distanceMeters: 3000,
      movingSeconds: 100,
      maxKmh: 120,
      maxLateralMps2: 1,
      brakes: 1,
      speedSeconds: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 150],
    );
    final s = a + b;
    expect(s.distanceMeters, 4000);
    expect(s.maxKmh, 120);
    expect(s.maxLateralMps2, 2);
    expect(s.brakes, 3);
    expect(s.averageKmh, closeTo(72, 0.01));
    expect(s.mostFrequentKmh, 120);
    expect(totalOf(const []).distanceMeters, 0);
  });

  test('JSON hin und zurück', () {
    final sim = TripSim()
      ..begin(kmh: 60)
      ..hold(60, 300)
      ..ramp(0, 4)
      ..stand(20)
      ..ramp(60, 2)
      ..hold(60, 60);
    final trip = record(sim.fixes)!;
    final back = TripSummary.fromJson(trip.toJson())!;
    expect(back.id, trip.id);
    expect(back.start, trip.start);
    expect(back.end, trip.end);
    expect(back.figures.toJson(), trip.figures.toJson());
    expect(
      back.figures.distanceMeters,
      closeTo(trip.figures.distanceMeters, 0.1),
    );
    expect(TripSummary.fromJson({'id': 1}), isNull);
  });

  test('Aufbewahrung: alte Fahrten fallen weg, neueste zuerst', () {
    final now = DateTime.utc(2026, 11, 2);
    TripSummary at(int daysAgo) {
      final start = now.subtract(Duration(days: daysAgo));
      return TripSummary(
        id: '$daysAgo',
        start: start,
        end: start.add(const Duration(minutes: 5)),
        figures: DriveFigures(),
      );
    }

    final kept = retain(
      [at(40), at(1), at(100), at(10)],
      now: now,
      keep: const Duration(days: 30),
    );
    expect([for (final t in kept) t.id], ['1', '10']);
    final many = retain(
      [for (var i = 0; i < maxStoredTrips + 5; i++) at(0)],
      now: now,
      keep: const Duration(days: 30),
    );
    expect(many, hasLength(maxStoredTrips));
  });
}
