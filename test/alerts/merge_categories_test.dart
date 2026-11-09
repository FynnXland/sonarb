import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/alerts/merge_points.dart';

AlertPoint _p(String source, String id, AlertCategory c, double lat) =>
    AlertPoint(
      id: 'plugin:$source:$id',
      kind: AlertKind.live,
      position: GeoPoint(lat, 8.05),
      source: source,
      category: c,
    );

void main() {
  test('Stauende verschmilzt nicht mit einem mobilen Blitzer daneben', () {
    final merged = mergePoints([
      _p('a', '1', AlertCategory.mobileSpeed, 52.05),
      _p('b', '2', AlertCategory.trafficJamEnd, 52.0505), // ca. 55 m
    ]);
    expect(merged, hasLength(2));
  });

  test('Unfall aus zwei Quellen wird ein Punkt mit beiden Quellen', () {
    final merged = mergePoints([
      _p('a', '1', AlertCategory.accident, 52.05),
      _p('b', '2', AlertCategory.accident, 52.0505),
    ]);
    expect(merged, hasLength(1));
    expect(merged.single.sources.map((s) => s.id).toSet(), {'a', 'b'});
  });

  test('Unfall und Stauende bleiben getrennt', () {
    final merged = mergePoints([
      _p('a', '1', AlertCategory.accident, 52.05),
      _p('b', '2', AlertCategory.trafficJamEnd, 52.0505),
    ]);
    expect(merged, hasLength(2));
  });

  test('mobile Blitzer aus zwei Quellen werden weiter zusammengeführt', () {
    final merged = mergePoints([
      _p('a', '1', AlertCategory.mobileSpeed, 52.05),
      _p('b', '2', AlertCategory.mobileSpeed, 52.0505),
    ]);
    expect(merged, hasLength(1));
  });
}
