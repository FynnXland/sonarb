import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_country.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_parser.dart';
import 'package:sonarb/features/osm/osm_source.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

/// Aufgezeichneter Ausschnitt der echten Länderabfrage (21 Messstellen in Berlin, Hamburg, München
/// und Frankfurt/Oder, mit Relationen und Wegen), Stand 30.10.2026.
String sample() =>
    File('test/osm/fixtures_country_sample.json').readAsStringSync();

TileId tileAt(double lat, double lon) => TileId.of(lat, lon);

/// Wenige Kacheln für Tests, die nicht das ganze Land brauchen: Berlin, Hamburg, Hessen, Grenze.
final _few = [
  tileAt(52.52, 13.45),
  tileAt(53.55, 10.00),
  tileAt(51.02, 9.02),
  tileAt(52.34, 14.55),
  tileAt(49.40, 11.00),
];

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  group('Umriss', () {
    final tiles = germanyTiles().toSet();

    test('Kachelzahl in der Größenordnung des Landes', () {
      // 357 000 km² bei rund 75 km² je Kachel.
      expect(tiles.length, inInclusiveRange(4200, 5600));
    });

    test('Städte drin, Nachbarländer draußen', () {
      for (final (lat, lon) in [
        (52.52, 13.40), // Berlin
        (53.55, 10.00), // Hamburg
        (48.14, 11.58), // München
        (50.94, 6.96), // Köln
        (49.00, 12.10), // Regensburg
        (54.32, 10.14), // Kiel
        (47.70, 10.30), // Allgäu
      ]) {
        expect(tiles, contains(tileAt(lat, lon)), reason: '$lat/$lon');
      }
      for (final (lat, lon) in [
        (48.86, 2.35), // Paris
        (52.23, 21.01), // Warschau
        (47.37, 8.54), // Zürich
        (48.21, 16.37), // Wien
        (50.08, 14.43), // Prag
        (52.37, 4.90), // Amsterdam
        (55.68, 12.57), // Kopenhagen
      ]) {
        expect(tiles, isNot(contains(tileAt(lat, lon))), reason: '$lat/$lon');
      }
    });

    test('Randkacheln sind unvollständig, das Innere nicht', () {
      expect(isInteriorTile(tileAt(50.98, 9.50)), isTrue); // nördlich Kassel
      expect(isInteriorTile(tileAt(49.40, 11.00)), isTrue); // Nürnberg
      expect(isInteriorTile(tileAt(52.34, 14.55)), isFalse); // Frankfurt (Oder)
      expect(
        isInteriorTile(tileAt(47.80, 7.60)),
        isFalse,
      ); // Basel, Dreiländereck
      expect(isInteriorTile(tileAt(54.10, 7.90)), isFalse); // Nordsee
    });
  });

  test(
    'Abfrage: Fläche Deutschland, alle Kontrollarten, kein Tempolimit-Weg',
    () {
      final q = buildCountryQuery();
      expect(q, startsWith('[out:json][timeout:240]'));
      for (final part in [
        'area["ISO3166-1"="DE"][admin_level=2]',
        'node["highway"="speed_camera"](area.de)',
        'rel(bn.cams)',
        'maxheight|maxweight',
        '(area.de)->.enfOther',
        '.cams out meta;',
        '.camways out geom;',
      ]) {
        expect(q, contains(part));
      }
      expect(q, isNot(contains('maxspeed"]')));
    },
  );

  group('loadCountryCameras', () {
    late List<String> queries;

    /// Mit [full] schreibt der Lauf alle Kacheln des Landes (langsam), sonst eine Handvoll.
    OsmSource make(
      Future<http.Response> Function(http.Request) handler, {
      int parallel = 2,
      bool full = false,
    }) {
      queries = [];
      return OsmSource(
        cacheDir: env.dir,
        client: MockClient((req) async {
          queries.add(req.bodyFields['data']!);
          return handler(req);
        }),
        now: () => env.clock,
        maxParallelRequests: parallel,
        detailGrace: const Duration(milliseconds: 50),
        countryTiles: full ? null : () => _few,
      );
    }

    test(
      'eine Anfrage, alle Kacheln des Landes im Cache, Punkte an ihrer Stelle',
      () async {
        final source = make(
          (_) async => http.Response(sample(), 200),
          full: true,
        );
        final r = await source.loadCountryCameras();

        expect(queries, hasLength(1));
        expect(r.ok, isTrue);
        final all = parseAll(
          jsonDecode(sample()) as Map<String, dynamic>,
          withWays: false,
        );
        expect(r.points, all.points.length);
        expect(r.points, greaterThan(15));
        expect(r.tiles, greaterThanOrEqualTo(germanyTiles().length));
        expect(r.fetchedAt, env.clock);

        // Kacheln im Cache: mit Punkten und leere.
        final berlin = source.loadedCameraTilesIn(
          const GeoBounds(south: 52.50, west: 13.40, north: 52.60, east: 13.50),
        );
        expect(berlin, isNotEmpty);
        final empty = source.loadedCameraTilesIn(
          const GeoBounds(south: 51.00, west: 9.00, north: 51.05, east: 9.05),
        );
        expect(
          empty,
          isNotEmpty,
          reason: 'leere Kachel in Hessen ist „geladen“',
        );
        final abroad = source.loadedCameraTilesIn(
          const GeoBounds(south: 48.80, west: 2.30, north: 48.90, east: 2.40),
        );
        expect(abroad, isEmpty);
      },
      // Schreibt jede Kachel Deutschlands einzeln mit flush auf die Platte: allein gut 20 s,
      // im parallelen Volllauf mehr als die üblichen 30 s.
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('danach braucht eine Karte oder Fahrt im Inneren kein Netz', () async {
      final source = make((_) async => http.Response(sample(), 200));
      await source.loadCountryCameras();
      queries.clear();

      // Hamburg: Innenkachel 53,5–53,6 / 10,0–10,1, Messstellen aus dem Cache, kein Netz.
      const area = GeoBounds(
        south: 53.50,
        west: 10.00,
        north: 53.59,
        east: 10.09,
      );
      final r = await source.loadCameras(area);
      final expected = parseAll(
        jsonDecode(sample()) as Map<String, dynamic>,
        withWays: false,
      ).points.where((p) => area.contains(p.position)).length;
      expect(queries, isEmpty);
      expect(r.error, isNull);
      expect(r.fromCache, isTrue);
      expect(r.points, hasLength(expected));
    });

    test(
      'Randkacheln gelten als veraltet und werden beim Besuch ergänzt',
      () async {
        final source = make((req) async {
          return queries.length == 1
              ? http.Response(sample(), 200)
              : http.Response(overpassBody([]), 200);
        });
        await source.loadCountryCameras();
        queries.clear();

        // Frankfurt (Oder), Grenzkachel 52,3–52,4 / 14,5–14,6.
        final file = env.file('cameras_523_145');
        expect(jsonDecode(file.readAsStringSync())['pt'], 1);
        await source.loadCameras(
          const GeoBounds(south: 52.30, west: 14.50, north: 52.31, east: 14.51),
        );
        expect(queries, hasLength(1), reason: 'Randkachel wird nachgeladen');
        expect(
          jsonDecode(file.readAsStringSync())['pt'],
          isNull,
          reason: 'jetzt vollständig und frisch',
        );
      },
    );

    test(
      'eine frische vollständige Randkachel wird nicht überschrieben',
      () async {
        final source = make((req) async => ok(req));
        // Normaler Besuch lädt die Kachel vollständig (52,0–52,1 / 8,0–8,1 liegt in Deutschland).
        await source.load(testArea);
        final before = env.camFile.readAsStringSync();
        expect(jsonDecode(before)['pt'], isNull);

        queries.clear();
        final other = make((_) async => http.Response(sample(), 200));
        await other.loadCountryCameras();
        expect(
          jsonDecode(env.camFile.readAsStringSync())['t'],
          jsonDecode(before)['t'],
        );
      },
    );

    test('Überlast und Müllantwort: Fehlertext, nichts im Cache', () async {
      final busy = make((_) async => http.Response('', 502));
      final r = await busy.loadCountryCameras();
      expect(r.ok, isFalse);
      expect(r.error, 'Overpass überlastet');
      expect(
        env.dir.listSync().whereType<File>().where(
          (f) => f.path.contains('cameras_'),
        ),
        isEmpty,
      );

      final junk = make((_) async => http.Response('<html>', 200));
      expect((await junk.loadCountryCameras()).error, 'Antwort unbrauchbar');
      final cut = make((_) async {
        final s = sample();
        return http.Response(s.substring(0, s.length ~/ 2), 200);
      });
      expect((await cut.loadCountryCameras()).error, 'Verbindung abgebrochen');
    });

    test('Cache geleert während des Laufs: nichts wird geschrieben', () async {
      final gate = Completer<void>();
      final asked = Completer<void>();
      final source = make((_) async {
        asked.complete();
        await gate.future;
        return http.Response(sample(), 200);
      });
      final run = source.loadCountryCameras();
      await asked.future; // die Anfrage läuft
      await source.clearCache();
      gate.complete();
      final r = await run;
      expect(r.ok, isFalse);
      expect(await source.cacheSizeBytes(), 0);
    });

    test('steht hinter der Fahrt in der Warteschlange', () async {
      final holdLimits = Completer<void>();
      final order = <String>[];
      final source = make((req) async {
        final q = req.bodyFields['data']!;
        if (q.contains('ISO3166-1')) {
          order.add('land');
          return http.Response(sample(), 200);
        }
        order.add(layerOf(req).name);
        if (layerOf(req).hasWays) await holdLimits.future;
        return ok(req);
      });
      // Tempolimit-Abfrage der Fahrt hängt und hält den Einzelplatz.
      await source.load(testArea);
      final country = source.loadCountryCameras();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        order,
        isNot(contains('land')),
        reason: 'wartet auf den Einzelplatz',
      );

      // Die Blitzer der Fahrt an anderer Stelle kommen sofort durch.
      final r = await source.load(
        const GeoBounds(south: 54.0, west: 10.0, north: 54.02, east: 10.02),
      );
      expect(r.error, isNull);
      holdLimits.complete();
      expect((await country).ok, isTrue);
      expect(order.last, anyOf('land', 'limits', 'minorLimits'));
    });
  });

  test(
    'Teil-Kacheln: partial überlebt den Cache und gilt als nicht frisch',
    () {
      final t = TileData(
        fetchedAt: DateTime.utc(2026, 1, 1),
        points: const [],
        ways: const [],
        partial: true,
      );
      final back = TileData.fromJson(
        jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>,
      );
      expect(back.partial, isTrue);
      expect(
        TileData.fromJson({'v': 1, 't': 0, 'p': [], 'w': []}).partial,
        isFalse,
      );
    },
  );

  test(
    'Obergrenzen je Schicht: ein großer Umkreis fordert nicht alles an',
    () async {
      final seen = <OsmLayer, int>{};
      final source = env.make(
        MockClient((req) async {
          seen.update(layerOf(req), (n) => n + 1, ifAbsent: () => 1);
          return http.Response(overpassBody([]), 200);
        }),
        grace: const Duration(milliseconds: 50),
      );
      // 50 km Umkreis bei Berlin: 10 × 16 Ampel-Kacheln, 19 × 30 Wegzellen.
      await source.load(GeoBounds.around(const GeoPoint(52.52, 13.40), 50000));
      await source.whenIdle();
      expect(seen[OsmLayer.cameras], 1, reason: 'eine Hüllenabfrage');
      expect(seen[OsmLayer.signals], lessThanOrEqualTo(16));
      expect(seen[OsmLayer.limits], lessThanOrEqualTo(20));
      expect(seen[OsmLayer.minorLimits], lessThanOrEqualTo(20));
    },
  );
}
