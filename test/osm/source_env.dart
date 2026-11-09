import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sonarb/features/osm/osm_source.dart';

import 'osm_fixtures.dart';

http.Response ok(http.Request req) =>
    http.Response(layerBody(layerOf(req)), 200);

/// Gemeinsamer Aufbau der Quelle-Tests: Temp-Ordner, steuerbare Uhr, Schlaf ohne Wartezeit.
class SourceEnv {
  late Directory dir;
  DateTime clock = DateTime.utc(2026, 5, 1);
  List<Duration> sleeps = [];

  /// Zuletzt gebaute Quelle; [whenIdle] wartet, bis sie nichts mehr lädt.
  OsmSource? last;

  Future<void> whenIdle() => last?.whenIdle() ?? Future<void>.value();

  void setUp() {
    dir = Directory.systemTemp.createTempSync('osm_test');
    clock = DateTime.utc(2026, 5, 1);
    sleeps = [];
  }

  void tearDown() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  OsmSource make(
    http.Client client, {
    int parallel = 2,
    Duration grace = const Duration(seconds: 5),
    Duration deadline = const Duration(seconds: 150),
    Directory? cacheDir,
  }) => last = OsmSource(
    cacheDir: cacheDir ?? dir,
    client: client,
    now: () => clock,
    sleep: (d) async {
      sleeps.add(d);
      clock = clock.add(d);
    },
    maxParallelRequests: parallel,
    detailGrace: grace,
    cameraDeadline: deadline,
  );

  File file(String name) =>
      File('${dir.path}${Platform.pathSeparator}$name.json');

  File get camFile => file('cameras_${testTile.key}');
}
