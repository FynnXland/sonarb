import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_details.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

/// Eine Stelle in [testTile], nahe an der Nachbarkachel im Osten (8,1).
const _here = GeoPoint(52.05, 8.09);

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  /// Blitzer-Kachel im Cache, wie eine frühere Fahrt sie angelegt hat.
  void writeCamera(TileId id, {required DateTime fetchedAt}) {
    final data = TileData(
      fetchedAt: fetchedAt,
      points: const [],
      ways: const [],
      detailVersion: pointDetailVersion,
    );
    env.file('cameras_${id.key}').writeAsStringSync(jsonEncode(data.toJson()));
  }

  group('Stufe 0: Cache ohne Netz', () {
    test(
      'veraltete Kachel zählt als verfügbar, es geht keine Anfrage raus',
      () async {
        writeCamera(
          testTile,
          fetchedAt: env.clock.subtract(const Duration(days: 40)),
        );
        var requests = 0;
        final source = env.make(
          MockClient((req) async {
            requests++;
            return ok(req);
          }),
        );
        final r = await source.loadCached(testArea);
        expect(requests, 0);
        expect(r.error, isNull);
        expect(r.fromCache, isTrue);
        expect(source.loadedCameraTilesIn(testArea), isNotEmpty);
      },
    );

    test('ohne Cache: leeres Ergebnis ohne Fehler', () async {
      final source = env.make(
        MockClient((req) async => http.Response('', 503)),
      );
      final r = await source.loadCached(testArea);
      expect(r.points, isEmpty);
      expect(r.error, isNull);
      expect(source.loadedCameraTilesIn(testArea), isEmpty);
    });
  });

  group('Stufe 1: die Kachel unter dem Fahrzeug', () {
    test('nur eine Blitzer-Anfrage, keine Ampeln und Tempolimits', () async {
      final seen = <OsmLayer>[];
      final source = env.make(
        MockClient((req) async {
          seen.add(layerOf(req));
          return ok(req);
        }),
      );
      final r = await source.loadFirstStage(_here);
      expect(seen, [OsmLayer.cameras]);
      expect(r.error, isNull);
      expect(r.points.map((p) => p.id), ['osm:node/1']);
      expect(source.loadedCameraTilesIn(testArea), isNotEmpty);
    });

    test(
      'Fehlschlag: Fehlertext, Cache-Stand der Kachel bleibt nutzbar',
      () async {
        writeCamera(
          testTile,
          fetchedAt: env.clock.subtract(const Duration(days: 40)),
        );
        final source = env.make(
          MockClient((req) async => http.Response('', 503)),
          grace: const Duration(milliseconds: 20),
        );
        final r = await source.loadFirstStage(_here);
        expect(r.error, isNotNull);
        expect(source.loadedCameraTilesIn(testArea), isNotEmpty);
      },
    );

    test(
      'Frist: hängt die Anfrage, kommt nach der Frist ein Fehlertext',
      () async {
        final never = Completer<http.Response>();
        final source = env.make(
          MockClient((req) => never.future),
          deadline: const Duration(milliseconds: 50),
        );
        final r = await source.loadFirstStage(_here);
        expect(r.error, isNotNull);
        expect(r.points, isEmpty);
      },
    );

    test('teilt sich die Anfrage mit dem Fenster', () async {
      var cameraRequests = 0;
      final source = env.make(
        MockClient((req) async {
          if (layerOf(req) == OsmLayer.cameras) cameraRequests++;
          return ok(req);
        }),
        grace: const Duration(milliseconds: 20),
      );
      final first = source.loadFirstStage(_here);
      final full = source.load(testArea);
      await Future.wait([first, full]);
      expect(cameraRequests, 1);
    });
  });
}
