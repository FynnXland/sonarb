import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';
import 'package:sonarb/features/alerts/load_stages.dart';
import 'package:sonarb/features/osm/staged_source.dart';

import 'fakes.dart';

const start = GeoPoint(52.0, 13.0);

/// Kachel (0,1°) um [start].
const tile = GeoBounds(south: 52.0, west: 13.0, north: 52.1, east: 13.1);

/// Ein Punkt in [m] Metern östlich von [start].
GeoPoint east(double m) => GeoPoint(52.0, 13.0 + m / 68500);

/// Quelle mit Stufen: Cache, Kachel unter dem Fahrzeug und Fenster treffen einzeln ein.
class StagedOsm extends FakeOsm implements StagedPointSource {
  Completer<SourceResult>? cachedGate, firstGate;
  SourceResult cachedResult = const SourceResult(points: []);
  SourceResult firstResult = const SourceResult(points: []);
  int cachedCalls = 0, firstCalls = 0;

  @override
  Future<SourceResult> loadCached(GeoBounds area) {
    cachedCalls++;
    return cachedGate?.future ?? Future.value(cachedResult);
  }

  @override
  Future<SourceResult> loadFirstStage(GeoPoint position) {
    firstCalls++;
    return firstGate?.future ?? Future.value(firstResult);
  }
}

void main() {
  late StagedOsm osm;
  late DateTime now;
  late FakePlugin live, roadworks, history;
  late AlertRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    osm = StagedOsm();
    now = DateTime(2026, 11, 2, 12);
    live = FakePlugin('blitzer_live');
    roadworks = FakePlugin('baustellen_test');
    history = FakePlugin('mein_verlauf');
    repo = AlertRepositoryImpl(
      osm: osm,
      hotspots: FakeHotspots(),
      plugins: [live, roadworks, history],
      prefs: await SharedPreferences.getInstance(),
      clock: () => now,
      overviewDebounce: const Duration(milliseconds: 20),
    );
    for (final p in [live, roadworks, history]) {
      await repo.setPluginEnabled(p.id, true);
    }
  });
  tearDown(() => repo.dispose());

  Future<PluginStatus> osmStatus() async =>
      (await repo.watchStatus().first).firstWhere((s) => s.id == 'osm').status;

  Future<void> poke([GeoPoint p = start]) async {
    repo.pointsAround(p);
    await pumpEventQueue();
  }

  List<String> ids() => [for (final p in repo.pointsAround(start)) p.id];

  test('Stufen eines Plugins nach seiner ID', () {
    expect(pluginLoadStage('blitzer_live'), 1);
    expect(pluginLoadStage('sammelquelle'), 1);
    expect(pluginLoadStage('baustellen_berlin'), 2);
    expect(pluginLoadStage('strassen_roadworks'), 2);
    expect(pluginLoadStage('mein_verlauf'), 3);
  });

  group('Start in einer Gegend ohne Daten, Netz langsam', () {
    setUp(() {
      osm.cachedGate = Completer();
      osm.firstGate = Completer();
      osm.gate = Completer();
    });

    test(
      'alles hängt: nur Stufe 1 lädt, weder Fernblock noch spätere Plugins',
      () async {
        await poke();
        expect(osm.cachedCalls, 1);
        expect(osm.firstCalls, 1);
        expect(osm.loads, 1);
        expect(live.fetches, 1, reason: 'feste und mobile Blitzer sofort');
        expect(roadworks.fetches, 0);
        expect(history.fetches, 0);
        expect(osm.cameraLoads, 0, reason: 'der große Umkreis kommt zuletzt');
        expect(await osmStatus(), PluginStatus.loading);
      },
    );

    test(
      'die Stufen treffen nacheinander ein und werden sofort genutzt',
      () async {
        await poke();

        // Stufe 0: der Cache. Gespeicherte Daten zählen als verfügbar, auch ohne Netz.
        osm.loadedTiles = const [tile];
        osm.cachedGate!.complete(
          SourceResult(
            points: [osmPoint('cache', 52.0, 13.005)],
            fromCache: true,
          ),
        );
        await poke();
        expect(ids(), ['osm:node/cache']);
        expect(await osmStatus(), PluginStatus.loading, reason: 'kein Fehler');
        expect(
          roadworks.fetches,
          1,
          reason: 'Stufe 2 darf, die Blitzer sind da',
        );
        expect(history.fetches, 0, reason: 'Stufe 3 wartet auf das Fenster');

        // Stufe 1: die Kachel unter dem Fahrzeug.
        osm.firstGate!.complete(
          SourceResult(points: [osmPoint('first', 52.0, 13.01)]),
        );
        await poke();
        expect(ids(), containsAll(['osm:node/cache', 'osm:node/first']));

        // Stufe 2: das Fenster ersetzt die frühen Stände; danach der Fernblock und der Verlauf.
        osm.gate!.complete(
          SourceResult(points: [osmPoint('full', 52.0, 13.02)]),
        );
        await poke();
        expect(ids(), ['osm:node/full']);
        expect(osm.cameraLoads, greaterThan(0));
        expect(history.fetches, 1);
        expect(await osmStatus(), PluginStatus.ok);
      },
    );

    test(
      'ein später Teilstand überschreibt das fertige Fenster nicht',
      () async {
        await poke();
        osm.gate!.complete(
          SourceResult(points: [osmPoint('full', 52.0, 13.02)]),
        );
        await poke();
        osm.firstGate!.complete(
          SourceResult(points: [osmPoint('late', 52.0, 13.03)]),
        );
        await poke();
        expect(ids(), ['osm:node/full']);
      },
    );

    test('ohne Blitzer-Kachel und ohne Punkte aus Stufe 0 und 1: weiter laden, kein Ausfall', () async {
      await poke();
      osm.cachedGate!.complete(const SourceResult(points: [], fromCache: true));
      osm.firstGate!.complete(
        const SourceResult(points: [], error: 'Overpass antwortet nicht'),
      );
      await poke();
      expect(ids(), isEmpty);
      expect(await osmStatus(), PluginStatus.loading);
      expect(roadworks.fetches, 0, reason: 'noch keine Blitzer für die Stelle');
    });

    test('spätere Stufen warten höchstens 30 s, der Verlauf 60 s', () async {
      await poke();
      expect(roadworks.fetches + history.fetches, 0);
      now = now.add(const Duration(seconds: 31));
      await poke();
      expect(roadworks.fetches, 1);
      expect(history.fetches, 0);
      now = now.add(const Duration(seconds: 30));
      await poke();
      expect(history.fetches, 1);
    });
  });

  group('Netz weg, Cache da', () {
    test('Blitzer-Kachel aus dem Cache: kein Ausfall, auch wenn jedes Laden scheitert', () async {
      osm.loadedTiles = const [tile];
      osm.cachedResult = SourceResult(
        points: [osmPoint('cache', 52.0, 13.005)],
        fromCache: true,
      );
      osm.firstResult = const SourceResult(
        points: [],
        error: 'Overpass nicht erreichbar',
      );
      // Das Fenster liefert, was im Cache liegt, und den Fehler dazu.
      osm.result = SourceResult(
        points: [osmPoint('cache', 52.0, 13.005)],
        error: 'Overpass nicht erreichbar, Daten unvollständig',
      );
      await poke();
      now = now.add(const Duration(minutes: 3));
      await poke();
      expect(ids(), ['osm:node/cache']);
      expect(await osmStatus(), PluginStatus.ok);
    });

    test('ohne OSM-Daten, aber ein Blitzer-Plugin liefert für die Stelle: kein Ausfall', () async {
      live.onFetch = (_) async => [
        pluginPoint('blitzer_live', '1', 52.0, 13.001),
      ];
      osm.result = const SourceResult(
        points: [],
        error: 'Overpass nicht erreichbar, Daten unvollständig',
      );
      await poke();
      await poke();
      expect(await osmStatus(), PluginStatus.ok);
    });

    test('Baustellen-Plugin allein ersetzt die Blitzerdaten nicht', () async {
      roadworks.onFetch = (_) async => [
        pluginPoint('baustellen_test', '1', 52.0, 13.001),
      ];
      live.onFetch = (_) async => throw Exception('kaputt');
      osm.result = const SourceResult(
        points: [],
        error: 'Overpass nicht erreichbar, Daten unvollständig',
      );
      await poke();
      now = now.add(const Duration(seconds: 31));
      await poke();
      await poke();
      expect(roadworks.fetches, 1);
      expect(await osmStatus(), PluginStatus.error);
    });

    test('nichts im Cache, nichts geladen, kein Plugin: Ausfall', () async {
      live.onFetch = (_) async => throw Exception('kaputt');
      osm.result = const SourceResult(
        points: [],
        error: 'Overpass nicht erreichbar, Daten unvollständig',
      );
      await poke();
      expect(await osmStatus(), PluginStatus.error);
    });

    test('keine frühen Stufen, solange der Bestand die Stelle deckt', () async {
      osm.result = SourceResult(points: [osmPoint('a', 52.0, 13.005)]);
      await poke();
      expect(osm.cachedCalls, 1);
      await poke(east(900));
      expect(osm.loads, 2);
      expect(osm.cachedCalls, 1);
      expect(osm.firstCalls, 1);
    });
  });
}
