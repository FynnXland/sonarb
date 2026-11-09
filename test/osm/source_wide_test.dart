import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_source.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  /// Legt eine Blitzer-Kachel mit einem Punkt in die Cache-Datei, [age] alt.
  void writeCameraTile(
    int iy,
    int ix,
    String id, {
    Duration age = Duration.zero,
  }) {
    final at = env.clock.subtract(age).millisecondsSinceEpoch;
    env.file('cameras_${iy}_$ix')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'v': 1,
          'x': 3,
          't': at,
          'p': [
            {
              'i': 'osm:node/$id',
              'k': 'speedCamera',
              'la': iy / 10 + 0.05,
              'lo': ix / 10 + 0.05,
            },
          ],
          'w': <dynamic>[],
        }),
      );
  }

  const wide = GeoBounds(south: 50.0, west: 10.0, north: 53.0, east: 14.0);

  test(
    'weiter Ausschnitt: nur Cache, kein Netz, auch veraltete Kacheln',
    () async {
      writeCameraTile(520, 130, '1');
      writeCameraTile(521, 131, '2', age: const Duration(days: 30));
      writeCameraTile(400, 100, '3'); // außerhalb
      var calls = 0;
      final source = env.make(
        MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      final r = await source.loadCameras(wide);
      expect(calls, 0);
      expect(r.error, isNull);
      expect(r.fromCache, isTrue);
      expect(r.points.map((p) => p.id).toSet(), {'osm:node/1', 'osm:node/2'});
      expect(r.fetchedAt, env.clock.subtract(const Duration(days: 30)));
    },
  );

  test('weiter Ausschnitt ohne Cache: leer ohne Fehler', () async {
    final source = env.make(MockClient((_) async => http.Response('', 500)));
    final r = await source.loadCameras(wide);
    expect(r.points, isEmpty);
    expect(r.error, isNull);
  });

  test('genau 0,5° lädt noch, darüber nicht', () async {
    var calls = 0;
    final source = env.make(
      MockClient((req) async {
        calls++;
        return ok(req);
      }),
    );
    await source.loadCameras(
      const GeoBounds(south: 52.0, west: 8.0, north: 52.5, east: 8.5),
    );
    expect(calls, 1);
    calls = 0;
    await source.loadCameras(
      const GeoBounds(south: 53.0, west: 9.0, north: 53.51, east: 9.2),
    );
    expect(calls, 0);
  });

  test('Kachelgrenze: die mittennächsten zuerst', () async {
    writeCameraTile(520, 130, 'nah'); // 52,0 / 13,0
    writeCameraTile(500, 100, 'fern'); // 50,0 / 10,0
    writeCameraTile(510, 120, 'mitte'); // 51,0 / 12,0
    final limited = OsmSource(
      cacheDir: env.dir,
      client: MockClient((_) async => http.Response('', 500)),
      now: () => env.clock,
      maxCachedTiles: 2,
    );
    // Mitte des Ausschnitts bei 51,5 / 12,0: „mitte“ und „nah“ sind näher als „fern“.
    final r = await limited.loadCameras(
      const GeoBounds(south: 50.0, west: 10.0, north: 53.0, east: 14.0),
    );
    expect(r.points.map((p) => p.id).toSet(), {
      'osm:node/mitte',
      'osm:node/nah',
    });
  });

  test('viele Kacheln lesen verdrängt die Tempolimit-Wege nicht', () async {
    final source = OsmSource(
      cacheDir: env.dir,
      client: MockClient((req) async => ok(req)),
      now: () => env.clock,
      maxMemoryTiles: 12,
    );
    await source.load(testArea);
    const p = GeoPoint(52.05002, 8.05);
    expect(await source.speedLimitAt(p, 90), 50);

    for (var i = 0; i < 30; i++) {
      writeCameraTile(600 + i, 150, 'x$i');
    }
    final r = await source.loadCameras(
      const GeoBounds(south: 50.0, west: 5.0, north: 65.0, east: 20.0),
    );
    expect(r.points.length, greaterThanOrEqualTo(30));
    expect(
      await source.speedLimitAt(p, 90),
      50,
      reason: 'Wege noch im Speicher',
    );
  });

  test('kaputte Datei im Ordner wird übersprungen', () async {
    writeCameraTile(520, 130, '1');
    env.file('cameras_521_130')
      ..createSync(recursive: true)
      ..writeAsStringSync('kein json');
    final source = env.make(MockClient((_) async => http.Response('', 500)));
    final r = await source.loadCameras(wide);
    expect(r.points.map((p) => p.id), ['osm:node/1']);
    expect(r.error, isNull);
  });

  test('Grenzwerte passen zur Karte', () {
    expect(cacheOnlySpanDeg, 0.5);
    expect(maxCachedTilesPerView, greaterThan(100));
  });
}
