import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_source.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  /// Wartet, bis die Quelle nichts mehr lädt (auch das Nachladen im Hintergrund).
  Future<void> settle() => env.whenIdle();

  const here = GeoPoint(52.07, 8.03); // Zelle 8,00–8,05 / 52,05–52,10

  test('fehlende Zelle unter der Position wird beim Abfragen geholt', () async {
    final seen = <String>[];
    final source = env.make(
      MockClient((req) async {
        seen.add('${layerOf(req).name} ${westOf(req)}');
        return ok(req);
      }),
    );
    expect(await source.speedLimitAt(here, null), isNull);
    await settle();
    expect(seen, unorderedEquals(['limits 7.99998', 'minorLimits 7.99998']));
    // Wege kommen an: jetzt gibt es ein Limit (der Weg der Fixture liegt bei 52,05 N).
    expect(await source.speedLimitAt(const GeoPoint(52.05002, 8.045), 90), 50);
  });

  test('mit Kurs auch die Zelle voraus, ohne Kurs nur die eigene', () async {
    final west = <String>{};
    final source = env.make(
      MockClient((req) async {
        if (layerOf(req) == OsmLayer.limits) west.add(westOf(req));
        return ok(req);
      }),
    );
    await source.speedLimitAt(here, null);
    await settle();
    expect(west, {'7.99998'});

    // 3,5 km nach Osten (Kurs 90): 8,03 + 0,051° = 8,081 → Zelle 8,05–8,10.
    await source.speedLimitAt(here, 90);
    await settle();
    expect(west, {'7.99998', '8.04998'});
  });

  test('Zellen voraus kommen vor dem Rest der Umgebung', () async {
    final hang = Completer<void>();
    final order = <String>[];
    final source = env.make(
      MockClient((req) async {
        final tag = '${layerOf(req).name} ${westOf(req)}';
        order.add(tag);
        if (order.length == 2) await hang.future; // erste Wegabfrage hängt
        return ok(req);
      }),
      parallel: 1,
      grace: const Duration(milliseconds: 20),
    );
    // Umgebung: zwei Zellen (8,00 und 8,05), Mitte in der linken.
    await source.load(
      const GeoBounds(south: 52.06, west: 8.03, north: 52.08, east: 8.055),
    );
    // Weit weg, Kurs Nord: die Zelle 55 km voraus ist nicht nötig, aber 3,5 km voraus schon.
    unawaited(source.speedLimitAt(const GeoPoint(53.0, 9.02), 0));
    await source.whenIdle(fetches: false); // Zellen voraus sind eingeplant
    hang.complete();
    await settle();

    final limitCells = [
      for (final o in order)
        if (o.startsWith('limits ')) o.split(' ')[1],
    ];
    final farFirst = limitCells.contains("9.00002")
        ? limitCells.indexOf('9.00002')
        : limitCells.indexWhere((w) => double.parse(w) > 8.5);
    final restOfArea = limitCells.indexOf('8.04998');
    expect(farFirst, greaterThanOrEqualTo(0));
    expect(restOfArea, greaterThanOrEqualTo(0));
    expect(
      farFirst,
      lessThan(restOfArea),
      reason:
          'die Zelle auf dem Weg vor der entfernten Nachbarzelle der Umgebung',
    );
  });

  test('frische Zellen kosten nichts, im Funkloch kein Dauerfeuer', () async {
    var calls = 0;
    var offline = false;
    final source = env.make(
      MockClient((req) async {
        calls++;
        if (offline) throw const SocketException('Network is unreachable');
        return ok(req);
      }),
    );
    await source.speedLimitAt(here, null);
    await settle();
    final first = calls;
    for (var i = 0; i < 20; i++) {
      await source.speedLimitAt(here, null);
    }
    await settle();
    expect(calls, first, reason: 'schon geladen');

    // Neue Gegend ohne Netz: jede Abfrage wäre ein Versuch, die Pause fängt das ab.
    offline = true;
    const elsewhere = GeoPoint(50.5, 9.5);
    calls = 0;
    for (var i = 0; i < 30; i++) {
      await source.speedLimitAt(elsewhere, null);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await settle();
    expect(
      calls,
      lessThanOrEqualTo(4),
      reason: '2 Schichten × 2 Endpunkte, einmal',
    );
  });

  test(
    'Zelle unter der Position: Abstand 0, auch wenn Cache-Datei schon da ist',
    () async {
      var calls = 0;
      final first = env.make(
        MockClient((req) async {
          calls++;
          return ok(req);
        }),
      );
      await first.speedLimitAt(here, null);
      await settle();
      final loaded = calls;
      // Neustart: die Zellen liegen auf der Platte, es braucht kein Netz.
      final restarted = env.make(
        MockClient((req) async {
          calls++;
          return ok(req);
        }),
      );
      await restarted.speedLimitAt(const GeoPoint(52.05002, 8.045), null);
      await settle();
      expect(calls, loaded);
      expect(
        TileId.of(here.lat, here.lon, OsmLayer.limits.perDegree),
        const TileId(160, 1041, 20),
      );
    },
  );

  test('viele Kamerakacheln verdrängen die Wege im Speicher nicht', () async {
    var layersCalled = <String>[];
    final source = OsmSource(
      cacheDir: env.dir,
      client: MockClient((req) async {
        layersCalled.add(layerOf(req).name);
        return ok(req);
      }),
      now: () => env.clock,
      maxMemoryTiles: 8,
      detailGrace: const Duration(milliseconds: 20),
    );
    await source.load(
      testArea,
    ); // 10 Kacheln, davon 8 Wegzellen: mehr als passen
    await settle();
    const p = GeoPoint(52.05002, 8.045);
    expect(await source.speedLimitAt(p, 90), 50);

    // 50 Blitzer-Kacheln wandern beim Auslesen durch den Speicher (große Umkreise, Cache-Dateien da).
    for (var iy = 600; iy < 610; iy++) {
      for (var ix = 100; ix < 105; ix++) {
        env
            .file('cameras_${iy}_$ix')
            .writeAsStringSync(
              '{"v":1,"x":3,"t":${env.clock.millisecondsSinceEpoch},"p":[],"w":[]}',
            );
      }
    }
    for (final south in [60.0, 60.5]) {
      await source.loadCameras(
        GeoBounds(south: south, west: 10.0, north: south + 0.49, east: 10.49),
      );
    }
    layersCalled = [];
    // Die Haltezeit (15 s) ist um: ein Wert kann nur noch aus dem Speicher kommen, und zwar sofort.
    env.clock = env.clock.add(const Duration(seconds: 20));
    expect(await source.speedLimitAt(p, 90), 50);
    await settle();
    expect(
      layersCalled.where((l) => l.endsWith('imits')),
      isEmpty,
      reason: 'die Zelle war im Speicher geblieben, kein erneuter Abruf',
    );
  });
}
