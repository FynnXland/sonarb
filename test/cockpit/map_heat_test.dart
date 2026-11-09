import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/map_layer_settings.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/heat_sheet.dart';
import 'package:sonarb/features/cockpit/map_heat.dart';
import 'package:sonarb/features/cockpit/map_layers.dart';

final _now = DateTime(2026, 10, 30, 12);

/// Mobile Beobachtung [meters] östlich von 52,5 / 13,4.
AlertPoint _obs(
  String id, {
  double meters = 0,
  DateTime? at,
  bool historical = true,
}) => AlertPoint(
  id: id,
  kind: AlertKind.hotspot,
  reportKind: HotspotKind.mobileCamera,
  position: GeoPoint(52.5, 13.4 + meters / 67800),
  source: 'plugin:x',
  observedAt: at,
  historical: historical,
);

HeatCell _strongest(List<HeatCell> cells) =>
    cells.reduce((a, b) => a.intensity >= b.intensity ? a : b);

void main() {
  group('Kurve', () {
    test('eine Meldung ein Hauch, drei deutlich, acht bis zehn kräftig', () {
      expect(heatIntensity(0), 0);
      expect(heatIntensity(1), lessThan(0.1));
      expect(heatIntensity(3), inInclusiveRange(0.3, 0.45));
      expect(heatIntensity(8), greaterThanOrEqualTo(0.8));
      expect(heatIntensity(10), greaterThanOrEqualTo(0.85));
      expect(heatIntensity(40), greaterThan(0.98));
      expect(heatIntensity(40), lessThanOrEqualTo(1));
    });

    test('steigt mit jeder weiteren Beobachtung', () {
      var last = 0.0;
      for (var n = 1; n <= 30; n++) {
        final i = heatIntensity(n.toDouble());
        expect(i, greaterThan(last));
        last = i;
      }
    });
  });

  group('Alter', () {
    test('Halbwertszeit ein Jahr, ohne Datum zählt voll', () {
      expect(observationWeight(_obs('a'), _now), 1);
      expect(observationWeight(_obs('a', at: _now), _now), 1);
      expect(
        observationWeight(
          _obs('a', at: _now.add(const Duration(days: 3))),
          _now,
        ),
        1,
      );
      expect(
        observationWeight(_obs('a', at: _now.subtract(heatHalfLife)), _now),
        closeTo(0.5, 0.001),
      );
      expect(
        observationWeight(_obs('a', at: _now.subtract(heatHalfLife * 2)), _now),
        closeTo(0.25, 0.001),
      );
    });

    test('acht alte Meldungen wiegen weniger als acht neue', () {
      final fresh = [for (var i = 0; i < 8; i++) _obs('n$i', meters: i * 10)];
      final old = [
        for (var i = 0; i < 8; i++)
          _obs('o$i', meters: i * 10, at: _now.subtract(heatHalfLife * 2)),
      ];
      final f = _strongest(heatCells(fresh, _now));
      final o = _strongest(heatCells(old, _now));
      expect(f.intensity, greaterThanOrEqualTo(0.79));
      expect(o.intensity, lessThan(0.25));
      expect(o.count, 8, reason: 'gezählt werden alle, gewichtet weniger');
    });
  });

  group('Raster', () {
    test('eine einzelne Meldung: Zelle mit Hauch', () {
      final cells = heatCells([_obs('a')], _now);
      expect(cells, hasLength(1));
      expect(cells.single.count, 1);
      expect(cells.single.intensity, lessThan(0.1));
    });

    test('nur Beobachtungen im Umkreis von 300 m zählen zusammen', () {
      final cells = heatCells([
        for (var i = 0; i < 5; i++) _obs('near$i', meters: i * 20),
        for (var i = 0; i < 5; i++) _obs('far$i', meters: 2000 + i * 20),
      ], _now);
      for (final c in cells) {
        expect(c.count, 5);
      }
    });

    test('jüngste Beobachtung für „zuletzt am“', () {
      final cells = heatCells([
        _obs('a', at: DateTime(2025, 3, 1)),
        _obs('b', meters: 30, at: DateTime(2026, 8, 12)),
        _obs('c', meters: 60),
      ], _now);
      expect(_strongest(cells).latest, DateTime(2026, 8, 12));
    });

    test('Tausende alter Beobachtungen bleiben schnell', () {
      final many = [
        for (var i = 0; i < 6000; i++)
          AlertPoint(
            id: 'h$i',
            kind: AlertKind.live,
            position: GeoPoint(52 + (i % 100) * 0.01, 13 + (i ~/ 100) * 0.01),
            source: 'plugin:x',
            observedAt: _now.subtract(Duration(days: i % 700)),
            historical: true,
          ),
      ];
      final watch = Stopwatch()..start();
      final cells = heatCells(many, _now);
      watch.stop();
      expect(cells, isNotEmpty);
      expect(cells.length, lessThanOrEqualTo(many.length));
      expect(watch.elapsedMilliseconds, lessThan(1500));
    });

    test('Zwischenspeicher rechnet nur bei neuer Liste neu', () {
      final cache = HeatCache();
      final points = [_obs('a')];
      final first = cache.cellsFor(points, {MapLayer.mobile}, _now);
      expect(
        identical(cache.cellsFor(points, {MapLayer.mobile}, _now), first),
        isTrue,
      );
      expect(cache.cellsFor(points, {MapLayer.fixedCameras}, _now), isEmpty);
      expect(
        cache.cellsFor([...points], {MapLayer.mobile}, _now),
        hasLength(1),
      );
    });
  });

  group('vergangene Beobachtungen', () {
    test('zählen für die Wärme, zeigen aber kein Symbol', () {
      final old = _obs('old');
      final current = _obs('now', meters: 900, historical: false);
      final layers = {MapLayer.mobile};
      expect(heatPoints([old, current], layers), [old, current]);
      expect(markerPoints([old, current], layers, 15), [current]);
    });
  });

  test('Text im Blatt', () {
    expect(heatCountText(1), 'Hier 1 mobiler Blitzer gemeldet');
    expect(heatCountText(7), 'Hier 7 mobile Blitzer gemeldet');
  });
}
