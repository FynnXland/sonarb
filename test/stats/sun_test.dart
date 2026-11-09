import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/stats/sun.dart';

void main() {
  const berlin = GeoPoint(52.52, 13.40);

  test('Mittagshöhe im Sommer und Winter', () {
    // Sonnenwende: 90° − 52,5° ± 23,4°.
    expect(
      sunElevationDeg(berlin, DateTime.utc(2026, 6, 21, 11, 7)),
      closeTo(60.9, 0.7),
    );
    expect(
      sunElevationDeg(berlin, DateTime.utc(2026, 12, 21, 11, 5)),
      closeTo(14.1, 0.7),
    );
  });

  test('Nacht ab dem Ende der bürgerlichen Dämmerung', () {
    // Sonnenuntergang in Berlin am 2.11.2026 gegen 15:40 UTC, Dämmerung bis etwa 16:20.
    expect(isNight(berlin, DateTime.utc(2026, 11, 2, 15, 30)), isFalse);
    expect(isNight(berlin, DateTime.utc(2026, 11, 2, 16, 45)), isTrue);
    expect(isNight(berlin, DateTime.utc(2026, 11, 2, 2)), isTrue);
    expect(isNight(berlin, DateTime.utc(2026, 11, 2, 11)), isFalse);
  });
}
