import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/osm/osm_parser.dart';
import 'package:sonarb/features/osm/osm_speed.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

import 'osm_fixtures.dart';

final _t = DateTime.utc(2026, 1, 1);

TileData parse(List<Map<String, dynamic>> elements) =>
    parseOverpassJson(overpassBody(elements), testTile, _t);

AlertPoint byId(TileData d, String id) =>
    d.points.firstWhere((p) => p.id == id);

void main() {
  test('rohes Overpass-JSON als String', () {
    const body = '''
{"version":0.6,"elements":[
 {"type":"node","id":42,"lat":52.05,"lon":8.05,"tags":{"highway":"speed_camera","direction":"NE","maxspeed":"70","name":"B64"}},
 {"type":"node","id":43,"lat":52.06,"lon":8.06,"tags":{"highway":"traffic_signals"}},
 {"type":"way","id":7,"nodes":[1,2],"tags":{"highway":"secondary","maxspeed":"30 mph","oneway":"yes"},
  "geometry":[{"lat":52.05,"lon":8.04},{"lat":52.05,"lon":8.06}]}
]}''';
    final d = parseOverpassJson(body, testTile, _t);
    final cam = byId(d, 'osm:node/42');
    expect(cam.kind, AlertKind.speedCamera);
    expect(cam.travelBearings, [45]);
    expect(cam.maxSpeed, 70);
    expect(cam.label, 'B64');
    expect(cam.source, 'osm');
    expect(byId(d, 'osm:node/43').kind, AlertKind.trafficSignal);
    expect(d.ways.single.forward, 48);
    expect(d.ways.single.oneway, 1);
  });

  test('Punkte außerhalb der Kachel werden verworfen', () {
    final d = parse([
      node(1, 52.05, 8.05, {'highway': 'speed_camera'}),
      node(2, 52.15, 8.05, {'highway': 'speed_camera'}),
      node(3, 52.05, 8.15, {'highway': 'traffic_signals'}),
    ]);
    expect(d.points.map((p) => p.id), ['osm:node/1']);
  });

  group('Blitzerknoten', () {
    test('direction=forward/backward über die Weggeometrie', () {
      // Weg 100 läuft nach Norden, Weg 200 nach Westen.
      final d = parse([
        node(11, 52.05, 8.05, {
          'highway': 'speed_camera',
          'direction': 'forward',
        }),
        node(12, 52.04, 8.05, {
          'highway': 'speed_camera',
          'direction': 'backward',
        }),
        node(13, 52.03, 8.05, {
          'highway': 'speed_camera',
          'direction': 'forward',
        }),
        way(
          100,
          [
            [52.04, 8.05],
            [52.05, 8.05],
            [52.06, 8.05],
          ],
          {'highway': 'primary'},
          nodes: [12, 11, 99],
        ),
        way(
          200,
          [
            [52.03, 8.06],
            [52.03, 8.05],
            [52.03, 8.04],
          ],
          {'highway': 'primary'},
          nodes: [98, 13, 97],
        ),
      ]);
      expect(byId(d, 'osm:node/11').travelBearings.single, closeTo(0, 0.1));
      expect(byId(d, 'osm:node/12').travelBearings.single, closeTo(180, 0.1));
      expect(byId(d, 'osm:node/13').travelBearings.single, closeTo(270, 0.5));
    });

    test('forward ohne Weg ist leer', () {
      final d = parse([
        node(11, 52.05, 8.05, {
          'highway': 'speed_camera',
          'direction': 'forward',
        }),
      ]);
      expect(d.points.single.travelBearings, isEmpty);
    });

    test('Knoten am Wegende nutzt das letzte Segment', () {
      final d = parse([
        node(11, 52.06, 8.05, {
          'highway': 'speed_camera',
          'direction': 'forward',
        }),
        way(
          100,
          [
            [52.05, 8.05],
            [52.06, 8.05],
          ],
          {'highway': 'primary'},
          nodes: [5, 11],
        ),
      ]);
      expect(d.points.single.travelBearings.single, closeTo(0, 0.1));
    });

    test(
      'Grad, Himmelsrichtung, Liste, both, camera:direction, ohne Angabe',
      () {
        final d = parse([
          node(1, 52.05, 8.05, {'highway': 'speed_camera', 'direction': '135'}),
          node(2, 52.05, 8.051, {
            'highway': 'speed_camera',
            'direction': 'SSW',
          }),
          node(3, 52.05, 8.052, {
            'highway': 'speed_camera',
            'direction': '90;270',
          }),
          node(4, 52.05, 8.053, {
            'highway': 'speed_camera',
            'direction': 'both',
          }),
          node(5, 52.05, 8.054, {
            'highway': 'speed_camera',
            'camera:direction': '10',
          }),
          node(6, 52.05, 8.055, {'highway': 'speed_camera'}),
          node(7, 52.05, 8.056, {
            'highway': 'speed_camera',
            'direction': 'kaputt',
          }),
        ]);
        expect(byId(d, 'osm:node/1').travelBearings, [135]);
        expect(byId(d, 'osm:node/2').travelBearings, [202.5]);
        expect(byId(d, 'osm:node/3').travelBearings, [90, 270]);
        expect(byId(d, 'osm:node/4').travelBearings, isEmpty);
        expect(byId(d, 'osm:node/5').travelBearings, [10]);
        expect(byId(d, 'osm:node/6').travelBearings, isEmpty);
        expect(byId(d, 'osm:node/7').travelBearings, isEmpty);
      },
    );

    test(
      'Kamera auf Einbahnstraße ohne direction übernimmt deren Richtung',
      () {
        final d = parse([
          node(11, 52.05, 8.05, {'highway': 'speed_camera'}),
          way(
            100,
            [
              [52.05, 8.04],
              [52.05, 8.05],
              [52.05, 8.06],
            ],
            {'highway': 'residential', 'oneway': 'yes'},
            nodes: [1, 11, 2],
          ),
        ]);
        expect(d.points.single.travelBearings.single, closeTo(90, 0.5));
      },
    );
  });

  group('Enforcement-Relationen', () {
    test(
      'maxspeed: Peilung von from nach device, Geräteknoten nicht doppelt',
      () {
        final d = parse([
          node(20, 52.05, 8.05, {'highway': 'speed_camera', 'maxspeed': '50'}),
          relation(
            500,
            {'type': 'enforcement', 'enforcement': 'maxspeed'},
            [
              member('node', 20, 'device', lat: 52.05, lon: 8.05),
              member('node', 21, 'from', lat: 52.049, lon: 8.05),
              member('node', 22, 'to', lat: 52.048, lon: 8.05),
            ],
          ),
        ]);
        expect(d.points.length, 1);
        final p = d.points.single;
        expect(p.id, 'osm:relation/500');
        expect(p.kind, AlertKind.speedCamera);
        expect(p.position, const GeoPoint(52.05, 8.05));
        expect(p.travelBearings.single, closeTo(0, 0.1));
        expect(p.maxSpeed, 50);
      },
    );

    test('Rotlicht und Gegenrichtung', () {
      final d = parse([
        relation(
          501,
          {'type': 'enforcement', 'enforcement': 'traffic_signals'},
          [
            member('node', 30, 'device', lat: 52.05, lon: 8.05),
            member('node', 31, 'from', lat: 52.05, lon: 8.051),
          ],
        ),
      ]);
      expect(d.points.single.kind, AlertKind.redLightCamera);
      expect(d.points.single.travelBearings.single, closeTo(270, 0.5));
    });

    test('Abschnittskontrolle: Start als Position, Richtung from nach to', () {
      final d = parse([
        relation(
          502,
          {'type': 'enforcement', 'enforcement': 'average_speed'},
          [
            member('node', 40, 'device', lat: 52.04, lon: 8.045),
            member('node', 41, 'from', lat: 52.03, lon: 8.03),
            member('node', 42, 'to', lat: 52.03, lon: 8.05),
          ],
        ),
        relation(
          503,
          {'type': 'enforcement', 'enforcement': 'section_control'},
          [
            member('node', 43, 'from', lat: 52.06, lon: 8.03),
            member('node', 44, 'to', lat: 52.06, lon: 8.02),
          ],
        ),
      ]);
      final a = byId(d, 'osm:relation/502');
      expect(a.kind, AlertKind.sectionControl);
      expect(a.position, const GeoPoint(52.03, 8.03));
      expect(a.travelBearings.single, closeTo(90, 0.5));
      final b = byId(d, 'osm:relation/503');
      expect(b.kind, AlertKind.sectionControl);
      expect(b.travelBearings.single, closeTo(270, 0.5));
    });

    test('ohne from: Richtung des Geräteknotens, sonst leer', () {
      final d = parse([
        node(50, 52.05, 8.05, {'highway': 'speed_camera', 'direction': '200'}),
        relation(
          504,
          {'type': 'enforcement', 'enforcement': 'maxspeed'},
          [member('node', 50, 'device', lat: 52.05, lon: 8.05)],
        ),
        relation(
          505,
          {'type': 'enforcement', 'enforcement': 'maxspeed'},
          [member('node', 51, 'device', lat: 52.06, lon: 8.06)],
        ),
      ]);
      expect(byId(d, 'osm:relation/504').travelBearings, [200]);
      expect(byId(d, 'osm:relation/505').travelBearings, isEmpty);
    });

    test(
      'Gerät als Weg: Mitte der Geometrie; fremde enforcement-Werte entfallen',
      () {
        final d = parse([
          relation(
            506,
            {'type': 'enforcement', 'enforcement': 'maxspeed'},
            [
              {
                'type': 'way',
                'ref': 9,
                'role': 'device',
                'geometry': [
                  {'lat': 52.05, 'lon': 8.05},
                  {'lat': 52.0501, 'lon': 8.05},
                  {'lat': 52.0502, 'lon': 8.05},
                ],
              },
            ],
          ),
          relation(
            507,
            {'type': 'enforcement', 'enforcement': 'toll'},
            [member('node', 60, 'device', lat: 52.05, lon: 8.05)],
          ),
        ]);
        expect(d.points.single.id, 'osm:relation/506');
        expect(d.points.single.position, const GeoPoint(52.0501, 8.05));
      },
    );
  });

  group('Tempolimit-Wege', () {
    test('maxspeed, forward/backward, oneway, nur Kfz-Straßen', () {
      final d = parse([
        way(
          1,
          [
            [52.05, 8.04],
            [52.05, 8.05],
          ],
          {'highway': 'primary', 'maxspeed': '60', 'maxspeed:backward': '30'},
        ),
        way(
          2,
          [
            [52.04, 8.04],
            [52.04, 8.05],
          ],
          {'highway': 'residential', 'maxspeed': 'DE:urban', 'oneway': '-1'},
        ),
        way(
          3,
          [
            [52.03, 8.04],
            [52.03, 8.05],
          ],
          {'highway': 'footway', 'maxspeed': '10'},
        ),
        way(
          4,
          [
            [52.02, 8.04],
            [52.02, 8.05],
          ],
          {'highway': 'motorway', 'maxspeed': 'none'},
        ),
        way(
          5,
          [
            [52.01, 8.04],
            [52.01, 8.05],
          ],
          {'highway': 'primary'},
        ),
      ]);
      expect(d.ways.length, 3);
      expect([d.ways[0].forward, d.ways[0].backward], [60, 30]);
      expect(
        [d.ways[1].forward, d.ways[1].backward, d.ways[1].oneway],
        [50, 50, -1],
      );
      // none auf der Autobahn: ausdrücklich kein Limit, nicht „unbekannt“.
      expect([d.ways[2].forward, d.ways[2].oneway], [speedWayNoLimit, 1]);
    });
  });

  test('Cache-Format: toJson/fromJson ist verlustfrei', () {
    final d = parse([
      node(1, 52.05, 8.05, {
        'highway': 'speed_camera',
        'direction': '90',
        'maxspeed': '50',
        'name': 'X',
      }),
      node(2, 52.06, 8.05, {'highway': 'traffic_signals'}),
      way(
        10,
        [
          [52.05, 8.04],
          [52.05, 8.06],
        ],
        {'highway': 'primary', 'maxspeed': '50', 'oneway': 'yes'},
      ),
    ]);
    final back = TileData.fromJson(d.toJson());
    expect(back.fetchedAt, _t);
    expect(back.points.length, 2);
    final cam = byId(back, 'osm:node/1');
    expect(cam.travelBearings, [90]);
    expect(cam.maxSpeed, 50);
    expect(cam.label, 'X');
    expect(back.ways.single.oneway, 1);
    expect(back.ways.single.points.length, 2);
  });
}
