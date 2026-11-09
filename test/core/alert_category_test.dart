import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';

void main() {
  test('jede Art hat eine Kategorie, gesetzte Kategorie hat Vorrang', () {
    for (final k in AlertKind.values) {
      expect(defaultCategory(k, null), isA<AlertCategory>());
    }
    const p = AlertPoint(
      id: 'osm:node/1',
      kind: AlertKind.speedCamera,
      position: GeoPoint(52, 13),
      source: 'osm',
    );
    expect(p.effectiveCategory, AlertCategory.fixedSpeed);
    expect(
      p.copyWith(category: AlertCategory.tunnelSpeed).effectiveCategory,
      AlertCategory.tunnelSpeed,
    );
  });

  test('Meldungen bekommen ihre feine Art', () {
    expect(
      defaultCategory(AlertKind.hotspot, HotspotKind.distanceCheck),
      AlertCategory.mobileDistance,
    );
    expect(
      defaultCategory(AlertKind.hotspot, HotspotKind.construction),
      AlertCategory.dayRoadworks,
    );
  });

  test('Bezeichnungen sind eindeutig', () {
    final labels = AlertCategory.values.map((c) => c.label).toSet();
    expect(labels.length, AlertCategory.values.length);
  });
}
