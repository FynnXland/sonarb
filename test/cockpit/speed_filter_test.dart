import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/position_fix.dart';
import 'package:sonarb/features/cockpit/speed_filter.dart';

final _t0 = DateTime.utc(2026, 10, 30, 12);

PositionFix _at(double seconds, double kmh) => PositionFix(
  position: const GeoPoint(52.5, 13.4),
  speedMps: kmh / 3.6,
  accuracyMeters: 4,
  time: _t0.add(Duration(milliseconds: (seconds * 1000).round())),
);

void main() {
  double run(SpeedFilter f, double s, double kmh) =>
      f.apply(_at(s, kmh)).speedKmh;

  test('erster Wert ungefiltert', () {
    expect(run(SpeedFilter(), 0, 87), closeTo(87, 1e-9));
  });

  test('Tempowechsel: nach 1 s rund drei Viertel, nach 2 s über 90 %', () {
    final f = SpeedFilter();
    run(f, 0, 50);
    final after1 = run(f, 1, 70);
    final after2 = run(f, 2, 70);
    expect((after1 - 50) / 20, closeTo(0.76, 0.02));
    expect((after2 - 50) / 20, greaterThan(0.9));
  });

  test('Zittern um ±1 km/h wird ruhiger', () {
    final f = SpeedFilter();
    run(f, 0, 50);
    final values = [
      for (var i = 1; i <= 10; i++) run(f, i.toDouble(), i.isEven ? 51 : 49),
    ];
    for (final v in values.skip(2)) {
      expect(v, inInclusiveRange(49.3, 50.7));
    }
  });

  test('Bremsen bis zum Stand: nach 3 s fast 0', () {
    final f = SpeedFilter();
    run(f, 0, 50);
    for (var i = 1; i <= 3; i++) {
      run(f, i.toDouble(), 0);
    }
    expect(run(f, 4, 0), lessThan(1));
  });

  test('unmöglicher Sprung (Positionssprung ohne Doppler) wird gekappt', () {
    final f = SpeedFilter();
    run(f, 0, 0);
    final spike = run(f, 1, 1491);
    expect(spike, lessThan(12 * 3.6));
  });

  test('nach einer Pause von über 3 s neu ohne Glättung', () {
    final f = SpeedFilter();
    run(f, 0, 50);
    expect(run(f, 5, 120), closeTo(120, 1e-9));
  });
}
