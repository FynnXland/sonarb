import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/osm/osm_category.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_parser.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

import 'osm_fixtures.dart';

final _t = DateTime.utc(2026, 1, 1);

TileData parse(List<Map<String, dynamic>> elements) =>
    parseOverpassJson(overpassBody(elements), testTile, _t);

AlertPoint one(
  Map<String, String> tags, {
  List<Map<String, dynamic>> more = const [],
}) => parse([
  node(1, 52.05, 8.05, {'highway': 'speed_camera', ...tags}),
  ...more,
]).points.single;

Map<String, dynamic> roadAt(Map<String, String> tags, int nodeId) => way(
  11,
  [
    [52.05, 8.04],
    [52.05, 8.06],
  ],
  {'highway': 'primary', ...tags},
  nodes: [5, nodeId],
);

Map<String, dynamic> rel(
  int id,
  Map<String, String> tags, {
  bool section = false,
  bool end = true,
}) => relation(
  id,
  {'type': 'enforcement', ...tags},
  [
    member('node', 60, 'device', lat: 52.05, lon: 8.05),
    if (section) member('node', 61, 'from', lat: 52.05, lon: 8.05),
    if (section && end) member('node', 62, 'to', lat: 52.05, lon: 8.07),
  ],
);

List<String> details(AlertPoint p) => [for (final d in p.details) '$d'];

void main() {
  group('Knoten', () {
    test('einfache Messstelle: fester Blitzer mit Tempo', () {
      final p = one({'maxspeed': '70'});
      expect(p.kind, AlertKind.speedCamera);
      expect(p.category, AlertCategory.fixedSpeed);
      expect(p.maxSpeed, 70);
    });

    test('Rotlicht, mit und ohne Tempomessung', () {
      final red = one({'enforcement': 'traffic_signals', 'maxspeed': '50'});
      expect(red.kind, AlertKind.redLightCamera);
      expect(red.category, AlertCategory.fixedRedLight);
      expect(red.maxSpeed, isNull, reason: 'Symbol ohne Tempo');

      final both = one({
        'enforcement': 'maxspeed;traffic_signals',
        'maxspeed': '50',
      });
      expect(both.kind, AlertKind.speedCamera);
      expect(both.category, AlertCategory.fixedRedLightSpeed);
      expect(both.maxSpeed, 50);
    });

    test('Tunnel: am Weg oder am Knoten, Brücke nicht', () {
      expect(
        one(
          {},
          more: [
            roadAt({'tunnel': 'yes'}, 1),
          ],
        ).category,
        AlertCategory.tunnelSpeed,
      );
      expect(one({'tunnel': 'yes'}).category, AlertCategory.tunnelSpeed);
      expect(
        one(
          {},
          more: [
            roadAt({'bridge': 'yes'}, 1),
          ],
        ).category,
        AlertCategory.fixedSpeed,
      );
    });

    test('mobil und Anhänger', () {
      expect(
        one({'camera:type': 'mobile'}).category,
        AlertCategory.mobileSpeed,
      );
      expect(
        one({'camera:mount': 'trailer'}).category,
        AlertCategory.semiStationary,
      );
    });

    test('unbekannte Kontrollart am Blitzerknoten: bleibt fester Blitzer', () {
      expect(one({'enforcement': 'check'}).category, AlertCategory.fixedSpeed);
    });
  });

  group('Relationen', () {
    AlertPoint rp(Map<String, String> tags) =>
        parse([rel(9, tags)]).points.single;

    test('Tempo, Rotlicht, beides', () {
      expect(
        rp({'enforcement': 'maxspeed', 'maxspeed': '30'}).category,
        AlertCategory.fixedSpeed,
      );
      expect(
        rp({'enforcement': 'traffic_signals'}).category,
        AlertCategory.fixedRedLight,
      );
      final both = rp({
        'enforcement': 'traffic_signals;maxspeed',
        'maxspeed': '50',
      });
      expect(both.category, AlertCategory.fixedRedLightSpeed);
      expect(both.kind, AlertKind.speedCamera);
      expect(both.maxSpeed, 50);
    });

    test('Abschnittskontrolle: Anfang und Ende als zwei Punkte', () {
      final pts = parse([
        rel(9, {
          'enforcement': 'average_speed',
          'maxspeed': '80',
        }, section: true),
      ]).points;
      expect(pts.map((p) => p.id), ['osm:relation/9', 'osm:relation/9#end']);
      final start = pts[0], end = pts[1];
      expect(start.category, AlertCategory.sectionStart);
      expect(start.kind, AlertKind.sectionControl);
      expect(start.maxSpeed, 80);
      expect(start.position, const GeoPoint(52.05, 8.05));
      expect(end.category, AlertCategory.sectionEnd);
      expect(end.position, const GeoPoint(52.05, 8.07));
      expect(end.travelBearings, start.travelBearings);
      expect(end.sources.single.url, start.sources.single.url);
    });

    test('Abschnittskontrolle ohne „to“: nur der Anfang', () {
      final pts = parse([
        rel(9, {'enforcement': 'section_control'}, section: true, end: false),
      ]).points;
      expect(pts.single.category, AlertCategory.sectionStart);
    });

    test('Höhe, Gewicht, Einfahrt, Überholverbot: nur Ansage', () {
      final expected = {
        'maxheight': AlertCategory.heightControl,
        'maxweight': AlertCategory.weightControl,
        'weight': AlertCategory.weightControl,
        'access': AlertCategory.accessControl,
        'noovertaking': AlertCategory.noOvertaking,
        'no_overtaking': AlertCategory.noOvertaking,
      };
      expected.forEach((value, category) {
        final p = rp({'enforcement': value, 'maxspeed': '50'});
        expect(p.category, category, reason: value);
        expect(p.kind, AlertKind.construction, reason: value);
        expect(p.maxSpeed, isNull, reason: value);
      });
    });

    test('Höhe und Gewicht als Angabe', () {
      final h = rp({'enforcement': 'maxheight', 'maxheight': '3.8'});
      expect(details(h), contains('Höchsthöhe: bis 3,8 m'));
      expect(details(h), contains('Kontrolle: Höhe'));
      final w = rp({'enforcement': 'maxweight', 'maxweight': '7,5 t'});
      expect(details(w), contains('Höchstgewicht: bis 7,5 t'));
      final bad = rp({'enforcement': 'maxheight', 'maxheight': 'default'});
      expect(bad.details.map((d) => d.label), isNot(contains('Höchsthöhe')));
    });

    test('Abstand: fest wie eine feste Messstelle, mobil als eigene Art', () {
      final fixed = rp({'enforcement': 'mindistance'});
      expect(fixed.kind, AlertKind.speedCamera);
      expect(fixed.category, AlertCategory.fixedSpeed);
      final mobile = rp({
        'enforcement': 'mindistance',
        'camera:type': 'mobile',
      });
      expect(mobile.kind, AlertKind.live);
      expect(mobile.category, AlertCategory.mobileDistance);
    });

    test('fremde Kontrollarten entfallen', () {
      for (final v in ['toll', 'check', 'seatbelt', 'mobile_phone']) {
        expect(
          parse([
            rel(9, {'enforcement': v}),
          ]).points,
          isEmpty,
          reason: v,
        );
      }
    });

    test('Tunnel am Geräteknoten der Relation', () {
      final p = parse([
        node(60, 52.05, 8.05, {'highway': 'speed_camera'}),
        roadAt({'tunnel': 'yes'}, 60),
        rel(9, {'enforcement': 'maxspeed'}),
      ]).points.single;
      expect(p.id, 'osm:relation/9');
      expect(p.category, AlertCategory.tunnelSpeed);
    });
  });

  test('enforcementValues vereinheitlicht', () {
    expect(
      enforcementValues(' maxspeed ; weight;no_overtaking;section_control '),
      {'maxspeed', 'maxweight', 'noovertaking', 'average_speed'},
    );
    expect(enforcementValues(null), isEmpty);
  });

  test('Abfrage findet auch Kontrollen ohne Blitzerknoten', () {
    final q = buildLayerQuery(
      OsmLayer.cameras,
      const GeoBounds(south: 52, west: 8, north: 52.1, east: 8.1),
    );
    expect(q, contains('maxheight|maxweight|weight|access|mindistance'));
    expect(q, contains('->.enfOther;'));
    expect(q, contains('(.enfCams; .enfOther;)->.enf;'));
    // Kombinationen wie „maxspeed;traffic_signals“ müssen treffen: kein ^…$.
    expect(q, contains('"enforcement"~"maxspeed|traffic_signals'));
  });

  test('Kategorie übersteht den Cache; unbekannter Name wird ignoriert', () {
    final d = parse([
      node(1, 52.05, 8.05, {
        'highway': 'speed_camera',
        'camera:mount': 'trailer',
      }),
    ]);
    final back = TileData.fromJson(
      jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>,
    );
    expect(back.points.single.category, AlertCategory.semiStationary);

    final old = TileData.fromJson({
      'v': 1,
      't': _t.millisecondsSinceEpoch,
      'p': [
        {
          'i': 'osm:node/1',
          'k': 'speedCamera',
          'la': 52.05,
          'lo': 8.05,
          'c': 'gibtsNicht',
        },
      ],
      'w': <dynamic>[],
    });
    expect(old.points.single.category, isNull);
    expect(old.points.single.effectiveCategory, AlertCategory.fixedSpeed);
  });
}
