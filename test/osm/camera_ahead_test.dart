import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_source.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

/// Startpunkt: Blitzer-Kachel 8,0–8,1 / 52,0–52,1 (Gitter 0,1°).
const _start = GeoPoint(52.07, 8.01);

/// Kantenwert einer Blitzer-Kachel im Format der Abfrage (2 mm Rand).
String edge(int index) => (index / 10 - 0.00002).toStringAsFixed(5);

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  late List<(OsmLayer, String, String)> seen;
  late OsmSource source;
  late GeoPoint pos;
  var failCameras = false;

  setUp(() {
    seen = [];
    pos = _start;
    failCameras = false;
    source = env.make(
      MockClient((req) async {
        final layer = layerOf(req);
        seen.add((layer, westOf(req), southOf(req)));
        if (failCameras && layer == OsmLayer.cameras) {
          return http.Response('', 503);
        }
        return ok(req);
      }),
      grace: const Duration(milliseconds: 20),
    );
  });

  /// Wartet, bis die Quelle nichts mehr lädt (auch das Nachladen im Hintergrund).
  Future<void> settle() => env.whenIdle();

  /// Fährt [seconds] Sekunden mit [mps] nach Osten und meldet jede Sekunde die Position.
  Future<void> drive(int seconds, double mps, {double? heading = 90}) async {
    for (var i = 0; i < seconds; i++) {
      env.clock = env.clock.add(const Duration(seconds: 1));
      pos = GeoPoint(
        pos.lat,
        pos.lon + mps / (111320 * math.cos(pos.lat * math.pi / 180)),
      );
      await source.speedLimitAt(pos, heading);
    }
    await settle();
  }

  Set<(String, String)> cameraTiles() => {
    for (final s in seen)
      if (s.$1 == OsmLayer.cameras) (s.$2, s.$3),
  };

  int requestsFor(String west) =>
      seen.where((s) => s.$1 == OsmLayer.cameras && s.$2 == west).length;

  test('Autobahntempo: die nächste Blitzer-Kachel wird geholt, bevor das 3-km-Fenster sie berührt', () async {
    await drive(25, 28); // 100 km/h, rund 700 m weit
    // Die Position liegt bei 8,02: bis zur Kachel 8,1 sind es 5,5 km, das Fenster reicht 3 km.
    expect(pos.lon, lessThan(8.03));
    expect(cameraTiles(), contains((edge(81), edge(520))));
    expect(
      cameraTiles(),
      isNot(contains((edge(79), edge(520)))),
      reason: 'nichts hinter uns',
    );
  });

  test('bei 29 km/h gilt der Mindestwert von 6 km', () async {
    // 8 m/s · 240 s wären nur 1,9 km; die Kachel 8,1 liegt 5,5 km voraus und kommt trotzdem dran.
    await drive(25, 8);
    expect(cameraTiles(), contains((edge(81), edge(520))));
    expect(cameraTiles(), isNot(contains((edge(82), edge(520)))));
  });

  test('die Reichweite wächst mit dem Tempo', () async {
    await drive(25, 33); // 120 km/h: 7,9 km voraus, von 8,022 bis 8,137
    expect(cameraTiles(), contains((edge(81), edge(520))));
    expect(cameraTiles(), isNot(contains((edge(82), edge(520)))));
  });

  test('langsam wird nichts vorausgeholt', () async {
    await drive(25, 3); // 11 km/h
    expect(cameraTiles(), isEmpty);
  });

  test('ohne Kurs wird nichts vorausgeholt', () async {
    await drive(25, 28, heading: null);
    expect(cameraTiles(), isEmpty, reason: 'ohne Kurs keine Richtung');
  });

  test('frische Kacheln werden nicht noch einmal gefragt', () async {
    await drive(25, 28);
    await drive(25, 28);
    expect(requestsFor(edge(81)), 1);
    expect(requestsFor(edge(80)), 1);
  });

  test('gescheiterte Kachel: Pause, dann erst wieder', () async {
    failCameras = true;
    await drive(25, 28);
    final first = requestsFor(edge(80));
    expect(first, greaterThan(0));
    await drive(20, 28); // nicht einmal eine Minute später
    expect(
      requestsFor(edge(80)),
      first,
      reason: 'während der Pause kein neuer Versuch',
    );
    env.clock = env.clock.add(const Duration(minutes: 3));
    await drive(5, 28);
    expect(
      requestsFor(edge(80)),
      greaterThan(first),
      reason: 'nach der Pause wieder',
    );
  });

  test('geladene Kachel kostet das spätere load keine Anfrage mehr', () async {
    await drive(25, 28);
    seen.clear();
    // Fenster nahe der Kachelgrenze: berührt jetzt auch Kachel 81.
    final r = await source.load(
      GeoBounds.around(const GeoPoint(52.07, 8.09), 3000),
    );
    await settle();
    expect(r.error, isNull);
    expect(
      seen.where((s) => s.$1 == OsmLayer.cameras),
      isEmpty,
      reason: 'beide Blitzer-Kacheln waren schon da',
    );
  });
}
