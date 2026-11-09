import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';

import 'fakes.dart';

const start = GeoPoint(52.0, 13.0);

/// Ein Punkt in [m] Metern östlich von [start] (0,001° Länge ≈ 68,5 m bei 52° Breite).
GeoPoint east(double m) => GeoPoint(52.0, 13.0 + m / 68500);

void main() {
  late FakeOsm osm;
  late DateTime now;
  late AlertRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    osm = FakeOsm();
    now = DateTime(2026, 11, 2, 12);
    repo = AlertRepositoryImpl(
      osm: osm,
      hotspots: FakeHotspots(),
      plugins: const [],
      prefs: await SharedPreferences.getInstance(),
      clock: () => now,
      overviewDebounce: const Duration(milliseconds: 20),
    );
  });
  tearDown(() => repo.dispose());

  Future<SourceStatus> osmStatus() async =>
      (await repo.watchStatus().first).firstWhere((s) => s.id == 'osm');

  Future<void> step(
    GeoPoint p, {
    Duration dt = const Duration(seconds: 1),
  }) async {
    now = now.add(dt);
    repo.pointsAround(p);
    await pumpEventQueue();
  }

  group('Nahdaten und Fernblock getrennt', () {
    test('ein hängender Fernblock hält die Nahdaten nicht zurück', () async {
      osm.result = SourceResult(points: [osmPoint('near', 52.0, 13.005)]);
      osm.cameraGate =
          Completer(); // der große Umkreis hängt in der Warteschlange
      repo.pointsAround(start);
      await pumpEventQueue();
      expect(
        osm.cameraLoads,
        greaterThan(0),
        reason: 'Fernblock wurde gestartet',
      );
      expect(repo.pointsAround(start).map((p) => p.id), [
        'osm:node/near',
      ], reason: 'die Umgebung steht, obwohl der Fernblock noch läuft');
      expect((await osmStatus()).status, PluginStatus.ok);
    });

    test('der Fernblock ergänzt, sobald er fertig ist', () async {
      osm.result = SourceResult(points: [osmPoint('near', 52.0, 13.005)]);
      final gate = osm.cameraGate = Completer();
      repo.pointsAround(start);
      await pumpEventQueue();
      gate.complete(SourceResult(points: [osmPoint('far', 52.0, 13.06)]));
      await pumpEventQueue();
      final ids = repo
          .pointsAround(start, radiusMeters: 10000)
          .map((p) => p.id);
      expect(ids, containsAll(['osm:node/near', 'osm:node/far']));
    });

    test(
      'neue Umgebung wird geladen, während der Fernblock noch hängt',
      () async {
        osm.result = SourceResult(points: [osmPoint('a', 52.0, 13.005)]);
        osm.cameraGate = Completer();
        repo.pointsAround(start);
        await pumpEventQueue();
        expect(osm.loads, 1);
        // Nach 1 km Fahrt ist die Nahabfrage dran, auch wenn der Fernblock noch läuft.
        osm.result = SourceResult(points: [osmPoint('b', 52.0, 13.02)]);
        await step(east(1000), dt: const Duration(seconds: 30));
        expect(osm.loads, 2);
        expect(
          repo.pointsAround(east(1000), radiusMeters: 3000).map((p) => p.id),
          contains('osm:node/b'),
        );
      },
    );

    test(
      'Fernblock gescheitert, Umgebung da: kein Ausfall, Meldung bleibt',
      () async {
        osm.result = SourceResult(points: [osmPoint('near', 52.0, 13.005)]);
        osm.cameraResult = const SourceResult(
          points: [],
          error: 'Overpass überlastet',
        );
        repo.pointsAround(start);
        await pumpEventQueue();
        final s = await osmStatus();
        expect(s.status, PluginStatus.ok);
        expect(s.message, 'Blitzer nicht vollständig');
      },
    );
  });

  group('Fahrt am Rand des geladenen Gebiets', () {
    test('langsamer Abruf: der alte Bestand bleibt bis zum Eintreffen der neuen Daten', () async {
      osm.result = SourceResult(
        points: [
          osmPoint('p1', 52.0, 13.0 + 500 / 68500),
          osmPoint('p2', 52.0, 13.0 + 2500 / 68500),
        ],
      );
      repo.pointsAround(start);
      await pumpEventQueue();

      // Autobahntempo (120 km/h): der nächste Abruf hängt 90 s.
      final gate = osm.gate = Completer();
      var pos = start;
      for (var i = 1; i <= 60; i++) {
        pos = east(33.3 * i);
        await step(pos);
      }
      expect(
        osm.loads,
        2,
        reason: 'nach 750 m wurde nachgeladen, der Abruf hängt',
      );
      // 2 km gefahren, mitten im Rest des alten Kreises: Punkt 2 liegt noch voraus und ist da.
      expect(repo.pointsAround(pos).map((p) => p.id), contains('osm:node/p2'));
      expect(
        (await osmStatus()).status,
        PluginStatus.loading,
        reason: 'läuft, kein Ausfall',
      );

      for (var i = 61; i <= 90; i++) {
        pos = east(33.3 * i);
        await step(pos);
      }
      osm.result = SourceResult(
        points: [osmPoint('p3', 52.0, 13.0 + 5000 / 68500)],
      );
      osm.gate = null; // weitere Abrufe kommen sofort
      gate.complete(osm.result);
      await pumpEventQueue();
      expect(repo.pointsAround(pos, radiusMeters: 4000).map((p) => p.id), [
        'osm:node/p3',
      ]);
      await pumpEventQueue();
      expect((await osmStatus()).status, PluginStatus.ok);
    });

    test('Abruf scheitert, Blitzer-Kachel für die Stelle liegt vor: keine Ausfall-Ansage', () async {
      osm.result = SourceResult(points: [osmPoint('p1', 52.0, 13.005)]);
      repo.pointsAround(start);
      await pumpEventQueue();
      // Zwei Kilometer weiter: der Abruf scheitert ohne Treffer (Strecke ohne Blitzer, eine Kachel fehlt),
      // die Kachel unter dem Fahrzeug ist aber geladen.
      const here = GeoPoint(52.0, 13.0 + 4000 / 68500);
      osm.loadedTiles = const [
        GeoBounds(south: 51.9, west: 12.9, north: 52.0, east: 13.1),
        GeoBounds(south: 52.0, west: 12.9, north: 52.1, east: 13.1),
      ];
      osm.result = const SourceResult(
        points: [],
        error: 'Overpass überlastet, Daten unvollständig',
      );
      await step(here, dt: const Duration(minutes: 2));
      expect((await osmStatus()).status, PluginStatus.ok);
    });

    test(
      'Abruf scheitert und keine Kachel für die Stelle: Ausfall wie bisher',
      () async {
        osm.result = SourceResult(points: [osmPoint('p1', 52.0, 13.005)]);
        repo.pointsAround(start);
        await pumpEventQueue();
        const here = GeoPoint(52.0, 13.0 + 4000 / 68500);
        osm.loadedTiles = const [];
        osm.result = const SourceResult(
          points: [],
          error: 'Overpass überlastet, Daten unvollständig',
        );
        await step(here, dt: const Duration(minutes: 2));
        expect((await osmStatus()).status, PluginStatus.error);
      },
    );
  });
}
