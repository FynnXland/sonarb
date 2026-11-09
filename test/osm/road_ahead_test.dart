import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_parser.dart';
import 'package:sonarb/features/osm/osm_road_ahead.dart';
import 'package:sonarb/features/osm/osm_speed.dart';
import 'package:sonarb/features/osm/osm_tile.dart';
import 'package:sonarb/features/osm/osm_way_limits.dart';

/// Kreuzung irgendwo auf dem Land.
const _j = GeoPoint(51.30, 9.50);

GeoPoint at(double east, double north) =>
    destinationPoint(destinationPoint(_j, 90, east), 0, north);

/// Weg aus OSM-Tags über Punkte in Metern relativ zur Kreuzung (Ost, Nord), alle 50 m ein
/// Eckpunkt.
SpeedWay road(Map<String, String> tags, List<(double, double)> from) {
  final pts = <GeoPoint>[];
  for (var i = 0; i + 1 < from.length; i++) {
    final a = at(from[i].$1, from[i].$2);
    final b = at(from[i + 1].$1, from[i + 1].$2);
    final m = distanceMeters(a, b);
    final steps = (m / 50).ceil();
    for (var s = 0; s < steps; s++) {
      pts.add(destinationPoint(a, bearingDegrees(a, b), m * s / steps));
    }
  }
  pts.add(at(from.last.$1, from.last.$2));
  final rank = motorRoadTypes.indexOf(tags['highway']!);
  return speedWayOf(tags, pts, rank: rank);
}

/// Wie ein Weg aus einem Offline-Paket: nur Haupt- oder Nebenstraße, ohne Name.
SpeedWay packaged(SpeedWay w) => SpeedWay(
  points: w.points,
  forward: w.forward,
  backward: w.backward,
  oneway: w.oneway,
  minor: w.minor,
);

/// Endpunkt der Linie in Metern relativ zur Kreuzung (Ost, Nord), gerundet.
(int, int) endOf(List<GeoPoint> line) {
  final e = line.last;
  final north =
      distanceMeters(GeoPoint(_j.lat, e.lon), e) * (e.lat >= _j.lat ? 1 : -1);
  final east =
      distanceMeters(GeoPoint(e.lat, _j.lon), e) * (e.lon >= _j.lon ? 1 : -1);
  return (east.round(), north.round());
}

void main() {
  group('abknickende Vorfahrt', () {
    // Hauptstraße kommt von Westen und knickt an der Kreuzung nach Norden ab, geradeaus geht
    // eine Nebenstraße weiter nach Osten.
    final main = road(
      {'highway': 'primary', 'maxspeed': '50', 'name': 'Hauptstraße'},
      [(-1000, 0), (0, 0)],
    );
    final bend = road(
      {'highway': 'primary', 'maxspeed': '50', 'name': 'Hauptstraße'},
      [(0, 0), (0, 1500)],
    );
    final straight = road(
      {'highway': 'residential', 'maxspeed': '30', 'name': 'Dorfweg'},
      [(0, 0), (1500, 0)],
    );

    test('die Linie folgt dem Namen nach Norden, nicht geradeaus', () {
      final line = roadAhead([main, straight, bend], at(-500, 0), 90)!;
      final (east, north) = endOf(line);
      expect(east.abs(), lessThan(5));
      expect(north, greaterThan(1500 - 520));
    });

    test('ohne Namen: dieselbe Straßenart geht vor', () {
      SpeedWay unnamed(SpeedWay w, String highway) => road(
        {'highway': highway, 'maxspeed': '50'},
        [
          for (final p in [w.points.first, w.points.last])
            (
              distanceMeters(GeoPoint(p.lat, _j.lon), p) *
                  (p.lon >= _j.lon ? 1 : -1),
              distanceMeters(GeoPoint(_j.lat, p.lon), p) *
                  (p.lat >= _j.lat ? 1 : -1),
            ),
        ],
      );
      final line = roadAhead(
        [
          unnamed(main, 'primary'),
          unnamed(straight, 'tertiary'),
          unnamed(bend, 'primary'),
        ],
        at(-500, 0),
        90,
      )!;
      expect(endOf(line).$2, greaterThan(900));
    });

    test(
      'aus dem Paket (nur Haupt- oder Nebenstraße): Hauptstraße geht vor',
      () {
        final line = roadAhead(
          [packaged(main), packaged(straight), packaged(bend)],
          at(-500, 0),
          90,
        )!;
        expect(endOf(line).$2, greaterThan(900));
      },
    );

    test('dieselbe Straße geht geradeaus weiter: die Linie auch', () {
      final ahead = road(
        {'highway': 'primary', 'maxspeed': '50', 'name': 'Hauptstraße'},
        [(0, 0), (1500, 0)],
      );
      final side = road(
        {'highway': 'residential', 'maxspeed': '30', 'name': 'Feldweg'},
        [(0, 0), (0, 1500)],
      );
      final line = roadAhead([main, side, ahead], at(-500, 0), 90)!;
      final (east, north) = endOf(line);
      expect(north.abs(), lessThan(5));
      expect(east, greaterThan(1500 - 520));
    });
  });

  group('Autobahn', () {
    // Autobahn nach Osten, an der Kreuzung beginnt die Abfahrt nach Südosten (ohne maxspeed).
    final motorway = road(
      {'highway': 'motorway', 'maxspeed': '120', 'ref': 'A 7'},
      [(-2000, 0), (3000, 0)],
    );
    final ramp = road(
      {'highway': 'motorway_link'},
      [(0, 0), (400, -60), (700, -300), (700, -1200)],
    );

    test('auf der Autobahn: die Linie bleibt auf der Autobahn', () {
      final line = roadAhead([motorway, ramp], at(-1000, 0), 90)!;
      expect(endOf(line).$2.abs(), lessThan(5));
    });

    test('auf der Abfahrt: die Linie folgt der Rampe', () {
      final line = roadAhead([motorway, ramp], at(300, -45), 98)!;
      final (east, north) = endOf(line);
      expect(east, closeTo(700, 5));
      expect(north, lessThan(-1100));
    });

    test('Rampe ohne maxspeed direkt neben der Autobahn: Limit der Autobahn bleibt', () {
      expect(ramp.limitTagged, isFalse);
      // 8 m neben der Autobahn, 3 m neben der Rampe: die Rampe wäre näher.
      for (final (pos, heading) in [
        (destinationPoint(at(40, -5), 0, -3), 90.0),
        (at(20, -3), 95.0),
      ]) {
        expect(pickSpeedLimit([ramp, motorway], pos, heading), 120);
        expect(pickSpeedLimit([motorway, ramp], pos, heading), 120);
      }
      // Nur die Rampe da: unbekannt wie bisher, kein Wert aus der Rampe.
      expect(pickSpeedLimit([ramp], at(400, -60), 98), isNull);
    });
  });

  group('Daten', () {
    test('Einbahnstraße gegen den Kurs: keine Linie', () {
      final oneway = road(
        {'highway': 'primary', 'maxspeed': '50', 'oneway': 'yes'},
        [(0, 0), (1000, 0)],
      );
      expect(roadAhead([oneway], at(300, 0), 270), isNull);
      expect(roadAhead([oneway], at(300, 0), 90), isNotNull);
    });

    test('ohne passenden Weg: keine Linie', () {
      final far = road(
        {'highway': 'primary', 'maxspeed': '50'},
        [(0, 200), (1000, 200)],
      );
      expect(roadAhead([far], at(300, 0), 90), isNull);
    });

    test('Cache: neue Felder überleben, alter Eintrag lädt ohne Klasse und ohne Linie', () {
      final w = road(
        {'highway': 'motorway_link', 'name': 'Ausfahrt', 'ref': 'A 7'},
        [(0, 0), (500, 0)],
      );
      final back = SpeedWay.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
      );
      expect(back.rank, motorRoadTypes.indexOf('motorway_link'));
      expect(back.minor, isFalse);
      expect(back.name, 'Ausfahrt');
      expect(back.ref, 'A 7');
      expect(back.limitTagged, isFalse);
      expect(roadAhead([back], at(100, 0), 90), isNotNull);

      // Eintrag aus wayDetailVersion 4: nur Geometrie, Limit und Einbahn.
      final old = SpeedWay.fromJson({
        'g': [
          for (final p in w.points) ...[p.lat, p.lon],
        ],
        'f': 50,
      });
      expect(old.classKnown, isFalse);
      expect(old.limitTagged, isTrue);
      expect(pickSpeedLimit([old], at(100, 0), 90), 50);
      expect(roadAhead([old], at(100, 0), 90), isNull);
    });

    test('Abfrage-Antwort: Rampe ohne Limit bleibt, andere Straße ohne Limit nicht', () {
      Map<String, dynamic> item(
        int id,
        String highway, [
        Map<String, String>? more,
      ]) => {
        'type': 'item',
        'id': id,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [9.50, 51.30],
            [9.51, 51.30],
          ],
        },
        'tags': {
          'highway': highway,
          'maxspeed': '',
          'name': '',
          'ref': '',
          ...?more,
        },
      };
      final parsed = parseAll({
        'elements': [
          item(1, 'motorway_link', {'ref': 'A 7'}),
          item(2, 'primary'),
          item(3, 'secondary', {'maxspeed': '70', 'name': 'Landstraße'}),
        ],
      });
      expect(parsed.ways, hasLength(2));
      final ramp = parsed.ways.firstWhere((w) => !w.limitTagged);
      expect(ramp.ref, 'A 7');
      expect(ramp.name, isNull, reason: 'leerer Text heißt kein Name');
      final tagged = parsed.ways.firstWhere((w) => w.limitTagged);
      expect(tagged.forward, 70);
      expect(tagged.name, 'Landstraße');
      expect(tagged.rank, motorRoadTypes.indexOf('secondary'));
    });
  });
}
