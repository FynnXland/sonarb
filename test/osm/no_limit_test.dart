import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/road_limit.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_speed.dart';
import 'package:sonarb/features/osm/osm_tile.dart';
import 'package:sonarb/features/osm/osm_way_limits.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

const _line = [GeoPoint(52.05, 8.04), GeoPoint(52.05, 8.06)];

SpeedWay _way(Map<String, String> tags) => speedWayOf(tags, _line);

void main() {
  group('„kein Limit“ aus maxspeed', () {
    test('none und DE:motorway heißen kein Limit', () {
      expect(isNoSpeedLimit('none'), isTrue);
      expect(isNoSpeedLimit(' None '), isTrue);
      expect(isNoSpeedLimit('none;120'), isTrue);
      expect(isNoSpeedLimit('DE:motorway'), isTrue);
    });

    test('signals, Zahl und fehlend nicht', () {
      // Schilderbrücken zeigen mal 80, mal nichts: ohne Wert bleibt es unbekannt.
      expect(isNoSpeedLimit('signals'), isFalse);
      expect(isNoSpeedLimit('variable'), isFalse);
      expect(isNoSpeedLimit('120'), isFalse);
      expect(isNoSpeedLimit('AT:motorway'), isFalse, reason: 'dort gilt 130');
      expect(isNoSpeedLimit(null), isFalse);
      expect(isNoSpeedLimit(''), isFalse);
    });

    test('parseMaxspeed und limitsOf bleiben wie beim Paket-Generator', () {
      expect(parseMaxspeed('none'), isNull);
      expect(limitsOf({'highway': 'motorway', 'maxspeed': 'none'}), (
        null,
        null,
      ));
    });
  });

  group('Weg', () {
    test('none: in beiden Richtungen kein Limit', () {
      final w = _way({'highway': 'motorway', 'maxspeed': 'none'});
      expect(w.forward, speedWayNoLimit);
      expect(w.backward, speedWayNoLimit);
      expect(w.oneway, 1);
    });

    test('signals ohne Wert: unbekannt', () {
      final w = _way({'highway': 'motorway', 'maxspeed': 'signals'});
      expect(w.forward, isNull);
      expect(w.backward, isNull);
    });

    test('Zahl: die Zahl', () {
      final w = _way({'highway': 'motorway', 'maxspeed': '120'});
      expect(w.forward, 120);
    });

    test('fehlend: unbekannt', () {
      final w = _way({'highway': 'motorway'});
      expect(w.forward, isNull);
      expect(hasLimitTag({'highway': 'motorway'}), isFalse);
    });

    test('nur eine Richtung ohne Limit', () {
      final w = _way({
        'highway': 'trunk',
        'maxspeed': '80',
        'maxspeed:forward': 'none',
      });
      expect(w.forward, speedWayNoLimit);
      expect(w.backward, 80);
    });

    test('auf Nebenstraßen zählt none nicht (Tagging-Fehler)', () {
      final w = _way({'highway': 'living_street', 'maxspeed': 'none'});
      expect(w.forward, isNull);
    });

    test('übersteht den Cache (JSON)', () {
      final w = _way({'highway': 'motorway', 'maxspeed': 'none'});
      final back = SpeedWay.fromJson(w.toJson());
      expect(back.forward, speedWayNoLimit);
      expect(back.backward, speedWayNoLimit);
    });
  });

  group('Auswahl', () {
    const p = GeoPoint(52.05002, 8.05);

    test('auf dem Weg ohne Limit: kein Limit', () {
      final w = _way({'highway': 'motorway', 'maxspeed': 'none'});
      expect(roadLimitOf(pickSpeedLimit([w], p, 90)), const RoadLimit.none());
    });

    test('Richtung unklar: eine Zahl geht vor „kein Limit“', () {
      final w = SpeedWay(points: _line, forward: speedWayNoLimit, backward: 80);
      expect(pickSpeedLimit([w], p, null), 80);
      final both = SpeedWay(
        points: _line,
        forward: speedWayNoLimit,
        backward: speedWayNoLimit,
      );
      expect(pickSpeedLimit([both], p, null), speedWayNoLimit);
    });

    test('Umsetzung für die anderen Bereiche', () {
      expect(roadLimitOf(null), const RoadLimit.unknown());
      expect(roadLimitOf(speedWayNoLimit), const RoadLimit.none());
      expect(roadLimitOf(100), const RoadLimit.kmh(100));
      expect(const RoadLimit.none().kmh, isNull);
      expect(const RoadLimit.unknown().isUnknown, isTrue);
    });
  });

  group('Quelle, von der Overpass-Antwort bis roadLimitAt', () {
    final env = SourceEnv();
    setUp(env.setUp);
    tearDown(env.tearDown);

    Future<RoadLimit> limitFor(Map<String, String> tags) async {
      final source = env.make(
        MockClient(
          (req) async => layerOf(req) == OsmLayer.limits
              ? http.Response(
                  overpassBody([
                    way(21, [
                      [52.05, 8.04],
                      [52.05, 8.06],
                    ], tags),
                  ]),
                  200,
                )
              : ok(req),
        ),
      );
      await source.load(testArea);
      const at = GeoPoint(52.05002, 8.05);
      final road = await source.roadLimitAt(at, 90);
      env.clock = env.clock.add(const Duration(seconds: 1));
      // speedLimitAt bleibt bei null: Warnlogik und Ansagen vergleichen nicht.
      expect(await source.speedLimitAt(at, 90), road.kmh);
      return road;
    }

    test('none', () async {
      expect(
        await limitFor({'highway': 'motorway', 'maxspeed': 'none'}),
        const RoadLimit.none(),
      );
    });

    test('signals', () async {
      expect(
        await limitFor({'highway': 'motorway', 'maxspeed': 'signals'}),
        const RoadLimit.unknown(),
      );
    });

    test('Zahl', () async {
      expect(
        await limitFor({'highway': 'motorway', 'maxspeed': '120'}),
        const RoadLimit.kmh(120),
      );
    });
  });
}
