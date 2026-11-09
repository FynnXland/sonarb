import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  const wide = GeoBounds(south: 51.0, west: 7.0, north: 53.0, east: 9.0);
  const elsewhere = GeoBounds(south: 40.0, west: 0.0, north: 41.0, east: 1.0);

  test('geladene Blitzer-Kacheln im Ausschnitt, sonst nichts', () async {
    final source = env.make(MockClient((req) async => ok(req)));
    expect(source.loadedCameraTilesIn(wide), isEmpty);

    await source.load(testArea);
    final tiles = source.loadedCameraTilesIn(wide);
    expect(tiles, isNotEmpty);
    expect(
      tiles.map((b) => (b.south, b.west)),
      contains((testTile.bounds.south, testTile.bounds.west)),
    );
    expect(source.loadedCameraTilesIn(elsewhere), isEmpty);
  });

  test('nach Neustart aus dem Cache-Ordner, ohne Abruf', () async {
    await env.make(MockClient((req) async => ok(req))).load(testArea);

    var calls = 0;
    final restarted = env.make(
      MockClient((req) async {
        calls++;
        return http.Response('', 500);
      }),
    );
    // Der erste Aufruf liest den Ordner im Hintergrund.
    restarted.loadedCameraTilesIn(wide);
    for (
      var i = 0;
      i < 100 && restarted.loadedCameraTilesIn(wide).isEmpty;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(restarted.loadedCameraTilesIn(wide), isNotEmpty);
    expect(calls, 0);
  });

  test('gescheiterter Abruf ohne Daten zählt nicht als geladen', () async {
    final source = env.make(MockClient((req) async => http.Response('', 500)));
    await source.load(testArea);
    expect(source.loadedCameraTilesIn(wide), isEmpty);
  });

  test('Cache leeren: keine geladenen Gebiete mehr', () async {
    final source = env.make(MockClient((req) async => ok(req)));
    await source.load(testArea);
    expect(source.loadedCameraTilesIn(wide), isNotEmpty);
    await source.clearCache();
    expect(source.loadedCameraTilesIn(wide), isEmpty);
  });
}
