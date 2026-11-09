import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';
import 'package:sonarb/features/alerts/mobile_history.dart';
import 'package:sonarb/features/warning/heat_spots.dart';

import 'fakes.dart';

const spot = GeoPoint(53.3439, 9.7633);

/// 1 m Nord ≈ 0,000009° Breite.
GeoPoint north(double meters, [GeoPoint from = spot]) =>
    GeoPoint(from.lat + meters / 111195, from.lon);

AlertPoint mobile(
  String n,
  GeoPoint at, {
  String source = 'live',
  AlertCategory? category,
  AlertKind kind = AlertKind.live,
  DateTime? observedAt,
  bool historical = false,
  List<double> bearings = const [],
}) => AlertPoint(
  id: 'plugin:$source:$n',
  kind: kind,
  position: at,
  source: source,
  category: category,
  observedAt: observedAt,
  historical: historical,
  travelBearings: bearings,
);

void main() {
  late DateTime now;
  late MemoryMobileHistoryStore store;
  late MobileHistory history;

  setUp(() async {
    now = DateTime(2026, 11, 3, 8);
    store = MemoryMobileHistoryStore();
    history = MobileHistory(store, clock: () => now);
    await history.load();
  });

  tearDown(() => history.dispose());

  group('was aufgenommen wird', () {
    test('mobile, Rotlicht, Abstand und halbfeste Blitzer', () {
      final added = history.record([
        mobile('1', north(0), category: AlertCategory.mobileSpeed),
        mobile('2', north(500), category: AlertCategory.mobileRedLight),
        mobile('3', north(1000), category: AlertCategory.mobileDistance),
        mobile('4', north(1500), category: AlertCategory.semiStationary),
        mobile('5', north(2000)), // grobe Art live: mobiler Blitzer
      ]);
      expect(added, isTrue);
      expect(history.length, 5);
    });

    test(
      'nicht: feste Blitzer, Baustellen, Gefahren, Hotspots, Vergangenes',
      () {
        final added = history.record([
          mobile('1', north(0), category: AlertCategory.fixedSpeed),
          mobile(
            '2',
            north(500),
            kind: AlertKind.construction,
            category: AlertCategory.dayRoadworks,
          ),
          mobile('3', north(1000), category: AlertCategory.accident),
          mobile('4', north(1500), kind: AlertKind.hotspot),
          mobile(
            '5',
            north(2000),
            category: AlertCategory.mobileSpeed,
            historical: true,
          ),
        ]);
        expect(added, isFalse);
        expect(history.length, 0);
      },
    );
  });

  group('dieselbe Stelle am selben Tag zählt einmal', () {
    test('unter 50 m, auch aus zwei Quellen', () {
      history.record([
        mobile('1', spot),
        mobile('2', north(40), source: 'zweite'),
      ]);
      expect(history.length, 1);
    });

    test('ab 60 m sind es zwei', () {
      history.record([mobile('1', spot), mobile('2', north(60))]);
      expect(history.length, 2);
    });

    test('am nächsten Tag zählt dieselbe Stelle neu', () {
      history.record([mobile('1', spot)]);
      now = now.add(const Duration(days: 1));
      history.record([mobile('1', spot)]);
      expect(history.length, 2);
    });

    test('wiederholter Abruf desselben Punkts ändert nichts', () {
      history.record([mobile('1', spot)]);
      expect(history.record([mobile('1', spot)]), isFalse);
      expect(history.length, 1);
    });

    test('der Tag der Beobachtung zählt, wenn das Plugin ihn nennt', () {
      history.record([
        mobile('1', spot, observedAt: DateTime(2026, 10, 20, 14)),
        mobile('2', spot, observedAt: DateTime(2026, 10, 21, 9)),
      ]);
      expect(history.length, 2);
      final days = history.around(spot, 100).map((p) => p.observedAt!.day);
      expect(days.toSet(), {20, 21});
    });

    test('Meldungen, die älter als zwei Jahre sind, kommen nicht hinein', () {
      history.record([
        mobile('1', spot, observedAt: DateTime(2024, 10, 1)),
        mobile('2', north(500), observedAt: DateTime(2024, 11, 20)),
      ]);
      expect(history.length, 1);
    });
  });

  group('als vergangene Beobachtung', () {
    test('Ort, Art, Richtung und Datum bleiben erhalten', () {
      history.record([
        mobile(
          '1',
          spot,
          category: AlertCategory.semiStationary,
          bearings: [93.4],
          observedAt: DateTime(2026, 9, 14, 16, 30),
        ),
      ]);
      final p = history.around(spot, 50).single;
      expect(p.historical, isTrue);
      expect(p.kind, AlertKind.live);
      expect(p.effectiveCategory, AlertCategory.semiStationary);
      expect(p.travelBearings, [93]);
      expect(p.source, mobileHistorySource);
      expect(p.observedAt!.year, 2026);
      expect(p.observedAt!.month, 9);
      expect(p.observedAt!.day, 14);
      expect(distanceMeters(p.position, spot), lessThan(1.5));
      expect(countsForHeatSpot(p), isTrue);
    });

    test('nur Einträge im Umkreis', () {
      history.record([mobile('1', spot), mobile('2', north(2500))]);
      expect(history.around(spot, 1000), hasLength(1));
      expect(history.around(spot, 3000), hasLength(2));
      expect(history.around(north(20000), 3000), isEmpty);
    });

    test('mehrere Tage an einer Stelle ergeben einen Hotspot', () {
      for (var day = 0; day < 4; day++) {
        history.record([mobile('1', north(day * 30.0))]);
        now = now.add(const Duration(days: 7));
      }
      final spots = findHeatSpots(history.around(spot, 3000), now);
      expect(spots, hasLength(1));
      expect(spots.single.details.single.value, '4');
    });
  });

  group('Speicher', () {
    test(
      'wird nach der Wartezeit geschrieben, nicht bei jeder Meldung',
      () async {
        final slow = MobileHistory(
          store,
          clock: () => now,
          saveDelay: const Duration(milliseconds: 30),
        );
        await slow.load();
        slow.record([mobile('1', spot)]);
        slow.record([mobile('2', north(500))]);
        expect(store.saves, 0);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await slow.flush();
        expect(store.saves, 1);
        expect(store.items, hasLength(2));
        await slow.dispose();
      },
    );

    test('dispose schreibt offene Änderungen', () async {
      history.record([mobile('1', spot)]);
      await history.dispose();
      expect(store.items, hasLength(1));
    });

    test('nach dem Neustart ist der Verlauf wieder da', () async {
      history.record([
        mobile('1', spot, bearings: [90]),
      ]);
      await history.dispose();
      final again = MobileHistory(store, clock: () => now);
      await again.load();
      expect(again.length, 1);
      expect(again.around(spot, 50).single.travelBearings, [90]);
      await again.dispose();
    });

    test(
      'Meldungen vor dem Lesen gehen nicht verloren und überschreiben nichts',
      () async {
        store.items = [
          MobileSighting(
            latE5: 5334390,
            lonE5: 776330,
            category: 0,
            bearing: -1,
            day: 20700,
          ),
        ];
        final fresh = MobileHistory(store, clock: () => now);
        fresh.record([mobile('1', north(800))]);
        await fresh.flush();
        expect(store.saves, 0, reason: 'vor load() wird nicht geschrieben');
        await fresh.load();
        await fresh.dispose();
        expect(store.items, hasLength(2));
      },
    );

    test('Einträge über zwei Jahre fallen beim Laden weg', () async {
      final old = DateTime(2024, 10, 1);
      final day = old.difference(DateTime.utc(1970)).inDays;
      store.items = [
        MobileSighting(
          latE5: 5334390,
          lonE5: 776330,
          category: 0,
          bearing: -1,
          day: day,
        ),
        MobileSighting(
          latE5: 5334390,
          lonE5: 776330,
          category: 0,
          bearing: -1,
          day: day + 700,
        ),
      ];
      final again = MobileHistory(store, clock: () => now);
      await again.load();
      expect(again.length, 1);
      await again.dispose();
    });

    test('Obergrenze: die ältesten gehen zuerst', () {
      final big = MobileHistory(MemoryMobileHistoryStore(), clock: () => now);
      // Je Tag eine Stelle weit auseinander: jede zählt.
      for (var i = 0; i < mobileHistoryMax + 50; i++) {
        final at = GeoPoint(47 + (i % 200) * 0.01, 6 + (i ~/ 200) * 0.01);
        big.record([
          mobile(
            '$i',
            at,
            observedAt: DateTime(2026, 11, 3).subtract(
              Duration(days: 700 - (i * 700 ~/ (mobileHistoryMax + 50))),
            ),
          ),
        ]);
      }
      expect(big.length, lessThanOrEqualTo(mobileHistoryMax));
      expect(big.length, greaterThan(mobileHistoryMax * 0.9));
      final days = big.items.map((s) => s.day);
      final newest = DateTime(
        2026,
        11,
        3,
      ).difference(DateTime.utc(1970)).inDays;
      expect(days.reduce((a, b) => a > b ? a : b), greaterThan(newest - 5));
      expect(
        days.reduce((a, b) => a < b ? a : b),
        greaterThan(newest - 700),
        reason: 'der älteste Tag fiel weg',
      );
    });

    test('Platzbedarf der vollen Datei', () async {
      final dir = await Directory.systemTemp.createTemp('verlauf');
      addTearDown(() => dir.delete(recursive: true));
      final fileStore = FileMobileHistoryStore(dir);
      final big = MobileHistory(fileStore, clock: () => now);
      await big.load();
      final watch = Stopwatch()..start();
      for (var i = 0; i < mobileHistoryMax; i++) {
        big.record([
          mobile(
            '$i',
            GeoPoint(47 + (i % 200) * 0.01, 6 + (i ~/ 200) * 0.01),
            bearings: [(i * 7 % 360).toDouble()],
            observedAt: DateTime(2026, 11, 3).subtract(Duration(days: i % 700)),
          ),
        ]);
      }
      watch.stop();
      await big.flush();
      final bytes = fileStore.file.lengthSync();
      // Beispielhafte Messung für docs/VERLAUF.md.
      // ignore: avoid_print
      print(
        'Verlauf voll: ${big.length} Einträge, $bytes Byte, '
        'Aufnahme ${watch.elapsedMilliseconds} ms',
      );
      expect(big.length, mobileHistoryMax);
      expect(bytes, lessThan(1024 * 1024));
      final again = MobileHistory(fileStore, clock: () => now);
      await again.load();
      expect(again.length, mobileHistoryMax);
      await big.dispose();
      await again.dispose();
    });
  });

  group('Datei', () {
    late Directory dir;
    late FileMobileHistoryStore files;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('verlauf');
      files = FileMobileHistoryStore(dir);
    });
    tearDown(() => dir.delete(recursive: true));

    test('fehlende Datei: leer', () async {
      expect(await files.load(), isEmpty);
    });

    test('Schreiben und Lesen; kein .tmp bleibt liegen', () async {
      final s = MobileSighting(
        latE5: 5334390,
        lonE5: 776330,
        category: 3,
        bearing: 185,
        day: 20400,
      );
      await files.save([s]);
      final back = (await files.load()).single;
      expect(
        [back.latE5, back.lonE5, back.category, back.bearing, back.day],
        [5334390, 776330, 3, 185, 20400],
      );
      expect(File('${files.file.path}.tmp').existsSync(), isFalse);
    });

    test(
      'kaputte Datei wird beiseitegelegt, der Verlauf beginnt leer',
      () async {
        await files.file.writeAsString('{"items": [[1,2');
        expect(await files.load(), isEmpty);
        expect(File('${files.file.path}.bad').existsSync(), isTrue);
      },
    );

    test('ungültige Einträge werden übersprungen, gültige bleiben', () async {
      await files.file.writeAsString(
        jsonEncode({
          'version': 1,
          'items': [
            [5334390, 776330, 0, 90, 20400],
            [5334390, 776330, 9, 90, 20400],
            'x',
            [1, 2],
            [5334390, 776330, 0, 400, 20400],
          ],
        }),
      );
      expect(await files.load(), hasLength(1));
    });
  });

  group('doppelte Sichtungen', () {
    test('die Sichtung steht schon im Verlauf eines Plugins: zählt einmal', () {
      final plugin = [
        mobile(
          'h1',
          spot,
          source: 'mein_verlauf',
          historical: true,
          observedAt: DateTime(2026, 11, 3, 7, 12),
        ),
      ];
      final index = ObservationIndex(plugin);
      history.record([mobile('1', north(30))]); // heute 8 Uhr, 30 m weiter
      history.record([mobile('2', north(600))]);
      final own = history.around(spot, 2000);
      expect(own, hasLength(2));
      expect([
        for (final p in own) index.covers(p),
      ], containsAll([true, false]));
    });
  });

  group('im Repository', () {
    late FakePlugin live;
    late AlertRepositoryImpl repo;
    late MemoryMobileHistoryStore repoStore;
    late SharedPreferences prefs;

    Future<AlertRepositoryImpl> open(MemoryMobileHistoryStore s) async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final r = AlertRepositoryImpl(
        osm: FakeOsm(),
        hotspots: FakeHotspots(),
        plugins: [live],
        prefs: prefs,
        clock: () => now,
        historyStore: s,
        overviewDebounce: const Duration(milliseconds: 20),
      );
      await r.setPluginEnabled(live.id, true);
      return r;
    }

    Future<void> poke(AlertRepositoryImpl r) async {
      r.pointsAround(spot);
      await pumpEventQueue();
    }

    setUp(() async {
      live = FakePlugin('live')
        ..onFetch = (_) async => [
          mobile('7', north(100), bearings: [90]),
          mobile('8', north(900), category: AlertCategory.accident),
        ];
      repoStore = MemoryMobileHistoryStore();
      repo = await open(repoStore);
    });
    tearDown(() => repo.dispose());

    test('ein mobiler Blitzer eines Plugins landet im Verlauf, auch nach dem Neustart', () async {
      await poke(repo);
      await poke(repo);
      final live1 = repo.pointsAround(spot, withHistory: true);
      expect(live1.where((p) => !p.historical), hasLength(2));
      final past = live1.where((p) => p.historical).toList();
      expect(past, hasLength(1), reason: 'nur der Blitzer, nicht der Unfall');
      expect(past.single.source, mobileHistorySource);
      expect(repo.pointsAround(spot).where((p) => p.historical), isEmpty);

      await repo.dispose();
      expect(repoStore.items, hasLength(1));

      // Neustart: das Plugin liefert nichts mehr, der Verlauf bleibt.
      live.onFetch = (_) async => const [];
      final again = await open(repoStore);
      await poke(again);
      await poke(again);
      final points = again.pointsAround(spot, withHistory: true);
      expect(points.where((p) => !p.historical), isEmpty);
      expect(points.where((p) => p.historical), hasLength(1));
      await again.dispose();
    });

    test('ohne Ablage führt das Repository keinen Verlauf', () async {
      final plain = AlertRepositoryImpl(
        osm: FakeOsm(),
        hotspots: FakeHotspots(),
        plugins: [live],
        prefs: prefs,
        clock: () => now,
      );
      await plain.setPluginEnabled(live.id, true);
      await poke(plain);
      await poke(plain);
      expect(
        plain.pointsAround(spot, withHistory: true).where((p) => p.historical),
        isEmpty,
      );
      await plain.dispose();
    });

    test(
      'Verlauf eines Plugins und eigener Verlauf: dieselbe Sichtung einmal',
      () async {
        final both = FakePlugin('mein_verlauf')
          ..onFetch = (_) async => [
            mobile(
              'h',
              north(100),
              source: 'mein_verlauf',
              historical: true,
              observedAt: now,
            ),
          ];
        SharedPreferences.setMockInitialValues({});
        final r = AlertRepositoryImpl(
          osm: FakeOsm(),
          hotspots: FakeHotspots(),
          plugins: [live, both],
          prefs: await SharedPreferences.getInstance(),
          clock: () => now,
          historyStore: MemoryMobileHistoryStore(),
          overviewDebounce: const Duration(milliseconds: 20),
        );
        await r.setPluginEnabled(live.id, true);
        await r.setPluginEnabled(both.id, true);
        for (var i = 0; i < 4; i++) {
          await poke(r);
        }
        final past = r
            .pointsAround(spot, withHistory: true)
            .where((p) => p.historical);
        expect(past, hasLength(1));
        expect(past.single.source, 'mein_verlauf');
        await r.dispose();
      },
    );
  });
}
