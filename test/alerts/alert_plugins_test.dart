import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';
import 'package:sonarb/features/alerts/point_merge.dart';

import 'fakes.dart';

const center = GeoPoint(52.0, 13.0);

void main() {
  late FakeOsm osm;
  late FakeHotspots hotspots;
  late FakePlugin plugin;
  late DateTime now;
  late SharedPreferences prefs;
  late AlertRepositoryImpl repo;

  Future<AlertRepositoryImpl> build({
    Map<String, Object> stored = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    return AlertRepositoryImpl(
      osm: osm,
      hotspots: hotspots,
      plugins: [plugin],
      prefs: prefs,
      clock: () => now,
      pluginTimeout: timeout,
    );
  }

  Future<SourceStatus> pluginStatus() async =>
      (await repo.watchStatus().first).firstWhere((s) => s.id == 'feed');

  setUp(() async {
    osm = FakeOsm();
    hotspots = FakeHotspots();
    plugin = FakePlugin(
      'feed',
      onFetch: (_) async => [pluginPoint('feed', '1', 52.001, 13.0)],
    );
    now = DateTime(2026, 1, 1, 12);
    repo = await build();
  });

  tearDown(() => repo.dispose());

  test('Plugin ist standardmäßig aus und liefert nichts', () async {
    expect(repo.isPluginEnabled('feed'), isFalse);
    repo.pointsAround(center);
    await pumpEventQueue();
    expect(plugin.initializes, 0);
    expect(plugin.fetches, 0);
    expect(repo.pointsAround(center), isEmpty);
    expect((await pluginStatus()).status, PluginStatus.disabled);
  });

  test(
    'Einschalten initialisiert einmal, speichert in prefs und lädt Punkte',
    () async {
      repo.pointsAround(center);
      await repo.setPluginEnabled('feed', true);
      await pumpEventQueue();

      expect(repo.isPluginEnabled('feed'), isTrue);
      expect(prefs.getBool('plugin.feed.enabled'), isTrue);
      expect(plugin.initializes, 1);
      expect(plugin.fetches, 1);
      expect(repo.pointsAround(center).map((p) => p.id), ['plugin:feed:1']);
      final s = await pluginStatus();
      expect(s.status, PluginStatus.ok);
      expect(s.pointCount, 1);
      expect(s.updatedAt, now);

      await repo.setPluginEnabled('feed', true);
      expect(plugin.initializes, 1);
    },
  );

  test('Abruf nutzt 5 km um die letzte Position', () async {
    repo.pointsAround(center);
    await repo.setPluginEnabled('feed', true);
    await pumpEventQueue();
    final e = GeoBounds.around(center, 5000);
    final a = plugin.lastArea!;
    expect(
      [a.south, a.west, a.north, a.east],
      [e.south, e.west, e.north, e.east],
    );
  });

  test(
    'bereits gespeicherte Einstellung "an" wird beim ersten Aufruf genutzt',
    () async {
      await repo.dispose();
      repo = await build(stored: {'plugin.feed.enabled': true});
      expect(repo.isPluginEnabled('feed'), isTrue);
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(plugin.initializes, 1);
      expect(repo.pointsAround(center), hasLength(1));
    },
  );

  test(
    'Ausschalten ruft dispose, entfernt Punkte und speichert "aus"',
    () async {
      repo.pointsAround(center);
      await repo.setPluginEnabled('feed', true);
      await pumpEventQueue();
      await repo.setPluginEnabled('feed', false);

      expect(plugin.disposes, 1);
      expect(prefs.getBool('plugin.feed.enabled'), isFalse);
      expect(repo.pointsAround(center), isEmpty);
      expect((await pluginStatus()).status, PluginStatus.disabled);

      // Erneutes Einschalten initialisiert neu.
      await repo.setPluginEnabled('feed', true);
      expect(plugin.initializes, 2);
    },
  );

  test(
    'refreshInterval begrenzt die Abrufe, Bewegung > 1,5 km löst früher aus',
    () async {
      await repo.setPluginEnabled('feed', true);
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(plugin.fetches, 1);

      now = now.add(const Duration(seconds: 10));
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(plugin.fetches, 1);

      repo.pointsAround(const GeoPoint(52.02, 13.0));
      await pumpEventQueue();
      expect(plugin.fetches, 2);

      now = now.add(const Duration(seconds: 31));
      repo.pointsAround(const GeoPoint(52.02, 13.0));
      await pumpEventQueue();
      expect(plugin.fetches, 3);
    },
  );

  test(
    'Fehler: Status error mit Meldung, Punkte des letzten Erfolgs bleiben',
    () async {
      await repo.setPluginEnabled('feed', true);
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(repo.pointsAround(center), hasLength(1));

      plugin.onFetch = (_) async => throw Exception('Server 503');
      now = now.add(const Duration(minutes: 1));
      repo.pointsAround(center);
      await pumpEventQueue();

      final s = await pluginStatus();
      expect(s.status, PluginStatus.error);
      expect(s.message, 'Server 503');
      expect(repo.pointsAround(center), hasLength(1));
    },
  );

  test('Punkte des letzten Erfolgs verfallen nach 15 min', () async {
    await repo.setPluginEnabled('feed', true);
    repo.pointsAround(center);
    await pumpEventQueue();
    plugin.onFetch = (_) async => throw Exception('weg');

    now = now.add(const Duration(minutes: 14));
    repo.pointsAround(center);
    await pumpEventQueue();
    expect(repo.pointsAround(center), hasLength(1));

    now = now.add(const Duration(minutes: 2));
    expect(repo.pointsAround(center), isEmpty);
    expect((await pluginStatus()).pointCount, 0);
  });

  test('Gültigkeit: mindestens zwei Abrufintervalle, mindestens 15 min', () {
    expect(
      AlertRepositoryImpl.pluginValidity(const Duration(seconds: 30)),
      const Duration(minutes: 15),
    );
    expect(
      AlertRepositoryImpl.pluginValidity(const Duration(minutes: 15)),
      const Duration(minutes: 30),
    );
  });

  test('Erfolg nach Fehler setzt den Status zurück auf ok', () async {
    plugin.onFetch = (_) async => throw Exception('weg');
    await repo.setPluginEnabled('feed', true);
    repo.pointsAround(center);
    await pumpEventQueue();
    expect((await pluginStatus()).status, PluginStatus.error);

    plugin.onFetch = (_) async => [pluginPoint('feed', '1', 52.001, 13.0)];
    now = now.add(const Duration(minutes: 1));
    repo.pointsAround(center);
    await pumpEventQueue();
    final s = await pluginStatus();
    expect(s.status, PluginStatus.ok);
    expect(s.message, isNull);
  });

  test('initialize-Fehler zeigt Status error und wird beim nächsten Abruf wiederholt', () async {
    plugin.initializeError = Exception('kein Zugang');
    await repo.setPluginEnabled('feed', true);
    var s = await pluginStatus();
    expect(s.status, PluginStatus.error);
    expect(s.message, 'kein Zugang');
    expect(plugin.fetches, 0);

    plugin.initializeError = null;
    repo.pointsAround(center);
    await pumpEventQueue();
    expect(plugin.fetches, 1);
    s = await pluginStatus();
    expect(s.status, PluginStatus.ok);
  });

  test('Timeout: Abruf gilt als fehlgeschlagen', () async {
    await repo.dispose();
    plugin.onFetch = (_) => Completer<List<AlertPoint>>().future;
    repo = await build(timeout: const Duration(milliseconds: 40));
    await repo.setPluginEnabled('feed', true);
    repo.pointsAround(center);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final s = await pluginStatus();
    expect(s.status, PluginStatus.error);
    expect(s.message, 'Zeitüberschreitung');
  });

  test('Punkte ohne Präfix plugin:<id>: werden verworfen', () async {
    plugin.onFetch = (_) async => [
      pluginPoint('feed', 'ok', 52.001, 13.0),
      osmPoint('9', 52.002, 13.0), // fremde Core-ID
      pluginPoint('anderes', 'x', 52.003, 13.0), // fremdes Plugin
      const AlertPoint(
        id: 'hotspot:1',
        kind: AlertKind.hotspot,
        position: GeoPoint(52.004, 13.0),
        source: 'feed',
      ),
    ];
    await repo.setPluginEnabled('feed', true);
    repo.pointsAround(center);
    await pumpEventQueue();

    expect(repo.pointsAround(center).map((p) => p.id), ['plugin:feed:ok']);
    final s = await pluginStatus();
    expect(s.pointCount, 1);
    expect(s.message, contains('3'));
  });

  test('Plugin-Punkte bekommen die Plugin-ID als source', () {
    final r = checkPluginPoints('feed', [
      const AlertPoint(
        id: 'plugin:feed:1',
        kind: AlertKind.live,
        position: center,
        source: 'osm',
        maxSpeed: 30,
        travelBearings: [10],
      ),
    ]);
    expect(r.accepted.single.source, 'feed');
    expect(r.accepted.single.maxSpeed, 30);
    expect(r.accepted.single.travelBearings, [10.0]);
  });

  group('Dedup', () {
    test(
      'Plugin-Punkt gleicher Art < 30 m von OSM entfällt, sonst bleibt er',
      () async {
        // 0,0001° Breite ≈ 11 m
        osm.result = SourceResult(points: [osmPoint('1', 52.001, 13.0)]);
        plugin.onFetch = (_) async => [
          pluginPoint(
            'feed',
            'dup',
            52.0011,
            13.0,
            kind: AlertKind.speedCamera,
          ),
          pluginPoint('feed', 'andereArt', 52.0011, 13.0, kind: AlertKind.live),
          pluginPoint(
            'feed',
            'weit',
            52.0015,
            13.0,
            kind: AlertKind.speedCamera,
          ),
        ];
        await repo.setPluginEnabled('feed', true);
        repo.pointsAround(center);
        await pumpEventQueue();

        final ids = repo.pointsAround(center).map((p) => p.id).toSet();
        expect(ids, {
          'osm:node/1',
          'plugin:feed:andereArt',
          'plugin:feed:weit',
        });
      },
    );
  });
}
