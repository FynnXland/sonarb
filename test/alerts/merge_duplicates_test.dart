import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/alerts/merge_points.dart';

/// Typischer Fall aus OSM, an eine erfundene Stelle verschoben: zwei feste Blitzer, einen je
/// Fahrtrichtung, 113 m auseinander, beide mit 50 km/h.
const _north = GeoPoint(53.3439501, 9.7632975);
const _south = GeoPoint(53.3429387, 9.7637115);

AlertPoint osm(String n, GeoPoint at, double bearing) => AlertPoint(
  id: 'osm:node/$n',
  kind: AlertKind.speedCamera,
  position: at,
  source: 'osm',
  travelBearings: [bearing],
  maxSpeed: 50,
);

final osmNorth = osm('1001', _north, 9);
final osmSouth = osm('1002', _south, 185);

/// Punkt auf der Geraden durch die beiden OSM-Kameras: [meters] vom nördlichen Knoten Richtung Süden
/// (negativ: nach Norden), optional [sideMeters] seitlich (nach Osten).
GeoPoint onRoad(double meters, {double sideMeters = 0}) {
  final total = distanceMeters(_north, _south);
  final t = meters / total;
  final lat = _north.lat + (_south.lat - _north.lat) * t;
  final lon = _north.lon + (_south.lon - _north.lon) * t;
  return GeoPoint(lat, lon + sideMeters / (111195 * 0.598));
}

AlertPoint feed(
  String n,
  GeoPoint at, {
  String source = 'blitzer',
  List<double> bearings = const [],
  int? maxSpeed,
  AlertCategory category = AlertCategory.fixedSpeed,
  AlertKind kind = AlertKind.speedCamera,
}) => AlertPoint(
  id: 'plugin:$source:$n',
  kind: kind,
  position: at,
  source: source,
  travelBearings: bearings,
  maxSpeed: maxSpeed,
  category: category,
);

/// Beteiligte Quellen; ein nie zusammengeführter Punkt nennt nur seine eigene.
Set<String> sourceIds(AlertPoint p) =>
    p.sources.isEmpty ? {p.source} : p.sources.map((s) => s.id).toSet();

void main() {
  test('die beiden OSM-Blitzer liegen wie erwartet 113 m auseinander', () {
    expect(distanceMeters(_north, _south), inInclusiveRange(110, 116));
  });

  group('feste Blitzer: Plugin-Punkt neben zwei OSM-Blitzern', () {
    test('ohne Richtung, zwischen beiden: geht an den näheren, OSM bleibt', () {
      final p = feed('1', onRoad(45), maxSpeed: 50);
      final r = mergePoints([osmNorth, osmSouth, p]);
      expect(r.map((x) => x.id), ['osm:node/1001', 'osm:node/1002']);
      expect(sourceIds(r.first), {'osm', 'blitzer'});
      expect(r.first.position, _north, reason: 'OSM-Position gewinnt');
      expect(sourceIds(r.last), {'osm'});
    });

    test('Plugin-Punkt näher am südlichen: dorthin, auch in umgekehrter Reihenfolge', () {
      final p = feed('1', onRoad(70), maxSpeed: 50);
      final r = mergePoints([p, osmSouth, osmNorth]);
      expect(r.map((x) => x.id), ['osm:node/1002', 'osm:node/1001']);
      expect(sourceIds(r.first), {'osm', 'blitzer'});
      expect(sourceIds(r.last), {'osm'});
    });

    test('mit Richtung: nur zur Kamera der eigenen Richtung, auch wenn die andere näher liegt', () {
      final p = feed('1', onRoad(70), bearings: [10], maxSpeed: 50);
      final r = mergePoints([osmNorth, osmSouth, p]);
      expect(r, hasLength(2));
      expect(sourceIds(r.first), {'osm', 'blitzer'}, reason: '9° passt zu 10°');
      expect(sourceIds(r.last), {'osm'});
    });

    test('Plugin 150 m von der Kamera, gleiche Richtung: derselbe Blitzer', () {
      final p = feed('1', onRoad(-150), bearings: [12]);
      final r = mergePoints([osmNorth, p]);
      expect(r.map((x) => x.id), ['osm:node/1001']);
      expect(sourceIds(r.single), {'osm', 'blitzer'});
    });

    test('Plugin 150 m entfernt, gleiches Tempolimit, keine Richtung: derselbe Blitzer', () {
      final p = feed('1', onRoad(-150), maxSpeed: 50);
      expect(mergePoints([osmNorth, p]), hasLength(1));
    });

    test('Plugin 150 m entfernt ohne Hinweis (keine Richtung, kein Limit): zwei Punkte', () {
      final p = feed('1', onRoad(-150));
      expect(mergePoints([osmNorth, p]), hasLength(2));
    });

    test('Plugin 150 m entfernt mit anderem Limit: zwei Punkte', () {
      final p = feed('1', onRoad(-150), maxSpeed: 30);
      expect(mergePoints([osmNorth, p]), hasLength(2));
    });

    test('Plugin 150 m entfernt, Gegenrichtung: zwei Punkte', () {
      final p = feed('1', onRoad(-150), bearings: [189], maxSpeed: 50);
      expect(mergePoints([osmNorth, p]), hasLength(2));
    });

    test('über 200 m bleibt es getrennt, auch mit allen Hinweisen', () {
      final p = feed('1', onRoad(-230), bearings: [9], maxSpeed: 50);
      expect(mergePoints([osmNorth, p]), hasLength(2));
    });

    test('zwei Punkte derselben Quelle neben einem OSM-Blitzer: der nähere wird aufgenommen', () {
      final r = mergePoints([
        osmNorth,
        feed('1', onRoad(-150), bearings: [9]),
        feed('2', onRoad(-170), bearings: [9]),
      ]);
      expect(r.map((x) => x.id), ['osm:node/1001', 'plugin:blitzer:2']);
      expect(sourceIds(r.first), {'osm', 'blitzer'});
    });

    test(
      'beide Quellen kennen beide Kameras: zwei Punkte mit je zwei Quellen',
      () {
        final r = mergePoints([
          osmNorth,
          osmSouth,
          feed('n', onRoad(8, sideMeters: 4), bearings: [5], maxSpeed: 50),
          feed('s', onRoad(105, sideMeters: 4), bearings: [180], maxSpeed: 50),
        ]);
        expect(r, hasLength(2));
        expect(r.map(sourceIds), everyElement({'osm', 'blitzer'}));
        expect(r.map((p) => p.id), ['osm:node/1001', 'osm:node/1002']);
      },
    );

    test('zwei Plugins plus OSM: alle drei Quellen an einem Punkt', () {
      final r = mergePoints([
        osmNorth,
        feed('1', onRoad(60), maxSpeed: 50),
        feed('2', onRoad(-40), source: 'zweite', bearings: [9]),
      ]);
      expect(r, hasLength(1));
      expect(sourceIds(r.single), {'osm', 'blitzer', 'zweite'});
    });
  });

  group(
    'Plugin mit mehreren Anbietern (sammelquelle): zwei Pins statt vier',
    () {
      /// Ein Punkt aus der Fusion des Plugins: Quelle `sammelquelle`, die Anbieter stehen in `sources`.
      AlertPoint multi(
        String n,
        GeoPoint at,
        List<String> providers, {
        List<double> bearings = const [],
        List<PointDetail> details = const [],
      }) => AlertPoint(
        id: 'plugin:sammelquelle:$n',
        kind: AlertKind.speedCamera,
        category: AlertCategory.fixedSpeed,
        position: at,
        source: 'sammelquelle',
        travelBearings: bearings,
        maxSpeed: 50,
        details: details,
        sources: [for (final id in providers) PointSource(id: id, name: id)],
      );

      // An jeder OSM-Kamera ein Punkt von Anbieter A (bei der hinteren zusammen mit Anbieter B)
      // und einer von Anbieter C. Früher verschmolz je Kamera nur einer, der andere blieb als Pin stehen.
      void expectTwoPins(List<AlertPoint> r) {
        expect(r, hasLength(2));
        expect(r.map((p) => p.id), ['osm:node/1001', 'osm:node/1002']);
        expect(sourceIds(r.first), {'osm', 'anbieter_a', 'anbieter_c'});
        expect(sourceIds(r.last), {
          'osm',
          'anbieter_a',
          'anbieter_b',
          'anbieter_c',
        });
        expect(r.map((p) => p.position), [_north, _south]);
      }

      test('mit Richtungen', () {
        expectTwoPins(
          mergePoints([
            osmNorth,
            osmSouth,
            multi('s1', onRoad(10), ['anbieter_a'], bearings: [9]),
            multi('q1', onRoad(65), ['anbieter_c'], bearings: [5]),
            multi('q2', onRoad(101), ['anbieter_c'], bearings: [185]),
            multi(
              's2',
              onRoad(60),
              ['anbieter_a', 'anbieter_b'],
              bearings: [185],
            ),
          ]),
        );
      });

      test('ohne Richtung bei den Punkten dazwischen: der nächste Anbieter-Punkt je Kamera', () {
        expectTwoPins(
          mergePoints([
            osmNorth,
            osmSouth,
            multi('s1', onRoad(10), ['anbieter_a']),
            multi('q1', onRoad(65), ['anbieter_c']),
            multi('q2', onRoad(101), ['anbieter_c']),
            multi('s2', onRoad(60), ['anbieter_a', 'anbieter_b']),
          ]),
        );
      });

      test('Reihenfolge der Eingabe spielt keine Rolle', () {
        final input = [
          osmNorth,
          osmSouth,
          multi('s1', onRoad(10), ['anbieter_a'], bearings: [9]),
          multi('q1', onRoad(65), ['anbieter_c'], bearings: [5]),
          multi('q2', onRoad(101), ['anbieter_c'], bearings: [185]),
          multi(
            's2',
            onRoad(60),
            ['anbieter_a', 'anbieter_b'],
            bearings: [185],
          ),
        ];
        for (final shuffled in [
          input.reversed.toList(),
          [...input.sublist(2), ...input.sublist(0, 2)],
          [input[3], input[5], input[0], input[2], input[1], input[4]],
        ]) {
          final r = mergePoints(shuffled);
          expect(r, hasLength(2));
          expect(r.map((p) => p.id).toSet(), {
            'osm:node/1001',
            'osm:node/1002',
          });
          expect(r.every((p) => p.sources.length >= 3), isTrue);
        }
      });

      test(
        'derselbe Anbieter zweimal an einer Kamera: nur einer wird aufgenommen',
        () {
          final r = mergePoints([
            osmNorth,
            multi('q1', onRoad(20), ['anbieter_c'], bearings: [9]),
            multi('q1b', onRoad(40), ['anbieter_c'], bearings: [9]),
          ]);
          expect(r, hasLength(2));
          expect(sourceIds(r.first), {'osm', 'anbieter_c'});
        },
      );

      test('ohne OSM bleiben die Punkte eines Plugins getrennt, auch mit verschiedenen Anbietern', () {
        final r = mergePoints([
          multi('s1', onRoad(10), ['anbieter_a'], bearings: [9]),
          multi('q1', onRoad(30), ['anbieter_c'], bearings: [9]),
          feed('x', onRoad(15), source: 'anderes', bearings: [9]),
        ]);
        expect(r.where((p) => p.source == 'sammelquelle'), hasLength(2));
      });
    },
  );

  group('Richtungsangaben, die einander widersprechen', () {
    const rotatable = [PointDetail('Ausrichtung', 'Drehbar')];

    AlertPoint multi(
      GeoPoint at,
      List<double> bearings, {
      List<PointDetail> details = const [],
      String n = 's',
      List<String> providers = const ['anbieter_a', 'anbieter_b'],
    }) => AlertPoint(
      id: 'plugin:sammelquelle:$n',
      kind: AlertKind.speedCamera,
      category: AlertCategory.fixedSpeed,
      position: at,
      source: 'sammelquelle',
      travelBearings: bearings,
      maxSpeed: 50,
      details: details,
      sources: [for (final id in providers) PointSource(id: id, name: id)],
    );

    test(
      '20 m von einer OSM-Kamera, Richtung 91° daneben: dieselbe Kamera',
      () {
        final r = mergePoints([
          osmNorth,
          osmSouth,
          multi(onRoad(20), [100]),
        ]);
        expect(r, hasLength(2));
        expect(sourceIds(r.first), {'osm', 'anbieter_a', 'anbieter_b'});
        expect(r.first.travelBearings, [9], reason: 'Richtung von OSM');
      },
    );

    test('drehbare Anlage: Richtung zählt nicht, auch die Gegenrichtung', () {
      final r = mergePoints([
        osmNorth,
        osmSouth,
        multi(onRoad(20), [189], details: rotatable),
      ]);
      expect(r, hasLength(2));
      expect(sourceIds(r.first), {'osm', 'anbieter_a', 'anbieter_b'});
    });

    test('drehbare Anlage zwischen den Kameras: geht an die nähere', () {
      final r = mergePoints([
        osmNorth,
        osmSouth,
        multi(onRoad(75), [9], details: rotatable),
      ]);
      expect(r, hasLength(2));
      expect(sourceIds(r.last), {'osm', 'anbieter_a', 'anbieter_b'});
    });

    test('Gegenrichtung ohne „Drehbar“ bleibt eine eigene Kamera', () {
      expect(
        mergePoints([
          osmNorth,
          multi(onRoad(20), [189]),
        ]),
        hasLength(2),
      );
    });

    test('über 30 m gilt der Richtungsunterschied wieder', () {
      expect(
        mergePoints([
          osmNorth,
          multi(onRoad(45), [100]),
        ]),
        hasLength(2),
      );
    });

    test('zwei OSM-Kameras am selben Mast: kein Übergehen der Richtung', () {
      final north = osm('1', _north, 9);
      final twin = osm('2', onRoad(8), 189);
      final r = mergePoints([
        north,
        twin,
        multi(onRoad(4), [100]),
      ]);
      expect(r, hasLength(3));
    });

    test('Konstellation mit drehbarer Anlage: zwei Pins', () {
      final r = mergePoints([
        osmNorth,
        osmSouth,
        multi(onRoad(20), [189], details: rotatable, n: 's2'),
        multi(onRoad(65), [5], n: 'q1', providers: const ['anbieter_c']),
        multi(onRoad(101), [185], n: 'q2', providers: const ['anbieter_c']),
        multi(onRoad(15), [9], n: 's1', providers: const ['anbieter_a']),
      ]);
      expect(r, hasLength(2));
      expect(r.map((p) => p.id), ['osm:node/1001', 'osm:node/1002']);
    });
  });

  group('mobile Blitzer: Kern aus dem Plugin', () {
    AlertPoint mobile(String id, String source, GeoPoint at) => AlertPoint(
      id: id,
      kind: AlertKind.live,
      position: at,
      source: source,
      category: AlertCategory.mobileSpeed,
      travelBearings: const [90],
    );

    test('OSM und Plugin: Position, ID und Quelle des Plugins, OSM als weitere Quelle', () {
      final plugin = mobile(
        'plugin:blitzer:7',
        'blitzer',
        onRoad(0, sideMeters: 80),
      );
      final r = mergePoints([mobile('osm:node/5', 'osm', onRoad(0)), plugin]);
      expect(r, hasLength(1));
      expect(r.single.id, 'plugin:blitzer:7');
      expect(r.single.position, plugin.position);
      expect(r.single.source, 'blitzer');
      expect(sourceIds(r.single), {'osm', 'blitzer'});
    });

    test('zwei Plugins plus OSM: das erste Plugin ist der Kern', () {
      final r = mergePoints([
        mobile('osm:node/5', 'osm', onRoad(0)),
        mobile('plugin:a:1', 'a', onRoad(0, sideMeters: 30)),
        mobile('plugin:b:1', 'b', onRoad(0, sideMeters: 60)),
      ]);
      expect(r.single.id, 'plugin:a:1');
      expect(sourceIds(r.single), {'osm', 'a', 'b'});
    });

    test('feste Blitzer behalten OSM als Kern, auch neben mobilen', () {
      final r = mergePoints([
        feed('1', onRoad(5, sideMeters: 3)),
        osmNorth,
        mobile('plugin:blitzer:9', 'blitzer', onRoad(-20)),
      ]);
      expect(r.map((p) => p.id), containsAll(['osm:node/1001']));
      expect(r, hasLength(2));
    });
  });
}
