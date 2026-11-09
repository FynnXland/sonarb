import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_parser.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

import 'osm_fixtures.dart';

const _cell = TileId(268, 1050, 20); // 52,50–52,55 N / 13,40–13,45 O (Berlin)

/// Aufgezeichneter Ausschnitt der schlanken Antwort (`convert item …`), 30 Wege in Berlin-Mitte.
String sample() =>
    File('test/osm/fixtures_limits_convert_sample.json').readAsStringSync();

TileData parse(String body) =>
    parseOverpassJson(body, _cell, DateTime.utc(2026, 1, 1));

String bodyOf(List<Map<String, dynamic>> items) =>
    jsonEncode({'version': 0.6, 'elements': items});

Map<String, dynamic> item(
  int id,
  List<List<double>> lonLat,
  Map<String, String> tags, {
  String type = 'LineString',
}) => {
  'type': 'item',
  'id': id,
  'geometry': {
    'type': type,
    'coordinates': type == 'Polygon' ? [lonLat] : lonLat,
  },
  'tags': tags,
};

void main() {
  group('Abfrage', () {
    for (final layer in [OsmLayer.limits, OsmLayer.minorLimits]) {
      test(
        '${layer.name}: nur die nötigen Tags, Geometrie, keine Knoten-IDs',
        () {
          final q = buildLayerQuery(layer, _cell.bounds);
          expect(q, contains('convert item'));
          for (final tag in [
            'highway',
            'maxspeed',
            'maxspeed:forward',
            'maxspeed:backward',
            'oneway',
            'junction',
            // Name und Nummer für die Linie voraus (Fortsetzung an Kreuzungen).
            'name',
            'ref',
          ]) {
            expect(q, contains('t["$tag"]'), reason: tag);
          }
          expect(q, contains('::geom=geom()'));
          // Alles andere (Belag, Spuren …) wird gar nicht erst übertragen.
          for (final tag in ['surface', 'lanes', 'lit']) {
            expect(q, isNot(contains('t["$tag"]')), reason: tag);
          }
          expect(
            q.contains('way["highway"="living_street"]'),
            layer == OsmLayer.minorLimits,
            reason:
                'nur die Nebenstraßen-Schicht holt verkehrsberuhigte Bereiche',
          );
          expect(q, endsWith('out geom;\n'));
        },
      );
    }
  });

  group('Auswertung der schlanken Antwort', () {
    test('aufgezeichnete Antwort: Wege mit Limit, Richtung und Einbahn', () {
      final d = parse(sample());
      expect(d.ways, hasLength(30));
      final first = d.ways.first;
      expect(first.points.first, const GeoPoint(52.5189411, 13.402628));
      expect(first.forward, 50);
      expect(first.backward, 50);
      expect(first.oneway, 1, reason: 'oneway=yes');
      expect(d.points, isEmpty);
    });

    test('gleiches Ergebnis wie die ausführliche Form', () {
      final slim = parse(
        bodyOf([
          item(
            7,
            [
              [13.40, 52.50],
              [13.41, 52.51],
            ],
            {
              'highway': 'secondary',
              'maxspeed': '50',
              'maxspeed:forward': '',
              'maxspeed:backward': '30',
              'oneway': '',
              'junction': '',
            },
          ),
        ]),
      );
      final full = parse(
        overpassBody([
          way(
            7,
            [
              [52.50, 13.40],
              [52.51, 13.41],
            ],
            {
              'highway': 'secondary',
              'maxspeed': '50',
              'maxspeed:backward': '30',
            },
          ),
        ]),
      );
      expect(slim.ways.single.toJson(), full.ways.single.toJson());
      expect(slim.ways.single.backward, 30);
    });

    test('leere Tags gelten als fehlend: junction, oneway, Richtungen', () {
      final w = parse(
        bodyOf([
          item(
            1,
            [
              [13.40, 52.50],
              [13.41, 52.50],
            ],
            {
              'highway': 'primary',
              'maxspeed': '70',
              'maxspeed:forward': '',
              'maxspeed:backward': '',
              'oneway': '',
              'junction': '',
            },
          ),
        ]),
      ).ways.single;
      expect((w.forward, w.backward, w.oneway), (70, 70, 0));
    });

    test('Kreisverkehr als Fläche: äußerer Ring, einseitig', () {
      final w = parse(
        bodyOf([
          item(
            2,
            [
              [13.40, 52.50],
              [13.41, 52.50],
              [13.41, 52.51],
              [13.40, 52.50],
            ],
            {'highway': 'primary', 'maxspeed': '30', 'junction': 'roundabout'},
            type: 'Polygon',
          ),
        ]),
      ).ways.single;
      expect(w.points, hasLength(4));
      expect(w.oneway, 1);
    });

    test('verkehrsberuhigter Bereich ohne maxspeed: Schrittgeschwindigkeit, sonst die Angabe', () {
      List<int?> limits(Map<String, String> tags) {
        final w = parse(
          bodyOf([
            item(9, [
              [13.40, 52.50],
              [13.41, 52.50],
            ], tags),
          ]),
        ).ways;
        return w.isEmpty ? [] : [w.single.forward, w.single.backward];
      }

      expect(limits({'highway': 'living_street', 'maxspeed': ''}), [7, 7]);
      expect(limits({'highway': 'living_street'}), [7, 7]);
      expect(limits({'highway': 'living_street', 'maxspeed': '10'}), [10, 10]);
      expect(limits({'highway': 'living_street', 'maxspeed': 'none'}), [
        null,
        null,
      ], reason: 'eine Angabe geht vor');
      // Andere Straßen ohne maxspeed werden nicht geraten.
      expect(limits({'highway': 'residential', 'maxspeed': ''}), isEmpty);
    });

    test('kaputte Einträge fallen einzeln heraus', () {
      final d = parse(
        bodyOf([
          {
            'type': 'item',
            'id': 1,
            'tags': {'highway': 'primary', 'maxspeed': '50'},
          },
          {
            'type': 'item',
            'id': 2,
            'geometry': {'type': 'LineString', 'coordinates': 'x'},
            'tags': {'highway': 'primary', 'maxspeed': '50'},
          },
          item(
            3,
            [
              [13.40, 52.50],
            ],
            {'highway': 'primary', 'maxspeed': '50'},
          ),
          item(
            4,
            [
              [13.40, 52.50],
              [13.41, 52.50],
            ],
            {'highway': 'footway', 'maxspeed': '50'},
          ),
          item(
            5,
            [
              [13.40, 52.50],
              [13.41, 52.50],
            ],
            {'highway': 'primary', 'maxspeed': '50'},
          ),
        ]),
      );
      expect(d.ways, hasLength(1), reason: 'nur Eintrag 5 ist brauchbar');
    });
  });
}
