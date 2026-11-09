import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/model/road_limit.dart';
import 'package:sonarb/features/stats/trip_log.dart';
import 'package:sonarb/features/stats/trip_recorder.dart';
import 'package:sonarb/features/stats/trip_store.dart';
import 'package:sonarb/features/stats/trip_summary.dart';
import 'package:sonarb/features/stats/trip_trace.dart';

import '../cockpit/fakes.dart';
import 'trip_sim.dart';

/// Spielt [sim] ein und liefert Zusammenfassung und Verlauf.
(TripSummary, TripTrace) run(TripSim sim, {RoadLimit Function(int i)? road}) {
  final r = TripRecorder();
  for (var i = 0; i < sim.fixes.length; i++) {
    final limit = road?.call(i) ?? const RoadLimit.unknown();
    r.add(
      sim.fixes[i],
      road: limit,
      update: WarningUpdate(active: const [], speedLimitKmh: limit.kmh),
    );
  }
  final summary = r.finish('t')!;
  return (summary, r.trace()!);
}

DriveFigures figures(TripSim sim, {RoadLimit Function(int i)? road}) =>
    run(sim, road: road).$1.figures;

void main() {
  group('Bremsen und Beschleunigen', () {
    test('bekannte harte Bremsung: Spitze, Stufe, Vorgang im Verlauf', () {
      final sim = TripSim()
        ..begin(kmh: 80)
        ..hold(80, 60)
        ..ramp(20, 4)
        ..hold(20, 60);
      final (trip, trace) = run(sim);
      final f = trip.figures;
      expect(f.maxDecelMps2, closeTo(4, 0.01));
      expect(f.decelPeaks[peakBinOf(4)], 1);
      expect(f.decelPeaks.fold(0.0, (a, b) => a + b), 1);
      expect(f.decelShares!.hard, 1);
      expect(f.decelShares!.count, 1);
      final e = trace.events.single;
      expect(e.kind, TraceEventKind.decel);
      expect(e.peakMps2, 4);
      expect(e.fromKmh, 80);
      expect(e.toKmh, 20);
      // Beginn zwei Sekunden vor dem ersten Fix mit Verzögerung, also bei Sekunde 60.
      expect(e.second, closeTo(60, 1));
    });

    test('sanftes Verzögern: Stufe bis 1,5 m/s², kein Vorgang im Verlauf', () {
      final sim = TripSim()
        ..begin(kmh: 80)
        ..hold(80, 60)
        ..ramp(50, 1)
        ..hold(50, 60);
      final (trip, trace) = run(sim);
      final f = trip.figures;
      expect(f.maxDecelMps2, closeTo(1, 0.01));
      expect(f.decelShares!.gentle, 1);
      expect(trace.events, isEmpty);
    });

    test('Anfahren mit 2 m/s²: mittlere Stufe, stärkste Beschleunigung', () {
      // Erst kurz stehen wie an der Ampel: Das geglättete Tempo braucht zwei Fixe mit 0.
      final sim = TripSim()
        ..begin()
        ..stand(3)
        ..ramp(50, 2)
        ..hold(50, 120);
      final (trip, trace) = run(sim);
      final f = trip.figures;
      expect(f.maxAccelMps2, closeTo(2, 0.01));
      expect(f.accelShares!.medium, 1);
      expect(f.decelShares, isNull);
      expect(trace.events.single.kind, TraceEventKind.accel);
      expect(trace.events.single.fromKmh, 0);
      expect(trace.events.single.toKmh, 50);
    });

    test('Anteile aus den Stufen', () {
      expect(peakBinOf(0.5), 0);
      expect(peakBinOf(1.49), 1);
      expect(peakBinOf(1.5), 2);
      expect(peakBinOf(3), 5);
      expect(peakBinOf(9), StatsLimits.peakBins - 1);
      final bins = List<double>.filled(StatsLimits.peakBins, 0)
        ..[0] = 2
        ..[3] = 1
        ..[6] = 1;
      final s = peakSharesOf(bins)!;
      expect(s.gentle, 0.5);
      expect(s.medium, 0.25);
      expect(s.hard, 0.25);
      expect(s.count, 4);
      expect(peakSharesOf(List.filled(StatsLimits.peakBins, 0)), isNull);
    });
  });

  group('Rauschen', () {
    /// Normalverteilt mit Streuung [sigma] (Box-Muller), fester Startwert.
    double Function() gauss(double sigma, {int seed = 7}) {
      final rnd = math.Random(seed);
      return () =>
          sigma *
          math.sqrt(-2 * math.log(1 - rnd.nextDouble())) *
          math.cos(2 * math.pi * rnd.nextDouble());
    }

    /// 60 km/h mit Zittern von ±1,1 km/h (gut das Fünffache des Doppler-Fehlers), dazu
    /// Ausreißer: einzelne Fixe 22 km/h zu tief, ein Fix mit schlechter Genauigkeit, zweimal
    /// zwei Fixe fast 0 km/h, ein Tunnel mit Tempo-Sprung danach. Echt ist nur eine harte
    /// Bremsung von 60 auf 20 km/h mit 4 m/s².
    TripSim noisy({bool filtered = false}) {
      final noise = gauss(0.3 * 3.6);
      final sim = TripSim()..begin(kmh: 60);
      void cruise(double kmh, int seconds) {
        for (var i = 0; i < seconds; i++) {
          sim.hold(kmh + noise(), 1);
        }
      }

      for (var k = 0; k < 5; k++) {
        cruise(60, 55);
        sim.hold(38, 1);
      }
      cruise(60, 30);
      sim.poor();
      cruise(60, 30);
      sim
        ..hold(3, 1)
        ..hold(2, 1);
      cruise(60, 30);
      sim.gap(10);
      cruise(40, 30);
      sim.ramp(60, 1.2);
      cruise(60, 40);
      sim.ramp(20, 4);
      cruise(20, 40);
      sim.ramp(50, 1.2);
      sim
        ..hold(1, 1)
        ..hold(0, 1);
      cruise(50, 60);
      return sim;
    }

    test('nur die echte Bremsung zählt, kein Phantom', () {
      final f = figures(noisy());
      expect(f.hardBrakes, 1);
      expect(f.brakes, 1);
      expect(f.maxDecelMps2, closeTo(4, 0.6));
      expect(f.strongAccelerations, 0);
      expect(f.decelShares!.hard, closeTo(1 / f.decelerations, 1e-9));
      expect(f.calmShare, greaterThan(0.9));
      expect(f.cruiseSwingKmh, lessThan(1.5));
    });

    test('ohne Glättung wären es mehrere harte Bremsungen', () {
      // Gegenprobe der Testfahrt: Die rohe Tempoänderung über 2 s zeigt die Ausreißer.
      final fixes = noisy().fixes;
      var spikes = 0;
      for (var i = 2; i < fixes.length; i++) {
        final dt =
            fixes[i].time.difference(fixes[i - 2].time).inMilliseconds / 1000;
        if (dt > 2.5 || fixes[i].accuracyMeters > 30) continue;
        final a = (fixes[i].speedMps - fixes[i - 2].speedMps) / dt;
        if (a <= -3) spikes++;
      }
      expect(spikes, greaterThan(5));
    });

    test('Delle von 2 Fixen bei 100 km/h ist keine Bremsung', () {
      final f = figures(
        TripSim()
          ..begin(kmh: 100)
          ..hold(100, 60)
          ..hold(0, 1)
          ..hold(0, 1)
          ..hold(100, 60),
      );
      expect(f.brakes, 0);
      expect(f.starts, 0);
    });

    test(
      'echtes Bremsen mit sofortigem normalem Anfahren bleibt eine Bremsung',
      () {
        final f = figures(
          TripSim()
            ..begin(kmh: 50)
            ..hold(50, 60)
            ..ramp(10, 3.5)
            ..ramp(50, 2.5)
            ..hold(50, 60),
        );
        expect(f.hardBrakes, 1);
        expect(f.accelerations, 1);
      },
    );
  });

  group('Gleichmäßigkeit', () {
    test('konstant gefahren: ganz ruhig, keine Schwankung', () {
      final f = figures(
        TripSim()
          ..begin(kmh: 50)
          ..hold(50, 600),
      );
      expect(f.calmShare, 1);
      expect(f.cruiseSwingKmh, closeTo(0, 0.01));
      // Die ersten drei Schritte haben noch kein geglättetes Tempo, die letzten zwei warten
      // auf Bestätigung und fallen am Ende weg.
      expect(f.cruiseSeconds, closeTo(595, 0.5));
    });

    test('eine Beschleunigung: 9 unruhige Sekunden', () {
      final f = figures(
        TripSim()
          ..begin(kmh: 50)
          ..hold(50, 300)
          ..ramp(110, 2)
          ..hold(110, 300),
      );
      // 609 Schritte; die Beschleunigung braucht vier Fixe, die ersten drei Schritte fehlen.
      expect(f.kinematicSeconds, 606);
      expect(f.calmShare, closeTo(1 - 9 / 606, 0.002));
    });

    test('Pendeln um 60 km/h mit ±3 km/h: Schwankung 3/√2 km/h', () {
      final sim = TripSim()..begin(kmh: 60);
      for (var i = 1; i <= 600; i++) {
        sim.hold(60 + 3 * math.sin(2 * math.pi * i / 60), 1);
      }
      final f = figures(sim);
      expect(f.cruiseSwingKmh, closeTo(3 / math.sqrt2, 0.05));
      // Unter 0,5 m/s² Tempoänderung: alles ruhig.
      expect(f.calmShare, 1);
    });

    test('Bremsen zählt nicht als Schwankung', () {
      final f = figures(
        TripSim()
          ..begin(kmh: 70)
          ..hold(70, 100)
          ..ramp(40, 3)
          ..hold(40, 100),
      );
      expect(f.cruiseSwingKmh, closeTo(0, 0.05));
      expect(f.cruiseSeconds, inInclusiveRange(185, 200));
    });

    test('unter 30 km/h kein gleichmäßiger Abschnitt', () {
      final f = figures(
        TripSim()
          ..begin(kmh: 25)
          ..hold(25, 300),
      );
      expect(f.cruiseSwingKmh, isNull);
      expect(f.calmShare, 1);
    });
  });

  group('Halte und Schnitt', () {
    test('Haltedauer: längster Halt, Mittel, kurzer Stand zählt nicht', () {
      final sim = TripSim()
        ..begin(kmh: 40)
        ..hold(40, 60)
        ..ramp(0, 4)
        ..stand(30)
        ..ramp(40, 2)
        ..hold(40, 60)
        ..ramp(0, 4)
        ..stand(10)
        ..ramp(40, 2)
        ..hold(40, 60)
        ..ramp(0, 4)
        ..stand(3)
        ..ramp(40, 2)
        ..hold(40, 60);
      final f = figures(sim);
      expect(f.stops, 2);
      // Je Halt zählt der letzte Bremsschritt (unter 3,6 km/h im Mittel) mit.
      expect(f.longestStopSeconds, closeTo(31, 1));
      expect(f.stopSeconds, closeTo(42, 2));
      expect(f.meanStopSeconds, closeTo(21, 1));
      expect(
        f.tripAverageKmh,
        closeTo(
          f.distanceMeters / (f.movingSeconds + f.standSeconds) * 3.6,
          1e-9,
        ),
      );
      expect(f.tripAverageKmh!, lessThan(f.averageKmh!));
    });
  });

  group('Je Tempolimit', () {
    test('Zeit über dem Limit und Höchsttempo je Limit', () {
      final sim = TripSim()
        ..begin(kmh: 58)
        ..hold(58, 120)
        ..ramp(90, 2)
        ..hold(90, 200);
      final (trip, trace) = run(
        sim,
        road: (i) =>
            i <= 120 ? const RoadLimit.kmh(50) : const RoadLimit.kmh(100),
      );
      final l = trip.figures.limits;
      expect(l.keys, unorderedEquals([50, 100]));
      expect(l[50]!.totalSeconds, closeTo(120, 0.5));
      expect(l[50]!.seconds[OverLimit.upTo10.index], closeTo(120, 0.5));
      expect(l[50]!.overShare, 1);
      expect(l[50]!.over10Share, 0);
      expect(l[50]!.maxKmh, closeTo(58, 0.01));
      expect(l[100]!.overShare, 0);
      expect(l[100]!.maxKmh, closeTo(90, 0.01));
      expect(
        [for (final x in trace.limits) (x.second, x.kmh)],
        [(0, 50), (121, 100)],
      );
      expect(trace.limitAt(120), 50);
      expect(trace.limitAt(121), 100);
    });

    test('kein Limit wird im Verlauf als eigener Wert geführt', () {
      final (trip, trace) = run(
        TripSim()
          ..begin(kmh: 150)
          ..hold(150, 120),
        road: (_) => const RoadLimit.none(),
      );
      expect(trip.figures.limits, isEmpty);
      expect(trace.limitAt(60), TraceLimit.none);
    });
  });

  group('Verlauf', () {
    test('ein Wert je Sekunde bis zum letzten Fix in Bewegung', () {
      final (_, trace) = run(
        TripSim()
          ..begin(kmh: 50)
          ..hold(50, 600)
          ..ramp(0, 5)
          ..stand(300),
      );
      expect(trace.speedAt(0), 50);
      expect(trace.speedAt(300), 50);
      // 600 s Fahrt, Bremsen in 3 Schritten (Mittel 41, 23 und 7 km/h, alle in Bewegung).
      expect(trace.length, 604);
      expect(trace.peakKmh, 50);
    });

    test('Tunnel als Lücke, Stand ohne Fixes als 0', () {
      final sim = TripSim()
        ..begin(kmh: 60)
        ..hold(60, 60)
        ..gap(10)
        ..hold(60, 60)
        ..ramp(0, 4)
        ..stand(5)
        ..gap(20)
        ..ramp(60, 2)
        ..hold(60, 60);
      final (_, trace) = run(sim);
      expect(trace.speedAt(60), 60);
      for (var i = 61; i < 70; i++) {
        expect(trace.speedAt(i), isNull, reason: 'Sekunde $i');
      }
      expect(trace.speedAt(70), 60);
      // Nach dem Bremsen: 5 s Stand mit Fixes, dann 20 s ohne.
      final standStart = 130 + 5;
      for (var i = standStart; i < standStart + 25; i++) {
        expect(trace.speedAt(i), 0, reason: 'Sekunde $i');
      }
    });

    test('Füllen zwischen Fixes und Limit nur bei Wechsel', () {
      final b = TraceBuilder()
        ..add(0, 10)
        ..add(2, 30)
        ..add(2.2, 31)
        ..add(5, 0, fill: TraceFill.stand)
        ..add(7, 40, fill: TraceFill.gap)
        ..limit(0, null)
        ..limit(1, 50)
        ..limit(2, 50)
        ..limit(4, 70);
      final t = b.build(10);
      expect(
        [for (var i = 0; i < t.length; i++) t.speedAt(i)],
        [10, 20, 31, 0, 0, 0, null, 40],
      );
      expect([for (final l in t.limits) (l.second, l.kmh)], [(1, 50), (4, 70)]);
      expect(t.limitAt(0), isNull);
      expect(b.build(3).length, 4);
    });

    test('JSON hin und zurück, kaputter Inhalt ergibt null', () {
      final (_, trace) = run(
        TripSim()
          ..begin(kmh: 80)
          ..hold(80, 60)
          ..ramp(20, 4)
          ..hold(20, 60),
        road: (_) => const RoadLimit.kmh(70),
      );
      final back = TripTrace.fromJson(trace.toJson())!;
      expect(back.speeds, trace.speeds);
      expect(back.limits.single.kmh, 70);
      expect(back.events.single.toJson(), trace.events.single.toJson());
      expect(TripTrace.fromJson({'speed': 'kein base64!'}), isNull);
      expect(TripTrace.fromJson('x'), isNull);
    });
  });

  group('Ältere Fahrten', () {
    test(
      'ohne neue Felder: keine ausführlichen Werte, Summe nur aus neuen',
      () {
        final (trip, _) = run(
          TripSim()
            ..begin(kmh: 60)
            ..hold(60, 300)
            ..ramp(0, 4)
            ..stand(20)
            ..ramp(60, 2)
            ..hold(60, 60),
          road: (_) => const RoadLimit.kmh(50),
        );
        final json = trip.toJson();
        expect(json['detail'], isNotNull);
        final old = Map.of(json)
          ..removeWhere(
            (k, _) => const {
              'detail',
              'stopSum',
              'stopMax',
              'decelPk',
              'accelPk',
              'decelMax',
              'accelMax',
              'calm',
              'kin',
              'cruise',
              'cruiseVar',
              'limits',
            }.contains(k),
          );
        final o = TripSummary.fromJson(old)!.figures;
        expect(o.hasDetail, isFalse);
        expect(o.calmShare, isNull);
        expect(o.cruiseSwingKmh, isNull);
        expect(o.meanStopSeconds, isNull);
        expect(o.decelShares, isNull);
        expect(o.limits, isEmpty);
        expect(o.toJson().containsKey('detail'), isFalse);
        expect(o.distanceMeters, closeTo(trip.figures.distanceMeters, 0.1));

        final back = TripSummary.fromJson(json)!.figures;
        expect(back.toJson(), trip.figures.toJson());

        final sum = o + back;
        expect(sum.detailSeconds, back.movingSeconds);
        expect(sum.limits[50]!.totalSeconds, back.limits[50]!.totalSeconds);
        expect(sum.calmShare, back.calmShare);
      },
    );

    test('Summe: Höchstwerte als Maximum, Zeiten addiert', () {
      final a = DriveFigures(
        detailSeconds: 100,
        maxDecelMps2: 3,
        longestStopSeconds: 40,
        limits: {
          50: LimitFigures(seconds: [10, 5, 0, 0], maxKmh: 61),
        },
      );
      final b = DriveFigures(
        detailSeconds: 50,
        maxDecelMps2: 5,
        longestStopSeconds: 20,
        limits: {
          50: LimitFigures(seconds: [20, 0, 0, 0], maxKmh: 55),
          100: LimitFigures(seconds: [30, 0, 0, 0], maxKmh: 104),
        },
      );
      final s = a + b;
      expect(s.maxDecelMps2, 5);
      expect(s.longestStopSeconds, 40);
      expect(s.limits[50]!.seconds, [30, 5, 0, 0]);
      expect(s.limits[50]!.maxKmh, 61);
      expect(s.limits[100]!.maxKmh, 104);
    });
  });

  group('Ablage der Verläufe', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sonarb_trace'));
    tearDown(() => dir.deleteSync(recursive: true));

    TripSummary summary(String id) => TripSummary(
      id: id,
      start: DateTime.utc(2026, 11, 2, 8),
      end: DateTime.utc(2026, 11, 2, 9),
      figures: DriveFigures(distanceMeters: 5000, movingSeconds: 600),
    );

    final trace =
        (TraceBuilder()
              ..add(0, 30)
              ..add(1, 32))
            .build(1);

    test(
      'Datei hin und zurück, Löschen der Fahrt löscht den Verlauf',
      () async {
        final store = FileTripStore(() async => dir);
        await store.save([summary('a'), summary('b')]);
        await store.saveTrace('a', trace);
        await store.saveTrace('b', trace);
        expect((await store.loadTrace('a'))!.speeds, [30, 32]);
        expect(await store.loadTrace('c'), isNull);

        await store.save([summary('b')]);
        expect(await store.loadTrace('a'), isNull);
        expect(await store.loadTrace('b'), isNotNull);
        await store.save(const []);
        expect(
          Directory('${dir.path}${Platform.pathSeparator}traces').listSync(),
          isEmpty,
        );
      },
    );

    test('unsichere ID und kaputte Datei', () async {
      final store = FileTripStore(() async => dir);
      await store.saveTrace('../raus', trace);
      expect(File('${dir.parent.path}/raus.json').existsSync(), isFalse);
      expect(await store.loadTrace('../raus'), isNull);
      await store.saveTrace('a', trace);
      File(
        '${dir.path}${Platform.pathSeparator}traces${Platform.pathSeparator}a.json',
      ).writeAsStringSync('{kaputt');
      expect(await store.loadTrace('a'), isNull);
    });

    test('Fahrtende speichert den Verlauf, Löschen entfernt ihn', () async {
      final rig = await TestRig.create();
      final store = MemoryTripStore();
      final c = ProviderContainer.test(
        overrides: [
          ...rig.overrides,
          tripStoreProvider.overrideWithValue(store),
          statsClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 6, 10, 12),
          ),
        ],
      );
      final log = c.read(tripLogProvider)..started();
      final sim = TripSim()
        ..begin(kmh: 60)
        ..hold(60, 120);
      for (final f in sim.fixes) {
        log
          ..context(f, const RoadLimit.kmh(50), const WarningUpdate(active: []))
          ..fix(f);
      }
      await log.ended();
      final id = store.trips.single.id;
      expect(store.traces[id]!.length, 121);
      expect(
        await c.read(tripTraceProvider(id).future),
        same(store.traces[id]),
      );
      await c.read(tripsProvider.notifier).delete(id);
      expect(store.traces, isEmpty);
    });
  });
}
