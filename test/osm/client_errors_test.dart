import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/overpass_client.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

OverpassClient make(
  Future<http.Response> Function(http.Request) handler, {
  List<String> endpoints = const ['https://a.test/api'],
}) => OverpassClient(client: MockClient(handler), endpoints: endpoints);

Future<OverpassException> failure(
  OverpassClient c, [
  OsmLayer layer = OsmLayer.cameras,
]) async {
  try {
    await c.fetch(layer, [testTile]);
  } on OverpassException catch (e) {
    return e;
  }
  fail('Es hätte scheitern müssen');
}

String goodBody() => layerBody(OsmLayer.cameras);

void main() {
  group('Ursachen', () {
    test('abgeschnittenes JSON: Verbindung abgebrochen, bald erneut', () async {
      final full = goodBody();
      final c = make(
        (_) async => http.Response(full.substring(0, full.length ~/ 2), 200),
      );
      final e = await failure(c);
      expect(e.reason, OverpassReason.aborted);
      expect(e.retryAfter, Duration.zero);
    });

    test('großes abgeschnittenes JSON (Isolate-Pfad) genauso', () async {
      final big = overpassBody([
        for (var i = 0; i < 3000; i++)
          node(i + 10, 52.05, 8.05, {
            'highway': 'speed_camera',
            'note': 'x' * 100,
          }),
      ]);
      expect(big.length, greaterThan(200 * 1024));
      final c = make(
        (_) async => http.Response(big.substring(0, big.length - 50), 200),
      );
      expect((await failure(c)).reason, OverpassReason.aborted);
    });

    test('HTML mit Status 200: Antwort unbrauchbar, bald erneut', () async {
      final c = make(
        (_) async => http.Response(
          '<html><body>Bad Gateway</body></html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      );
      final e = await failure(c);
      expect(e.reason, OverpassReason.unusable);
      expect(e.retryAfter, Duration.zero);
    });

    test('text/plain und leere Antwort: Antwort unbrauchbar', () async {
      for (final body in ['Server is busy', '', '  \n']) {
        final c = make(
          (_) async =>
              http.Response(body, 200, headers: {'content-type': 'text/plain'}),
        );
        expect(
          (await failure(c)).reason,
          OverpassReason.unusable,
          reason: body,
        );
      }
    });

    test('gültiges JSON ohne elements: unbrauchbar, kein Warten', () async {
      for (final body in ['{"foo": 1}', '[]', '{"elements": "x"}']) {
        final c = make((_) async => http.Response(body, 200));
        final e = await failure(c);
        expect(e.reason, OverpassReason.unusable, reason: body);
        expect(e.retryAfter, isNull, reason: body);
      }
    });

    test('Verbindungsabbruch während der Übertragung', () async {
      for (final msg in [
        'Connection closed while receiving data',
        'SocketException: Connection reset by peer',
        'HttpException: Connection terminated during handshake',
      ]) {
        final c = make((_) async => throw http.ClientException(msg));
        final e = await failure(c);
        expect(e.reason, OverpassReason.aborted, reason: msg);
        expect(e.retryAfter, Duration.zero, reason: msg);
      }
    });

    test('kein Netz: nicht erreichbar, kein Grund zu warten', () async {
      for (final err in [
        const SocketException('Failed host lookup'),
        http.ClientException('SocketException: Network is unreachable'),
        const FormatException('Invalid HTTP header field value'),
      ]) {
        final e = await failure(make((_) async => throw err));
        expect(e.reason, OverpassReason.unreachable, reason: '$err');
        expect(e.retryAfter, isNull, reason: '$err');
      }
    });

    test('Überlast bleibt Überlast', () async {
      final e = await failure(make((_) async => http.Response('', 502)));
      expect(e.reason, OverpassReason.overloaded);
    });

    test('kaputte UTF-8-Bytes im Text werfen nicht', () async {
      final bytes = [
        ...utf8.encode(
          overpassBody([
            node(1, 52.05, 8.05, {'highway': 'speed_camera', 'name': 'AB'}),
          ]).replaceFirst('AB', 'A'),
        ),
      ];
      // 0xFF ist in UTF-8 nie gültig; steht mitten im Namen.
      final i = utf8.decode(bytes).indexOf('"A"') + 1;
      bytes[i] = 0xFF;
      final c = make(
        (_) async => http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final data = await c.fetch(OsmLayer.cameras, [testTile]);
      expect(data[testTile]!.points, hasLength(1));
    });
  });

  group('Erholung', () {
    test('zweiter Endpunkt springt bei unbrauchbarer Antwort ein', () async {
      final hosts = <String>[];
      final c = make((req) async {
        hosts.add(req.url.host);
        return req.url.host == 'a.test'
            ? http.Response('<html>', 200)
            : http.Response(goodBody(), 200);
      }, endpoints: const ['https://a.test/api', 'https://b.test/api']);
      final data = await c.fetch(OsmLayer.cameras, [testTile]);
      expect(data[testTile]!.points, isNotEmpty);
      expect(hosts, ['a.test', 'b.test']);
    });

    test('Abbruch und Müllantwort pausieren den Endpunkt nicht', () async {
      var calls = 0;
      final c = make((_) async {
        calls++;
        return calls == 1
            ? http.Response('<html>', 200)
            : http.Response(goodBody(), 200);
      });
      await failure(c);
      expect(
        (await c.fetch(OsmLayer.cameras, [testTile]))[testTile],
        isNotNull,
      );
      expect(calls, 2);
    });
  });

  group('Quelle', () {
    final env = SourceEnv();
    setUp(env.setUp);
    tearDown(env.tearDown);

    test('Blitzer-Kachel: bei abgeschnittener Antwort von beiden Servern neuer Versuch', () async {
      var cameraCalls = 0;
      final source = env.make(
        MockClient((req) async {
          final layer = layerOf(req);
          final body = layerBody(layer);
          if (layer == OsmLayer.cameras && ++cameraCalls <= 2) {
            return http.Response(body.substring(0, body.length ~/ 2), 200);
          }
          return http.Response(body, 200);
        }),
        parallel: 1,
      );
      final r = await source.load(testArea);
      expect(cameraCalls, 3);
      expect(env.sleeps, [const Duration(seconds: 1)]);
      expect(r.points.map((p) => p.id), contains('osm:node/1'));
      expect(r.error, isNull);
    });

    test('Cache bleibt heil: Müllantwort, Meldung, später Erholung', () async {
      await env
          .make(
            MockClient(
              (req) async => http.Response(layerBody(layerOf(req)), 200),
            ),
          )
          .load(testArea);
      final before = env.camFile.readAsStringSync();
      env.clock = env.clock.add(const Duration(days: 8)); // veraltet

      final garbage = env.make(
        MockClient((_) async => http.Response('<html>nope</html>', 200)),
      );
      final r = await garbage.load(testArea);
      expect(r.points.map((p) => p.id), contains('osm:node/1'));
      expect(r.error, 'Antwort unbrauchbar, Daten aus dem Cache');
      expect(
        env.camFile.readAsStringSync(),
        before,
        reason: 'Datei unverändert',
      );

      // Neustart mit gesundem Netz holt neu und überschreibt.
      final healthy = env.make(
        MockClient((req) async => http.Response(layerBody(layerOf(req)), 200)),
      );
      final again = await healthy.load(testArea);
      expect(again.error, isNull);
      expect(again.fromCache, isFalse);
    });

    test('Meldungen ohne Cache', () async {
      final cut = env.make(
        MockClient((req) async {
          final body = layerBody(layerOf(req));
          return http.Response(body.substring(0, body.length - 20), 200);
        }),
      );
      expect(
        (await cut.load(testArea)).error,
        'Verbindung abgebrochen, Daten unvollständig',
      );
    });
  });
}
