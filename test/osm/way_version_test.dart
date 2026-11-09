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

/// Zellen des Testgebiets im feinen Gitter (0,05°): Breite 52,00–52,10, Länge 8,00–8,10.
const _cells = [(1040, 160), (1040, 161), (1041, 160), (1041, 161)];

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  /// Schreibt eine Kachel-Datei im Cache, wie eine frühere Fassung der App sie angelegt hätte.
  void write(OsmLayer layer, (int, int) cell, int version) {
    final data = TileData(
      fetchedAt: env.clock,
      points: const [],
      ways: [
        SpeedWay(
          points: const [GeoPoint(52.06, 8.01), GeoPoint(52.06, 8.03)],
          forward: 50,
          backward: 50,
        ),
      ],
      detailVersion: version,
    );
    env
        .file('${layer.name}_${cell.$1}_${cell.$2}')
        .writeAsStringSync(jsonEncode(data.toJson()));
  }

  void writeCameras(int version) {
    final data = TileData(
      fetchedAt: env.clock,
      points: const [],
      ways: const [],
      detailVersion: version,
    );
    env.camFile.writeAsStringSync(jsonEncode(data.toJson()));
  }

  Map<String, dynamic> read(String name) =>
      jsonDecode(env.file(name).readAsStringSync()) as Map<String, dynamic>;

  test('die beiden Versionen sind getrennt', () {
    expect(wayDetailVersion, greaterThan(pointDetailVersion));
  });

  test(
    'alte Tempolimit-Kacheln werden erneuert, Blitzer-Kacheln nicht',
    () async {
      for (final c in _cells) {
        write(OsmLayer.limits, c, pointDetailVersion);
        write(OsmLayer.minorLimits, c, pointDetailVersion);
      }
      writeCameras(pointDetailVersion);
      final seen = <OsmLayer>[];
      final source = env.make(
        MockClient((req) async {
          seen.add(layerOf(req));
          return ok(req);
        }),
        grace: const Duration(seconds: 2),
      );
      await source.load(testArea);
      expect(
        seen,
        isNot(contains(OsmLayer.cameras)),
        reason: 'Blitzer-Kachel gilt weiter',
      );
      expect(seen, contains(OsmLayer.limits));
      expect(seen, contains(OsmLayer.minorLimits));
      // Die neu geholten Kacheln tragen die neue Version, die Blitzer-Kachel blieb unberührt.
      final fresh = env.dir
          .listSync()
          .map((e) => e.path.split(RegExp(r'[\\/]')).last)
          .where((n) => n.startsWith('limits_') || n.startsWith('minorLimits_'))
          .toList();
      expect(fresh, isNotEmpty);
      for (final n in fresh) {
        expect(
          read(n.replaceAll('.json', ''))['x'],
          wayDetailVersion,
          reason: n,
        );
      }
      expect(read('cameras_${testTile.key}')['x'], pointDetailVersion);
    },
  );

  test('Tempolimit-Kacheln der neuen Version bleiben frisch', () async {
    for (final c in _cells) {
      write(OsmLayer.limits, c, wayDetailVersion);
      write(OsmLayer.minorLimits, c, wayDetailVersion);
    }
    writeCameras(pointDetailVersion);
    final seen = <OsmLayer>[];
    final source = env.make(
      MockClient((req) async {
        seen.add(layerOf(req));
        return ok(req);
      }),
      grace: const Duration(seconds: 2),
    );
    await source.load(testArea);
    expect(seen.where((l) => l.hasWays), isEmpty);
  });

  test('bis zum Ersatz bleibt die alte Kachel in Gebrauch, auch wenn der Abruf scheitert', () async {
    write(OsmLayer.limits, (1041, 160), pointDetailVersion);
    final source = env.make(
      MockClient((req) async => http.Response('', 503)),
      grace: const Duration(milliseconds: 50),
    );
    await source.load(testArea);
    expect(await source.speedLimitAt(const GeoPoint(52.06, 8.02), 90), 50);
  });
}
