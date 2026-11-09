import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/map_layer_settings.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/map_layers.dart';

AlertPoint point(
  AlertKind kind, {
  double lat = 52.5,
  double lon = 13.4,
  HotspotKind? report,
  double? radius,
}) => AlertPoint(
  id: '$kind/$lat/$lon/$report',
  kind: kind,
  position: GeoPoint(lat, lon),
  source: 'test',
  reportKind: report,
  radiusMeters: radius,
);

void main() {
  test('jeder Punkt gehört zu genau einer Ebene', () {
    expect(layerOf(point(AlertKind.speedCamera)), MapLayer.fixedCameras);
    expect(layerOf(point(AlertKind.redLightCamera)), MapLayer.fixedCameras);
    expect(layerOf(point(AlertKind.sectionControl)), MapLayer.fixedCameras);
    expect(layerOf(point(AlertKind.trafficSignal)), MapLayer.signals);
    expect(layerOf(point(AlertKind.live)), MapLayer.mobile);
    expect(layerOf(point(AlertKind.construction)), MapLayer.construction);
    final hotspot = {
      HotspotKind.mobileCamera: MapLayer.mobile,
      HotspotKind.distanceCheck: MapLayer.mobile,
      HotspotKind.construction: MapLayer.construction,
      HotspotKind.danger: MapLayer.danger,
      HotspotKind.other: MapLayer.danger,
      // Ohne Art gilt die Standardart beim Melden: mobiler Blitzer (`defaultCategory`).
      null: MapLayer.mobile,
    };
    hotspot.forEach((kind, layer) {
      expect(layerOf(point(AlertKind.hotspot, report: kind)), layer);
    });
  });

  group('Symbole', () {
    final all = [
      point(AlertKind.speedCamera, lat: 52.50),
      point(AlertKind.trafficSignal, lat: 52.51),
      point(AlertKind.construction, lat: 52.52),
      point(AlertKind.hotspot, lat: 52.53, report: HotspotKind.danger),
      point(AlertKind.hotspot, lat: 52.54, report: HotspotKind.mobileCamera),
    ];

    List<AlertKind> kinds(Set<MapLayer> on, double zoom) => [
      for (final p in markerPoints(all, on, zoom)) p.kind,
    ];

    test('feste Blitzer stehen in jeder Zoomstufe da', () {
      for (final zoom in [3.0, 8.0, 12.0, 17.0]) {
        expect(kinds({MapLayer.fixedCameras}, zoom), [AlertKind.speedCamera]);
      }
    });

    test('ausgeschaltete Ebenen verschwinden von der Karte', () {
      expect(kinds({}, 16), isEmpty);
      expect(kinds({MapLayer.construction}, 16), [AlertKind.construction]);
      expect(kinds({MapLayer.danger}, 16), [AlertKind.hotspot]);
    });

    test('Ampeln erst ab Zoom 15', () {
      expect(kinds({MapLayer.signals}, 14.9), isEmpty);
      expect(kinds({MapLayer.signals}, 15), [AlertKind.trafficSignal]);
    });

    test('mobile Blitzer stehen in jeder Zoomstufe als Symbol da', () {
      for (final zoom in [6.0, 10.0, 13.0, 17.0]) {
        expect(kinds({MapLayer.mobile}, zoom), [AlertKind.hotspot]);
      }
    });

    test('Standard: alles außer Ampeln', () {
      expect(defaultMapLayers, isNot(contains(MapLayer.signals)));
      expect(defaultMapLayers.length, MapLayer.values.length - 1);
    });
  });

  group('Wärme', () {
    test('nur mobile Blitzer, Abstandsmessungen und Live-Punkte', () {
      final all = [
        point(AlertKind.hotspot, report: HotspotKind.mobileCamera),
        point(AlertKind.hotspot, report: HotspotKind.distanceCheck),
        point(AlertKind.live),
        point(AlertKind.speedCamera),
        point(AlertKind.construction),
        point(AlertKind.hotspot, report: HotspotKind.danger),
      ];
      expect(heatPoints(all, {MapLayer.mobile}).length, 3);
      expect(heatPoints(all, {MapLayer.fixedCameras}), isEmpty);
    });

    test('Meter je Bildpunkt halbiert sich mit jeder Zoomstufe', () {
      final z10 = metersPerPixel(52.5, 10);
      expect(metersPerPixel(52.5, 11), closeTo(z10 / 2, 0.001));
      expect(metersPerPixel(0, 0), closeTo(156543.03, 0.1));
      expect(metersPerPixel(60, 5), closeTo(metersPerPixel(0, 5) / 2, 0.5));
    });
  });

  test('Fleck wird ganz nah schwächer, aber nie unsichtbar', () {
    expect(heatStrengthForZoom(10), 1);
    expect(heatStrengthForZoom(16), 1);
    expect(heatStrengthForZoom(17), closeTo(0.75, 0.001));
    expect(heatStrengthForZoom(18), closeTo(0.5, 0.001));
    expect(heatStrengthForZoom(22), 0.25);
  });

  test('Symbolgröße wächst mit dem Zoom, nie unter 16 und nie über 26', () {
    expect(markerSizeForZoom(2), markerMinSize);
    expect(markerSizeForZoom(8), markerMinSize);
    expect(markerMinSize, 16);
    expect(markerSizeForZoom(12), greaterThan(markerSizeForZoom(9)));
    expect(markerSizeForZoom(20), 26);
  });
}
