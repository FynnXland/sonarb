import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/features/osm/osm_parser.dart';

import 'osm_fixtures.dart';

final _t = DateTime.utc(2026, 1, 1);

void main() {
  final good = node(1, 52.05, 8.05, {'highway': 'speed_camera'});
  final goodSignal = node(2, 52.06, 8.06, {'highway': 'traffic_signals'});
  final goodWay = way(
    10,
    [
      [52.05, 8.04],
      [52.05, 8.06],
    ],
    {'highway': 'primary', 'maxspeed': '50'},
  );

  /// Gültiges JSON mit einem kaputten Element mittendrin: der Rest der Kachel bleibt.
  void expectGoodSurvives(Map<String, dynamic> broken, {String? why}) {
    final d = parseOverpassJson(
      overpassBody([broken, good, goodSignal, goodWay]),
      testTile,
      _t,
    );
    expect(
      d.points.map((p) => p.id),
      containsAll(['osm:node/1', 'osm:node/2']),
      reason: why,
    );
    expect(d.ways, hasLength(1), reason: why);
  }

  test('Knoten ohne id, mit Text als Koordinate', () {
    expectGoodSurvives({
      'type': 'node',
      'lat': 52.0,
      'lon': 8.0,
      'tags': {'highway': 'speed_camera'},
    }, why: 'ohne id');
    expectGoodSurvives({
      'type': 'node',
      'id': 3,
      'lat': 'x',
      'lon': 8.0,
      'tags': {'highway': 'speed_camera'},
    }, why: 'lat Text');
    expectGoodSurvives({
      'type': 'node',
      'id': 3,
      'lat': 52.05,
      'lon': 8.05,
      'tags': {'highway': 'traffic_signals'},
      'timestamp': 12,
    }, why: 'Zeitstempel Zahl');
  });

  test('Weg ohne Knoten, mit kaputter Geometrie', () {
    expectGoodSurvives({
      'type': 'way',
      'id': 4,
      'tags': {'highway': 'primary', 'maxspeed': '30'},
      'geometry': [
        {'lat': 52.0, 'lon': 8.0},
        null,
        'x',
      ],
      'nodes': ['a', null],
    }, why: 'Geometrie');
    expectGoodSurvives({
      'type': 'way',
      'id': 'vier',
      'nodes': [1, 2],
      'tags': {'highway': 'primary', 'maxspeed': '30'},
      'geometry': [
        {'lat': 52.0, 'lon': 8.0},
        {'lat': 52.1, 'lon': 8.0},
      ],
    }, why: 'id Text');
  });

  test(
    'Relation ohne Mitglieder, mit kaputten Mitgliedern, ohne Geometrie',
    () {
      expectGoodSurvives({
        'type': 'relation',
        'id': 5,
        'tags': {'type': 'enforcement', 'enforcement': 'maxspeed'},
      }, why: 'ohne members');
      expectGoodSurvives({
        'type': 'relation',
        'id': 6,
        'tags': {'type': 'enforcement', 'enforcement': 'maxspeed'},
        'members': [
          'x',
          null,
          {
            'type': 'node',
            'ref': 'abc',
            'role': 'device',
            'lat': 52.0,
            'lon': 8.0,
          },
          {'type': 'way', 'ref': 9, 'role': 'device', 'geometry': 'kaputt'},
        ],
      }, why: 'members');
      expectGoodSurvives({
        'type': 'relation',
        'id': 'sieben',
        'tags': {'type': 'enforcement', 'enforcement': 'average_speed'},
        'members': [
          {'type': 'node', 'ref': 1, 'role': 'from', 'lat': 52.0, 'lon': 8.0},
        ],
      }, why: 'id Text');
    },
  );

  test('Elemente mit Tags als Liste, ohne Typ, mit meta-Feldern', () {
    expectGoodSurvives({
      'type': 'node',
      'id': 7,
      'tags': ['x'],
    }, why: 'tags');
    expectGoodSurvives({'id': 8}, why: 'ohne type');
    expectGoodSurvives({
      ...node(9, 52.05, 8.0501, {'highway': 'speed_camera'}),
      'timestamp': '2024-13-45T99:00:00Z',
      'version': 'abc',
      'user': null,
    }, why: 'meta');
  });

  test(
    'ein kaputtes Element lässt gültige Punkte der Relation nicht fallen',
    () {
      final d = parseOverpassJson(
        overpassBody([
          {'type': 'relation', 'id': 1, 'tags': 'kaputt', 'members': 3},
          relation(
            2,
            {'type': 'enforcement', 'enforcement': 'maxspeed'},
            [member('node', 60, 'device', lat: 52.05, lon: 8.05)],
          ),
        ]),
        testTile,
        _t,
      );
      expect(d.points.single.id, 'osm:relation/2');
    },
  );
}
