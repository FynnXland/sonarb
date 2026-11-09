import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';
import 'package:sonarb/features/alerts/plugin_slot.dart';
import 'package:sonarb/features/alerts/point_store.dart';

import 'fakes.dart';

const _debounce = Duration(milliseconds: 30);
const _wait = Duration(milliseconds: 110);

GeoBounds box(double south, double west, [double size = 0.2]) =>
    GeoBounds(south: south, west: west, north: south + size, east: west + size);

List<String> ids(Iterable<AlertPoint> ps) =>
    (ps.map((p) => p.id).toList()..sort());

void main() {
  group('PointStore', () {
    AlertPoint p(String n, double lat, double lon) => osmPoint(n, lat, lon);

    test('Zellen: aufnehmen, ergänzen, vollständig ersetzen', () {
      final store = PointStore();
      final area = box(51.0, 12.0, 0.3);
      expect(
        store.ingest(area, [
          p('1', 51.05, 12.05),
          p('2', 51.15, 12.15),
        ], authoritative: true),
        isTrue,
      );
      expect(ids(store.pointsIn(box(50.0, 11.0, 3))), [
        'osm:node/1',
        'osm:node/2',
      ]);

      // Unvollständig: ergänzt nur, nichts verschwindet.
      store.ingest(area, [p('3', 51.25, 12.25)], authoritative: false);
      expect(store.all, hasLength(3));

      // Vollständig: Punkt 1 gibt es nicht mehr, Zelle ohne Punkte bleibt als leer vermerkt.
      store.ingest(area, [
        p('2', 51.15, 12.15),
        p('3', 51.25, 12.25),
      ], authoritative: true);
      expect(ids(store.all), ['osm:node/2', 'osm:node/3']);
      expect(store.covers(const GeoPoint(51.05, 12.05)), isTrue);
    });

    test('gleiche Antwort noch einmal: keine Änderung gemeldet', () {
      final store = PointStore();
      final area = box(51.0, 12.0, 0.3);
      final list = [p('1', 51.05, 12.05)];
      store.ingest(area, list, authoritative: true);
      expect(store.ingest(area, list, authoritative: true), isFalse);
    });

    test('Randzellen werden nur ergänzt, nie geleert', () {
      final store = PointStore();
      store.ingest(box(51.0, 12.0, 0.2), [
        p('1', 51.05, 12.05),
      ], authoritative: true);
      // Ausschnitt schneidet die Zelle 51,0–51,1 nur zur Hälfte: Punkt 1 bleibt.
      store.ingest(box(51.05, 12.05, 0.2), const [], authoritative: true);
      expect(ids(store.all), ['osm:node/1']);
    });

    test('Speicherbudget: zuletzt benutzte Zellen bleiben', () {
      final store = PointStore(maxCells: 3);
      for (var i = 0; i < 3; i++) {
        store.ingest(box(50.0 + i, 12.0, 0.1), [
          p('$i', 50.05 + i, 12.05),
        ], authoritative: false);
      }
      // Zelle 0 wird angesehen und ist damit die jüngste.
      store.pointsIn(box(50.0, 12.0, 0.1));
      store.ingest(box(60.0, 12.0, 0.1), [
        p('9', 60.05, 12.05),
      ], authoritative: false);
      expect(store.cellCount, 3);
      expect(ids(store.all), ['osm:node/0', 'osm:node/2', 'osm:node/9']);
    });
  });

  group('Repository', () {
    late FakeOsm osm;
    late DateTime now;
    late AlertRepositoryImpl repo;

    Future<AlertRepositoryImpl> build({
      List<FakePlugin> plugins = const [],
      int maxCells = 800,
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
        overviewMaxCells: maxCells,
      );
    }

    setUp(() async {
      osm = FakeOsm();
      now = DateTime(2026, 1, 1, 12);
      repo = await build();
    });
    tearDown(() => repo.dispose());

    test('Zoomwechsel: einmal Geladenes kommt in jeder Stufe zurück', () async {
      final near = box(51.0, 12.0);
      osm.cameraResult = SourceResult(points: [osmPoint('1', 51.05, 12.05)]);
      repo.pointsInView(near);
      await Future<void>.delayed(_wait);
      final loads = osm.cameraLoads;

      osm.cameraResult = SourceResult(points: [osmPoint('2', 53.05, 14.05)]);
      final far = box(53.0, 14.0);
      repo.pointsInView(far);
      await Future<void>.delayed(_wait);

      // Herauszoomen über beide Gegenden und zurück: sofort alles da, ohne zu warten.
      final wide = box(50.0, 11.0, 4.0);
      expect(ids(repo.pointsInView(wide)), ['osm:node/1', 'osm:node/2']);
      expect(ids(repo.pointsInView(near)), ['osm:node/1']);
      expect(ids(repo.pointsInView(far)), ['osm:node/2']);
      await Future<void>.delayed(_wait);
      // Nur die Cache-Runde für den weiten Ausschnitt kam dazu, nicht erneut je Gegend.
      expect(osm.cameraLoads, loads + 2);
    });

    test(
      'nie leer, während nachgeladen wird oder der Abruf scheitert',
      () async {
        final view = box(51.0, 12.0);
        osm.cameraResult = SourceResult(points: [osmPoint('1', 51.05, 12.05)]);
        repo.pointsInView(view);
        await Future<void>.delayed(_wait);

        // Veraltet: neuer Abruf hängt, dann scheitert er mit leerer Antwort.
        now = now.add(const Duration(minutes: 11));
        final gate = Completer<SourceResult>();
        osm.cameraGate = gate;
        expect(ids(repo.pointsInView(view)), ['osm:node/1']);
        await Future<void>.delayed(_wait);
        expect(ids(repo.pointsInView(view)), ['osm:node/1'], reason: 'lädt');
        gate.complete(
          const SourceResult(points: [], error: 'Overpass überlastet'),
        );
        await Future<void>.delayed(_wait);
        expect(ids(repo.pointsInView(view)), ['osm:node/1'], reason: 'Fehler');
      },
    );

    test('vollständige Antwort ohne den Punkt entfernt ihn', () async {
      final view = box(51.0, 12.0);
      osm.cameraResult = SourceResult(points: [osmPoint('1', 51.05, 12.05)]);
      repo.pointsInView(view);
      await Future<void>.delayed(_wait);

      now = now.add(const Duration(minutes: 11));
      osm.cameraResult = const SourceResult(points: []);
      repo.pointsInView(view);
      await Future<void>.delayed(_wait);
      expect(repo.pointsInView(view), isEmpty);
    });

    test(
      'Umgebung der Position bleibt nach dem Weiterfahren bekannt',
      () async {
        osm.result = SourceResult(
          points: [
            osmPoint('1', 51.02, 12.02),
            osmPoint('9', 51.03, 12.03, kind: AlertKind.trafficSignal),
          ],
        );
        repo.pointsAround(const GeoPoint(51.02, 12.02));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        osm.result = SourceResult(points: [osmPoint('2', 51.52, 12.52)]);
        final there = const GeoPoint(51.52, 12.52);
        repo.pointsAround(there); // > 1,5 km weiter: lädt neu
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Warnlogik: nur die aktuelle Umgebung.
        expect(ids(repo.pointsAround(there, radiusMeters: 100000)), [
          'osm:node/2',
        ]);
        // Karte: auch die Gegend davor, aber ohne Ampeln.
        expect(ids(repo.pointsInView(box(50.9, 11.9, 1))), [
          'osm:node/1',
          'osm:node/2',
        ]);
      },
    );

    test('Fehler bei der Umgebung leert das Gedächtnis nicht', () async {
      osm.result = SourceResult(points: [osmPoint('1', 51.02, 12.02)]);
      repo.pointsAround(const GeoPoint(51.02, 12.02));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      now = now.add(const Duration(minutes: 11));
      osm.result = const SourceResult(points: [], error: 'Overpass überlastet');
      repo.pointsAround(const GeoPoint(51.02, 12.02));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(ids(repo.pointsInView(box(50.9, 11.9, 0.4))), ['osm:node/1']);
    });

    test(
      'Speicherbudget in Zellen: die zuletzt angesehene Gegend bleibt',
      () async {
        repo = await build(maxCells: 2);
        for (var i = 0; i < 3; i++) {
          osm.cameraResult = SourceResult(
            points: [osmPoint('$i', 50.05 + i * 2, 12.05)],
          );
          repo.pointsInView(box(50.0 + i * 2, 12.0, 0.1));
          await Future<void>.delayed(_wait);
        }
        final all = repo.pointsInView(box(49.0, 11.0, 7.0));
        expect(ids(all), ['osm:node/1', 'osm:node/2']);
      },
    );
  });

  group('Plugin-Punkte', () {
    late FakeOsm osm;
    late FakePlugin plugin;
    late DateTime now;
    late AlertRepositoryImpl repo;

    AlertPoint site(String n, double lat, double lon) =>
        pluginPoint('feed', n, lat, lon, kind: AlertKind.construction);

    setUp(() async {
      SharedPreferences.setMockInitialValues({'plugin.feed.enabled': true});
      osm = FakeOsm();
      plugin = FakePlugin('feed');
      now = DateTime(2026, 1, 1, 12);
      repo = AlertRepositoryImpl(
        osm: osm,
        hotspots: FakeHotspots(),
        plugins: [plugin],
        prefs: await SharedPreferences.getInstance(),
        clock: () => now,
        overviewDebounce: _debounce,
      );
    });
    tearDown(() => repo.dispose());

    Future<void> visit(GeoPoint p, List<AlertPoint> returns) async {
      plugin.onFetch = (_) async => returns;
      repo.pointsAround(p);
      await pumpEventQueue();
      // Die nächste Runde soll abrufen dürfen.
      now = now.add(const Duration(minutes: 1));
    }

    test(
      'Baustellen aus der früheren Gegend bleiben beim Weiterfahren',
      () async {
        const a = GeoPoint(51.0, 12.0), b = GeoPoint(51.5, 12.0); // ~55 km
        await visit(a, [site('a', 51.01, 12.0)]);
        await visit(b, [site('b', 51.51, 12.0)]);

        final view = box(50.9, 11.9, 0.9);
        expect(ids(repo.pointsInView(view)), [
          'plugin:feed:a',
          'plugin:feed:b',
        ]);
        // Die Warnlogik sieht nur, was nah ist.
        expect(ids(repo.pointsAround(b, radiusMeters: 3000)), [
          'plugin:feed:b',
        ]);
      },
    );

    test(
      'in der abgerufenen Gegend ersetzt die Antwort, was fehlt, ist weg',
      () async {
        const a = GeoPoint(51.0, 12.0);
        await visit(a, [site('a1', 51.01, 12.0), site('a2', 51.02, 12.0)]);
        await visit(a, [site('a2', 51.02, 12.0)]);
        expect(ids(repo.pointsInView(box(50.9, 11.9, 0.3))), [
          'plugin:feed:a2',
        ]);
      },
    );

    test('Punkte gelten nur, solange sie gültig sind', () async {
      const a = GeoPoint(51.0, 12.0), b = GeoPoint(51.5, 12.0);
      await visit(a, [site('a', 51.01, 12.0)]);
      final validity = AlertRepositoryImpl.pluginValidity(
        plugin.refreshInterval,
      );
      await visit(b, [site('b', 51.51, 12.0)]);

      now = now.add(validity); // a wurde vor validity + 2 min geliefert
      repo.pointsInView(box(50.9, 11.9, 0.9));
      repo.pointsAround(b); // stößt das Verfallen an
      await pumpEventQueue();
      expect(ids(repo.pointsInView(box(50.9, 11.9, 0.9))), ['plugin:feed:b']);
    });

    test(
      'Plugin-Punkt und OSM-Blitzer an einer Stelle: ein Punkt in der Karte',
      () async {
        const a = GeoPoint(51.0, 12.0);
        osm.result = SourceResult(points: [osmPoint('1', 51.0100, 12.0)]);
        await visit(a, [
          pluginPoint('feed', 'x', 51.0102, 12.0, kind: AlertKind.speedCamera),
        ]);
        repo.pointsAround(a);
        await pumpEventQueue();
        final got = repo.pointsInView(box(50.9, 11.9, 0.3));
        expect(ids(got), ['osm:node/1']);
        expect(got.single.sources.map((s) => s.id), ['osm', 'feed']);
      },
    );

    test('PluginSlot: Obergrenze für gemerkte Punkte', () {
      final s = PluginSlot(plugin, enabled: true);
      s.absorb(
        [for (var i = 0; i < PluginSlot.maxKnown + 10; i++) site('$i', 51, 12)],
        box(40, 5, 0.1),
        now,
      );
      expect(s.points, hasLength(PluginSlot.maxKnown));
    });
  });
}
