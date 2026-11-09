import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/alerts/merge_points.dart';

/// 1 m Nord ≈ 0,0000090° Breite.
const _m = 1 / 111195;

AlertPoint at(
  String source,
  String n,
  double northMeters, {
  AlertKind kind = AlertKind.live,
  AlertCategory? category,
  double? radius,
  List<double> bearings = const [],
}) => AlertPoint(
  id: source == 'osm' ? 'osm:node/$n' : 'plugin:$source:$n',
  kind: kind,
  position: GeoPoint(52.0 + northMeters * _m, 13.0),
  source: source,
  category: category,
  radiusMeters: radius,
  travelBearings: bearings,
);

AlertPoint works(
  String source,
  String n,
  double northMeters, {
  double? radius,
  AlertCategory category = AlertCategory.longTermRoadworks,
}) => at(
  source,
  n,
  northMeters,
  kind: AlertKind.construction,
  category: category,
  radius: radius,
);

void main() {
  group('Baustellen: Abstand wächst mit den Radien', () {
    test(
      'Kreise überlappen (300 m + 300 m, 450 m auseinander): eine Baustelle',
      () {
        final r = mergePoints([
          works('a', '1', 0, radius: 300),
          works('b', '1', 450, radius: 300),
        ]);
        expect(r, hasLength(1));
        expect(r.single.sources.map((s) => s.id).toSet(), {'a', 'b'});
      },
    );

    test('lange Strecke: der Punkt der anderen Quelle liegt im Radius', () {
      final r = mergePoints([
        works('a', '1', 0, radius: 1000),
        works('b', '1', 800),
      ]);
      expect(r, hasLength(1));
    });

    test('ohne Radius bleibt es beim Mindestabstand von 150 m', () {
      expect(
        mergePoints([works('a', '1', 0), works('b', '1', 140)]),
        hasLength(1),
      );
      expect(
        mergePoints([works('a', '1', 0), works('b', '1', 400)]),
        hasLength(2),
      );
    });

    test('kleine Radien holen eine weiter entfernte Baustelle nicht dazu', () {
      expect(
        mergePoints([
          works('a', '1', 0, radius: 50),
          works('b', '1', 600, radius: 50),
        ]),
        hasLength(2),
      );
    });

    test('auch große Radien enden bei 1,5 km', () {
      expect(
        mergePoints([
          works('a', '1', 0, radius: 3000),
          works('b', '1', 1400, radius: 3000),
        ]),
        hasLength(1),
      );
      expect(
        mergePoints([
          works('a', '1', 0, radius: 3000),
          works('b', '1', 1600, radius: 3000),
        ]),
        hasLength(2),
      );
    });

    test('Dauer- und Tagesbaustelle derselben Strecke sind eine Stelle', () {
      final r = mergePoints([
        works('a', '1', 0, radius: 200),
        works('b', '1', 300, radius: 200, category: AlertCategory.dayRoadworks),
      ]);
      expect(r, hasLength(1));
    });

    test(
      'je Quelle nur eine Baustelle: die zweite derselben Quelle bleibt eigen',
      () {
        final r = mergePoints([
          works('a', '1', 0, radius: 300),
          works('a', '2', 800, radius: 300),
          works('b', '1', 400, radius: 300),
        ]);
        expect(r, hasLength(2));
      },
    );

    test('in Ost-West-Richtung genauso (Gitterzelle ist breit genug)', () {
      // 1 km östlich bei 52° N: rund 0,0146° Länge.
      final a = works('a', '1', 0, radius: 600);
      final b = AlertPoint(
        id: 'plugin:b:1',
        kind: AlertKind.construction,
        position: const GeoPoint(52.0, 13.0146),
        source: 'b',
        radiusMeters: 600,
      );
      expect(mergePoints([a, b]), hasLength(1));
    });
  });

  group('Gefahrenmeldungen', () {
    test('derselbe Unfall, Warnradien 200 m, 250 m auseinander: ein Punkt', () {
      final r = mergePoints([
        at('a', '1', 0, category: AlertCategory.accident, radius: 200),
        at('b', '1', 250, category: AlertCategory.accident, radius: 200),
      ]);
      expect(r, hasLength(1));
    });

    test('mehr als 300 m: zwei Unfälle, auch bei großen Radien', () {
      final r = mergePoints([
        at('a', '1', 0, category: AlertCategory.accident, radius: 500),
        at('b', '1', 350, category: AlertCategory.accident, radius: 500),
      ]);
      expect(r, hasLength(2));
    });
  });

  group('mobile Blitzer', () {
    test(
      'gleiche bestätigte Richtung, 200 m auseinander, eindeutig: ein Punkt',
      () {
        final r = mergePoints([
          at('osm', '1', 0, bearings: [90]),
          at('a', '1', 200, bearings: [100]),
        ]);
        expect(r, hasLength(1));
        expect(
          r.single.id,
          'plugin:a:1',
          reason: 'bei mobilen Blitzern ist das Plugin der Kern',
        );
        expect(r.single.sources.map((s) => s.id).toSet(), {'osm', 'a'});
      },
    );

    test('ohne Richtung bei einer Quelle bleibt es bei 150 m', () {
      expect(
        mergePoints([
          at('a', '1', 0, bearings: [90]),
          at('b', '1', 200),
        ]),
        hasLength(2),
      );
    });

    test('Richtungen nur verträglich (60°), nicht bestätigt: über 150 m zwei Punkte', () {
      expect(
        mergePoints([
          at('a', '1', 0, bearings: [90]),
          at('b', '1', 200, bearings: [150]),
        ]),
        hasLength(2),
      );
    });

    test('Gegenrichtung 100 m daneben: zwei Blitzer', () {
      expect(
        mergePoints([
          at('a', '1', 0, bearings: [90]),
          at('b', '1', 100, bearings: [270]),
        ]),
        hasLength(2),
      );
    });

    test(
      'zwei Kandidaten der anderen Quelle in Reichweite: nicht über 150 m',
      () {
        final r = mergePoints([
          at('a', '1', 0, bearings: [90]),
          at('b', '1', 200, bearings: [90]),
          at('b', '2', -220, bearings: [90]),
        ]);
        expect(r, hasLength(3));
      },
    );
  });

  group('zwei echte Stellen kurz hintereinander', () {
    test('feste Blitzer 120 m hintereinander, beide Quellen kennen beide', () {
      final r = mergePoints([
        at('osm', '1', 0, kind: AlertKind.speedCamera, bearings: [90]),
        at('osm', '2', 120, kind: AlertKind.speedCamera, bearings: [90]),
        at('f', '1', 6, kind: AlertKind.speedCamera, bearings: [90]),
        at('f', '2', 126, kind: AlertKind.speedCamera, bearings: [90]),
      ]);
      expect(r, hasLength(2));
      expect(
        r.map((p) => p.sources.map((s) => s.id).toSet()),
        everyElement({'osm', 'f'}),
      );
    });

    test('mobile Blitzer 200 m hintereinander, beide Quellen kennen beide', () {
      final r = mergePoints([
        at('a', '1', 0, bearings: [90]),
        at('a', '2', 200, bearings: [90]),
        at('b', '1', 12, bearings: [90]),
        at('b', '2', 212, bearings: [90]),
      ]);
      expect(r, hasLength(2));
    });

    test('Anfang und Ende einer Abschnittskontrolle bleiben getrennt', () {
      final r = mergePoints([
        at(
          'osm',
          '1',
          0,
          kind: AlertKind.sectionControl,
          category: AlertCategory.sectionStart,
        ),
        at(
          'f',
          '1',
          20,
          kind: AlertKind.sectionControl,
          category: AlertCategory.sectionEnd,
        ),
      ]);
      expect(r, hasLength(2));
    });

    test('je Richtung ein Blitzer am selben Mast: zwei Punkte', () {
      final r = mergePoints([
        at('osm', '1', 0, kind: AlertKind.speedCamera, bearings: [0]),
        at('osm', '2', 8, kind: AlertKind.speedCamera, bearings: [180]),
        at('f', '1', 3, kind: AlertKind.speedCamera, bearings: [350]),
        at('f', '2', 9, kind: AlertKind.speedCamera, bearings: [175]),
      ]);
      expect(r, hasLength(2));
      expect(r.map((p) => p.travelBearings.single).toSet(), {0, 180});
    });
  });

  test('Baustelle und mobiler Blitzer an einer Stelle bleiben getrennt', () {
    final r = mergePoints([
      works('a', '1', 0, radius: 500),
      at('b', '1', 20, category: AlertCategory.mobileSpeed),
    ]);
    expect(r, hasLength(2));
  });
}
