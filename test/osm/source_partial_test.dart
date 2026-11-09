import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_layer.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  group('Teilergebnisse', () {
    test(
      'Blitzer da, Tempolimits scheitern: nutzbar mit knapper Meldung',
      () async {
        final source = env.make(
          MockClient(
            (req) async =>
                layerOf(req).hasWays ? http.Response('', 500) : ok(req),
          ),
        );
        final r = await source.load(testArea);
        expect(r.points.map((p) => p.id).toSet(), {'osm:node/1', 'osm:node/2'});
        expect(
          r.error,
          'Overpass nicht erreichbar, Ampeln und Tempolimits unvollständig',
        );
        expect(r.errorInDetailsOnly, isTrue, reason: 'Blitzer vollständig');
        expect(
          await source.speedLimitAt(const GeoPoint(52.05002, 8.05), 90),
          isNull,
        );
      },
    );

    test(
      'langsame Tempolimits: load kehrt zurück, Daten folgen im Hintergrund',
      () async {
        final gate = Completer<void>();
        final source = env.make(
          MockClient((req) async {
            if (layerOf(req) == OsmLayer.limits) await gate.future;
            return ok(req);
          }),
          grace: const Duration(milliseconds: 20),
        );
        final r = await source.load(testArea);
        expect(r.points.map((p) => p.id), contains('osm:node/1'));
        expect(r.error, isNull);
        expect(r.notice, 'Ampeln und Tempolimits werden nachgeladen');
        const p = GeoPoint(52.05002, 8.05);
        expect(await source.speedLimitAt(p, 90), isNull);

        gate.complete();
        // Unter Last (volle Testsuite) dauert das Schreiben in den Cache länger als ein fester Takt.
        int? limit;
        final until = DateTime.now().add(const Duration(seconds: 5));
        while (limit == null && DateTime.now().isBefore(until)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          limit = await source.speedLimitAt(p, 90);
        }
        expect(limit, 50);
        var again = await source.load(testArea);
        while ((again.error != null || !again.fromCache) &&
            DateTime.now().isBefore(until)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          again = await source.load(testArea);
        }
        expect(again.error, isNull);
        expect(again.fromCache, isTrue);
      },
    );

    test(
      'Blitzer hängen: nach der Frist kommt das Vorhandene mit Meldung',
      () async {
        final gate = Completer<void>();
        final source = env.make(
          MockClient((req) async {
            if (layerOf(req) == OsmLayer.cameras) await gate.future;
            return ok(req);
          }),
          deadline: const Duration(milliseconds: 30),
        );
        final r = await source.load(testArea);
        expect(r.points.map((p) => p.id), [
          'osm:node/2',
        ], reason: 'nur die Ampel');
        expect(r.error, 'Overpass antwortet nicht, Daten unvollständig');

        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final again = await source.load(testArea);
        expect(again.points.map((p) => p.id).toSet(), {
          'osm:node/1',
          'osm:node/2',
        });
      },
    );

    test('mehrere fehlende Blitzer-Kacheln gehen in einer Anfrage', () async {
      final cameraQueries = <String>[];
      final source = env.make(
        MockClient((req) async {
          if (layerOf(req) == OsmLayer.cameras) {
            cameraQueries.add(req.bodyFields['data']!);
          }
          return http.Response(
            overpassBody([
              if (layerOf(req) == OsmLayer.cameras) ...[
                node(1, 52.05, 8.05, {'highway': 'speed_camera'}),
                node(2, 52.15, 8.05, {'highway': 'speed_camera'}),
              ],
            ]),
            200,
          );
        }),
      );
      // Zwei Kacheln übereinander (52,0–52,1 und 52,1–52,2).
      const area = GeoBounds(
        south: 52.05,
        west: 8.04,
        north: 52.15,
        east: 8.06,
      );
      final r = await source.load(area);
      expect(cameraQueries, hasLength(1));
      expect(
        cameraQueries.single,
        contains('(51.99998,7.99998,52.20002,8.10002)'),
      );
      expect(r.points.map((p) => p.id).toSet(), {'osm:node/1', 'osm:node/2'});
      expect(env.file('cameras_520_80').existsSync(), isTrue);
      expect(env.file('cameras_521_80').existsSync(), isTrue);

      // Nur eine Kachel veraltet: nur sie wird erneut geholt, und zwar allein.
      cameraQueries.clear();
      env.clock = env.clock.add(const Duration(days: 8));
      await source.load(
        const GeoBounds(south: 52.12, west: 8.04, north: 52.15, east: 8.06),
      );
      expect(
        cameraQueries.single,
        contains('(52.09998,7.99998,52.20002,8.10002)'),
      );
    });

    test('Blitzer-Anfrage scheitert: beide Kacheln melden es', () async {
      final source = env.make(
        MockClient(
          (req) async => layerOf(req) == OsmLayer.cameras
              ? http.Response('', 500)
              : http.Response(overpassBody([]), 200),
        ),
      );
      final r = await source.load(
        const GeoBounds(south: 52.05, west: 8.04, north: 52.15, east: 8.06),
      );
      expect(r.points, isEmpty);
      expect(r.error, 'Overpass nicht erreichbar, Daten unvollständig');
      expect(r.errorInDetailsOnly, isFalse);
    });
  });

  group('Fehler und Wiederholung', () {
    test(
      'beide Endpunkte tot und kein Cache: Fehlertext, keine Punkte',
      () async {
        var calls = 0;
        final source = env.make(
          MockClient((_) async {
            calls++;
            throw const SocketException('offline');
          }),
        );
        final r = await source.load(testArea);
        expect(calls, 2 * 10, reason: '10 Kacheln, je beide Endpunkte');
        expect(r.points, isEmpty);
        expect(r.error, 'Overpass nicht erreichbar, Daten unvollständig');
        expect(r.fetchedAt, isNull);
      },
    );

    test('Blitzer-Kachel wartet die Pause nach 429 ab und lädt dann', () async {
      var cameraCalls = 0;
      final source = env.make(
        MockClient((req) async {
          if (layerOf(req) != OsmLayer.cameras) {
            return http.Response('', 500);
          }
          return ++cameraCalls <= 2 ? http.Response('busy', 429) : ok(req);
        }),
        parallel: 1,
      );
      final r = await source.load(testArea);
      expect(cameraCalls, 3);
      expect(env.sleeps, [const Duration(seconds: 31)]);
      expect(r.points.map((p) => p.id), contains('osm:node/1'));
    });

    test(
      'Retry-After länger als die Wartegrenze: Blitzer-Kachel gibt auf',
      () async {
        var cameraCalls = 0;
        final source = env.make(
          MockClient((req) async {
            if (layerOf(req) == OsmLayer.cameras) cameraCalls++;
            return http.Response('', 429, headers: {'retry-after': '300'});
          }),
          parallel: 1,
        );
        final r = await source.load(testArea);
        expect(cameraCalls, 2, reason: 'je Endpunkt einmal');
        expect(env.sleeps, isEmpty);
        expect(r.error, 'Overpass überlastet, Daten unvollständig');
      },
    );

    test('Fehlschlag wird eine Minute lang nicht wiederholt', () async {
      var calls = 0;
      final source = env.make(
        MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      await source.load(testArea);
      final first = calls;
      env.clock = env.clock.add(const Duration(seconds: 30));
      expect((await source.load(testArea)).error, isNotNull);
      expect(calls, first);
      env.clock = env.clock.add(const Duration(seconds: 40));
      await source.load(testArea);
      expect(calls, first * 2);
    });
  });
}
