import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/overpass_client.dart';

import 'osm_fixtures.dart';

void main() {
  var clock = DateTime.utc(2026, 5, 1);
  setUp(() => clock = DateTime.utc(2026, 5, 1));

  OverpassClient make(
    Future<http.Response> Function(http.Request) handler, {
    List<String>? endpoints,
  }) => OverpassClient(
    client: MockClient(handler),
    endpoints: endpoints ?? const ['https://a.test/api'],
    now: () => clock,
  );

  Future<Duration?> failure(OverpassClient c) async {
    try {
      await c.fetch(OsmLayer.cameras, [testTile]);
    } on OverpassException catch (e) {
      return e.retryAfter ?? Duration.zero;
    }
    fail('Es hätte scheitern müssen');
  }

  test('User-Agent ist ein gültiger Kopfzeilenwert (nur ASCII)', () {
    expect(
      RegExp(r'^[ -~]+$').hasMatch(overpassUserAgent),
      isTrue,
      reason: overpassUserAgent,
    );
    // dart:io prüft genauso, bevor eine Anfrage rausgeht.
    final headers = HttpClient().userAgent = overpassUserAgent;
    expect(headers, overpassUserAgent);
  });

  test('echte Anfrage mit dem User-Agent geht raus (Kopfzeile gültig)', () async {
    // Der MockClient prüft keine Kopfzeilen; erst dart:io lehnt Nicht-ASCII ab.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? seen;
    server.listen((req) async {
      seen = req.headers.value('user-agent');
      await utf8.decoder.bind(req).drain<void>();
      req.response
        ..statusCode = 200
        ..write(layerBody(OsmLayer.cameras));
      await req.response.close();
    });
    final c = OverpassClient(
      client: http.Client(),
      endpoints: ['http://127.0.0.1:${server.port}/api'],
    );
    final data = await c.fetch(OsmLayer.cameras, [testTile]);
    expect(data[testTile]!.points, isNotEmpty);
    expect(seen, overpassUserAgent);
    expect(
      overpassUserAgent.codeUnits.every((u) => u >= 0x20 && u < 0x7f),
      isTrue,
    );
  });

  test('Standard-Endpunkte: Hauptinstanz und Private.coffee', () {
    expect(defaultOverpassEndpoints, [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.private.coffee/api/interpreter',
    ]);
  });

  test(
    'Pause nach 429 steigt 30 → 60 → 120 s und bleibt dann bei 120 s',
    () async {
      var calls = 0;
      final c = make((_) async {
        calls++;
        return http.Response('', 429);
      });
      final seen = <Duration?>[];
      for (var i = 0; i < 5; i++) {
        seen.add(await failure(c));
        clock = clock.add(seen.last! + const Duration(seconds: 1));
      }
      expect(seen, [
        const Duration(seconds: 30),
        const Duration(seconds: 60),
        const Duration(seconds: 120),
        const Duration(seconds: 120),
        const Duration(seconds: 120),
      ]);
      expect(calls, 5);
    },
  );

  test('während der Pause geht keine Anfrage raus', () async {
    var calls = 0;
    final c = make((_) async {
      calls++;
      return http.Response('', 429);
    });
    await failure(c);
    clock = clock.add(const Duration(seconds: 10));
    expect(await failure(c), const Duration(seconds: 20));
    expect(calls, 1);
  });

  test('Retry-After hat Vorrang vor der Staffel', () async {
    final c = make(
      (_) async => http.Response('', 429, headers: {'retry-after': '45'}),
    );
    expect(await failure(c), const Duration(seconds: 45));
  });

  test('502, 503, 504 und 406 zählen als Überlast', () async {
    for (final code in [406, 502, 503, 504]) {
      final c = make((_) async => http.Response('', code));
      expect(await failure(c), const Duration(seconds: 30), reason: '$code');
    }
  });

  test('Erfolg setzt die Staffel zurück', () async {
    var busy = true;
    final c = make(
      (req) async => busy
          ? http.Response('', 429)
          : http.Response(layerBody(layerOf(req)), 200),
    );
    await failure(c);
    clock = clock.add(const Duration(seconds: 31));
    busy = false;
    expect(
      (await c.fetch(OsmLayer.cameras, [testTile]))[testTile]!.points,
      isNotEmpty,
    );
    busy = true;
    expect(await failure(c), const Duration(seconds: 30));
  });

  test(
    'anderer Endpunkt springt ein; retryAfter nur, wenn alle pausieren',
    () async {
      final hosts = <String>[];
      final c = make((req) async {
        hosts.add(req.url.host);
        return req.url.host == 'a.test'
            ? http.Response('', 429)
            : http.Response(layerBody(layerOf(req)), 200);
      }, endpoints: const ['https://a.test/api', 'https://b.test/api']);
      expect(await c.fetch(OsmLayer.cameras, [testTile]), isNotNull);
      expect(hosts, ['a.test', 'b.test']);
      // a pausiert, b antwortet: nur b wird gefragt.
      await c.fetch(OsmLayer.cameras, [testTile]);
      expect(hosts.skip(2), ['b.test']);
    },
  );

  test('Netzfehler pausiert nicht und nennt keine Wartezeit', () async {
    var calls = 0;
    final c = make((_) async {
      calls++;
      throw const SocketException('offline');
    });
    expect(await failure(c), Duration.zero);
    expect(await failure(c), Duration.zero);
    expect(calls, 2);
  });

  test('Abfrage-Timeout liegt bei mindestens 60 s, HTTP-Timeout darüber', () {
    for (final l in OsmLayer.values) {
      expect(l.queryTimeout, greaterThanOrEqualTo(60));
      expect(l.httpTimeout.inSeconds, greaterThan(l.queryTimeout));
    }
  });
}
