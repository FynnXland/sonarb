import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sonarb/app/map_layer_settings.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/map_heat.dart';
import 'package:sonarb/features/cockpit/map_layers.dart';
import 'package:sonarb/features/cockpit/symbols/category_symbol.dart';
import 'package:sonarb/features/cockpit/map_point_layers.dart';

final _flat = find.byWidgetPredicate((w) => w is CategorySymbol && !w.upright);

AlertPoint _p(
  AlertKind kind, {
  double lon = 13.4,
  HotspotKind? report,
  String? id,
}) => AlertPoint(
  id: id ?? '$kind/$lon/$report',
  kind: kind,
  position: GeoPoint(52.5, lon),
  source: 'test',
  reportKind: report,
);

final _now = DateTime(2026, 10, 30);

void main() {
  group('Ebenen auf der Karte', () {
    Future<void> pumpMap(
      WidgetTester tester,
      List<AlertPoint> points,
      Set<MapLayer> layers,
      double zoom,
    ) async {
      tester.view.physicalSize = const Size(360, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 360,
            height: 400,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(52.5, 13.4),
                initialZoom: zoom,
              ),
              children: [
                HeatLayer(cells: heatCells(heatPoints(points, layers), _now)),
                MapPointLayer(points: points, layers: layers),
              ],
            ),
          ),
        ),
      );
    }

    List<HeatSpot> spots(WidgetTester tester) {
      final paint = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      for (final p in paint) {
        final painter = p.painter;
        if (painter is HeatPainter) return painter.spots;
      }
      return const [];
    }

    final mobile = _p(AlertKind.hotspot, report: HotspotKind.mobileCamera);
    final second = _p(
      AlertKind.hotspot,
      lon: 13.4005,
      report: HotspotKind.distanceCheck,
    );

    testWidgets('Flecken für mobile Blitzer, auch weit herausgezoomt', (
      tester,
    ) async {
      await pumpMap(tester, [mobile, second], {MapLayer.mobile}, 6);
      final s = spots(tester);
      // 35 m auseinander: ein Zählkreis, ein Fleck mit zwei Beobachtungen.
      expect(s.length, 1);
      for (final spot in s) {
        expect(spot.radius, heatMinRadiusPx);
      }
      // Über den Flecken steht das Symbol, beide nah beieinander als Bündel mit Zahl.
      expect(_flat, findsOneWidget);
      expect(find.byType(ClusterBadge), findsOneWidget);
    });

    testWidgets('nah wächst der Fleck mit dem Zoom auf 360 m', (tester) async {
      await pumpMap(tester, [mobile], {MapLayer.mobile}, 15);
      final r = spots(tester).single.radius;
      // 360 m bei Zoom 15 in Berlin: 2,9 m je Bildpunkt, also rund 124 Bildpunkte.
      expect(r, closeTo(123.8, 2));
      expect(_flat, findsOneWidget);
    });

    testWidgets('ganz nah bleibt der Fleck begrenzt und blasser', (
      tester,
    ) async {
      await pumpMap(tester, [mobile], {MapLayer.mobile}, 19);
      final spot = spots(tester).single;
      expect(spot.radius, heatMaxRadiusPx);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<HeatPainter>()
          .single;
      expect(painter.strength, closeTo(0.25, 0.001));
    });

    testWidgets('Fleck weg, wenn die Ebene aus ist', (tester) async {
      await pumpMap(tester, [mobile], {MapLayer.fixedCameras}, 12);
      expect(spots(tester), isEmpty);
    });

    testWidgets(
      'feste Blitzer: ein Symbol je Stelle, nah beieinander gebündelt',
      (tester) async {
        final a = _p(AlertKind.speedCamera, lon: 13.4000);
        final b = _p(AlertKind.speedCamera, lon: 13.4001);
        final far = _p(AlertKind.speedCamera, lon: 13.6);
        await pumpMap(tester, [a, b, far], {MapLayer.fixedCameras}, 7);
        // Bei Zoom 7 liegen a und b im selben Bildpunkt, far ist 0,2 Grad weiter (ca. 40 px).
        expect(_flat, findsNWidgets(2));
      },
    );

    testWidgets('Marker sitzt mit dem Bodenpunkt auf dem Ort', (tester) async {
      final camera = _p(AlertKind.speedCamera);
      final work = _p(AlertKind.construction);
      for (final (point, layer) in [
        (camera, MapLayer.fixedCameras),
        (work, MapLayer.construction),
      ]) {
        await pumpMap(tester, [point], {layer}, 15);
        final symbol = tester.widget<CategorySymbol>(_flat);
        final l = categorySymbolLayout(symbol.category, size: symbol.size);
        final rect = tester.getRect(_flat);
        // Die Karte steht mittig auf dem Punkt: 360 × 400.
        expect(rect.left + l.ground.dx, closeTo(180, 0.5));
        expect(rect.top + l.ground.dy, closeTo(200, 0.5));
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Ampeln erst nah', (tester) async {
      final signal = _p(AlertKind.trafficSignal);
      await pumpMap(tester, [signal], {MapLayer.signals}, 14);
      expect(_flat, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pumpMap(tester, [signal], {MapLayer.signals}, 16);
      expect(_flat, findsOneWidget);
    });

    testWidgets('weit draußen: feste Mindestgröße, nichts blendet aus', (
      tester,
    ) async {
      final points = [
        for (var i = 0; i < 6; i++)
          _p(AlertKind.speedCamera, lon: 13.4 + i * 0.3, id: 'c$i'),
      ];
      for (final zoom in [4.0, 6.0, 8.0, 10.0]) {
        await pumpMap(tester, points, {MapLayer.fixedCameras}, zoom);
        final symbols = tester.widgetList<CategorySymbol>(_flat).toList();
        expect(symbols, isNotEmpty, reason: 'Zoom $zoom');
        for (final s in symbols) {
          expect(s.size, markerMinSize, reason: 'Zoom $zoom');
        }
        // Bei Zoom 4 liegen alle in einem Bündel, das alle sechs zählt.
        if (zoom == 4) {
          final group = tester.widget<GroupSymbol>(find.byType(GroupSymbol));
          expect(group.group.count, points.length);
        }
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('zwei Blitzer 5 m auseinander: ein Bündel mit der Zahl 2', (
      tester,
    ) async {
      final a = _p(AlertKind.speedCamera, id: 'a');
      final b = _p(AlertKind.speedCamera, lon: 13.40007, id: 'b');
      for (final zoom in [8.0, 12.0, 15.0, 18.0]) {
        await pumpMap(tester, [a, b], {MapLayer.fixedCameras}, zoom);
        expect(_flat, findsOneWidget, reason: 'Zoom $zoom');
        expect(find.text('2'), findsOneWidget, reason: 'Zoom $zoom');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
