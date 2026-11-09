import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/plugins/example/json_feed_plugin.dart';

const area = GeoBounds(south: 52.0, west: 13.0, north: 52.1, east: 13.2);

JsonFeedPlugin plugin(
  MockClient client, {
  String? token,
  String url = 'https://feed.test/api',
}) => JsonFeedPlugin(
  id: 'feed',
  displayName: 'Feed',
  baseUrl: Uri.parse(url),
  bearerToken: token,
  client: client,
);

http.Response json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('sendet Bereich als Query und Bearer-Token', () async {
    late http.Request seen;
    final p = plugin(
      MockClient((r) async {
        seen = r;
        return json({'points': []});
      }),
      token: 'geheim',
    );
    await p.fetch(area);

    expect(seen.method, 'GET');
    expect(seen.url.host, 'feed.test');
    expect(seen.url.queryParameters, {
      'south': '52.0',
      'west': '13.0',
      'north': '52.1',
      'east': '13.2',
    });
    expect(seen.headers['Authorization'], 'Bearer geheim');
  });

  test(
    'ohne Token kein Authorization-Header, vorhandene Query bleibt erhalten',
    () async {
      late http.Request seen;
      final p = plugin(
        MockClient((r) async {
          seen = r;
          return json({'points': []});
        }),
        url: 'https://feed.test/api?region=x',
      );
      await p.fetch(area);

      expect(seen.headers.containsKey('Authorization'), isFalse);
      expect(seen.url.queryParameters['region'], 'x');
      expect(seen.url.queryParameters['south'], '52.0');
    },
  );

  test('parst Punkte mit ID-Präfix, Art, Richtungen und Tempolimit', () async {
    final p = plugin(
      MockClient(
        (_) async => json({
          'points': [
            {
              'id': 'a1',
              'lat': 52.05,
              'lon': 13.1,
              'kind': 'speedCamera',
              'bearings': [90, 270.5],
              'maxSpeed': 50,
            },
            {'id': 7, 'lat': 52, 'lon': 13},
          ],
        }),
      ),
    );
    final pts = await p.fetch(area);

    expect(pts, hasLength(2));
    expect(pts[0].id, 'plugin:feed:a1');
    expect(pts[0].source, 'feed');
    expect(pts[0].kind, AlertKind.speedCamera);
    expect(pts[0].position, const GeoPoint(52.05, 13.1));
    expect(pts[0].travelBearings, [90.0, 270.5]);
    expect(pts[0].maxSpeed, 50);
    expect(pts[1].id, 'plugin:feed:7');
    expect(pts[1].kind, AlertKind.live);
    expect(pts[1].travelBearings, isEmpty);
    expect(pts[1].maxSpeed, isNull);
  });

  test('überspringt ungültige Einträge', () async {
    final p = plugin(
      MockClient(
        (_) async => json({
          'points': [
            'kein objekt',
            {'lat': 52, 'lon': 13}, // ohne id
            {'id': 'x', 'lat': 'oben', 'lon': 13},
            {'id': 'y', 'lat': 95, 'lon': 13},
            {'id': 'z', 'lat': 52, 'lon': 13, 'kind': 'ufo'},
            {'id': 'ok', 'lat': 52, 'lon': 13, 'kind': 'live'},
          ],
        }),
      ),
    );
    final pts = await p.fetch(area);
    expect(pts.map((e) => e.id), ['plugin:feed:ok']);
  });

  test('wirft bei HTTP-Fehler mit kurzer Meldung', () async {
    final p = plugin(MockClient((_) async => http.Response('nein', 401)));
    await expectLater(
      p.fetch(area),
      throwsA(
        isA<JsonFeedException>().having(
          (e) => e.toString(),
          'Meldung',
          'HTTP 401',
        ),
      ),
    );
  });

  test('wirft bei ungültigem JSON oder fehlendem Feld points', () async {
    await expectLater(
      plugin(MockClient((_) async => http.Response('<html>', 200))).fetch(area),
      throwsA(isA<JsonFeedException>()),
    );
    await expectLater(
      plugin(MockClient((_) async => json({'items': []}))).fetch(area),
      throwsA(isA<JsonFeedException>()),
    );
  });

  test('Netzfehler des Clients werden durchgereicht', () async {
    final p = plugin(
      MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(p.fetch(area), throwsA(isA<http.ClientException>()));
  });

  test('Plugin-Eigenschaften und Lebenszyklus', () async {
    final p = plugin(MockClient((_) async => json({'points': []})));
    expect(p.id, 'feed');
    expect(p.displayName, 'Feed');
    expect(p.refreshInterval, const Duration(seconds: 60));
    await p.initialize();
    await p.dispose();
  });
}
