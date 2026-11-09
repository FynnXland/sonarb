import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/alerts/alert_repository_impl.dart';
import 'package:sonarb/features/alerts/country_loader.dart';
import 'package:sonarb/features/alerts/merge_points.dart';
import 'package:sonarb/features/alerts/plugin_slot.dart';
import 'package:sonarb/features/osm/country_cameras.dart';

import 'fakes.dart';

/// Quelle, die auch ganz Deutschland laden kann (aufgezeichnet statt echt).
class FakeCountryOsm extends FakeOsm implements CountryCameraSource {
  int countryLoads = 0;
  CountryLoadResult next = CountryLoadResult(
    fetchedAt: DateTime(2026, 1, 1, 12),
    points: 5190,
    tiles: 4800,
  );
  Completer<CountryLoadResult>? countryGate;

  @override
  Future<CountryLoadResult> loadCountryCameras() {
    countryLoads++;
    return countryGate?.future ?? Future.value(next);
  }
}

void main() {
  late DateTime now;

  setUp(() => now = DateTime(2026, 1, 1, 12));

  group('CountryLoader', () {
    late SharedPreferences prefs;
    late FakeCountryOsm osm;
    late int changes;
    var idle = true;

    CountryLoader make({bool enabled = true, FakeCountryOsm? source}) =>
        CountryLoader(
          source: source ?? osm,
          prefs: prefs,
          clock: () => now,
          onChanged: () => changes++,
          canRun: () => idle,
          enabled: enabled,
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      osm = FakeCountryOsm();
      changes = 0;
      idle = true;
    });

    test('läuft einmal, dann erst nach einer Woche wieder', () async {
      final l = make();
      expect(l.state, CountryState.idle);
      await l.poke();
      expect(osm.countryLoads, 1);
      expect(l.state, CountryState.ok);
      expect(l.pointCount, 5190);
      expect(l.updatedAt, DateTime(2026, 1, 1, 12));

      expect(l.poke(), isNull);
      now = now.add(const Duration(days: 6, hours: 23));
      expect(l.poke(), isNull);
      now = now.add(const Duration(hours: 2));
      await l.poke();
      expect(osm.countryLoads, 2);
    });

    test('nie zwei Läufe gleichzeitig, Zustand „lädt“ sichtbar', () async {
      osm.countryGate = Completer();
      final l = make();
      final run = l.poke();
      expect(l.state, CountryState.loading);
      expect(l.poke(), isNull);
      expect(osm.countryLoads, 1);
      osm.countryGate!.complete(osm.next);
      await run;
      expect(l.state, CountryState.ok);
      expect(changes, greaterThanOrEqualTo(2), reason: 'Start und Ende');
    });

    test('Stand überlebt den Neustart', () async {
      await make().poke();
      final again = make();
      expect(again.updatedAt, DateTime(2026, 1, 1, 12));
      expect(again.pointCount, 5190);
      expect(again.poke(), isNull, reason: 'frisch');
      expect(again.state, CountryState.ok);
    });

    test('Fehlschläge: wachsende Pause, Fehlertext, danach Erfolg', () async {
      osm.next = const CountryLoadResult(error: 'Overpass überlastet');
      final l = make();
      await l.poke();
      expect(l.state, CountryState.error);
      expect(l.message, 'Overpass überlastet');

      now = now.add(const Duration(minutes: 29));
      expect(l.poke(), isNull);
      now = now.add(const Duration(minutes: 2)); // 31 min
      await l.poke();
      expect(osm.countryLoads, 2);

      now = now.add(const Duration(hours: 1, minutes: 59));
      expect(l.poke(), isNull); // zweite Pause: 2 h
      now = now.add(const Duration(minutes: 2));
      await l.poke();
      expect(osm.countryLoads, 3);

      osm.next = CountryLoadResult(fetchedAt: now, points: 1, tiles: 1);
      now = now.add(const Duration(hours: 12, minutes: 1));
      await l.poke();
      expect(l.state, CountryState.ok);
      expect(l.message, isNull);
    });

    test('Fehler bei vorhandenem Stand: Stand bleibt, Meldung dabei', () async {
      final l = make();
      await l.poke();
      osm.next = const CountryLoadResult(error: 'Overpass überlastet');
      now = now.add(const Duration(days: 8));
      await l.poke();
      expect(l.state, CountryState.ok);
      expect(l.updatedAt, DateTime(2026, 1, 1, 12));
      expect(l.message, 'Overpass überlastet');
    });

    test(
      'nicht, wenn die Fahrt etwas Dringendes hat oder abgeschaltet ist',
      () async {
        final l = make();
        idle = false;
        expect(l.poke(), isNull);
        idle = true;
        l.enabled = false;
        expect(l.state, CountryState.off);
        expect(l.poke(), isNull);
        expect(osm.countryLoads, 0);
        l.enabled = true; // schaltet an und startet gleich
        expect(osm.countryLoads, 1);
      },
    );

    test('Quelle ohne Länderlauf: aus', () {
      final l = CountryLoader(
        source: null,
        prefs: prefs,
        clock: () => now,
        onChanged: () {},
      );
      expect(l.state, CountryState.off);
      expect(l.poke(), isNull);
    });
  });

  group('Repository', () {
    late FakeCountryOsm osm;
    late FakePlugin plugin;
    late AlertRepositoryImpl repo;
    late SharedPreferences prefs;

    Future<AlertRepositoryImpl> build({
      Map<String, Object> stored = const {},
      FakeOsm? source,
    }) async {
      SharedPreferences.setMockInitialValues({
        'plugin.feed.enabled': true,
        ...stored,
      });
      prefs = await SharedPreferences.getInstance();
      return AlertRepositoryImpl(
        osm: source ?? osm,
        hotspots: FakeHotspots(),
        plugins: [plugin],
        prefs: prefs,
        clock: () => now,
        overviewDebounce: const Duration(milliseconds: 20),
      );
    }

    setUp(() async {
      osm = FakeCountryOsm();
      plugin = FakePlugin('feed');
      repo = await build();
    });
    tearDown(() => repo.dispose());

    const here = GeoPoint(52.0, 13.0);

    double radiusOf(GeoBounds b) =>
        (b.north - b.south) / 2 * 111320; // Meter, Nord-Süd

    test('Standard: 5 km, Deutschland aus (wie im Vertrag)', () {
      expect(repo.dataScope, const DataScope());
      expect(repo.dataScope.countryCameras, isFalse);
    });

    test('Umkreis gilt für Blitzer und Plugins, Ampeln und Tempolimits bleiben bei 3 km', () async {
      repo.pointsAround(here);
      await pumpEventQueue();
      expect(
        radiusOf(osm.areas.last),
        closeTo(3000, 1),
        reason: 'Ampeln, Tempolimits',
      );
      expect(radiusOf(plugin.lastArea!), closeTo(5000, 1));
      double camsRadius() {
        final north = osm.cameraAreas.map((a) => a.north).reduce(math.max);
        final south = osm.cameraAreas.map((a) => a.south).reduce(math.min);
        return (north - south) / 2 * 111320;
      }

      expect(camsRadius(), closeTo(5000, 1));

      osm.cameraAreas.clear();
      repo.dataScope = const DataScope(detailRadiusMeters: 25000);
      repo.pointsAround(
        here,
      ); // gleiche Stelle: ohne Wechsel gäbe es keinen neuen Abruf
      await pumpEventQueue();
      expect(radiusOf(osm.areas.last), closeTo(3000, 1));
      expect(radiusOf(plugin.lastArea!), closeTo(25000, 1));
      expect(camsRadius(), closeTo(25000, 1));
      expect(
        osm.cameraAreas.length,
        greaterThan(1),
        reason: 'Blöcke bis 0,49°',
      );
    });

    test(
      'Radiusgrenze: bis 3 km eine Abfrage, kleiner heißt kleiner',
      () async {
        for (final (radius, expected) in [(2000.0, 2000.0), (3000.0, 3000.0)]) {
          osm.areas.clear();
          osm.cameraAreas.clear();
          repo.dataScope = DataScope(detailRadiusMeters: radius);
          repo.pointsAround(here);
          await pumpEventQueue();
          expect(
            radiusOf(osm.areas.last),
            closeTo(expected, 1),
            reason: '$radius',
          );
          expect(
            osm.cameraAreas,
            isEmpty,
            reason: 'der kleine Radius deckt die Blitzer ab',
          );
          now = now.add(const Duration(minutes: 11));
        }
      },
    );

    test('Umkreis zurück auf klein: Blitzer des großen Kreises fallen nicht aus dem Speicher der Karte', () async {
      osm.cameraResult = SourceResult(points: [osmPoint('9', 52.1, 13.1)]);
      repo.dataScope = const DataScope(detailRadiusMeters: 25000);
      repo.pointsAround(here);
      await pumpEventQueue();
      expect(
        repo.pointsAround(here, radiusMeters: 50000).map((p) => p.id),
        contains('osm:node/9'),
      );

      repo.dataScope = const DataScope(detailRadiusMeters: 2000);
      now = now.add(const Duration(minutes: 11));
      repo.pointsAround(here);
      await pumpEventQueue();
      // Die Warnlogik sieht den kleinen Kreis; die Karte behält, was sie schon kennt.
      expect(
        repo.pointsAround(here, radiusMeters: 50000).map((p) => p.id),
        isNot(contains('osm:node/9')),
      );
      const view = GeoBounds(south: 51.9, west: 12.9, north: 52.3, east: 13.3);
      expect(repo.pointsInView(view).map((p) => p.id), contains('osm:node/9'));
    });

    test('Umkreis wird begrenzt und gemerkt', () async {
      repo.dataScope = const DataScope(detailRadiusMeters: 500000);
      expect(repo.dataScope.detailRadiusMeters, DataScope.maxRadiusMeters);
      repo.dataScope = const DataScope(detailRadiusMeters: 100);
      expect(repo.dataScope.detailRadiusMeters, DataScope.minRadiusMeters);
      repo.dataScope = const DataScope(
        detailRadiusMeters: 10000,
        countryCameras: false,
      );
      await repo.dispose();

      repo = await build(
        stored: {
          'scope.detailRadiusMeters': 10000.0,
          'scope.countryCameras': false,
        },
      );
      expect(
        repo.dataScope,
        const DataScope(detailRadiusMeters: 10000, countryCameras: false),
      );
    });

    test('Zwei Takte: Ampeln/Tempolimits nach 750 m, Blitzer nach einem Viertel des Radius', () async {
      repo.dataScope = const DataScope(detailRadiusMeters: 20000);
      repo.pointsAround(here);
      await pumpEventQueue();
      final loads = osm.loads, cams = osm.cameraLoads, fetches = plugin.fetches;
      // 4 km weiter: Ampeln und Tempolimits laden neu, Blitzer und Plugins (Schwelle 5 km) nicht.
      repo.pointsAround(const GeoPoint(52.036, 13.0));
      await pumpEventQueue();
      expect(osm.loads, loads + 1);
      expect(osm.cameraLoads, cams);
      expect(plugin.fetches, fetches);
      // 7 km vom Start: Blitzer und Plugins sind dran.
      repo.pointsAround(const GeoPoint(52.07, 13.0));
      await pumpEventQueue();
      expect(osm.cameraLoads, greaterThan(cams));
      expect(plugin.fetches, fetches + 1);
    });

    test('Umkreis wandert mit: Details nach einem Viertel von 3 km, Blitzer nach einem Viertel von 8 km', () async {
      repo.dataScope = const DataScope(detailRadiusMeters: 8000);
      repo.pointsAround(here);
      await pumpEventQueue();
      final loads = osm.loads, cams = osm.cameraLoads;
      // 0,006° ≈ 670 m: unter 750 m.
      repo.pointsAround(const GeoPoint(52.006, 13.0));
      await pumpEventQueue();
      expect(osm.loads, loads);
      // 0,008° ≈ 890 m: Ampeln und Tempolimits, Blitzer noch nicht (2 km).
      repo.pointsAround(const GeoPoint(52.008, 13.0));
      await pumpEventQueue();
      expect(osm.loads, loads + 1);
      expect(osm.cameraLoads, cams);
      // 0,019° ≈ 2,1 km vom Start: jetzt auch die Blitzer.
      repo.pointsAround(const GeoPoint(52.019, 13.0));
      await pumpEventQueue();
      expect(osm.cameraLoads, greaterThan(cams));
      final c = repo.loadedCircle!;
      expect(c.center, const GeoPoint(52.019, 13.0));
      expect(c.radiusMeters, 8000);
      expect(c.complete, isTrue);
    });

    test(
      'Kreis zum Anzeigen: erst nach dem Laden, unvollständig bei Fehler',
      () async {
        expect(repo.loadedCircle, isNull);
        osm.result = const SourceResult(
          points: [],
          error: 'Overpass überlastet',
        );
        repo.pointsAround(here);
        await pumpEventQueue();
        // Fehler ohne Daten: es gibt keinen geladenen Kreis.
        expect(repo.loadedCircle, isNull);

        osm.result = SourceResult(
          points: [osmPoint('1', 52.0, 13.0)],
          notice: 'Ampeln und Tempolimits werden nachgeladen',
        );
        now = now.add(const Duration(minutes: 2));
        repo.pointsAround(here);
        await pumpEventQueue();
        expect(
          repo.loadedCircle!.complete,
          isFalse,
          reason: 'Details laden noch',
        );
        expect(repo.loadedCircle!.radiusMeters, 5000);
      },
    );

    test(
      'Deutschland: Lauf nach der Umgebung, Statuszeile mit Stand',
      () async {
        repo.dataScope = const DataScope(countryCameras: true);
        repo.pointsAround(here);
        await pumpEventQueue();
        repo.pointsAround(here); // Umgebung fertig: jetzt darf das Land
        await pumpEventQueue();
        expect(osm.countryLoads, 1);

        final rows = await repo.watchStatus().first;
        final country = rows.firstWhere((s) => s.id == 'country');
        expect(country.name, 'Blitzer Deutschland');
        expect(country.status, PluginStatus.ok);
        expect(country.pointCount, 5190);
        expect(country.updatedAt, DateTime(2026, 1, 1, 12));
        expect(rows.map((s) => s.id).toList().indexOf('country'), 1);
      },
    );

    test('Deutschland: nicht vor der Umgebung, nicht ausgeschaltet', () async {
      repo.dataScope = const DataScope(countryCameras: true);
      repo.pointsAround(here); // Umgebung lädt noch
      expect(osm.countryLoads, 0);
      await pumpEventQueue();

      repo.dataScope = const DataScope();
      repo.pointsAround(here);
      await pumpEventQueue();
      expect(osm.countryLoads, 0);
      final rows = await repo.watchStatus().first;
      expect(rows.any((s) => s.id == 'country'), isFalse);

      repo.dataScope = const DataScope(
        countryCameras: true,
      ); // an: startet gleich
      await pumpEventQueue();
      expect(osm.countryLoads, 1);
    });

    test('Lauf fertig: Übersicht liest die neuen Kacheln', () async {
      repo.dataScope = const DataScope(countryCameras: true);
      const view = GeoBounds(south: 51.9, west: 12.9, north: 52.1, east: 13.1);
      osm.cameraResult = SourceResult(points: [osmPoint('1', 52.0, 13.0)]);
      repo.pointsInView(view);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final loads = osm.cameraLoads;
      repo.pointsInView(view);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(osm.cameraLoads, loads, reason: 'abgedeckt');

      repo.pointsAround(here);
      await pumpEventQueue();
      repo.pointsAround(here); // Länderlauf
      await pumpEventQueue();
      final afterRun = osm.cameraLoads;
      repo.pointsInView(view);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(osm.cameraLoads, afterRun + 1, reason: 'nach dem Lauf neu lesen');
    });

    test('andere Quelle ohne Länderlauf: keine Zeile, kein Absturz', () async {
      await repo.dispose();
      repo = await build(
        source: FakeOsm(),
        stored: {'scope.countryCameras': true},
      );
      repo.pointsAround(here);
      await pumpEventQueue();
      repo.pointsAround(here);
      final rows = await repo.watchStatus().first;
      expect(rows.any((s) => s.id == 'country'), isFalse);
    });
  });

  group('Vergangene Beobachtungen', () {
    late FakeOsm osm;
    late FakePlugin plugin;
    late AlertRepositoryImpl repo;

    AlertPoint past(String n, double lat, double lon, {DateTime? at}) =>
        AlertPoint(
          id: 'plugin:feed:$n',
          kind: AlertKind.live,
          position: GeoPoint(lat, lon),
          source: 'feed',
          historical: true,
          observedAt: at,
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues({'plugin.feed.enabled': true});
      osm = FakeOsm();
      plugin = FakePlugin('feed');
      repo = AlertRepositoryImpl(
        osm: osm,
        hotspots: FakeHotspots(),
        plugins: [plugin],
        prefs: await SharedPreferences.getInstance(),
        clock: () => now,
        overviewDebounce: const Duration(milliseconds: 20),
      );
    });
    tearDown(() => repo.dispose());

    const here = GeoPoint(52.0, 13.0);
    const view = GeoBounds(south: 51.9, west: 12.9, north: 52.1, east: 13.1);

    test('in der Karte, nie in der Warnlogik', () async {
      plugin.onFetch = (_) async => [
        past('alt', 52.001, 13.0),
        pluginPoint('feed', 'jetzt', 52.002, 13.0),
      ];
      repo.pointsAround(here);
      await pumpEventQueue();

      expect(repo.pointsAround(here).map((p) => p.id), ['plugin:feed:jetzt']);
      expect(repo.pointsInView(view).map((p) => p.id).toSet(), {
        'plugin:feed:alt',
        'plugin:feed:jetzt',
      });
    });

    test('werden nicht mit aktuellen Punkten oder untereinander vereinigt', () {
      final r = mergePoints([
        osmPoint('1', 52.0, 13.0),
        past('a', 52.0, 13.0),
        past('b', 52.0, 13.00001),
        pluginPoint('other', 'x', 52.0, 13.0, kind: AlertKind.speedCamera),
      ]);
      // OSM + Fremdplugin vereinigen sich; die zwei vergangenen bleiben einzeln als Zählpunkte.
      expect(r.map((p) => p.id), [
        'osm:node/1',
        'plugin:feed:a',
        'plugin:feed:b',
      ]);
      expect(r.where((p) => p.historical), hasLength(2));
    });

    test('Budget: die ältesten gehen zuerst, aktuelle zählen extra', () {
      final s = PluginSlot(plugin, enabled: true);
      final t0 = DateTime(2020);
      s.absorb(
        [
          for (var i = 0; i < PluginSlot.maxHistorical + 25; i++)
            past(
              '$i',
              50 + (i % 100) * 0.001,
              8 + (i ~/ 100) * 0.001,
              at: t0.add(Duration(days: i)),
            ),
          pluginPoint('feed', 'aktuell', 50.0, 8.0),
        ],
        const GeoBounds(south: 0, west: 0, north: 1, east: 1),
        now,
      );

      final hist = s.points.where((p) => p.historical).toList();
      expect(hist, hasLength(PluginSlot.maxHistorical));
      expect(
        hist.any((p) => p.id == 'plugin:feed:0'),
        isFalse,
        reason: 'ältester weg',
      );
      expect(hist.any((p) => p.id == 'plugin:feed:24'), isFalse);
      expect(hist.any((p) => p.id == 'plugin:feed:25'), isTrue);
      expect(s.points.where((p) => !p.historical), hasLength(1));
    });

    test('Ohne Zeitangabe gilt als ältestes', () {
      final s = PluginSlot(plugin, enabled: true);
      s.absorb(
        [
          for (var i = 0; i < PluginSlot.maxHistorical; i++)
            past('d$i', 50.0, 8.0, at: DateTime(2024)),
          past('ohne', 50.1, 8.1),
        ],
        const GeoBounds(south: 0, west: 0, north: 1, east: 1),
        now,
      );
      expect(s.points.any((p) => p.id == 'plugin:feed:ohne'), isFalse);
    });

    test('bleiben länger gemerkt als aktuelle Punkte', () {
      final s = PluginSlot(plugin, enabled: true);
      s.absorb(
        [past('alt', 52.0, 13.0), pluginPoint('feed', 'jetzt', 52.0, 13.0)],
        const GeoBounds(south: 40, west: 0, north: 41, east: 1),
        now,
      );
      const validity = Duration(minutes: 15);
      expect(s.expire(now.add(validity * 2), validity), isTrue);
      expect(s.points.map((p) => p.id), ['plugin:feed:alt']);
      expect(
        s.expire(now.add(PluginSlot.historicalValidity * 2), validity),
        isTrue,
      );
      expect(s.points, isEmpty);
    });
  });
}
