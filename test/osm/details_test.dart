import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/osm/osm_details.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_parser.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

final _t = DateTime.utc(2026, 1, 1);

TileData parse(List<Map<String, dynamic>> elements) =>
    parseOverpassJson(overpassBody(elements), testTile, _t);

Map<String, dynamic> stamped(Map<String, dynamic> e, String ts) => {
  ...e,
  'timestamp': ts,
};

Map<String, String?> asMap(AlertPoint p) => {
  for (final d in p.details) d.label: d.value,
};

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  group('Übersetzung', () {
    test('alle Angaben eines Blitzerknotens in kurzem Deutsch', () {
      final d = parse([
        stamped(
          node(1, 52.05, 8.05, {
            'highway': 'speed_camera',
            'maxspeed': '50',
            'enforcement': 'maxspeed',
            'camera:type': 'fixed',
            'camera:mount': 'pole',
            'surveillance:type': 'camera',
            'start_date': '2021-03',
            'check_date': '2024-05-17',
            'operator': 'Stadt  Musterstadt',
            'name': 'Messstelle A',
            'ref': 'M1',
            'note': 'Wird im Frühjahr erneuert',
            'description': 'Frontblitzer',
            'direction': '45',
          }),
          '2024-06-02T10:11:12Z',
        ),
        way(
          11,
          [
            [52.05, 8.04],
            [52.05, 8.06],
          ],
          {'highway': 'primary', 'name': 'Frankfurter Allee', 'ref': 'B 1'},
          nodes: [5, 1],
        ),
      ]);
      final p = d.points.single;
      expect(p.details.map((e) => e.toString()).toList(), [
        'Kontrolle: Geschwindigkeit',
        'Erlaubt: 50 km/h',
        'Seit: März 2021',
        'Richtung: in Richtung Nordost',
        'Straße: Frankfurter Allee (B 1)',
        'Bauart: fest installiert',
        'Montage: Mast',
        'Technik: Kamera',
        'Zuletzt geprüft: 17. Mai 2024',
        'Betreiber: Stadt Musterstadt',
        'Name: Messstelle A',
        'Kennung: M1',
        'Hinweis: Wird im Frühjahr erneuert',
        'Beschreibung: Frontblitzer',
      ]);
      final s = p.sources.single;
      expect(s.id, 'osm');
      expect(s.name, 'OpenStreetMap');
      expect(s.attribution, '© OpenStreetMap-Mitwirkende, ODbL');
      expect(s.url, 'https://www.openstreetmap.org/node/1');
      expect(s.updatedAt, DateTime.utc(2024, 6, 2, 10, 11, 12));
      expect(d.detailVersion, pointDetailVersion);
    });

    test('leere und unverständliche Werte erscheinen nicht', () {
      final p = parse([
        node(1, 52.05, 8.05, {
          'highway': 'speed_camera',
          'camera:type': 'ufo',
          'camera:mount': 'x',
          'start_date': '~2015',
          'check_date': '',
          'operator': '   ',
          'note': '',
          'maxspeed': 'signals',
          'enforcement': 'was_anderes',
        }),
      ]).points.single;
      expect(p.details.map((e) => e.label), ['Richtung']);
      expect(p.sources.single.updatedAt, isNull);
    });

    test('Richtung in Worten', () {
      Map<String, String?> dir(Map<String, String> tags) => asMap(
        parse([
          node(1, 52.05, 8.05, {'highway': 'speed_camera', ...tags}),
        ]).points.single,
      );
      expect(dir({})['Richtung'], 'unbekannt, warnt in beide Richtungen');
      expect(dir({'direction': 'both'})['Richtung'], 'beide Richtungen');
      expect(
        dir({'direction': '90;270'})['Richtung'],
        'in Richtung Ost und West',
      );
      expect(dir({'direction': 'S'})['Richtung'], 'in Richtung Süd');
    });

    test('Relation: Angaben von Relation und Geräteknoten, neuester Stand', () {
      final p = parse([
        stamped(
          node(1, 52.05, 8.05, {
            'highway': 'speed_camera',
            'operator': 'Landkreis',
            'maxspeed': '30',
            'camera:type': 'fixed',
          }),
          '2023-01-01T00:00:00Z',
        ),
        way(
          11,
          [
            [52.05, 8.04],
            [52.05, 8.06],
          ],
          {'highway': 'residential', 'name': 'Dorfstraße'},
          nodes: [5, 1],
        ),
        stamped(
          relation(
            9,
            {
              'type': 'enforcement',
              'enforcement': 'maxspeed',
              'maxspeed': '50',
              'start_date': '2019',
            },
            [
              member('node', 1, 'device', lat: 52.05, lon: 8.05),
              member('node', 3, 'from', lat: 52.0498, lon: 8.0498),
            ],
          ),
          '2025-02-03T04:05:06Z',
        ),
      ]).points.single;
      expect(p.id, 'osm:relation/9');
      expect(asMap(p), {
        'Kontrolle': 'Geschwindigkeit',
        'Erlaubt': '50 km/h',
        'Seit': '2019',
        'Richtung': 'in Richtung Nordost',
        'Straße': 'Dorfstraße',
        'Bauart': 'fest installiert',
        'Betreiber': 'Landkreis',
      });
      expect(p.sources.single.url, 'https://www.openstreetmap.org/relation/9');
      expect(p.sources.single.updatedAt, DateTime.utc(2025, 2, 3, 4, 5, 6));
    });

    test('Datum, Himmelsrichtung', () {
      expect(formatOsmDate('2021'), '2021');
      expect(formatOsmDate('2021-03'), 'März 2021');
      expect(formatOsmDate('2021-12-05'), '5. Dezember 2021');
      for (final bad in [
        '2021-13',
        '2021-02-40',
        '~2015',
        '',
        'gestern',
        null,
      ]) {
        expect(formatOsmDate(bad), isNull, reason: '$bad');
      }
      expect(compassName(0), 'Nord');
      expect(compassName(22), 'Nord');
      expect(compassName(23), 'Nordost');
      expect(compassName(359), 'Nord');
      expect(compassName(-90), 'West');
      expect(compassName(225), 'Südwest');
    });
  });

  group('Cache', () {
    test('Details und Quellen überstehen den Cache', () {
      final d = parse([
        stamped(
          node(1, 52.05, 8.05, {
            'highway': 'speed_camera',
            'maxspeed': '50',
            'start_date': '2020',
          }),
          '2024-06-02T10:11:12Z',
        ),
      ]);
      final back = TileData.fromJson(
        jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>,
      );
      final p = back.points.single;
      expect(p.details, d.points.single.details);
      expect(p.sources.single.url, 'https://www.openstreetmap.org/node/1');
      expect(p.sources.single.updatedAt, DateTime.utc(2024, 6, 2, 10, 11, 12));
      expect(p.sources.single.attribution, osmAttribution);
      expect(back.detailVersion, pointDetailVersion);
    });

    test('alte Datei ohne Details lädt weiter', () {
      final back = TileData.fromJson({
        'v': 1,
        't': _t.millisecondsSinceEpoch,
        'p': [
          {'i': 'osm:node/1', 'k': 'speedCamera', 'la': 52.05, 'lo': 8.05},
        ],
        'w': <dynamic>[],
      });
      expect(back.points.single.details, isEmpty);
      expect(back.points.single.sources, isEmpty);
      expect(back.detailVersion, 0);
    });

    File camFile() => env.file('cameras_${testTile.key}');

    void writeLegacy() => camFile()
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'v': 1,
          't': env.clock.millisecondsSinceEpoch,
          'p': [
            {'i': 'osm:node/77', 'k': 'speedCamera', 'la': 52.05, 'lo': 8.05},
          ],
          'w': <dynamic>[],
        }),
      );

    test('alte Kachel ohne Details wird erneuert', () async {
      writeLegacy();
      var cameraCalls = 0;
      final source = env.make(
        MockClient((req) async {
          if (layerOf(req) == OsmLayer.cameras) cameraCalls++;
          return http.Response(layerBody(layerOf(req)), 200);
        }),
      );
      final r = await source.load(testArea);
      expect(cameraCalls, 1);
      final cam = r.points.firstWhere((p) => p.id == 'osm:node/1');
      expect(cam.details, isNotEmpty);
      expect(jsonDecode(camFile().readAsStringSync())['x'], pointDetailVersion);
    });

    test('alte Kachel ohne Details dient offline weiter', () async {
      writeLegacy();
      final source = env.make(
        MockClient((_) async => throw const SocketException('offline')),
      );
      final r = await source.load(testArea);
      expect(r.points.map((p) => p.id), contains('osm:node/77'));
      expect(r.error, 'Overpass nicht erreichbar, Daten aus dem Cache');
    });

    test('Kachel mit Details wird nicht erneuert', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(layerBody(layerOf(req)), 200);
      });
      await env.make(client).load(testArea);
      final first = calls;
      await env.make(client).load(testArea);
      expect(calls, first);
    });
  });
}
