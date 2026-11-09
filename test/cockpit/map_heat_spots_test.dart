import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sonarb/app/services.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/core/model/heat_spot.dart';
import 'package:sonarb/features/cockpit/map_heat_spots.dart';
import 'package:sonarb/features/warning/heat_spots.dart';

final _now = DateTime.utc(2026, 11, 2, 12);
const _center = GeoPoint(52.5160, 13.4540);

AlertPoint _seen(GeoPoint pos, String id, int ageDays) => AlertPoint(
  id: id,
  kind: AlertKind.live,
  position: pos,
  source: 'verlauf',
  category: AlertCategory.mobileSpeed,
  observedAt: _now.subtract(Duration(days: ageDays)),
  historical: true,
);

/// Fünf Meldungen an derselben Stelle: ein Hotspot in jeder Stufe.
List<AlertPoint> _cluster(GeoPoint at, String prefix) => [
  for (var i = 0; i < 5; i++)
    _seen(destinationPoint(at, 90, i * 20.0), '$prefix$i', 10 + i),
];

Future<void> _pumpMap(WidgetTester tester, List<AlertPoint> spots) =>
    tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(52.5160, 13.4540),
              initialZoom: 16,
            ),
            children: [HeatSpotLayer(spots: spots)],
          ),
        ),
      ),
    );

List<Offset> _drawn(WidgetTester tester) {
  final paints = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<HeatSpotPainter>()
      .toList();
  return paints.isEmpty ? const [] : paints.single.centers;
}

void main() {
  for (final n in heatSpotReportChoices) {
    test('Stufe ab $n: Karte bekommt dieselben Hotspots wie die Warnlogik', () {
      final points = [
        ..._cluster(_center, 'a'),
        ..._cluster(destinationPoint(_center, 0, 2000), 'b'),
        // Zwei Meldungen: Hotspot nur bis Stufe 2.
        _seen(destinationPoint(_center, 180, 2000), 'c0', 5),
        _seen(destinationPoint(_center, 180, 2010), 'c1', 6),
        // Eine einzelne alte Meldung: nur bei „Jede gemeldete Stelle“.
        _seen(destinationPoint(_center, 270, 2000), 'd0', 700),
      ];
      final map = createHeatSpotFinder(minReports: () => n)(points, _now);
      final warning = findHeatSpots(points, _now, minReports: n);
      expect(map.map((s) => s.id), warning.map((s) => s.id));
      expect(
        map,
        hasLength(switch (n) {
          1 => 4,
          2 => 3,
          _ => 2,
        }),
      );
      expect(map.every(isHeatSpot), isTrue);
    });
  }

  test('Stufe wechselt: die Karte folgt sofort', () {
    var n = 1;
    final finder = createHeatSpotFinder(minReports: () => n);
    final points = [_seen(_center, 'e0', 3)];
    expect(finder(points, _now), hasLength(1));
    n = 2;
    expect(finder(points, _now), isEmpty);
  });

  test('ohne Warnlogik (Tests) keine Hotspots', () {
    expect(noHeatSpots(_cluster(_center, 'a'), _now), isEmpty);
  });

  testWidgets('Ring an jedem Hotspot im Ausschnitt', (tester) async {
    final spots = findHeatSpots([
      ..._cluster(_center, 'a'),
      // Weit draußen, außerhalb des Ausschnitts.
      ..._cluster(destinationPoint(_center, 90, 5000), 'b'),
    ], _now);
    expect(spots, hasLength(2));
    await _pumpMap(tester, spots);
    final centers = _drawn(tester);
    expect(centers, hasLength(1));
    // Mitte des Ausschnitts, auf wenige Bildpunkte genau.
    final mid = tester.getSize(find.byType(FlutterMap)).center(Offset.zero);
    expect((centers.single - mid).distance, lessThan(30));
  });

  testWidgets('ohne Hotspots wird nichts gezeichnet', (tester) async {
    await _pumpMap(tester, const []);
    expect(_drawn(tester), isEmpty);
  });

  test('zeichnet nur neu, wenn sich die Lage ändert', () {
    final a = HeatSpotPainter(const [Offset(1, 2)]);
    expect(a.shouldRepaint(HeatSpotPainter(const [Offset(1, 2)])), isFalse);
    expect(a.shouldRepaint(HeatSpotPainter(const [Offset(1, 3)])), isTrue);
  });
}
