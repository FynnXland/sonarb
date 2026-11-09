import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';

import 'fakes.dart';

const center = GeoPoint(52.0, 13.0);
// 0,01° Breite ≈ 1,1 km
const near = GeoPoint(52.01, 13.0);
const elsewhere = GeoPoint(52.5, 13.0);

const _debounce = Duration(milliseconds: 40);
const _wait = Duration(milliseconds: 120);

GeoBounds box(double south, double west, [double size = 0.2]) =>
    GeoBounds(south: south, west: west, north: south + size, east: west + size);

void main() {
  late FakeOsm osm;
  late DateTime now;
  late AlertRepositoryImpl repo;

  Future<AlertRepositoryImpl> build({
    List<DataSourcePlugin> plugins = const [],
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    return AlertRepositoryImpl(
      osm: osm,
      hotspots: FakeHotspots(),
      plugins: plugins,
      prefs: await SharedPreferences.getInstance(),
      clock: () => now,
      overviewDebounce: _debounce,
    );
  }

  setUp(() async {
    osm = FakeOsm();
    now = DateTime(2026, 1, 1, 12);
    repo = await build();
  });

  tearDown(() => repo.dispose());

  group('coverageAround', () {
    test('vor dem ersten Abruf und währenddessen: lädt', () async {
      expect(repo.coverageAround(center).state, CoverageState.loading);
      osm.gate = Completer<SourceResult>();
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(repo.coverageAround(center).state, CoverageState.loading);

      osm.gate!.complete(const SourceResult(points: []));
      await pumpEventQueue();
      expect(
        repo.coverageAround(center).state,
        CoverageState.ready,
        reason: 'geladen, aber leer: hier gibt es nichts',
      );
    });

    test('in der Nähe abgedeckt, in einer neuen Gegend wieder lädt', () async {
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(repo.coverageAround(near).state, CoverageState.ready);
      expect(repo.coverageAround(elsewhere).state, CoverageState.loading);

      osm.gate = Completer<SourceResult>();
      repo.pointsAround(elsewhere);
      await pumpEventQueue();
      expect(repo.coverageAround(elsewhere).state, CoverageState.loading);
      expect(
        repo.coverageAround(center).state,
        CoverageState.ready,
        reason: 'die alte Gegend bleibt abgedeckt',
      );
    });

    test(
      'Fehlschlag ohne Daten: failed, beim neuen Versuch wieder lädt',
      () async {
        osm.result = const SourceResult(
          points: [],
          error: 'Overpass nicht erreichbar, Daten unvollständig',
        );
        repo.pointsAround(center);
        await pumpEventQueue();
        expect(repo.coverageAround(center).state, CoverageState.failed);
        expect(
          repo.coverageAround(elsewhere).state,
          CoverageState.loading,
          reason: 'der Fehlschlag gilt nur für seine Gegend',
        );

        now = now.add(const Duration(minutes: 2));
        osm.gate = Completer<SourceResult>();
        repo.pointsAround(center);
        await pumpEventQueue();
        expect(repo.coverageAround(center).state, CoverageState.loading);

        osm.gate!.complete(SourceResult(points: [osmPoint('1', 52.0, 13.0)]));
        await pumpEventQueue();
        expect(repo.coverageAround(center).state, CoverageState.ready);
      },
    );

    test('geworfener Fehler zählt als Fehlschlag', () async {
      osm.throwOnLoad = Exception('kaputt');
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(repo.coverageAround(center).state, CoverageState.failed);
    });

    test('Blitzer aus dem Cache, Abruf gescheitert: stale', () async {
      osm.result = SourceResult(
        points: [osmPoint('1', 52.0, 13.0)],
        error: 'Overpass überlastet, Daten aus dem Cache',
      );
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(repo.coverageAround(center).state, CoverageState.stale);
    });

    test(
      'nur Ampeln und Tempolimits fehlen: Blitzer gelten als geladen',
      () async {
        osm.result = SourceResult(
          points: [osmPoint('1', 52.0, 13.0)],
          error: 'Overpass überlastet, Ampeln und Tempolimits unvollständig',
          errorInDetailsOnly: true,
        );
        repo.pointsAround(center);
        await pumpEventQueue();
        expect(repo.coverageAround(center).state, CoverageState.ready);
      },
    );

    test('Laden und Ergebnis melden sich über watchStatus', () async {
      final seen = <CoverageState>[];
      final sub = repo.watchStatus().listen(
        (_) => seen.add(repo.coverageAround(center).state),
      );
      await pumpEventQueue();
      osm.gate = Completer<SourceResult>();
      repo.pointsAround(center);
      await pumpEventQueue();
      osm.gate!.complete(const SourceResult(points: []));
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.last, CoverageState.ready);
      expect(seen, contains(CoverageState.loading));
    });

    test('Plugin lädt zum ersten Mal: Name in loadingPlugins', () async {
      await repo.dispose();
      final fetch = Completer<List<Never>>();
      final plugin = FakePlugin('feed', onFetch: (_) => fetch.future);
      repo = await build(
        plugins: [plugin],
        prefs: {'plugin.feed.enabled': true},
      );
      repo.pointsAround(center);
      await pumpEventQueue();
      final during = repo.coverageAround(center);
      expect(during.state, CoverageState.ready);
      expect(during.loadingPlugins, ['Plugin feed']);

      fetch.complete(const []);
      await pumpEventQueue();
      expect(repo.coverageAround(center).loadingPlugins, isEmpty);
    });

    test('gescheitertes Plugin lädt nicht mehr', () async {
      await repo.dispose();
      final plugin = FakePlugin(
        'feed',
        onFetch: (_) => Future.error(Exception('weg')),
      );
      repo = await build(
        plugins: [plugin],
        prefs: {'plugin.feed.enabled': true},
      );
      repo.pointsAround(center);
      await pumpEventQueue();
      expect(repo.coverageAround(center).loadingPlugins, isEmpty);
    });
  });

  group('coverageInView', () {
    test('lädt bis zur ersten Antwort, danach geladen', () async {
      final view = box(51.95, 12.95);
      osm.cameraGate = Completer<SourceResult>();
      repo.pointsInView(view);
      expect(repo.coverageInView(view).state, CoverageState.loading);
      await Future<void>.delayed(_wait);
      expect(repo.coverageInView(view).state, CoverageState.loading);

      osm.cameraGate!.complete(const SourceResult(points: []));
      await pumpEventQueue();
      expect(repo.coverageInView(view).state, CoverageState.ready);
    });

    test(
      'Ende der Abfrage meldet sich über watchStatus, auch ohne Punkte',
      () async {
        final view = box(51.95, 12.95);
        var statuses = 0;
        final sub = repo.watchStatus().listen((_) => statuses++);
        await pumpEventQueue();
        final before = statuses;
        repo.pointsInView(view);
        await Future<void>.delayed(_wait);
        await sub.cancel();
        expect(statuses, greaterThan(before));
      },
    );

    test('Fehlschlag: failed ohne Punkte, stale mit Punkten', () async {
      final empty = box(51.95, 12.95);
      osm.cameraResult = const SourceResult(points: [], error: 'weg');
      repo.pointsInView(empty);
      await Future<void>.delayed(_wait);
      expect(repo.coverageInView(empty).state, CoverageState.failed);

      final cached = box(50.0, 10.0);
      osm.cameraResult = SourceResult(
        points: [osmPoint('1', 50.1, 10.1)],
        error: 'weg',
      );
      repo.pointsInView(cached);
      await Future<void>.delayed(_wait);
      expect(repo.coverageInView(cached).state, CoverageState.stale);
    });

    test('zu großer Ausschnitt: tooWide', () {
      final wide = box(50.0, 10.0, 2);
      repo.pointsInView(wide);
      expect(repo.coverageInView(wide).state, CoverageState.tooWide);
    });
  });
}
