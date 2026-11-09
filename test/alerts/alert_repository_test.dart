import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/contracts/hotspot_repository.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';
import 'package:sonarb/features/alerts/alerts.dart';

import 'fakes.dart';

const center = GeoPoint(52.0, 13.0);
// 0,02° Breite ≈ 2,2 km, 0,01° ≈ 1,1 km
const far = GeoPoint(52.02, 13.0);
const near = GeoPoint(52.01, 13.0);

void main() {
  late FakeOsm osm;
  late FakeHotspots hotspots;
  late DateTime now;
  late AlertRepositoryImpl repo;

  Future<AlertRepositoryImpl> build({
    List<DataSourcePlugin> plugins = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return AlertRepositoryImpl(
      osm: osm,
      hotspots: hotspots,
      plugins: plugins,
      prefs: prefs,
      clock: () => now,
    );
  }

  setUp(() async {
    osm = FakeOsm();
    hotspots = FakeHotspots();
    now = DateTime(2026, 1, 1, 12);
    repo = await build();
  });

  tearDown(() => repo.dispose());

  test(
    'createAlertRepository liefert ein funktionierendes Repository',
    () async {
      SharedPreferences.setMockInitialValues({});
      final r = createAlertRepository(
        osm: osm,
        hotspots: hotspots,
        plugins: const [],
        prefs: await SharedPreferences.getInstance(),
      );
      expect(r.pointsAround(center), isEmpty);
      await r.dispose();
    },
  );

  group('pointsAround', () {
    test(
      'antwortet sofort mit dem bekannten Stand und lädt im Hintergrund nach',
      () async {
        osm.result = SourceResult(points: [osmPoint('1', 52.001, 13.0)]);
        expect(repo.pointsAround(center), isEmpty);
        await pumpEventQueue();
        expect(repo.pointsAround(center).map((p) => p.id), ['osm:node/1']);
        expect(osm.loads, 1);
      },
    );

    test('filtert auf den Radius', () async {
      osm.result = SourceResult(
        points: [osmPoint('nah', 52.001, 13.0), osmPoint('fern', 52.02, 13.0)],
      );
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(repo.pointsAround(center, radiusMeters: 500).map((p) => p.id), [
        'osm:node/nah',
      ]);
      expect(repo.pointsAround(center, radiusMeters: 5000), hasLength(2));
    });

    test(
      'Ampeln und Tempolimits im kleinen Radius, Blitzer im eingestellten',
      () async {
        repo.pointsAround(center);
        await pumpEventQueue();
        // Ampeln und Tempolimits: 3 km um den Mittelpunkt.
        final b = osm.areas.single;
        final e = GeoBounds.around(center, 3000);
        expect(
          [b.south, b.west, b.north, b.east],
          [e.south, e.west, e.north, e.east],
        );
        // Blitzer: 5 km, in Blöcken bis 0,49°; zusammen genau der 5-km-Umkreis.
        final cams = osm.cameraAreas;
        final big = GeoBounds.around(center, 5000);
        expect(
          cams.map((a) => a.south).reduce((a, b) => a < b ? a : b),
          closeTo(big.south, 1e-9),
        );
        expect(
          cams.map((a) => a.north).reduce((a, b) => a > b ? a : b),
          closeTo(big.north, 1e-9),
        );
        expect(
          cams.map((a) => a.west).reduce((a, b) => a < b ? a : b),
          closeTo(big.west, 1e-9),
        );
        expect(
          cams.map((a) => a.east).reduce((a, b) => a > b ? a : b),
          closeTo(big.east, 1e-9),
        );
        expect(
          cams.every(
            (a) => a.north - a.south <= 0.49 && a.east - a.west <= 0.49,
          ),
          isTrue,
        );
      },
    );

    test(
      'lädt erst nach einem Viertel des 3-km-Radius (750 m) oder 10 min erneut',
      () async {
        repo.pointsAround(center);
        await pumpEventQueue();
        expect(osm.loads, 1);

        repo.pointsAround(center);
        repo.pointsAround(const GeoPoint(52.005, 13.0)); // 560 m
        await pumpEventQueue();
        expect(osm.loads, 1);

        repo.pointsAround(far); // 2,2 km vom Ladezentrum
        await pumpEventQueue();
        expect(osm.loads, 2);

        now = now.add(const Duration(minutes: 9));
        repo.pointsAround(far);
        await pumpEventQueue();
        expect(osm.loads, 2);

        now = now.add(const Duration(minutes: 2));
        repo.pointsAround(far);
        await pumpEventQueue();
        expect(osm.loads, 3);
      },
    );

    test('startet nie zwei OSM-Ladevorgänge gleichzeitig', () async {
      osm.gate = Completer<SourceResult>();
      repo.pointsAround(center);
      repo.pointsAround(far);
      repo.pointsAround(const GeoPoint(52.1, 13.0));
      await pumpEventQueue();
      expect(osm.loads, 1);

      osm.gate!.complete(const SourceResult(points: []));
      osm.gate = null;
      await pumpEventQueue();
      repo.pointsAround(far);
      await pumpEventQueue();
      expect(osm.loads, 2);
    });

    test(
      'OSM-Fehler: Status error, alte Punkte bleiben, Wiederholung nach 15 s',
      () async {
        osm.result = SourceResult(points: [osmPoint('1', 52.001, 13.0)]);
        repo.pointsAround(center);
        await pumpEventQueue();

        osm.result = const SourceResult(
          points: [],
          error: 'Overpass nicht erreichbar',
        );
        repo.pointsAround(far);
        await pumpEventQueue();
        expect(osm.loads, 2);
        final s = (await repo.watchStatus().first).firstWhere(
          (e) => e.id == 'osm',
        );
        expect(s.status, PluginStatus.error);
        expect(s.message, 'Overpass nicht erreichbar');
        expect(s.pointCount, 1);
        expect(repo.pointsAround(far), hasLength(1));

        // Nichts unter dem Fahrzeug: die Wiederholung kommt schon nach 15 s.
        now = now.add(const Duration(seconds: 10));
        repo.pointsAround(far);
        await pumpEventQueue();
        expect(osm.loads, 2);
        now = now.add(const Duration(seconds: 10));
        repo.pointsAround(far);
        await pumpEventQueue();
        expect(osm.loads, 3);
      },
    );

    test('OSM-Fehler mit Blitzer-Kachel unter dem Fahrzeug: Wiederholung nach 1 min', () async {
      osm.result = SourceResult(points: [osmPoint('1', 52.001, 13.0)]);
      repo.pointsAround(center);
      await pumpEventQueue();
      osm.loadedTiles = const [
        GeoBounds(south: 51.9, west: 12.9, north: 52.1, east: 13.1),
      ];
      osm.result = const SourceResult(
        points: [],
        error: 'Overpass nicht erreichbar',
      );
      repo.pointsAround(far);
      await pumpEventQueue();
      expect(osm.loads, 2);
      now = now.add(const Duration(seconds: 30));
      repo.pointsAround(far);
      await pumpEventQueue();
      expect(osm.loads, 2);
      now = now.add(const Duration(seconds: 40));
      repo.pointsAround(far);
      await pumpEventQueue();
      expect(osm.loads, 3);
    });

    test('OSM-Hinweis (Nachladen): Status ok, Meldung sichtbar, Wiederholung nach 1 min', () async {
      osm.result = SourceResult(
        points: [osmPoint('1', 52.001, 13.0)],
        notice: 'Ampeln und Tempolimits werden nachgeladen',
      );
      repo.pointsAround(center);
      await pumpEventQueue();
      final s = (await repo.watchStatus().first).firstWhere(
        (e) => e.id == 'osm',
      );
      expect(s.status, PluginStatus.ok);
      expect(s.message, 'Ampeln und Tempolimits werden nachgeladen');

      now = now.add(const Duration(seconds: 70));
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(osm.loads, 2);
    });

    test('geworfener OSM-Fehler wird gefangen', () async {
      osm.throwOnLoad = Exception('kaputt');
      repo.pointsAround(center);
      await pumpEventQueue();
      final s = (await repo.watchStatus().first).firstWhere(
        (e) => e.id == 'osm',
      );
      expect(s.status, PluginStatus.error);
      expect(s.message, 'kaputt');
    });

    test('Ladeergebnis wird über changes gemeldet', () async {
      var events = 0;
      final sub = repo.changes.listen((_) => events++);
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(events, greaterThanOrEqualTo(1));
      await sub.cancel();
    });
  });

  group('Hotspots', () {
    Hotspot hs(String id, {double? heading, String? note}) => Hotspot(
      id: id,
      position: const GeoPoint(52.001, 13.0),
      createdAt: DateTime(2026),
      headingDeg: heading,
      note: note,
    );

    test('werden mit Richtung, Quelle und Label umgewandelt', () async {
      hotspots.set([hs('a', heading: 90, note: 'Kurve'), hs('b')]);
      await pumpEventQueue();
      final pts = {for (final p in repo.pointsAround(center)) p.id: p};
      final a = pts['hotspot:a']!;
      expect(a.kind, AlertKind.hotspot);
      expect(a.source, 'hotspot');
      expect(a.travelBearings, [90.0]);
      expect(a.label, 'Kurve');
      expect(pts['hotspot:b']!.travelBearings, isEmpty);
      expect(pts['hotspot:b']!.label, isNull);
    });

    test('sind sofort da und Änderungen melden changes', () async {
      repo.pointsAround(center);
      await pumpEventQueue(); // OSM-Ladeergebnis vorab abwarten
      var events = 0;
      final sub = repo.changes.listen((_) => events++);
      hotspots.set([hs('a')]);
      await pumpEventQueue();
      expect(events, 1);
      expect(repo.pointsAround(center), hasLength(1));

      hotspots.set([]);
      await pumpEventQueue();
      expect(events, 2);
      expect(repo.pointsAround(center), isEmpty);
      await sub.cancel();
    });
  });

  group('watchStatus', () {
    test('liefert beim Abonnieren sofort den Stand aller Quellen', () async {
      repo = await build(plugins: [FakePlugin('feed')]);
      final list = await repo.watchStatus().first;
      expect(list.map((s) => s.id), ['osm', 'hotspot', 'feed']);
      expect(list[0].name, 'OpenStreetMap');
      expect(list[1].name, 'Eigene Hotspots');
      expect(list[2].name, 'Plugin feed');
      expect(list[2].status, PluginStatus.disabled);
      expect(list[0].status, PluginStatus.idle);
    });

    test('meldet Laden, Ergebnis, Punktzahl und Zeitstempel', () async {
      osm.gate = Completer<SourceResult>();
      final events = <SourceStatus>[];
      final sub = repo.watchStatus().listen(
        (l) => events.add(l.firstWhere((s) => s.id == 'osm')),
      );
      await pumpEventQueue();
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(events.last.status, PluginStatus.loading);

      final fetched = DateTime(2026, 1, 1, 11, 59);
      osm.gate!.complete(
        SourceResult(
          points: [osmPoint('1', 52.001, 13.0), osmPoint('2', 52.002, 13.0)],
          fetchedAt: fetched,
        ),
      );
      await pumpEventQueue();
      expect(events.last.status, PluginStatus.ok);
      expect(events.last.pointCount, 2);
      expect(events.last.updatedAt, fetched);
      await sub.cancel();
    });

    test('Hotspot-Eintrag zählt die Hotspots', () async {
      hotspots.set([
        Hotspot(id: 'a', position: center, createdAt: DateTime(2026)),
        Hotspot(id: 'b', position: center, createdAt: DateTime(2026)),
      ]);
      await pumpEventQueue();
      final s = (await repo.watchStatus().first).firstWhere(
        (e) => e.id == 'hotspot',
      );
      expect(s.status, PluginStatus.ok);
      expect(s.pointCount, 2);
    });
  });

  test('speedLimitAt wird an die OSM-Quelle durchgereicht', () async {
    expect(await repo.speedLimitAt(center, 90), 50);
  });

  test('dispose beendet Streams und stoppt weitere Ladevorgänge', () async {
    final done = Completer<void>();
    repo.changes.listen((_) {}, onDone: done.complete);
    await repo.dispose();
    await done.future;
    expect(repo.pointsAround(center), isEmpty);
    expect(osm.loads, 0);
  });
}
