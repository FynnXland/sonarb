import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/heat_sheet.dart';
import 'package:sonarb/features/cockpit/map_heat.dart';
import 'package:sonarb/features/cockpit/map_heat_dots.dart';
import 'package:sonarb/features/cockpit/point_hits.dart';

final _now = DateTime(2026, 10, 30);

/// Vergangene Beobachtung [meters] östlich von 52,5 / 13,4.
AlertPoint _obs(
  String id, {
  double meters = 0,
  DateTime? at,
  bool historical = true,
}) => AlertPoint(
  id: id,
  kind: AlertKind.live,
  position: GeoPoint(52.5, 13.4 + meters / 67800),
  source: 'plugin:x',
  observedAt: at ?? DateTime(2026, 8, 12),
  historical: historical,
);

MapCamera _cameraAt(double zoom) => MapCamera(
  crs: const Epsg3857(),
  center: const LatLng(52.5, 13.4),
  zoom: zoom,
  rotation: 0,
  nonRotatedSize: const Size(360, 640),
);

void main() {
  group('rote Punkte', () {
    test('erst ab Zoom 14, einen halben Zoom davor blenden sie ein', () {
      expect(heatDotFade(13), 0);
      expect(heatDotFade(13.75), closeTo(0.5, 1e-9));
      expect(heatDotFade(heatDotMinZoom), 1);
      expect(heatDots([_obs('a')], _cameraAt(13)), isEmpty);
      expect(heatDots([_obs('a')], _cameraAt(15)), hasLength(1));
    });

    test('nur vergangene Beobachtungen; aktuelle haben ihr Symbol', () {
      final dots = heatDots([
        _obs('alt'),
        _obs('jetzt', meters: 200, historical: false),
      ], _cameraAt(16));
      expect([for (final d in dots) d.point.id], ['alt']);
    });

    test('dicht beieinander ein Punkt, damit nichts verklumpt', () {
      final camera = _cameraAt(15);
      final same = heatDots([
        for (var i = 0; i < 20; i++) _obs('s$i', meters: i * 0.1),
      ], camera);
      expect(same, hasLength(1));
      final apart = heatDots([
        for (var i = 0; i < 5; i++) _obs('a$i', meters: i * 100),
      ], camera);
      expect(apart, hasLength(5));
    });

    test('Tippfläche 48 dp, auch wenn der Punkt klein gezeichnet ist', () {
      expect(heatDotRadius * 2, lessThan(minTapSize));
      final dots = heatDots([_obs('a')], _cameraAt(16));
      final at = dots.single.center;
      expect(heatDotAt(dots, at + const Offset(23, 0)), isNotNull);
      expect(heatDotAt(dots, at + const Offset(0, -23)), isNotNull);
      expect(heatDotAt(dots, at + const Offset(30, 0)), isNull);
    });

    test('Fahrt: kleiner und blasser', () {
      expect(heatDotRadiusDriving, lessThan(heatDotRadius));
      expect(heatDotAlphaDriving, lessThan(heatDotAlpha));
      expect(heatDotAlpha, lessThan(1), reason: 'leicht durchsichtig');
    });
  });

  group('Blatt zum Punkt', () {
    test('zählt im Umkreis von 300 m um die Stelle, mit Zeitraum', () {
      final cell = heatCellAround(const GeoPoint(52.5, 13.4), [
        _obs('a', at: DateTime(2025, 2, 3)),
        _obs('b', meters: 150, at: DateTime(2026, 8, 12)),
        _obs('c', meters: 280, at: DateTime(2026, 1, 5)),
        _obs('weit', meters: 900, at: DateTime(2026, 10, 1)),
      ], _now);
      expect(cell.count, 3);
      expect(cell.earliest, DateTime(2025, 2, 3));
      expect(cell.latest, DateTime(2026, 8, 12));
    });

    test('Zeitraum „vom … bis …“, an einem Tag „am …“', () {
      expect(
        heatPeriodText(DateTime(2025, 2, 3), DateTime(2026, 8, 12)),
        'vom 03.02.2025 bis 12.08.2026',
      );
      expect(
        heatPeriodText(DateTime(2026, 8, 12, 9), DateTime(2026, 8, 12, 17)),
        'am 12.08.2026',
      );
      expect(heatPeriodText(null, DateTime(2026, 8, 12)), 'am 12.08.2026');
      expect(heatPeriodText(null, null), isNull);
    });
  });
}
