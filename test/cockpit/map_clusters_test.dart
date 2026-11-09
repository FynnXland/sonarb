import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/map_layer_settings.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/map_clusters.dart';

/// Länge um [meters] nach Osten verschoben (Berlin, 52,5° Nord).
double _east(double meters) => 13.4 + meters / 67800;

AlertPoint _p(
  String id, {
  double lon = 13.4,
  double lat = 52.5,
  AlertKind kind = AlertKind.speedCamera,
  AlertCategory? category,
  HotspotKind? report,
}) => AlertPoint(
  id: id,
  kind: kind,
  position: GeoPoint(lat, lon),
  source: 'test',
  category: category,
  reportKind: report,
);

const _all = {
  MapLayer.fixedCameras,
  MapLayer.mobile,
  MapLayer.construction,
  MapLayer.danger,
  MapLayer.signals,
};

int _members(List<MarkerGroup> groups) => groups.fold(0, (n, g) => n + g.count);

void main() {
  test('zwei feste Blitzer: in keiner Zoomstufe geht einer verloren', () {
    for (final meters in [5.0, 30.0, 100.0]) {
      final a = _p('a');
      final b = _p('b', lon: _east(meters));
      for (var zoom = 8; zoom <= 18; zoom++) {
        for (final z in [zoom.toDouble(), zoom + 0.5]) {
          final groups = clusterPoints([a, b], _all, z);
          final why = '$meters m bei Zoom $z';
          expect(groups, isNotEmpty, reason: why);
          expect(_members(groups), 2, reason: why);
          // Entweder beide einzeln oder ein Bündel mit Zahl 2.
          expect(
            groups.length == 2 || groups.single.count == 2,
            isTrue,
            reason: why,
          );
        }
      }
    }
  });

  test('100 m auseinander stehen nah beide einzeln', () {
    final groups = clusterPoints([_p('a'), _p('b', lon: _east(100))], _all, 17);
    expect(groups, hasLength(2));
  });

  test(
    'Ende und Anfang einer Abschnittskontrolle am selben Ort: ein Bündel mit 2',
    () {
      final end = _p(
        'end',
        kind: AlertKind.sectionControl,
        category: AlertCategory.sectionEnd,
      );
      final start = _p(
        'start',
        kind: AlertKind.sectionControl,
        category: AlertCategory.sectionStart,
      );
      for (var zoom = 8; zoom <= 18; zoom++) {
        final g = clusterPoints([end, start], _all, zoom.toDouble());
        expect(g.single.count, 2);
        // Anfang vor Ende (Reihenfolge der Arten), unabhängig von der Liefer-Reihenfolge.
        expect(g.single.lead.id, 'start');
      }
    },
  );

  test('verschiedene Ebenen am selben Ort stehen nebeneinander', () {
    final camera = _p('camera');
    final work = _p('work', kind: AlertKind.construction);
    final groups = clusterPoints([camera, work], _all, 14);
    expect(groups, hasLength(2));
    final spreads = [for (final g in groups) g.spread]..sort();
    expect(spreads, [-0.5, 0.5]);
  });

  test('stabil: gleiche Bündel bei anderer Reihenfolge und innerhalb einer Zoomstufe', () {
    final points = [
      for (var i = 0; i < 40; i++)
        _p('p$i', lon: _east(i * 37.0), lat: 52.5 + (i % 5) * 0.0004),
    ];
    String key(List<MarkerGroup> gs) =>
        [for (final g in gs) '${g.lead.id}:${g.count}'].join(',');
    final base = key(clusterPoints(points, _all, 13.1));
    expect(key(clusterPoints(points.reversed.toList(), _all, 13.1)), base);
    expect(key(clusterPoints(points, _all, 13.9)), base);
    expect(key(clusterPoints(points, _all, 13.0)), base);
  });

  test('viele Punkte: weniger Symbole, aber jeder zählt mit', () {
    final many = [
      for (var i = 0; i < 2000; i++) _p('m$i', lat: 52 + i * 0.00001, lon: 13),
    ];
    final groups = clusterPoints(many, _all, 10);
    expect(groups.length, lessThan(30));
    expect(_members(groups), 2000);
  });

  test('Ampeln erst nah, alles andere in jeder Zoomstufe', () {
    final signal = _p('s', kind: AlertKind.trafficSignal);
    final mobile = _p(
      'm',
      kind: AlertKind.hotspot,
      report: HotspotKind.mobileCamera,
      lon: _east(900),
    );
    expect(clusterPoints([signal, mobile], _all, 9).single.lead, mobile);
    expect(clusterPoints([signal, mobile], _all, 16), hasLength(2));
  });

  test('Raster hängt nicht am Ausschnitt: Weltbildpunkte je Zoomstufe', () {
    const g = GeoPoint(52.5, 13.4);
    final z10 = worldPixel(g, 10);
    final z11 = worldPixel(g, 11);
    expect(z11.dx, closeTo(z10.dx * 2, 0.001));
    expect(z11.dy, closeTo(z10.dy * 2, 0.001));
    expect(worldPixel(const GeoPoint(0, 0), 0).dx, closeTo(128, 0.001));
  });
}
