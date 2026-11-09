import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/features/cockpit/drive_zoom.dart';

void main() {
  test('Stadt nah, Autobahn weiter', () {
    expect(DriveZoom().targetFor(30), 17.25);
    expect(DriveZoom().targetFor(50), 16.75);
    expect(DriveZoom().targetFor(90), 16.25);
    expect(DriveZoom().targetFor(130), 15.75);
    expect(DriveZoom().targetFor(0), 17.25, reason: 'im Stand nah');
  });

  test('kein Pumpen um eine Grenze herum', () {
    final zoom = DriveZoom();
    final seen = <double>{};
    for (final kmh in <double>[30, 38, 33, 41, 36, 40, 34, 42]) {
      seen.add(zoom.targetFor(kmh));
    }
    expect(seen, {17.25});
    // Erst deutlich über der Grenze (35 + 8) wechselt die Stufe, zurück erst deutlich darunter.
    expect(zoom.targetFor(44), 16.75);
    expect(zoom.targetFor(30), 16.75);
    expect(zoom.targetFor(26), 17.25);
  });

  test('sanfter Übergang statt Sprung, kommt am Ziel an', () {
    final zoom = DriveZoom();
    final first = zoom.step(130, from: 17.25);
    expect(first, lessThan(17.25));
    expect(first, greaterThan(15.75));
    var z = first;
    for (var i = 0; i < 40; i++) {
      final next = zoom.step(130, from: 0);
      expect(
        next,
        lessThanOrEqualTo(z),
        reason: 'gleichmäßig in eine Richtung',
      );
      z = next;
    }
    expect(z, 15.75);
  });

  test('Zentrieren springt direkt, Verlassen beginnt neu', () {
    final zoom = DriveZoom()..step(30, from: 15.5);
    expect(zoom.jump(30), 17.25);
    expect(zoom.current, 17.25);
    zoom.reset();
    expect(zoom.current, isNull);
    expect(zoom.step(30, from: 15.5), lessThan(17.25));
  });

  test('unbrauchbares Tempo wie Stand', () {
    expect(DriveZoom().targetFor(double.nan), 17.25);
    expect(DriveZoom().targetFor(-5), 17.25);
  });
}
