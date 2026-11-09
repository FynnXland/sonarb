import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/map_layer_settings.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/format.dart';
import 'package:sonarb/features/cockpit/map_layers.dart';

// So liefern die Plugins ihre Punkte (grobe Art `live` auch für Gefahren).
AlertPoint _p(
  String id,
  AlertKind kind,
  AlertCategory category, {
  bool historical = false,
}) => AlertPoint(
  id: 'plugin:test:$id',
  kind: kind,
  position: const GeoPoint(52.5, 13.4),
  source: 'test',
  category: category,
  historical: historical,
);

void main() {
  const all = {...MapLayer.values};

  test(
    'Gefahren mit grober Art live landen bei Gefahren, nicht bei Mobile',
    () {
      for (final c in [
        AlertCategory.trafficJamEnd,
        AlertCategory.accident,
        AlertCategory.obstacle,
        AlertCategory.slipperyRoad,
        AlertCategory.poorVisibility,
        AlertCategory.breakdown,
        AlertCategory.officialNotice,
        AlertCategory.otherReport,
      ]) {
        expect(
          layerOf(_p(c.name, AlertKind.live, c)),
          MapLayer.danger,
          reason: c.name,
        );
      }
    },
  );

  test('Baustellen und Sperrungen bei Baustellen, Kontrollen bei Blitzern', () {
    expect(
      layerOf(_p('a', AlertKind.construction, AlertCategory.dayRoadworks)),
      MapLayer.construction,
    );
    expect(
      layerOf(_p('b', AlertKind.construction, AlertCategory.closure)),
      MapLayer.construction,
    );
    expect(
      layerOf(_p('c', AlertKind.speedCamera, AlertCategory.heightControl)),
      MapLayer.fixedCameras,
    );
    expect(
      layerOf(_p('d', AlertKind.sectionControl, AlertCategory.sectionEnd)),
      MapLayer.fixedCameras,
    );
  });

  test('Wärme zählt nur mobile Messungen, aktuell und vergangen', () {
    final points = [
      _p('m', AlertKind.live, AlertCategory.mobileSpeed),
      _p('h', AlertKind.live, AlertCategory.mobileSpeed, historical: true),
      _p('t', AlertKind.live, AlertCategory.semiStationary),
      _p('d', AlertKind.live, AlertCategory.mobileDistance, historical: true),
      _p('s', AlertKind.live, AlertCategory.trafficJamEnd),
      _p('u', AlertKind.live, AlertCategory.accident),
      _p('k', AlertKind.live, AlertCategory.otherReport),
    ];
    expect(heatPoints(points, all).map((p) => p.id), [
      'plugin:test:m',
      'plugin:test:h',
      'plugin:test:t',
      'plugin:test:d',
    ]);
  });

  test('Bezeichnung nach feiner Art statt „Live“', () {
    expect(
      pointLabel(_p('s', AlertKind.live, AlertCategory.trafficJamEnd)),
      'Stauende',
    );
    expect(
      pointLabel(_p('m', AlertKind.live, AlertCategory.mobileSpeed)),
      'Mobiler Blitzer',
    );
  });
}
