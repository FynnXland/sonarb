import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_speed.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

SpeedWay ew(
  double lat, {
  int? f,
  int? b,
  int oneway = 0,
  double w = 8.04,
  double e = 8.06,
}) => SpeedWay(
  points: [GeoPoint(lat, w), GeoPoint(lat, e)],
  forward: f,
  backward: b,
  oneway: oneway,
);

void main() {
  group('parseMaxspeed', () {
    test('Zahlen und Einheiten', () {
      expect(parseMaxspeed('50'), 50);
      expect(parseMaxspeed(' 30 '), 30);
      expect(parseMaxspeed('100 km/h'), 100);
      expect(parseMaxspeed('30 mph'), 48);
      expect(parseMaxspeed('70 mph'), 113);
      expect(parseMaxspeed('50;30'), 50);
    });

    test('Kürzel', () {
      expect(parseMaxspeed('DE:urban'), 50);
      expect(parseMaxspeed('DE:rural'), 100);
      expect(parseMaxspeed('DE:motorway'), isNull);
      expect(parseMaxspeed('DE:living_street'), 7);
      expect(parseMaxspeed('DE:zone30'), 30);
      expect(parseMaxspeed('DE:zone:30'), 30);
      expect(parseMaxspeed('walk'), 7);
      expect(parseMaxspeed('none'), isNull);
      expect(parseMaxspeed('signals'), isNull);
    });

    test('Unsinn ist null', () {
      expect(parseMaxspeed(null), isNull);
      expect(parseMaxspeed(''), isNull);
      expect(parseMaxspeed('schnell'), isNull);
      expect(parseMaxspeed('0'), isNull);
      expect(parseMaxspeed('900'), isNull);
    });
  });

  group('pickSpeedLimit', () {
    const pos = GeoPoint(52.05, 8.05);

    test('nächstes Segment innerhalb von 30 m', () {
      final near = ew(52.05005, f: 30, b: 30); // ca. 5,5 m
      final far = ew(52.0502, f: 70, b: 70); // ca. 22 m
      expect(pickSpeedLimit([far, near], pos, null), 30);
    });

    test('weiter als 30 m: null', () {
      expect(pickSpeedLimit([ew(52.0504, f: 50, b: 50)], pos, null), isNull);
      expect(pickSpeedLimit(const [], pos, 90), isNull);
    });

    test('Kurs wählt die passende Fahrbahn bei Parallelwegen', () {
      // Süd: Einbahn nach Osten (30), Nord: Einbahn nach Westen (50), beide ~10 m entfernt.
      final east = ew(52.04991, f: 30, oneway: 1);
      final west = ew(
        52.05009,
        b: 50,
        oneway: -1,
      ); // Geometrie nach Osten, befahrbar nur nach Westen
      expect(pickSpeedLimit([east, west], pos, 90), 30);
      expect(pickSpeedLimit([east, west], pos, 270), 50);
    });

    test(
      'Einbahn gegen den Kurs wird gemieden, wenn eine Alternative da ist',
      () {
        final oneWay = ew(
          52.05001,
          f: 30,
          oneway: 1,
        ); // 1 m, aber nur nach Osten
        final twoWay = ew(52.0501, f: 50, b: 50); // 11 m
        expect(pickSpeedLimit([oneWay, twoWay], pos, 270), 50);
        expect(pickSpeedLimit([oneWay, twoWay], pos, 90), 30);
      },
    );

    test('Einbahn ohne Alternative zählt trotzdem', () {
      expect(pickSpeedLimit([ew(52.05001, f: 30, oneway: 1)], pos, 270), 30);
    });

    test('maxspeed:forward/backward je nach Fahrtrichtung', () {
      final w = ew(52.05, f: 60, b: 30);
      expect(pickSpeedLimit([w], pos, 90), 60);
      expect(pickSpeedLimit([w], pos, 270), 30);
      expect(pickSpeedLimit([w], pos, 80), 60);
    });

    test('ohne Kurs: bei Einbahn deren Limit, sonst der niedrigere Wert', () {
      expect(pickSpeedLimit([ew(52.05, b: 40, oneway: -1)], pos, null), 40);
      expect(pickSpeedLimit([ew(52.05, f: 60, b: 30)], pos, null), 30);
    });

    test(
      'kein Limit (none) liefert null, auch wenn weiter weg eines existiert',
      () {
        final motorway = ew(52.05001, oneway: 1); // none
        final service = ew(52.0502, f: 30, b: 30);
        expect(pickSpeedLimit([service, motorway], pos, 90), isNull);
      },
    );

    test('Kurs quer zur Straße: Straße wird dennoch gefunden', () {
      expect(pickSpeedLimit([ew(52.05, f: 50, b: 50)], pos, 0), 50);
    });
  });
}
