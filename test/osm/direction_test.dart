import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_direction.dart';

void main() {
  group('parseDirection', () {
    test('Grad, auch mit Komma', () {
      expect(parseDirection('90')!.degrees, [90]);
      expect(parseDirection('87,5')!.degrees, [87.5]);
      expect(parseDirection('360')!.degrees, [0]);
    });

    test('Himmelsrichtungen', () {
      expect(parseDirection('N')!.degrees, [0]);
      expect(parseDirection('nne')!.degrees, [22.5]);
      expect(parseDirection('SW')!.degrees, [225]);
      expect(parseDirection('NNW')!.degrees, [337.5]);
      expect(parseDirection('west')!.degrees, [270]);
    });

    test('Listen', () {
      expect(parseDirection('90;270')!.degrees, [90, 270]);
      expect(parseDirection('N; E')!.degrees, [0, 90]);
    });

    test('relativ und alle', () {
      expect(parseDirection('forward')!.forward, isTrue);
      expect(parseDirection('backward')!.backward, isTrue);
      expect(parseDirection('both')!.all, isTrue);
      expect(parseDirection('all')!.all, isTrue);
    });

    test('Bereich: Mitte des Bogens', () {
      expect(parseDirection('67-292')!.degrees.single, closeTo(179.5, 0.01));
      expect(parseDirection('350-10')!.degrees.single, closeTo(0, 0.01));
    });

    test('Unverständliches ist null', () {
      expect(parseDirection(null), isNull);
      expect(parseDirection(''), isNull);
      expect(parseDirection('quer'), isNull);
      expect(parseDirection('400'), isNull);
      expect(parseDirection('-5'), isNull);
    });
  });

  group('resolveNodeBearings', () {
    const north = WayContext(bearing: 0);

    test('Grad und Himmelsrichtung', () {
      expect(resolveNodeBearings(direction: '135'), [135]);
      expect(resolveNodeBearings(direction: 'SE'), [135]);
      expect(resolveNodeBearings(direction: '90;270'), [90, 270]);
    });

    test('forward/backward über die Wegrichtung', () {
      expect(resolveNodeBearings(direction: 'forward', way: north), [0]);
      expect(resolveNodeBearings(direction: 'backward', way: north), [180]);
      expect(
        resolveNodeBearings(
          direction: 'forward',
          way: const WayContext(bearing: 90),
        ),
        [90],
      );
    });

    test('forward ohne Weg ist nicht auflösbar: leer', () {
      expect(resolveNodeBearings(direction: 'forward'), isEmpty);
    });

    test('both, all und forward;backward: leer', () {
      expect(resolveNodeBearings(direction: 'both', way: north), isEmpty);
      expect(resolveNodeBearings(direction: 'all'), isEmpty);
      expect(
        resolveNodeBearings(direction: 'forward;backward', way: north),
        isEmpty,
      );
    });

    test('camera:direction als Ersatz', () {
      expect(resolveNodeBearings(cameraDirection: '45'), [45]);
      expect(resolveNodeBearings(direction: 'quer', cameraDirection: '45'), [
        45,
      ]);
      expect(resolveNodeBearings(direction: '10', cameraDirection: '45'), [10]);
    });

    test('ohne Angabe: leer, auf Einbahn deren Richtung', () {
      expect(resolveNodeBearings(), isEmpty);
      expect(resolveNodeBearings(way: north), isEmpty);
      expect(
        resolveNodeBearings(way: const WayContext(bearing: 90, oneway: 1)),
        [90],
      );
      expect(
        resolveNodeBearings(way: const WayContext(bearing: 90, oneway: -1)),
        [270],
      );
    });

    test('doppelte Kurse werden zusammengefasst', () {
      expect(resolveNodeBearings(direction: '0;N;forward', way: north), [0]);
    });
  });

  group('bearingFromTo', () {
    test('Norden und Osten', () {
      // 0,001° Breite ≈ 111 m
      expect(
        bearingFromTo(
          const GeoPoint(52.0, 8.0),
          const GeoPoint(52.001, 8.0),
        ).single,
        closeTo(0, 0.01),
      );
      expect(
        bearingFromTo(
          const GeoPoint(52.0, 8.0),
          const GeoPoint(52.0, 8.002),
        ).single,
        closeTo(90, 0.2),
      );
    });

    test('fehlende oder zusammenfallende Punkte: leer', () {
      expect(bearingFromTo(null, const GeoPoint(52.0, 8.0)), isEmpty);
      expect(
        bearingFromTo(const GeoPoint(52.0, 8.0), const GeoPoint(52.0, 8.0)),
        isEmpty,
      );
    });
  });
}
