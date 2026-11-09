import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';

import 'fakes.dart';

const here = GeoPoint(52.0, 13.0);

void main() {
  late FakeOsm osm;
  late DateTime now;
  late AlertRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    osm = FakeOsm();
    now = DateTime(2026, 10, 30, 12);
    repo = AlertRepositoryImpl(
      osm: osm,
      hotspots: FakeHotspots(),
      plugins: const [],
      prefs: await SharedPreferences.getInstance(),
      clock: () => now,
      overviewDebounce: const Duration(milliseconds: 20),
    );
  });
  tearDown(() => repo.dispose());

  Future<SourceStatus> osmStatus() async =>
      (await repo.watchStatus().first).firstWhere((s) => s.id == 'osm');

  Future<void> load() async {
    repo.pointsAround(here);
    await pumpEventQueue();
    now = now.add(const Duration(minutes: 2)); // nächster Abruf darf kommen
  }

  test(
    'Ampeln und Tempolimits gescheitert, Blitzer da: kein Ausfall',
    () async {
      osm.result = SourceResult(
        points: [osmPoint('1', 52.0, 13.0)],
        error: 'Overpass überlastet, Ampeln und Tempolimits unvollständig',
        errorInDetailsOnly: true,
      );
      await load();
      final s = await osmStatus();
      expect(s.status, PluginStatus.ok);
      expect(
        s.message,
        contains('überlastet'),
        reason: 'die Meldung bleibt sichtbar',
      );
    },
  );

  test('Details gescheitert und gar keine Blitzer in der Gegend: auch kein Ausfall', () async {
    osm.result = const SourceResult(
      points: [],
      error: 'Overpass überlastet, Ampeln und Tempolimits unvollständig',
      errorInDetailsOnly: true,
    );
    await load();
    expect((await osmStatus()).status, PluginStatus.ok);
    expect(repo.coverageAround(here).state, isNot(CoverageState.failed));
  });

  test('ein Fernblock scheitert, die Umgebung ist da: kein Ausfall', () async {
    osm.result = SourceResult(points: [osmPoint('1', 52.0, 13.0)]);
    osm.cameraResult = const SourceResult(
      points: [],
      error: 'Overpass nicht erreichbar, Daten unvollständig',
    );
    repo.dataScope = const DataScope(detailRadiusMeters: 25000);
    await load();
    final s = await osmStatus();
    expect(s.status, PluginStatus.ok);
    expect(repo.coverageAround(here).state, CoverageState.stale);
    expect(repo.pointsAround(here).map((p) => p.id), ['osm:node/1']);
  });

  test('gespeicherte Daten bei Serverfehler: kein Ausfall', () async {
    osm.result = SourceResult(
      points: [osmPoint('1', 52.0, 13.0)],
      error: 'Overpass nicht erreichbar, Daten aus dem Cache',
      fromCache: true,
    );
    await load();
    expect((await osmStatus()).status, PluginStatus.ok);
  });

  test('Abruf scheitert, früherer Stand in der Nähe: kein Ausfall', () async {
    osm.result = SourceResult(points: [osmPoint('1', 52.0, 13.0)]);
    await load();
    osm.result = const SourceResult(points: [], error: 'Overpass überlastet');
    await load();
    expect((await osmStatus()).status, PluginStatus.ok);
  });

  test(
    'echter Ausfall: kein Cache, Blitzer gescheitert, genau ein Wechsel',
    () async {
      final seen = <PluginStatus>[];
      final sub = repo.watchStatus().listen(
        (l) => seen.add(l.firstWhere((s) => s.id == 'osm').status),
      );
      osm.result = const SourceResult(
        points: [],
        error: 'Overpass nicht erreichbar, Daten unvollständig',
      );
      await load();
      await load(); // zweiter Fehlschlag ändert nichts
      expect((await osmStatus()).status, PluginStatus.error);
      expect(repo.coverageAround(here).state, CoverageState.failed);

      osm.result = SourceResult(points: [osmPoint('1', 52.0, 13.0)]);
      await load();
      expect((await osmStatus()).status, PluginStatus.ok);

      // Verlauf ohne „lädt“: idle → error → ok, ohne Hin und Her dazwischen.
      final steady = [
        for (final s in seen)
          if (s != PluginStatus.loading) s,
      ];
      final changes = <PluginStatus>[];
      for (final s in steady) {
        if (changes.isEmpty || changes.last != s) changes.add(s);
      }
      expect(changes, [PluginStatus.idle, PluginStatus.error, PluginStatus.ok]);
      await sub.cancel();
    },
  );

  test(
    'Ausfall an anderer Stelle weit weg: dort gilt er, hier nicht',
    () async {
      osm.result = SourceResult(points: [osmPoint('1', 52.0, 13.0)]);
      await load();
      const far = GeoPoint(53.5, 10.0);
      osm.result = const SourceResult(points: [], error: 'Overpass überlastet');
      repo.pointsAround(far);
      await pumpEventQueue();
      expect((await osmStatus()).status, PluginStatus.error);
      expect(repo.coverageAround(here).state, isNot(CoverageState.failed));
    },
  );
}
