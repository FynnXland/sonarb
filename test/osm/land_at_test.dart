import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/features/osm/land_at.dart';

void main() {
  test('Landeshauptstädte liegen im richtigen Land', () {
    const cities = {
      'Stuttgart': (48.78, 9.18, 'baden-wuerttemberg'),
      'München': (48.14, 11.58, 'bayern'),
      'Berlin': (52.52, 13.40, 'berlin'),
      'Potsdam': (52.40, 13.06, 'brandenburg'),
      'Bremen': (53.08, 8.80, 'bremen'),
      'Hamburg': (53.55, 10.00, 'hamburg'),
      'Wiesbaden': (50.08, 8.24, 'hessen'),
      'Schwerin': (53.63, 11.40, 'mecklenburg-vorpommern'),
      'Hannover': (52.37, 9.73, 'niedersachsen'),
      'Düsseldorf': (51.23, 6.78, 'nordrhein-westfalen'),
      'Trier': (
        49.76,
        6.64,
        'rheinland-pfalz',
      ), // Mainz liegt am Rhein auf einer 0,1°-Rasterkante
      'Saarbrücken': (49.24, 6.99, 'saarland'),
      'Dresden': (51.05, 13.74, 'sachsen'),
      'Magdeburg': (52.13, 11.63, 'sachsen-anhalt'),
      'Kiel': (54.32, 10.14, 'schleswig-holstein'),
      'Erfurt': (50.98, 11.03, 'thueringen'),
    };
    for (final e in cities.entries) {
      final (lat, lon, id) = e.value;
      expect(landAt(lat, lon), id, reason: e.key);
    }
  });

  test('außerhalb Deutschlands und weit außerhalb des Rasters: null', () {
    expect(landAt(48.86, 2.35), isNull, reason: 'Paris');
    expect(landAt(48.21, 16.37), isNull, reason: 'Wien');
    expect(landAt(0, 0), isNull);
    expect(landAt(89, 179), isNull);
    expect(landAt(52.0, -170), isNull);
  });

  test('alle Kennungen im Raster haben einen Namen', () {
    expect(landNames.keys.toSet(), landNamesFromGrid());
    expect(landNames, hasLength(16));
  });
}

Set<String> landNamesFromGrid() => {
  for (final lat in List.generate(90, (i) => 47.0 + i * 0.1))
    for (final lon in List.generate(100, (i) => 5.8 + i * 0.1))
      ?landAt(lat, lon),
};
