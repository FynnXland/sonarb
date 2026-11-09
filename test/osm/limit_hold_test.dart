import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_source.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

/// Der 50er-Weg der Fixture liegt bei 52,05 N von 8,04 bis 8,06 O.
void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  Future<OsmSource> loaded() async {
    final source = env.make(MockClient((req) async => ok(req)));
    await source.load(testArea);
    return source;
  }

  GeoPoint at(double lon) => GeoPoint(52.05002, lon);

  test('auf dem Weg: das Limit', () async {
    final source = await loaded();
    expect(await source.speedLimitAt(at(8.055), 90), 50);
  });

  test(
    'hinter dem Ende des Wegs bleibt das Limit auf gerader Strecke bis 150 m',
    () async {
      final source = await loaded();
      expect(await source.speedLimitAt(at(8.059), 90), 50);
      env.clock = env.clock.add(const Duration(seconds: 5));
      // 60 m hinter dem Ende, 130 m vom letzten bekannten Punkt: gehalten.
      expect(await source.speedLimitAt(at(8.0609), 90), 50);
      env.clock = env.clock.add(const Duration(seconds: 5));
      // 290 m vom letzten bekannten Punkt: zu weit, unbekannt.
      expect(await source.speedLimitAt(at(8.063), 90), isNull);
    },
  );

  test('nach 15 s ist Schluss, auch wenn man kaum weiterkam', () async {
    final source = await loaded();
    await source.speedLimitAt(at(8.059), 90);
    env.clock = env.clock.add(const Duration(seconds: 10));
    expect(await source.speedLimitAt(at(8.0607), 90), 50);
    env.clock = env.clock.add(const Duration(seconds: 6));
    expect(await source.speedLimitAt(at(8.0607), 90), isNull);
  });

  test('beim Abbiegen (über 35°) nicht halten', () async {
    final source = await loaded();
    await source.speedLimitAt(at(8.059), 90);
    env.clock = env.clock.add(const Duration(seconds: 3));
    expect(await source.speedLimitAt(at(8.0609), 0), isNull);
    // Der Halt ist damit verbraucht: auch auf altem Kurs kein Limit mehr.
    expect(await source.speedLimitAt(at(8.0610), 90), isNull);
  });

  test('ein kleiner Knick (30°) ist noch derselbe Weg', () async {
    final source = await loaded();
    await source.speedLimitAt(at(8.059), 90);
    env.clock = env.clock.add(const Duration(seconds: 3));
    expect(await source.speedLimitAt(at(8.0609), 60), 50);
  });

  test(
    'ohne vorheriges Limit bleibt es unbekannt, ein neues ersetzt das alte',
    () async {
      final source = await loaded();
      expect(await source.speedLimitAt(const GeoPoint(52.0, 8.0), 90), isNull);
      await source.speedLimitAt(at(8.059), 90);
      expect(await source.speedLimitAt(at(8.055), 90), 50);
    },
  );
}
