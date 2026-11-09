import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/map_layer_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_map.dart';
import 'package:sonarb/features/cockpit/symbols/category_symbol.dart';
import 'package:sonarb/features/cockpit/map_point_layers.dart';

import 'fakes.dart';

final _flat = find.byWidgetPredicate((w) => w is CategorySymbol && !w.upright);

const _mobile = AlertPoint(
  id: 'hotspot:m',
  kind: AlertKind.hotspot,
  position: GeoPoint(52.5, 13.4),
  source: 'hotspot',
  reportKind: HotspotKind.mobileCamera,
);

const _work = AlertPoint(
  id: 'hotspot:w',
  kind: AlertKind.hotspot,
  position: GeoPoint(52.5003, 13.4003),
  source: 'hotspot',
  reportKind: HotspotKind.construction,
);

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  Future<ProviderContainer> pumpMap(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: rig.overrides,
        child: MaterialApp(
          theme: buildSonarTheme(),
          home: const Scaffold(body: DriveMap()),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DriveMap)),
    );
    await container.read(driveControllerProvider.notifier).start();
    await tester.pump();
    rig.location.emit(fixAt(52.5, 13.4, speedKmh: 50));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    return container;
  }

  testWidgets('mitführend: Punkte rund um die Position, kein Ausschnitt', (
    tester,
  ) async {
    rig.alerts.points = [_mobile];
    await pumpMap(tester);
    expect(rig.alerts.pointCalls, isNotEmpty);
    expect(rig.alerts.viewCalls, isEmpty);
    expect(find.text('Zentrieren'), findsNothing);
  });

  testWidgets(
    'nach einer Geste endet das Mitführen, der Ausschnitt wird abgefragt',
    (tester) async {
      rig.alerts.points = [_mobile];
      await pumpMap(tester);

      await tester.drag(find.byType(DriveMap), const Offset(-120, 40));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Zentrieren'), findsOneWidget);
      // Entprellt: erst nach der Pause, nicht bei jeder Bewegung.
      expect(rig.alerts.viewCalls, isEmpty);

      await tester.pump(const Duration(milliseconds: 500));
      expect(rig.alerts.viewCalls, hasLength(1));
      final view = rig.alerts.viewCalls.single;
      expect(view.north, greaterThan(view.south));
      expect(view.east, greaterThan(view.west));
    },
  );

  testWidgets('Zentrieren springt zurück ins Mitführen', (tester) async {
    await pumpMap(tester);
    await tester.drag(find.byType(DriveMap), const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 600));
    final calls = rig.alerts.viewCalls.length;

    await tester.tap(find.text('Zentrieren'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Zentrieren'), findsNothing);
    expect(
      rig.alerts.viewCalls.length,
      calls,
      reason: 'Mitführen fragt keinen Ausschnitt ab',
    );
  });

  testWidgets(
    'neue Daten melden sich über changes und erscheinen auf der Karte',
    (tester) async {
      rig.alerts.points = const [];
      await pumpMap(tester);
      expect(_flat, findsNothing);

      rig.alerts.points = [_mobile, _work];
      rig.alerts.changesController.add(null);
      await tester.pump();
      await tester.pump();
      // Nah (Zoom 15,5): Fleck, Symbol der Meldung und Baustelle.
      expect(_flat, findsNWidgets(2));
      final heat = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<HeatPainter>()
          .single;
      expect(heat.spots, hasLength(1));
    },
  );

  testWidgets('Ebene ausschalten blendet Symbole und Flecken aus', (
    tester,
  ) async {
    rig.alerts.points = [_mobile, _work];
    final container = await pumpMap(tester);
    rig.alerts.changesController.add(null);
    await tester.pump();
    await tester.pump();
    expect(_flat, findsNWidgets(2));

    await container.read(mapLayersProvider.notifier).toggle(MapLayer.mobile);
    await tester.pump();
    expect(_flat, findsOneWidget);
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<HeatPainter>(),
      isEmpty,
    );

    await container
        .read(mapLayersProvider.notifier)
        .toggle(MapLayer.construction);
    await tester.pump();
    expect(_flat, findsNothing);
  });

  testWidgets(
    'Übersicht: während der Ausschnitt lädt, bleiben die Symbole stehen',
    (tester) async {
      // Feste Blitzer aus OSM (eigene Hotspots liegen immer vollständig vor).
      rig.alerts.points = const [
        AlertPoint(
          id: 'osm:node/1',
          kind: AlertKind.speedCamera,
          position: GeoPoint(52.5, 13.4),
          source: 'osm',
        ),
        AlertPoint(
          id: 'osm:node/2',
          kind: AlertKind.redLightCamera,
          position: GeoPoint(52.502, 13.403),
          source: 'osm',
        ),
      ];
      await pumpMap(tester);
      await tester.drag(find.byType(DriveMap), const Offset(-30, 20));
      await tester.pump(const Duration(milliseconds: 600));
      final before = tester.widgetList(_flat).length;
      expect(before, 2);

      // Neue Abfrage liefert noch nichts, der Ausschnitt lädt: nichts verschwindet.
      rig.alerts.points = const [];
      rig.alerts.viewCoverage = DataCoverage.loading;
      // Länger als die Mindeststrecke einer Geste.
      await tester.drag(find.byType(DriveMap), const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(rig.alerts.viewCalls.length, greaterThanOrEqualTo(2));
      expect(tester.widgetList(_flat).length, before);

      // Fertig geladen: jetzt gilt die Antwort der Quelle.
      rig.alerts.viewCoverage = DataCoverage.ready;
      rig.alerts.changesController.add(null);
      await tester.pump();
      await tester.pump();
      expect(_flat, findsNothing);
    },
  );

  test('gelöschte eigene Hotspots bleiben auch beim Laden nicht stehen', () {
    const view = GeoBounds(south: 52, west: 13, north: 53, east: 14);
    const osm = AlertPoint(
      id: 'osm:node/5',
      kind: AlertKind.speedCamera,
      position: GeoPoint(52.5, 13.5),
      source: 'osm',
    );
    final kept = keepWhileLoading(
      previous: const [_mobile, osm],
      next: const [],
      view: view,
      ready: false,
    );
    expect(kept, [osm]);
    expect(
      keepWhileLoading(
        previous: const [osm],
        next: const [],
        view: view,
        ready: true,
      ),
      isEmpty,
    );
  });
}
