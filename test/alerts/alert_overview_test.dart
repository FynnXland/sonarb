import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';

import 'fakes.dart';

const _debounce = Duration(milliseconds: 40);
const _wait = Duration(milliseconds: 120);

GeoBounds box(double south, double west, [double size = 0.2]) =>
    GeoBounds(south: south, west: west, north: south + size, east: west + size);

void main() {
  late FakeOsm osm;
  late FakeHotspots hotspots;
  late DateTime now;
  late AlertRepositoryImpl repo;

  Future<AlertRepositoryImpl> build(FixedPointSource source) async =>
      AlertRepositoryImpl(
        osm: source,
        hotspots: hotspots,
        plugins: const [],
        prefs: await SharedPreferences.getInstance(),
        clock: () => now,
        overviewDebounce: _debounce,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    osm = FakeOsm();
    hotspots = FakeHotspots();
    now = DateTime(2026, 1, 1, 12);
    repo = await build(osm);
  });

  tearDown(() => repo.dispose());

  test('antwortet sofort mit dem bekannten Stand, ohne zu warten', () async {
    osm.result = SourceResult(points: [osmPoint('1', 52.0, 13.0)]);
    repo.pointsAround(const GeoPoint(52.0, 13.0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final before =
        osm.cameraLoads; // Blitzer im Umkreis der Position, nicht die Übersicht

    expect(repo.pointsInView(box(51.95, 12.95)).map((p) => p.id), [
      'osm:node/1',
    ]);
    expect(osm.cameraLoads, before, reason: 'erst nach der Entprellung');
  });

  test(
    'Entprellung: viele Bewegungen, eine Abfrage nach der letzten',
    () async {
      for (var i = 0; i < 5; i++) {
        repo.pointsInView(box(51.9 + i * 0.01, 12.9));
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      expect(osm.cameraLoads, 0);
      await Future<void>.delayed(_wait);
      expect(osm.cameraLoads, 1);
      expect(osm.cameraAreas.single.south, closeTo(51.94, 1e-9));
    },
  );

  test(
    'zu großer Ausschnitt: Quelle liest nur den Cache, Punkte bleiben',
    () async {
      osm.cameraResult = SourceResult(
        points: [osmPoint('7', 51.05, 12.05)],
        fromCache: true,
      );
      final big = box(50.5, 11.5, maxOverviewSpanDeg + 0.5);
      repo.pointsInView(big);
      await Future<void>.delayed(_wait);
      expect(osm.cameraLoads, 1, reason: 'die Quelle entscheidet: nur Cache');
      expect(osm.cameraAreas.single.north - osm.cameraAreas.single.south, 1.0);
      expect(repo.pointsInView(big).map((p) => p.id), ['osm:node/7']);

      // Gleicher Ausschnitt und Verschieben darin: keine neue Cache-Runde.
      repo.pointsInView(big);
      repo.pointsInView(box(50.6, 11.6, 0.8));
      await Future<void>.delayed(_wait);
      expect(osm.cameraLoads, 1);
    },
  );

  test('genau maxOverviewSpanDeg ist noch erlaubt', () async {
    repo.pointsInView(box(51.0, 12.0, maxOverviewSpanDeg));
    await Future<void>.delayed(_wait);
    expect(osm.cameraLoads, 1);
  });

  test('neue Punkte erscheinen und melden sich über changes', () async {
    osm.cameraResult = SourceResult(
      points: [osmPoint('7', 51.05, 12.05), osmPoint('8', 51.15, 12.15)],
    );
    await Future<void>.delayed(
      const Duration(milliseconds: 10),
    ); // Start-Hotspots
    var changes = 0;
    final sub = repo.changes.listen((_) => changes++);
    final view = box(51.0, 12.0);
    expect(repo.pointsInView(view), isEmpty);
    await Future<void>.delayed(_wait);

    expect(changes, 1);
    expect(repo.pointsInView(view).map((p) => p.id).toSet(), {
      'osm:node/7',
      'osm:node/8',
    });
    // Ein kleinerer Ausschnitt darin sieht nur seine Punkte.
    expect(repo.pointsInView(box(51.1, 12.1, 0.1)).map((p) => p.id), [
      'osm:node/8',
    ]);
    await sub.cancel();
  });

  test('abgedeckter Ausschnitt lädt nicht neu, kein changes-Kreis', () async {
    osm.cameraResult = SourceResult(points: [osmPoint('7', 51.05, 12.05)]);
    await Future<void>.delayed(
      const Duration(milliseconds: 10),
    ); // Start-Hotspots
    var changes = 0;
    final sub = repo.changes.listen((_) => changes++);
    repo.pointsInView(box(51.0, 12.0, 0.3));
    await Future<void>.delayed(_wait);
    expect(osm.cameraLoads, 1);

    // Gleicher und kleinerer Ausschnitt darin: bekannter Stand reicht.
    repo.pointsInView(box(51.0, 12.0, 0.3));
    repo.pointsInView(box(51.05, 12.05, 0.1));
    await Future<void>.delayed(_wait);
    expect(osm.cameraLoads, 1);
    expect(changes, 1);

    // Nach dem Verfall wird neu angefragt, aber ohne neue Punkte kein changes.
    now = now.add(const Duration(minutes: 11));
    repo.pointsInView(box(51.0, 12.0, 0.3));
    await Future<void>.delayed(_wait);
    expect(osm.cameraLoads, 2);
    expect(changes, 1);
    await sub.cancel();
  });

  test('Fehler: Wiederholung frühestens nach einer Minute', () async {
    osm.cameraResult = const SourceResult(
      points: [],
      error: 'Overpass überlastet, Daten unvollständig',
    );
    final view = box(51.0, 12.0);
    repo.pointsInView(view);
    await Future<void>.delayed(_wait);
    expect(osm.cameraLoads, 1);

    now = now.add(const Duration(seconds: 30));
    repo.pointsInView(view);
    await Future<void>.delayed(_wait);
    expect(osm.cameraLoads, 1);

    now = now.add(const Duration(seconds: 40));
    repo.pointsInView(view);
    await Future<void>.delayed(_wait);
    expect(osm.cameraLoads, 2);
  });

  test('Quelle wirft: kein Absturz, Ausschnitt bleibt leer', () async {
    final failing = _ThrowingOsm();
    final r = await build(failing);
    r.pointsInView(box(51.0, 12.0));
    await Future<void>.delayed(_wait);
    expect(failing.calls, 1);
    expect(r.pointsInView(box(51.0, 12.0)), isEmpty);
    await r.dispose();
  });

  test('Übersichtspunkte bleiben aus pointsAround heraus', () async {
    osm.cameraResult = SourceResult(points: [osmPoint('7', 51.05, 12.05)]);
    final view = box(51.0, 12.0);
    repo.pointsInView(view);
    await Future<void>.delayed(_wait);
    expect(repo.pointsInView(view), hasLength(1));
    expect(
      repo.pointsAround(const GeoPoint(51.05, 12.05), radiusMeters: 5000),
      isEmpty,
    );
  });

  test('Umgebung und Übersicht zusammen, ohne Dubletten', () async {
    osm.result = SourceResult(points: [osmPoint('1', 51.02, 12.02)]);
    osm.cameraResult = SourceResult(
      points: [osmPoint('1', 51.02, 12.02), osmPoint('2', 51.1, 12.1)],
    );
    repo.pointsAround(const GeoPoint(51.02, 12.02));
    final view = box(51.0, 12.0);
    repo.pointsInView(view);
    await Future<void>.delayed(_wait);
    final ids = repo.pointsInView(view).map((p) => p.id).toList()..sort();
    expect(ids, ['osm:node/1', 'osm:node/2']);
  });

  test('nach dispose keine Abfrage mehr', () async {
    repo.pointsInView(box(51.0, 12.0));
    await repo.dispose();
    await Future<void>.delayed(_wait);
    expect(osm.cameraLoads, 0);
    expect(repo.pointsInView(box(51.0, 12.0)), isEmpty);
  });
}

class _ThrowingOsm extends FakeOsm {
  int calls = 0;

  @override
  Future<SourceResult> loadCameras(GeoBounds area) {
    calls++;
    return Future.error(StateError('kaputt'));
  }
}
