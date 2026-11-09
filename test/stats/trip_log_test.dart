import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/model/road_limit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/stats/trip_log.dart';
import 'package:sonarb/features/stats/trip_store.dart';
import 'package:sonarb/features/stats/trip_summary.dart';

import '../cockpit/fakes.dart';
import 'trip_sim.dart';

Future<void> settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

TripSummary trip(String id, DateTime start, {double meters = 5000}) =>
    TripSummary(
      id: id,
      start: start,
      end: start.add(const Duration(minutes: 10)),
      figures: DriveFigures(distanceMeters: meters, movingSeconds: 600),
    );

void main() {
  final now = DateTime.utc(2026, 11, 2, 12);

  group('Ablage', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sonarb_stats'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('Datei hin und zurück, neueste zuerst', () async {
      final store = FileTripStore(() async => dir);
      expect(await store.load(), isEmpty);
      await store.save([
        trip('a', now),
        trip('b', now.add(const Duration(hours: 1))),
      ]);
      final back = await FileTripStore(() async => dir).load();
      expect([for (final t in back) t.id], ['b', 'a']);
      expect(back.first.figures.distanceMeters, 5000);
      final text = File('${dir.path}/trips.json').readAsStringSync();
      expect(text, isNot(contains('"lat"')));
    });

    test('kaputte Datei ergibt eine leere Liste', () async {
      File('${dir.path}/trips.json').writeAsStringSync('{kaputt');
      expect(await FileTripStore(() async => dir).load(), isEmpty);
    });
  });

  group('Fahrten verwalten', () {
    late TestRig rig;
    late MemoryTripStore store;
    late ProviderContainer c;

    setUp(() async {
      rig = await TestRig.create();
      store = MemoryTripStore([
        trip('neu', now.subtract(const Duration(days: 1))),
        trip('alt', now.subtract(const Duration(days: 60))),
        trip('uralt', now.subtract(const Duration(days: 400))),
      ]);
      c = ProviderContainer.test(
        overrides: [
          ...rig.overrides,
          tripStoreProvider.overrideWithValue(store),
          statsClockProvider.overrideWithValue(() => now),
        ],
      );
    });

    List<String> ids() => [for (final t in c.read(tripsProvider).value!) t.id];

    test('Laden wendet die Aufbewahrung an', () async {
      await c.read(tripsProvider.future);
      expect(ids(), ['neu', 'alt']);
      expect(store.trips, hasLength(2));
    });

    test('löschen, alle löschen, kürzer aufbewahren', () async {
      await c.read(tripsProvider.future);
      final ctrl = c.read(tripsProvider.notifier);
      await ctrl.add(trip('heute', now));
      expect(ids(), ['heute', 'neu', 'alt']);
      await ctrl.delete('neu');
      expect(ids(), ['heute', 'alt']);
      await c.read(statsSettingsProvider.notifier).setKeepDays(30);
      expect(ids(), ['heute']);
      expect(rig.prefs.getInt('stats.keepDays'), 30);
      await ctrl.clear();
      expect(ids(), isEmpty);
      expect(store.trips, isEmpty);
    });
  });

  group('Aufzeichnung aus der Überwachung', () {
    late TestRig rig;
    late MemoryTripStore store;
    late ProviderContainer c;

    setUp(() async {
      rig = await TestRig.create();
      store = MemoryTripStore();
      c = ProviderContainer.test(
        overrides: [
          ...rig.overrides,
          tripStoreProvider.overrideWithValue(store),
          statsClockProvider.overrideWithValue(() => now),
        ],
      );
    });

    Future<void> drive() async {
      final sim = TripSim(start: now.subtract(const Duration(minutes: 5)))
        ..begin(kmh: 60)
        ..hold(60, 120);
      await c.read(driveControllerProvider.notifier).start();
      for (final f in sim.fixes) {
        rig.location.emit(f);
        await settle();
      }
      await c.read(driveControllerProvider.notifier).stop();
    }

    test('eine Fahrt mit Limit landet in der Statistik', () async {
      rig.alerts.limit = 50;
      await drive();
      final saved = store.trips.single;
      // Die ersten zwei Fixes bestätigen erst die Fahrt.
      expect(saved.figures.distanceMeters, closeTo(60 / 3.6 * 118, 20));
      final urban = saved.figures.overLimitSeconds[RoadClass.urban]!;
      expect(urban[OverLimit.upTo10.index], closeTo(118, 2));
      expect(c.read(tripsProvider).value, hasLength(1));
    });

    test('Ampelhalt von 90 s: Standzeit und Halt trotz Stand-Filter', () async {
      rig.alerts.limit = 50;
      final sim = TripSim(start: now.subtract(const Duration(minutes: 10)))
        ..begin(kmh: 50)
        ..hold(50, 120)
        ..ramp(0, 2.5)
        ..stand(90)
        ..ramp(50, 2)
        ..hold(50, 120);
      await c.read(driveControllerProvider.notifier).start();
      for (final f in sim.fixes) {
        rig.location.emit(f);
        await settle();
      }
      await c.read(driveControllerProvider.notifier).stop();
      // Der Filter hat im Stand fast alles zurückgehalten: keine Warnlogik je Fix.
      expect(rig.engine.calls.length, lessThan(sim.fixes.length - 80));
      final f = store.trips.single.figures;
      // 90 s Stand plus der letzte Bremsschritt (Mittel unter 3,6 km/h).
      expect(f.standSeconds, closeTo(91, 1));
      expect(f.stops, 1);
      expect(f.decelerations, 1);
      expect(f.starts, 1);
    });

    test('abgeschaltet: nichts gespeichert', () async {
      await c.read(statsSettingsProvider.notifier).setEnabled(false);
      await drive();
      expect(store.trips, isEmpty);
      expect(store.saves, 0);
    });
  });

  group('Zwischenspeichern', () {
    late TestRig rig;

    setUp(() async => rig = await TestRig.create());

    ProviderContainer containerWith(TripStore store) => ProviderContainer.test(
      overrides: [
        ...rig.overrides,
        tripStoreProvider.overrideWithValue(store),
        statsClockProvider.overrideWithValue(() => now),
      ],
    );

    void feed(TripLog log, TripSim sim, {int from = 0}) {
      for (final f in sim.fixes.skip(from)) {
        log
          ..context(f, const RoadLimit.kmh(50), const WarningUpdate(active: []))
          ..fix(f);
      }
    }

    test(
      'alle 5 min und einmal je Halt ab 30 s, offen gekennzeichnet',
      () async {
        final store = MemoryTripStore();
        final c = containerWith(store);
        final log = c.read(tripLogProvider)..started();
        final sim = TripSim(start: now.subtract(const Duration(hours: 1)))
          ..begin(kmh: 60)
          ..hold(60, 4 * 60);
        feed(log, sim);
        await log.saving;
        expect(store.saves, 0);

        var seen = sim.fixes.length;
        sim.hold(60, 7 * 60);
        feed(log, sim, from: seen);
        await log.saving;
        expect(store.saves, 2);
        expect(store.trips.single.open, isTrue);

        seen = sim.fixes.length;
        sim.stand(120);
        feed(log, sim, from: seen);
        await log.saving;
        expect(store.saves, 3);

        await log.ended();
        expect(store.saves, 4);
        final done = store.trips.single;
        expect(done.open, isFalse);
        expect(done.id, store.trips.single.id);
      },
    );

    test(
      'harter Abbruch: offene Fahrt wird beim nächsten Start abgeschlossen',
      () async {
        final dir = Directory.systemTemp.createTempSync('sonarb_abort');
        addTearDown(() => dir.deleteSync(recursive: true));
        final first = containerWith(FileTripStore(() async => dir));
        final log = first.read(tripLogProvider)..started();
        final sim = TripSim(start: now.subtract(const Duration(hours: 1)))
          ..begin(kmh: 60)
          ..hold(60, 7 * 60)
          ..ramp(0, 2)
          ..stand(40);
        feed(log, sim);
        await log.saving;
        final file = File('${dir.path}${Platform.pathSeparator}trips.json');
        expect(file.readAsStringSync(), contains('"open":true'));
        expect(File('${file.path}.tmp').existsSync(), isFalse);

        // Prozess weg: kein ended(), kein Dispose-Speichern.
        first.dispose();

        final second = containerWith(FileTripStore(() async => dir));
        addTearDown(second.dispose);
        final trips = await second.read(tripsProvider.future);
        final t = trips.single;
        expect(t.open, isFalse);
        // Ende ist der letzte Fix in Bewegung vor dem gesicherten Halt.
        // Bremsen in 9 Schritten; der letzte (unter 3,6 km/h im Mittel) zählt als Stand.
        expect(t.end, sim.fixes[7 * 60 + 8].time);
        expect(t.figures.distanceMeters, closeTo(60 / 3.6 * 420 + 60, 15));
        expect(file.readAsStringSync(), isNot(contains('"open"')));
      },
    );

    test('die laufende Aufzeichnung bleibt beim Neuladen offen', () async {
      final store = MemoryTripStore();
      final c = containerWith(store);
      final log = c.read(tripLogProvider)..started();
      final sim = TripSim(start: now.subtract(const Duration(hours: 1)))
        ..begin(kmh: 60)
        ..hold(60, 6 * 60);
      feed(log, sim);
      await log.saving;
      c.invalidate(tripsProvider);
      final trips = await c.read(tripsProvider.future);
      expect(trips.single.open, isTrue);
    });
  });
}
