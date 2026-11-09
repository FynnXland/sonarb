import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_layer.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

const _areaB = GeoBounds(south: 53.0, west: 9.0, north: 53.05, east: 9.05);
const _areaC = GeoBounds(south: 54.0, west: 10.0, north: 54.02, east: 10.02);

/// Blitzer-Antwort mit je einer Messstelle in [_areaB] und [_areaC].
http.Response cameras(http.Request req) => http.Response(
  overpassBody([
    node(21, 53.02, 9.02, {'highway': 'speed_camera'}),
    node(31, 54.01, 10.01, {'highway': 'speed_camera'}),
  ]),
  200,
);

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  test(
    'loadCameras fragt nur Blitzer, mehrere Kacheln in einer Anfrage',
    () async {
      final seen = <OsmLayer, int>{};
      final cameraQueries = <String>[];
      final source = env.make(
        MockClient((req) async {
          seen.update(layerOf(req), (n) => n + 1, ifAbsent: () => 1);
          if (layerOf(req) == OsmLayer.cameras) {
            cameraQueries.add(req.bodyFields['data']!);
            return cameras(req);
          }
          return http.Response(overpassBody([]), 200);
        }),
      );
      // Knapp 0,3° × 0,3° bei Hamburg: 3 × 3 Kacheln.
      const area = GeoBounds(south: 53.0, west: 9.0, north: 53.29, east: 9.29);
      final r = await source.loadCameras(area);

      expect(seen, {OsmLayer.cameras: 1});
      expect(
        cameraQueries.single,
        contains('(52.99998,8.99998,53.30002,9.30002)'),
      );
      expect(r.error, isNull);
      expect(r.notice, isNull);
      expect(r.points.map((p) => p.id), ['osm:node/21']);
      expect(r.fromCache, isFalse);
      expect(env.file('cameras_530_90').existsSync(), isTrue);
      expect(env.file('signals_530_90').existsSync(), isFalse);
    },
  );

  test('Cache-Treffer: kein Netz, auch von load befüllte Kacheln', () async {
    var calls = 0;
    final source = env.make(
      MockClient((req) async {
        calls++;
        return layerOf(req) == OsmLayer.cameras
            ? cameras(req)
            : http.Response(overpassBody([]), 200);
      }),
    );
    await source.load(_areaB);
    final afterLoad = calls;

    final r = await source.loadCameras(_areaB);
    expect(calls, afterLoad);
    expect(r.fromCache, isTrue);
    expect(r.points.map((p) => p.id), ['osm:node/21']);

    // Größerer Ausschnitt: nur die fehlenden Kacheln werden geholt.
    final more = await source.loadCameras(
      const GeoBounds(south: 52.95, west: 8.95, north: 53.05, east: 9.05),
    );
    expect(calls, afterLoad + 1);
    expect(more.points.map((p) => p.id), ['osm:node/21']);
  });

  test('Fehler wird gemeldet, nichts wirft', () async {
    final source = env.make(MockClient((_) async => http.Response('', 500)));
    final r = await source.loadCameras(_areaB);
    expect(r.points, isEmpty);
    expect(r.error, 'Overpass nicht erreichbar, Daten unvollständig');
  });

  test('Übersicht wartet hinter der Fahrt und blockiert sie nie', () async {
    final hang = Completer<void>();
    final cameraBoxes = <String>[];
    final source = env.make(
      MockClient((req) async {
        if (layerOf(req) == OsmLayer.limits) await hang.future;
        if (layerOf(req) != OsmLayer.cameras) {
          return http.Response(overpassBody([]), 200);
        }
        cameraBoxes.add(req.bodyFields['data']!);
        return cameras(req);
      }),
      grace: const Duration(milliseconds: 20),
    );

    // Eine Tempolimit-Anfrage der Fahrt hängt und hält den Einzelplatz.
    await source.load(testArea);
    cameraBoxes.clear();

    final overview = source.loadCameras(_areaB);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cameraBoxes, isEmpty, reason: 'Übersicht steht in der Schlange');

    // Die Fahrt an einem dritten Ort kommt trotzdem sofort durch.
    final driving = await source.load(_areaC);
    expect(driving.points.map((p) => p.id), ['osm:node/31']);
    expect(cameraBoxes, hasLength(1));
    expect(cameraBoxes.single, contains('(53.99998,'));

    hang.complete();
    final r = await overview;
    expect(r.points.map((p) => p.id), ['osm:node/21']);
    expect(cameraBoxes, hasLength(2));
  });

  test(
    'Fahrt-Abfrage derselben Kachel wird von der Übersicht mitbenutzt',
    () async {
      var cameraCalls = 0;
      final gate = Completer<void>();
      final source = env.make(
        MockClient((req) async {
          if (layerOf(req) != OsmLayer.cameras) {
            return http.Response(overpassBody([]), 200);
          }
          cameraCalls++;
          await gate.future;
          return cameras(req);
        }),
        grace: const Duration(milliseconds: 20),
      );
      final driving = source.load(_areaB);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final overview = source.loadCameras(_areaB);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gate.complete();
      final results = await Future.wait([driving, overview]);
      expect(cameraCalls, 1);
      expect(results.every((r) => r.points.length == 1), isTrue);
    },
  );
}
