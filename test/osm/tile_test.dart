import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_gate.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

void main() {
  test('TileId: Gitter unterscheiden sich in Gleichheit und Grenzen', () {
    expect(TileId.of(52.05, 8.05), const TileId(80, 520));
    expect(TileId.of(52.05, 8.05, 20), const TileId(161, 1041, 20));
    expect(TileId.of(52.05, 8.05), isNot(TileId.of(52.05, 8.05, 20)));
    final b = const TileId(161, 1041, 20).bounds;
    expect((b.south, b.north), (52.05, 52.1));
    expect((b.west, b.east), (8.05, 8.1));
  });

  test('distanceTo: 0 innerhalb, sonst Abstand zur Kante', () {
    const t = TileId(80, 520);
    expect(t.distanceTo(const GeoPoint(52.05, 8.05)), 0);
    final d = t.distanceTo(const GeoPoint(52.05, 8.1 + 0.001));
    expect(d, closeTo(0.001 * 111320 * 0.6157, 5));
  });

  test('tilesCovering: Kachel mit der Mitte zuerst, dann nach Abstand', () {
    // Mitte bei 8,17 O: liegt in Kachel 81; die Kante von 82 (8,2) ist näher als die von 80 (8,1).
    const area = GeoBounds(south: 52.05, west: 8.07, north: 52.06, east: 8.27);
    expect(tilesCovering(area).map((t) => t.ix), [81, 82, 80]);
  });

  test('tilesCovering: Feinraster und Obergrenze', () {
    const area = GeoBounds(south: 52.0, west: 8.0, north: 52.2, east: 8.2);
    expect(tilesCovering(area, perDegree: 20).first.perDegree, 20);
    final few = tilesCovering(area, perDegree: 20, maxTiles: 5);
    expect(few, hasLength(5));
    final all = tilesCovering(area, perDegree: 20);
    expect(few, all.take(5));
  });

  test(
    'PriorityGate: Dringlichkeit vor Abstand vor Eingang, Limit gilt',
    () async {
      final gate = PriorityGate(1);
      final release = Completer<void>();
      final order = <String>[];
      final first = gate.run(() async {
        await release.future;
        order.add('erste');
      });
      final rest = [
        gate.run(() async => order.add('spät-fern'), priority: 1, order: 9),
        gate.run(() async => order.add('spät-nah'), priority: 1, order: 1),
        gate.run(() async => order.add('früh-fern'), priority: 0, order: 9),
        gate.run(() async => order.add('früh-nah'), priority: 0, order: 1),
      ];
      release.complete();
      await Future.wait([first, ...rest]);
      expect(order, [
        'erste',
        'früh-nah',
        'früh-fern',
        'spät-nah',
        'spät-fern',
      ]);
    },
  );
}
