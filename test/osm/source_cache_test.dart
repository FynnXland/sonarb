import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_layer.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  group('Cache', () {
    test('zweiter Aufruf kommt aus dem Cache, auch nach Neustart', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return ok(req);
      });
      await env.make(client).load(testArea);
      final first = calls;
      expect(env.camFile.existsSync(), isTrue);
      expect(env.file('signals_${testTile.key}').existsSync(), isTrue);
      expect(
        env.dir
            .listSync(recursive: true)
            .whereType<File>()
            .any((f) => f.path.endsWith('.tmp')),
        isFalse,
      );

      env.clock = env.clock.add(const Duration(days: 3));
      final r = await env
          .make(client)
          .load(testArea); // frische Instanz: liest von der Platte
      expect(calls, first);
      expect(r.fromCache, isTrue);
      expect(r.error, isNull);
      expect(r.fetchedAt, DateTime.utc(2026, 5, 1));
      expect(r.points.firstWhere((p) => p.id == 'osm:node/1').travelBearings, [
        90,
      ]);
    });

    test('veraltet (> 7 Tage) und Netz weg: alte Daten plus Fehler', () async {
      await env.make(MockClient((req) async => ok(req))).load(testArea);
      env.clock = env.clock.add(const Duration(days: 8));
      final offline = env.make(
        MockClient((_) async => throw const SocketException('offline')),
      );
      final r = await offline.load(testArea);
      expect(r.points.map((p) => p.id).toSet(), {'osm:node/1', 'osm:node/2'});
      expect(r.fromCache, isTrue);
      expect(r.fetchedAt, DateTime.utc(2026, 5, 1));
      expect(r.error, 'Overpass nicht erreichbar, Daten aus dem Cache');
    });

    test('veraltet und Netz da: wird neu geladen und überschrieben', () async {
      await env.make(MockClient((req) async => ok(req))).load(testArea);
      env.clock = env.clock.add(const Duration(days: 8));
      final source = env.make(
        MockClient(
          (req) async => layerOf(req) == OsmLayer.cameras
              ? http.Response(
                  overpassBody([
                    node(9, 52.06, 8.06, {'highway': 'speed_camera'}),
                  ]),
                  200,
                )
              : ok(req),
        ),
      );
      final r = await source.load(testArea);
      expect(r.points.map((p) => p.id), contains('osm:node/9'));
      expect(r.points.map((p) => p.id), isNot(contains('osm:node/1')));
      expect(r.fetchedAt, env.clock);
      expect(
        jsonDecode(env.camFile.readAsStringSync())['t'],
        env.clock.millisecondsSinceEpoch,
      );
    });

    test('kaputte Cache-Datei gilt als fehlend', () async {
      env.camFile
        ..createSync(recursive: true)
        ..writeAsStringSync('{"v":1,"t":');
      final r = await env
          .make(MockClient((req) async => ok(req)))
          .load(testArea);
      expect(r.points.map((p) => p.id), contains('osm:node/1'));
      expect(r.error, isNull);
      expect(jsonDecode(env.camFile.readAsStringSync())['v'], 1);
    });

    test('kaputte Datei und kein Netz: leer mit Fehler, kein Wurf', () async {
      env.camFile
        ..createSync(recursive: true)
        ..writeAsStringSync('kein json');
      final source = env.make(MockClient((_) async => http.Response('', 500)));
      final r = await source.load(testArea);
      expect(r.points, isEmpty);
      expect(r.error, isNotNull);
    });

    test('Cache liegt flach in cacheDir; Altlasten werden entfernt', () async {
      final nested = Directory('${env.dir.path}${Platform.pathSeparator}osm')
        ..createSync();
      File('${nested.path}${Platform.pathSeparator}t_520_80.json')
          .writeAsStringSync('{}');
      File('${env.dir.path}${Platform.pathSeparator}t_520_80.json')
          .writeAsStringSync('{}');
      await env.make(MockClient((req) async => ok(req))).load(testArea);
      expect(nested.existsSync(), isFalse);
      expect(env.file('t_520_80').existsSync(), isFalse);
      expect(env.camFile.existsSync(), isTrue);
    });

    test('cacheSizeBytes und clearCache rühren Fremdes nicht an', () async {
      final foreign = File('${env.dir.path}${Platform.pathSeparator}notiz.txt')
        ..writeAsStringSync('bleibt');
      final source = env.make(MockClient((req) async => ok(req)));
      expect(await source.cacheSizeBytes(), 0);
      await source.load(testArea);
      final size = await source.cacheSizeBytes();
      expect(size, greaterThan(0));
      expect(
        size,
        env.dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path != foreign.path)
            .fold<int>(0, (a, f) => a + f.lengthSync()),
      );

      await source.clearCache();
      expect(await source.cacheSizeBytes(), 0);
      expect(env.camFile.existsSync(), isFalse);
      expect(foreign.existsSync(), isTrue);
      expect(
        await source.speedLimitAt(const GeoPoint(52.05, 8.05), 90),
        isNull,
      );
      expect((await source.load(testArea)).fromCache, isFalse);
    });

    test('nicht schreibbarer Cache kippt die Abfrage nicht', () async {
      final blocked = File('${env.dir.path}${Platform.pathSeparator}blockiert')
        ..writeAsStringSync('x');
      final source = env.make(
        MockClient((req) async => ok(req)),
        cacheDir: Directory(blocked.path), // Datei statt Ordner
      );
      final r = await source.load(testArea);
      expect(r.points, hasLength(2));
      expect(r.error, isNull);
    });
  });
}
