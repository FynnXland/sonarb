import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';
import 'package:sonarb/features/alerts/merge_points.dart';

import 'fakes.dart';

/// 0,0001° Breite ≈ 11,1 m.
const _m = 0.0001 / 11.132;

AlertPoint pt(
  String id,
  String source,
  double northMeters, {
  AlertKind kind = AlertKind.speedCamera,
  List<double> bearings = const [],
  int? maxSpeed,
  String? label,
  List<PointDetail> details = const [],
  List<PointSource> sources = const [],
  AlertCategory? category,
}) => AlertPoint(
  id: id,
  kind: kind,
  position: GeoPoint(52.0 + northMeters * _m, 13.0),
  source: source,
  travelBearings: bearings,
  maxSpeed: maxSpeed,
  label: label,
  details: details,
  sources: sources,
  category: category,
);

String name(String id) => id == 'osm' ? 'OpenStreetMap' : 'Plugin $id';

void main() {
  group('feste Messstellen: Abstand', () {
    test('bis 40 m immer zusammen', () {
      final a = mergePoints([
        pt('osm:node/1', 'osm', 0),
        pt('plugin:f:1', 'f', 35),
      ]);
      expect(a.map((p) => p.id), ['osm:node/1']);
    });

    test('gleicher Blitzer aus zwei Quellen mit 60 m Abstand: ein Punkt', () {
      final r = mergePoints([
        pt('osm:node/1', 'osm', 0, bearings: [90]),
        pt('plugin:f:1', 'f', 60, bearings: [100]),
      ]);
      expect(r.map((p) => p.id), ['osm:node/1']);
      expect(r.single.travelBearings, [90], reason: 'Richtung von OSM');
    });

    test('über 100 m getrennt', () {
      final r = mergePoints([
        pt('osm:node/1', 'osm', 0),
        pt('plugin:f:1', 'f', 110),
      ]);
      expect(r.map((p) => p.id), ['osm:node/1', 'plugin:f:1']);
    });

    test('40 bis 100 m: OSM nimmt den nächsten Punkt des Plugins, der andere bleibt', () {
      final r0 = mergePoints([
        pt('osm:node/1', 'osm', 0),
        pt('plugin:f:1', 'f', 60),
        pt('plugin:f:2', 'f', 90),
      ]);
      expect(r0.map((p) => p.id), ['osm:node/1', 'plugin:f:2']);
      expect(r0.first.sources, hasLength(2));
      // Ohne OSM bleibt es bei der strengen Regel: Zwei Punkte derselben Quelle sind uneindeutig.
      final r = mergePoints([
        pt('plugin:g:1', 'g', 0),
        pt('plugin:f:1', 'f', 60),
        pt('plugin:f:2', 'f', 90),
      ]);
      expect(r, hasLength(3));
      // Ein weiterer OSM-Punkt nahe am Plugin-Punkt, aber in anderer Richtung: kein Konkurrent.
      final r2 = mergePoints([
        pt('osm:node/1', 'osm', 0, bearings: [90]),
        pt('osm:node/2', 'osm', 70, bearings: [270]),
        pt('plugin:f:1', 'f', 60, bearings: [100]),
      ]);
      expect(r2.map((p) => p.id), ['osm:node/1', 'osm:node/2']);
      expect(r2.first.sources.length, greaterThan(0));
    });
  });

  test('mobile und Baustellen: bis 150 m zusammen', () {
    for (final kind in [AlertKind.live, AlertKind.construction]) {
      final near = mergePoints([
        pt('plugin:a:1', 'a', 0, kind: kind),
        pt('plugin:b:1', 'b', 140, kind: kind),
      ]);
      expect(near, hasLength(1), reason: '$kind');
      final far = mergePoints([
        pt('plugin:a:1', 'a', 0, kind: kind),
        pt('plugin:b:1', 'b', 160, kind: kind),
      ]);
      expect(far, hasLength(2), reason: '$kind');
    }
  });

  test('Gruppen bleiben getrennt, Ampeln und Hotspots nie zusammen', () {
    final all = mergePoints([
      pt('osm:node/1', 'osm', 0),
      pt('plugin:f:live', 'f', 5, kind: AlertKind.live),
      pt('plugin:f:bau', 'f', 5, kind: AlertKind.construction),
      pt('osm:node/2', 'osm', 0, kind: AlertKind.trafficSignal),
      pt('plugin:f:amp', 'f', 3, kind: AlertKind.trafficSignal),
      pt('hotspot:1', 'hotspot', 2, kind: AlertKind.hotspot),
      pt('plugin:f:hot', 'f', 2, kind: AlertKind.hotspot),
    ]);
    expect(all, hasLength(7));
  });

  test('feste Arten untereinander: Blitzer, Rotlicht, Abschnitt', () {
    final r = mergePoints([
      pt('osm:node/1', 'osm', 0, kind: AlertKind.speedCamera),
      pt('plugin:f:1', 'f', 10, kind: AlertKind.redLightCamera),
    ]);
    expect(r.single.kind, AlertKind.speedCamera, reason: 'Art von OSM');
  });

  test(
    'Ende der Abschnittskontrolle und Höhen-/Gewichtskontrollen: nie Dubletten',
    () {
      for (final c in [
        AlertCategory.sectionEnd,
        AlertCategory.heightControl,
        AlertCategory.weightControl,
        AlertCategory.accessControl,
        AlertCategory.noOvertaking,
      ]) {
        final kind = c == AlertCategory.sectionEnd
            ? AlertKind.sectionControl
            : AlertKind.construction;
        final r = mergePoints([
          pt('osm:node/1', 'osm', 0, kind: kind, category: c),
          pt('plugin:f:1', 'f', 5, kind: kind),
        ]);
        expect(r, hasLength(2), reason: '$c');
      }
    },
  );

  test('Kategorie kommt vom Kern', () {
    final r = mergePoints([
      pt('osm:node/1', 'osm', 0, category: AlertCategory.tunnelSpeed),
      pt('plugin:f:1', 'f', 5, category: AlertCategory.fixedSpeed),
    ]);
    expect(r.single.category, AlertCategory.tunnelSpeed);
  });

  test('gleiche Quelle wird nie zusammengeführt', () {
    final r = mergePoints([
      pt('osm:node/1', 'osm', 0),
      pt('osm:node/2', 'osm', 10),
    ]);
    expect(r, hasLength(2));
  });

  group('Fahrtrichtung', () {
    List<AlertPoint> two(List<double> a, List<double> b) => mergePoints([
      pt('osm:node/1', 'osm', 0, bearings: a),
      pt('plugin:f:1', 'f', 10, bearings: b),
    ]);

    test('Gegenrichtung: nicht zusammen', () {
      expect(two([90], [270]), hasLength(2));
      expect(two([90], [250]), hasLength(2));
    });

    test('über 75° Abweichung: nur ganz nah und eindeutig zusammen', () {
      // 10 m und keine weitere OSM-Kamera in der Nähe: Der Unterschied gilt als Angabeunterschied.
      expect(two([90], [166]), hasLength(1));
      expect(two([90], [14]), hasLength(1));
      // Ab 40 m und bei einer zweiten OSM-Kamera daneben gilt die Richtung.
      expect(
        mergePoints([
          pt('osm:node/1', 'osm', 0, bearings: [90]),
          pt('plugin:f:1', 'f', 45, bearings: [166]),
        ]),
        hasLength(2),
      );
      expect(
        mergePoints([
          pt('osm:node/1', 'osm', 0, bearings: [90]),
          pt('osm:node/2', 'osm', 20, bearings: [270]),
          pt('plugin:f:1', 'f', 10, bearings: [166]),
        ]),
        hasLength(3),
      );
    });

    test('bis 75° Abweichung, auch über Nord: zusammen', () {
      expect(two([90], [135]), hasLength(1));
      expect(two([90], [165]), hasLength(1));
      expect(two([350], [50]), hasLength(1));
      expect(two([90, 270], [200]), hasLength(1));
    });

    test('Blickrichtung der Kamera und Straßenachse weichen um 60° ab: derselbe Blitzer', () {
      // OSM 240°, das Plugin kennt die Achse 180°/0°.
      expect(two([240], [180, 0]), hasLength(1));
    });

    test(
      'zwei Blitzer in Gegenrichtung 20 m auseinander bleiben zwei Punkte',
      () {
        final r = mergePoints([
          pt('osm:node/1', 'osm', 0, bearings: [90]),
          pt('plugin:f:1', 'f', 20, bearings: [270]),
        ]);
        expect(r.map((p) => p.id), ['osm:node/1', 'plugin:f:1']);
        // Auch wenn beide Quellen beide Richtungen kennen: je ein Punkt je Richtung.
        final four = mergePoints([
          pt('osm:node/1', 'osm', 0, bearings: [90]),
          pt('osm:node/2', 'osm', 20, bearings: [270]),
          pt('plugin:f:1', 'f', 5, bearings: [95]),
          pt('plugin:f:2', 'f', 25, bearings: [265]),
        ]);
        expect(four.map((p) => p.id), ['osm:node/1', 'osm:node/2']);
        expect(four[0].travelBearings, [90]);
        expect(four[1].travelBearings, [270]);
      },
    );

    test('ein Plugin-Punkt mit beiden Richtungen passt zu nur einem von zwei Gegenrichtungs-Punkten', () {
      final r = mergePoints([
        pt('osm:node/1', 'osm', 0, bearings: [104]),
        pt('osm:node/2', 'osm', 0, bearings: [285]),
        pt('plugin:f:1', 'f', 3, bearings: [175, 355]),
      ]);
      expect(r, hasLength(2));
      expect(r.where((p) => p.sources.length > 1), hasLength(1));
    });

    test('eine Quelle ohne Richtung übernimmt die der anderen', () {
      final r = mergePoints([
        pt('osm:node/1', 'osm', 0, bearings: [90]),
        pt('plugin:f:1', 'f', 15),
      ]);
      expect(r, hasLength(1));
      expect(r.single.travelBearings, [90]);
      final r2 = mergePoints([
        pt('osm:node/1', 'osm', 0),
        pt('plugin:f:1', 'f', 15, bearings: [270]),
      ]);
      expect(r2, hasLength(1));
      expect(r2.single.travelBearings, [270]);
    });

    test('unbekannte Richtung verträgt sich mit jeder', () {
      expect(two([], [270]), hasLength(1));
      expect(two([90], []), hasLength(1));
    });

    test('Richtung: zuerst OSM, fehlt sie dort, die des Plugins', () {
      expect(two([], [90]).single.travelBearings, [90]);
      expect(two([90], [100]).single.travelBearings, [90]);
      expect(two([90], []).single.travelBearings, [90]);
    });
  });

  group('Ergebnis', () {
    test('Kern ist OSM, egal in welcher Reihenfolge; Platz des Kerns', () {
      final r = mergePoints([
        pt('plugin:f:0', 'f', 500),
        pt('plugin:f:1', 'f', 10, label: 'Feed', maxSpeed: 70),
        pt('osm:node/1', 'osm', 0, label: 'OSM'),
      ], sourceName: name);
      expect(r.map((p) => p.id), ['plugin:f:0', 'osm:node/1']);
      final m = r.last;
      expect(m.source, 'osm');
      expect(m.position, pt('x', 'osm', 0).position);
      expect(m.label, 'OSM');
      expect(m.maxSpeed, 70, reason: 'erste vorhandene Angabe');
    });

    test('maxSpeed: die erste Angabe gewinnt', () {
      final r = mergePoints([
        pt('osm:node/1', 'osm', 0, maxSpeed: 50),
        pt('plugin:f:1', 'f', 10, maxSpeed: 70),
      ]);
      expect(r.single.maxSpeed, 50);
    });

    test('Details vereinigt; gleiche Angabe einmal', () {
      final r = mergePoints([
        pt(
          'osm:node/1',
          'osm',
          0,
          details: const [
            PointDetail('Seit', '2020'),
            PointDetail('Straße', 'A'),
          ],
        ),
        pt(
          'plugin:f:1',
          'f',
          10,
          details: const [
            PointDetail('Seit', '2020'),
            PointDetail('Betreiber', 'X'),
          ],
        ),
      ], sourceName: name);
      expect(r.single.details.map((d) => d.toString()), [
        'Seit: 2020',
        'Straße: A',
        'Betreiber: X',
      ]);
    });

    test('gleiches Label, verschiedene Werte: beide bleiben mit Quelle', () {
      final r = mergePoints([
        pt(
          'osm:node/1',
          'osm',
          0,
          details: const [PointDetail('Erlaubt', '50 km/h')],
          sources: const [PointSource(id: 'osm', name: 'OpenStreetMap')],
        ),
        pt(
          'plugin:f:1',
          'f',
          10,
          details: const [PointDetail('Erlaubt', '30 km/h')],
        ),
        pt(
          'plugin:g:1',
          'g',
          12,
          details: const [PointDetail('Erlaubt', '30 km/h')],
        ),
      ], sourceName: name);
      expect(r.single.details.map((d) => d.toString()), [
        'Erlaubt: 50 km/h (OpenStreetMap)',
        'Erlaubt: 30 km/h (Plugin f, Plugin g)',
      ]);
    });

    test('Quellen vereinigt, Plugins ohne Eintrag bekommen einen', () {
      const osm = PointSource(
        id: 'osm',
        name: 'OpenStreetMap',
        attribution: '© OpenStreetMap-Mitwirkende, ODbL',
        url: 'https://www.openstreetmap.org/node/1',
      );
      final r = mergePoints([
        pt('osm:node/1', 'osm', 0, sources: const [osm]),
        pt('plugin:f:1', 'f', 10),
      ], sourceName: name);
      expect(r.single.sources.map((s) => s.id), ['osm', 'f']);
      expect(r.single.sources.first.attribution, contains('ODbL'));
      expect(r.single.sources.last.name, 'Plugin f');
    });

    test('ohne Treffer bleibt alles unverändert', () {
      final list = [pt('osm:node/1', 'osm', 0), pt('plugin:f:1', 'f', 500)];
      expect(mergePoints(list), orderedEquals(list));
      final single = [pt('osm:node/1', 'osm', 0)];
      expect(identical(mergePoints(single), single), isTrue);
    });

    test('Kette: nur Punkte nahe am Kern, nicht nahe am Nachbarn', () {
      final r = mergePoints([
        pt('osm:node/1', 'osm', 0),
        pt('plugin:f:1', 'f', 30),
        pt('plugin:g:1', 'g', 130),
      ]);
      expect(r.map((p) => p.id), ['osm:node/1', 'plugin:g:1']);
    });
  });

  group('Vorrang und nichts geht verloren', () {
    test('OSM vor Plugin bei Position, Art, Kategorie, Richtung und Tempo', () {
      final osm = pt(
        'osm:node/1',
        'osm',
        0,
        kind: AlertKind.redLightCamera,
        category: AlertCategory.fixedRedLight,
        bearings: [90],
        maxSpeed: 50,
      );
      final plugin = AlertPoint(
        id: 'plugin:f:1',
        kind: AlertKind.speedCamera,
        category: AlertCategory.fixedSpeed,
        position: pt('x', 'f', 20).position,
        source: 'f',
        travelBearings: const [100],
        maxSpeed: 70,
      );
      final r = mergePoints([plugin, osm]).single;
      expect(r.id, 'osm:node/1');
      expect(
        r.kind,
        AlertKind.speedCamera == r.kind ? r.kind : AlertKind.redLightCamera,
      );
      expect(r.kind, AlertKind.redLightCamera);
      expect(r.category, AlertCategory.fixedRedLight);
      expect(r.position, osm.position);
      expect(r.travelBearings, [90]);
      expect(r.maxSpeed, 50);
    });

    test('fehlt bei OSM Tempo oder Kategorie, füllt das Plugin auf', () {
      final r = mergePoints([
        pt('osm:node/1', 'osm', 0),
        pt(
          'plugin:f:1',
          'f',
          10,
          maxSpeed: 60,
          category: AlertCategory.tunnelSpeed,
        ),
      ]).single;
      expect(r.maxSpeed, 60);
      expect(r.category, AlertCategory.tunnelSpeed);
    });

    test('zwei OSM-Blitzer nah beieinander bleiben zwei, das Plugin geht an den näheren', () {
      final r = mergePoints([
        pt('osm:node/1', 'osm', 0),
        pt('osm:node/2', 'osm', 25),
        pt('plugin:f:1', 'f', 20, label: 'Feed'),
      ]);
      expect(r.map((p) => p.id), ['osm:node/1', 'osm:node/2']);
      expect(
        r.last.label,
        'Feed',
        reason: 'näher an node/2 (5 m) als an node/1',
      );
      expect(r.first.label, isNull);
    });

    test(
      'Gegenrichtungen bleiben getrennt, das Plugin geht an die passende',
      () {
        final r = mergePoints([
          pt('osm:node/1', 'osm', 0, bearings: [90]),
          pt('osm:node/2', 'osm', 8, bearings: [270]),
          pt('plugin:f:1', 'f', 4, bearings: [265], label: 'West'),
        ]);
        expect(r.map((p) => p.id), ['osm:node/1', 'osm:node/2']);
        expect(r.last.label, 'West');
      },
    );

    test(
      'mehrere Punkte einer anderen Quelle: nur der nächste wird aufgenommen',
      () {
        final r = mergePoints([
          pt('osm:node/1', 'osm', 0),
          pt('plugin:f:near', 'f', 5),
          pt('plugin:f:far', 'f', 30),
        ]);
        expect(r.map((p) => p.id), ['osm:node/1', 'plugin:f:far']);
      },
    );

    test('drei Quellen an einer Stelle: ein Punkt mit allen Quellen', () {
      final r = mergePoints([
        pt('plugin:g:1', 'g', 6),
        pt('osm:node/1', 'osm', 0),
        pt('plugin:f:1', 'f', 3),
      ], sourceName: name);
      expect(r, hasLength(1));
      expect(r.single.id, 'osm:node/1');
      expect(r.single.sources.map((s) => s.id).toSet(), {'osm', 'f', 'g'});
    });

    test('ohne OSM gewinnt die erste Plugin-Quelle', () {
      final r = mergePoints([
        pt('plugin:f:1', 'f', 0, maxSpeed: 30),
        pt('plugin:g:1', 'g', 10, maxSpeed: 50),
      ]).single;
      expect(r.id, 'plugin:f:1');
      expect(r.maxSpeed, 30);
    });

    test(
      'Zufallstest: jede Quelle behält ihre Punkte als getrennte Punkte',
      () {
        final rnd = math.Random(7);
        for (var round = 0; round < 40; round++) {
          final pts = [
            for (var i = 0; i < 60; i++)
              pt(
                'p$i',
                ['osm', 'a', 'b'][rnd.nextInt(3)],
                rnd.nextDouble() * 300,
                kind: [
                  AlertKind.speedCamera,
                  AlertKind.live,
                  AlertKind.construction,
                ][rnd.nextInt(3)],
                bearings: rnd.nextBool()
                    ? [rnd.nextInt(360).toDouble()]
                    : const [],
              ),
          ];
          final out = mergePoints(pts);
          final perSource = <String, int>{};
          for (final p in pts) {
            perSource.update(p.source, (n) => n + 1, ifAbsent: () => 1);
          }
          // Gleiche Quelle wird nie zusammengelegt: so viele Ausgabepunkte wie die größte Quelle hat.
          expect(
            out.length,
            greaterThanOrEqualTo(perSource.values.reduce(math.max)),
          );
          expect(out.length, lessThanOrEqualTo(pts.length));
          expect(out.map((p) => p.id).toSet(), hasLength(out.length));
          expect(out.every((o) => pts.any((p) => p.id == o.id)), isTrue);
        }
      },
    );
  });

  group('Repository und Hotspots', () {
    late FakeOsm osm;
    late FakePlugin plugin;
    late AlertRepositoryImpl repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'plugin.feed.enabled': true});
      osm = FakeOsm();
      plugin = FakePlugin('feed');
      repo = AlertRepositoryImpl(
        osm: osm,
        hotspots: FakeHotspots(),
        plugins: [plugin],
        prefs: await SharedPreferences.getInstance(),
        clock: () => DateTime(2026, 1, 1, 12),
      );
    });

    tearDown(() => repo.dispose());

    test(
      'derselbe Blitzer aus OSM und Plugin: ein Punkt mit allen Angaben',
      () async {
        const center = GeoPoint(52.0, 13.0);
        osm.result = SourceResult(
          points: [
            pt(
              'osm:node/1',
              'osm',
              0,
              details: const [PointDetail('Seit', '2020')],
              sources: const [PointSource(id: 'osm', name: 'OpenStreetMap')],
            ),
          ],
        );
        plugin.onFetch = (_) async => [
          pt(
            'plugin:feed:9',
            'feed',
            15,
            maxSpeed: 60,
            details: const [PointDetail('Meldungen', '3')],
          ),
        ];
        repo.pointsAround(center);
        await pumpEventQueue();

        final around = repo.pointsAround(center);
        expect(
          around,
          hasLength(1),
          reason: 'kein Doppelpunkt für die Warnlogik',
        );
        final p = around.single;
        expect(p.id, 'osm:node/1');
        expect(p.maxSpeed, 60);
        expect(p.details.map((d) => d.label), ['Seit', 'Meldungen']);
        expect(p.sources.map((s) => s.name), ['OpenStreetMap', 'Plugin feed']);

        final view = GeoBounds(
          south: 51.9,
          west: 12.9,
          north: 52.1,
          east: 13.1,
        );
        expect(repo.pointsInView(view), hasLength(1));
      },
    );

    test('Hotspots bleiben eigene Punkte neben dem Blitzer', () async {
      // Ohne Hotspot-Eintrag nur der Blitzer; die Zusammenführung greift Hotspots nie an.
      final r = mergePoints([
        pt('osm:node/1', 'osm', 0),
        pt('hotspot:1', 'hotspot', 5, kind: AlertKind.hotspot),
      ]);
      expect(r, hasLength(2));
    });
  });
}
