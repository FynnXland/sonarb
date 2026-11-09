import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/osm/osm.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_source.dart';
import 'package:sonarb/features/osm/overpass_client.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  test('createOsmSource liefert die echte Quelle', () {
    expect(createOsmSource(cacheDir: env.dir), isA<OsmSource>());
  });

  test(
    'getrennte Abfragen je Schicht mit eigenem Gitter und Timeout',
    () async {
      final seen = <OsmLayer, List<String>>{};
      http.Request? first;
      final source = env.make(
        MockClient((req) async {
          first ??= req;
          seen.putIfAbsent(layerOf(req), () => []).add(req.bodyFields['data']!);
          return ok(req);
        }),
      );
      final r = await source.load(testArea);

      expect(first!.method, 'POST');
      expect(first!.url.toString(), 'https://overpass-api.de/api/interpreter');
      expect(first!.headers['User-Agent'], overpassUserAgent);
      expect(layerOf(first!), OsmLayer.cameras, reason: 'Blitzer zuerst');

      final cam = seen[OsmLayer.cameras]!.single;
      expect(cam, startsWith('[out:json][timeout:60];'));
      for (final part in [
        'speed_camera',
        'bn.cams',
        'enforcement',
        'average_speed',
        'section_control',
        '.camways out geom',
        '(51.99998,7.99998,52.10002,8.10002)',
      ]) {
        expect(cam, contains(part));
      }
      expect(cam, isNot(contains('traffic_signals"]')));
      expect(cam, isNot(contains('maxspeed"]')));

      final sig = seen[OsmLayer.signals]!.single;
      expect(sig, contains('"highway"="traffic_signals"'));
      expect(sig, contains('(51.99998,7.99998,52.10002,8.10002)'));
      expect(sig, isNot(contains('speed_camera')));

      expect(seen[OsmLayer.limits], hasLength(4), reason: '0,05°-Zellen');
      expect(seen[OsmLayer.minorLimits], hasLength(4));
      final lim = seen[OsmLayer.limits]!.first;
      expect(lim, startsWith('[out:json][timeout:90];'));
      for (final part in ['"maxspeed"]', 'maxspeed:forward', 'out geom']) {
        expect(lim, contains(part));
      }
      expect(lim, isNot(contains('residential')));
      expect(seen[OsmLayer.minorLimits]!.first, contains('residential'));
      expect(seen[OsmLayer.minorLimits]!.first, isNot(contains('primary')));

      expect(r.error, isNull);
      expect(r.fromCache, isFalse);
      expect(r.fetchedAt, env.clock);
      expect(r.points.map((p) => p.id).toSet(), {'osm:node/1', 'osm:node/2'});
      final camera = r.points.firstWhere((p) => p.id == 'osm:node/1');
      expect(camera.kind, AlertKind.speedCamera);
      expect(camera.travelBearings, [90]);
    },
  );

  test('Ergebnis wird auf area gefiltert', () async {
    final source = env.make(
      MockClient(
        (req) async => layerOf(req) == OsmLayer.cameras
            ? http.Response(
                overpassBody([
                  node(1, 52.05, 8.05, {'highway': 'speed_camera'}),
                  node(2, 52.095, 8.095, {'highway': 'speed_camera'}),
                ]),
                200,
              )
            : http.Response(overpassBody([]), 200),
      ),
    );
    final r = await source.load(testArea);
    expect(r.points.map((p) => p.id), ['osm:node/1']);
  });

  group('Reihenfolge', () {
    test('Blitzer, dann Tempolimits der nächsten Zelle (beide Schichten), dann Ampeln', () async {
      final order = <String>[];
      final source = env.make(
        MockClient((req) async {
          order.add(
            '${layerOf(req).name}${layerOf(req).hasWays ? ' ${westOf(req)}' : ''}',
          );
          return ok(req);
        }),
        parallel: 1,
      );
      // Mitte bei 8,0425 O: liegt in Zelle 160 (8,00–8,05), Zelle 161 ist 500 m weiter.
      await source.load(
        const GeoBounds(south: 52.06, west: 8.03, north: 52.08, east: 8.055),
      );
      expect(order, [
        'cameras',
        'limits 7.99998',
        'minorLimits 7.99998',
        'limits 8.04998',
        'minorLimits 8.04998',
        'signals',
      ]);
    });

    test('Blitzer-Platz bleibt frei, auch wenn Tempolimits hängen', () async {
      final hang = Completer<void>();
      final source = env.make(
        MockClient((req) async {
          if (layerOf(req).hasWays) await hang.future;
          return ok(req);
        }),
        grace: const Duration(milliseconds: 20),
      );
      final a = await source.load(testArea);
      expect(a.points, isNotEmpty);
      expect(a.error, isNull);
      expect(a.notice, 'Ampeln und Tempolimits werden nachgeladen');

      // Anderer Ort, andere Blitzer-Kachel: kommt trotz hängender Tempolimit-Anfrage.
      final b = await source.load(
        const GeoBounds(south: 53.0, west: 9.0, north: 53.02, east: 9.02),
      );
      expect(b.error, isNot(contains('Daten unvollständig')));
      hang.complete();
    });
  });

  test('parallele load-Aufrufe teilen sich eine Anfrage je Kachel', () async {
    var calls = 0;
    final gate = Completer<void>();
    final source = env.make(
      MockClient((req) async {
        calls++;
        await gate.future;
        return ok(req);
      }),
    );
    final a = source.load(testArea);
    final b = source.load(testArea);
    final c = source.load(
      const GeoBounds(south: 52.03, west: 8.03, north: 52.07, east: 8.07),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gate.complete();
    final results = await Future.wait([a, b, c]);
    expect(calls, lessThanOrEqualTo(10));
    expect(results.every((r) => r.points.length == 2), isTrue);
    expect(results.every((r) => r.error == null), isTrue);
  });

  test('höchstens zwei gleichzeitige Anfragen, davon eine für Ampeln und Tempolimits', () async {
    var running = 0, peak = 0, detail = 0, detailPeak = 0;
    final source = env.make(
      MockClient((req) async {
        final isDetail = layerOf(req) != OsmLayer.cameras;
        running++;
        if (isDetail) detail++;
        peak = math.max(peak, running);
        detailPeak = math.max(detailPeak, detail);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        running--;
        if (isDetail) detail--;
        return http.Response(overpassBody([]), 200);
      }),
    );
    // Zwei Orte gleichzeitig: Blitzer des einen laufen neben den Wegen des anderen.
    await Future.wait([
      source.load(
        const GeoBounds(south: 52.01, west: 8.01, north: 52.09, east: 8.09),
      ),
      source.load(
        const GeoBounds(south: 53.01, west: 9.01, north: 53.09, east: 9.09),
      ),
    ]);
    expect(peak, 2);
    expect(detailPeak, 1);
  });

  group('speedLimitAt', () {
    test('nutzt geladene Daten, davor null', () async {
      final source = env.make(MockClient((req) async => ok(req)));
      const p = GeoPoint(52.05002, 8.05);
      expect(await source.speedLimitAt(p, 90), isNull);
      await source.load(testArea);
      expect(await source.speedLimitAt(p, 90), 50);
      // Länger her als das Halten dauert (15 s): 90 m neben dem Weg ist das Limit unbekannt.
      env.clock = env.clock.add(const Duration(seconds: 20));
      expect(
        await source.speedLimitAt(const GeoPoint(52.0508, 8.05), 90),
        isNull,
      );
    });

    test('Straße der Nebenstraßen-Schicht zählt auch', () async {
      final source = env.make(
        MockClient(
          (req) async => layerOf(req) == OsmLayer.minorLimits
              ? http.Response(
                  overpassBody([
                    way(
                      11,
                      [
                        [52.07, 8.01],
                        [52.07, 8.03],
                      ],
                      {'highway': 'residential', 'maxspeed': '30'},
                    ),
                  ]),
                  200,
                )
              : ok(req),
        ),
      );
      await source.load(testArea);
      expect(await source.speedLimitAt(const GeoPoint(52.07, 8.02), 90), 30);
    });

    test('Straße liegt in der Nachbarzelle', () async {
      final source = env.make(
        MockClient(
          (req) async => layerOf(req) == OsmLayer.limits
              ? http.Response(
                  overpassBody([
                    way(
                      10,
                      [
                        [52.0499, 8.02],
                        [52.0499, 8.03],
                      ],
                      {'highway': 'primary', 'maxspeed': '70'},
                    ),
                  ]),
                  200,
                )
              : http.Response(overpassBody([]), 200),
        ),
      );
      await source.load(testArea);
      // Punkt knapp nördlich der Zellkante (52,05), Straße 11 m südlich.
      expect(await source.speedLimitAt(const GeoPoint(52.0500, 8.025), 90), 70);
    });
  });
}
