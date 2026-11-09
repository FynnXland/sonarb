import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/overpass_client.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  test('Anfrage nimmt gzip, die komprimierte Antwort wird gelesen', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? accept;
    var sent = 0;
    final body = overpassBody([
      for (var i = 0; i < 200; i++)
        node(i + 10, 52.05, 8.05, {
          'highway': 'speed_camera',
          'note': 'Wiederholter Text zum Komprimieren',
        }),
    ]);
    server.listen((req) async {
      accept = req.headers.value('accept-encoding');
      await utf8.decoder.bind(req).drain<void>();
      final zipped = gzip.encode(utf8.encode(body));
      sent = zipped.length;
      req.response
        ..statusCode = 200
        ..headers.set('content-encoding', 'gzip')
        ..headers.contentType = ContentType.json
        ..add(zipped);
      await req.response.close();
    });
    final c = OverpassClient(
      client: http.Client(),
      endpoints: ['http://127.0.0.1:${server.port}/api'],
    );
    final data = await c.fetch(OsmLayer.cameras, [testTile]);
    expect(accept, contains('gzip'));
    expect(data[testTile]!.points, hasLength(200));
    expect(sent, lessThan(body.length ~/ 5), reason: 'auf unter ein Fünftel');
  });

  group('Auffrischen', () {
    test('Blitzer nach 7 Tagen, Ampeln und Tempolimits erst nach 30', () async {
      final calls = <OsmLayer, int>{};
      final source = env.make(
        MockClient((req) async {
          calls.update(layerOf(req), (n) => n + 1, ifAbsent: () => 1);
          return ok(req);
        }),
      );
      await source.load(testArea);
      calls.clear();

      env.clock = env.clock.add(const Duration(days: 8));
      await source.load(testArea);
      expect(calls.keys, [
        OsmLayer.cameras,
      ], reason: 'nur Blitzer sind älter als 7 Tage');

      calls.clear();
      env.clock = env.clock.add(const Duration(days: 22)); // Tag 30
      await source.load(testArea);
      expect(calls.keys.toSet(), OsmLayer.values.toSet());
    });

    test('nie doppelt: gleiche Kacheln, gleicher Tag, kein Netz', () async {
      var calls = 0;
      final source = env.make(
        MockClient((req) async {
          calls++;
          return ok(req);
        }),
      );
      await source.load(testArea);
      final first = calls;
      for (var i = 0; i < 5; i++) {
        env.clock = env.clock.add(const Duration(hours: 3));
        await source.load(testArea);
      }
      expect(calls, first);
      // Ein Stück weiter: nur die neuen Kacheln.
      calls = 0;
      await source.load(
        const GeoBounds(south: 52.02, west: 8.08, north: 52.08, east: 8.14),
      );
      expect(calls, lessThan(first));
    });
  });

  group('Funkloch', () {
    test('Pausen wachsen mit jedem Fehlschlag, Erfolg setzt zurück', () async {
      var offline = true;
      var cameraCalls = 0;
      final source = env.make(
        MockClient((req) async {
          if (layerOf(req) == OsmLayer.cameras) cameraCalls++;
          if (offline) throw const SocketException('Network is unreachable');
          return ok(req);
        }),
      );

      /// Lädt zum Zeitpunkt [seconds] nach dem Start und sagt, ob angefragt wurde.
      Future<bool> at(int seconds) async {
        env.clock = DateTime.utc(2026, 5, 1).add(Duration(seconds: seconds));
        final before = cameraCalls;
        await source.load(testArea);
        return cameraCalls > before;
      }

      expect(await at(0), isTrue); // 1. Fehlschlag, Pause 60 s
      expect(await at(30), isFalse);
      expect(await at(61), isTrue); // 2. Fehlschlag, Pause 120 s
      expect(await at(61 + 100), isFalse);
      expect(await at(61 + 121), isTrue); // 3.: Pause 300 s
      expect(await at(182 + 250), isFalse);
      expect(await at(182 + 301), isTrue); // 4.: Pause 900 s
      expect(await at(483 + 800), isFalse);

      offline = false;
      expect(await at(483 + 901), isTrue, reason: 'Netz wieder da');
      // Danach beginnt es wieder bei einer Minute.
      offline = true;
      env.clock = env.clock.add(const Duration(days: 40)); // alles veraltet
      final base = env.clock.difference(DateTime.utc(2026, 5, 1)).inSeconds;
      expect(await at(base), isTrue);
      expect(
        await at(base + 61),
        isTrue,
        reason: 'nur 60 s Pause nach dem ersten',
      );
    });

    test('Überlast (429) zählt nicht als Funkloch', () async {
      var calls = 0;
      final source = env.make(
        MockClient((req) async {
          if (layerOf(req) == OsmLayer.cameras) calls++;
          return http.Response('', 429, headers: {'retry-after': '30'});
        }),
        parallel: 1,
      );
      await source.load(testArea);
      expect(calls, greaterThan(0));
    });
  });
}
