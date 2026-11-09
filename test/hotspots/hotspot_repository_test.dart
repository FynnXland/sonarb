import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/hotspot_repository.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/hotspots/file_hotspot_repository.dart';
import 'package:sonarb/features/hotspots/hotspots.dart';

/// Steuerbare Uhr für Doppel-Tap-Tests.
class FakeClock {
  DateTime now = DateTime.utc(2026, 5, 1, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  late Directory dir;
  late FakeClock clock;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sonarb_hotspots_');
    clock = FakeClock();
  });

  final opened = <FileHotspotRepository>[];

  // Erst offene Repos schließen: Unter Windows sperrt ein laufender Schreibvorgang die Datei.
  tearDown(() async {
    for (final r in opened) {
      try {
        await r.dispose();
      } catch (_) {}
    }
    opened.clear();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<FileHotspotRepository> open({List<String>? errors}) async {
    final r = await FileHotspotRepository.open(
      dir,
      clock: clock.call,
      onError: (m, e, s) => errors?.add(m),
    );
    opened.add(r);
    return r;
  }

  File dataFile() => File('${dir.path}${Platform.pathSeparator}hotspots.json');

  const berlin = GeoPoint(52.5, 13.4);
  // ca. 100 m nördlich
  const berlin100 = GeoPoint(52.5009, 13.4);

  group('Ein-Tap', () {
    test('legt Hotspot sofort an, neueste zuerst', () async {
      final repo = await open();
      final a = await repo.addAt(berlin, headingDeg: 90);
      clock.advance(const Duration(minutes: 1));
      final b = await repo.addAt(berlin100);

      expect(a.id, isNot(b.id));
      expect(a.id.length, 36);
      expect(a.headingDeg, 90);
      expect(a.kind, HotspotKind.mobileCamera);
      expect((await repo.all()).map((h) => h.id), [b.id, a.id]);
    });

    test('Liste ist schon vor dem Schreiben aktualisiert', () async {
      final repo = await open();
      final future = repo.addAt(berlin);
      final h = await future;
      expect((await repo.all()).single.id, h.id);
      await repo.flush();
      expect(dataFile().existsSync(), isTrue);
    });

    test(
      'Doppel-Tap: gleiche Art, < 50 m, < 10 s liefert den vorhandenen',
      () async {
        final repo = await open();
        final a = await repo.addAt(berlin);
        clock.advance(const Duration(seconds: 5));
        final again = await repo.addAt(const GeoPoint(52.50030, 13.4)); // ~33 m
        expect(again.id, a.id);
        expect(await repo.all(), hasLength(1));
      },
    );

    test('kein Schutz bei anderer Art, > 50 m oder >= 10 s', () async {
      final repo = await open();
      await repo.addAt(berlin);
      await repo.addAt(berlin, kind: HotspotKind.danger);
      await repo.addAt(const GeoPoint(52.50060, 13.4)); // ~67 m
      expect(await repo.all(), hasLength(3));

      clock.advance(const Duration(seconds: 10));
      await repo.addAt(berlin);
      expect(await repo.all(), hasLength(4));
    });
  });

  group('Undo, update, remove', () {
    test(
      'undoLast entfernt den zuletzt angelegten, nicht Index 0 nach Import',
      () async {
        final repo = await open();
        final a = await repo.addAt(berlin);
        clock.advance(const Duration(minutes: 1));
        final b = await repo.addAt(berlin100);
        // Import mit neuerem Zeitstempel schiebt einen fremden Eintrag an Index 0.
        await repo.importJson(
          jsonEncode([
            {'lat': 48.0, 'lon': 11.0, 'createdAt': '2030-01-01T00:00:00Z'},
          ]),
        );
        expect((await repo.all()).first.position.lat, 48.0);

        await repo.undoLast();
        final ids = (await repo.all()).map((h) => h.id).toList();
        expect(ids, isNot(contains(b.id)));
        expect(ids, contains(a.id));
        expect(ids, hasLength(2));
      },
    );

    test('undoLast zweimal und bei leerer Liste ist harmlos', () async {
      final repo = await open();
      await repo.undoLast();
      await repo.addAt(berlin);
      await repo.undoLast();
      await repo.undoLast();
      expect(await repo.all(), isEmpty);
    });

    test('undoLast nach manuellem remove löscht nichts anderes', () async {
      final repo = await open();
      final a = await repo.addAt(berlin);
      clock.advance(const Duration(minutes: 1));
      final b = await repo.addAt(berlin100);
      await repo.remove(b.id);
      await repo.undoLast();
      expect((await repo.all()).single.id, a.id);
    });

    test('update ersetzt per ID und bleibt gespeichert', () async {
      final repo = await open();
      final a = await repo.addAt(berlin);
      await repo.update(a.copyWith(note: 'Brücke', radiusMeters: 500));
      await repo.update(
        Hotspot(id: 'unbekannt', position: berlin, createdAt: clock.now),
      ); // ohne Wirkung

      final again = await open();
      final h = (await again.all()).single;
      expect(h.note, 'Brücke');
      expect(h.radiusMeters, 500);
    });

    test('remove löscht und ignoriert unbekannte IDs', () async {
      final repo = await open();
      final a = await repo.addAt(berlin);
      await repo.remove('gibt-es-nicht');
      expect(await repo.all(), hasLength(1));
      await repo.remove(a.id);
      expect(await repo.all(), isEmpty);
      expect(jsonDecode(dataFile().readAsStringSync())['hotspots'], isEmpty);
    });
  });

  group('Persistenz', () {
    test(
      'Stand überlebt eine Neuinstanz über createHotspotRepository',
      () async {
        final repo = await createHotspotRepository(dataDir: dir);
        final a = await repo.addAt(berlin, headingDeg: 270);
        await (repo as FileHotspotRepository).flush();

        final again = await createHotspotRepository(dataDir: dir);
        final h = (await again.all()).single;
        expect(h.id, a.id);
        expect(h.position, berlin);
        expect(h.headingDeg, 270);
        expect(h.createdAt.isAtSameMomentAs(a.createdAt), isTrue);
      },
    );

    test('Datenordner wird bei Bedarf angelegt', () async {
      final sub = Directory(
        '${dir.path}${Platform.pathSeparator}neu${Platform.pathSeparator}tief',
      );
      final repo = await FileHotspotRepository.open(sub);
      await repo.addAt(berlin);
      await repo.flush();
      expect(
        File('${sub.path}${Platform.pathSeparator}hotspots.json').existsSync(),
        isTrue,
      );
    });

    test('keine Temp-Datei bleibt zurück', () async {
      final repo = await open();
      await repo.addAt(berlin);
      await repo.flush();
      final names = dir.listSync().map((e) => e.uri.pathSegments.last);
      expect(names, ['hotspots.json']);
    });

    test('kaputte Datei wird beiseitegelegt, nicht überschrieben', () async {
      dataFile().writeAsStringSync('{"format":"sonarb-hotspots", kaputt');
      final errors = <String>[];
      final repo = await open(errors: errors);
      expect(await repo.all(), isEmpty);
      expect(errors, isNotEmpty);

      final aside = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('hotspots.json.defekt-'))
          .toList();
      expect(aside, hasLength(1));
      expect(aside.single.readAsStringSync(), contains('kaputt'));

      await repo.addAt(berlin);
      await repo.flush();
      expect(
        jsonDecode(dataFile().readAsStringSync())['hotspots'],
        hasLength(1),
      );
      expect(aside.single.readAsStringSync(), contains('kaputt'));
    });

    test(
      'Teildefekt: gültige Einträge bleiben, Kopie wird gesichert',
      () async {
        dataFile().writeAsStringSync(
          jsonEncode({
            'format': 'sonarb-hotspots',
            'version': 1,
            'hotspots': [
              {'id': 'ok', 'lat': 50.0, 'lon': 8.0},
              {'id': 'schlecht', 'lat': 500, 'lon': 8.0},
            ],
          }),
        );
        final repo = await open(errors: []);
        expect((await repo.all()).single.id, 'ok');
        final aside = dir.listSync().where((e) => e.path.contains('.defekt-'));
        expect(aside, hasLength(1));
        // Zweiter Start erzeugt keine weitere Kopie.
        await open(errors: []);
        expect(
          dir.listSync().where((e) => e.path.contains('.defekt-')),
          hasLength(1),
        );
      },
    );

    test('Schreibfehler werden geloggt, die Liste bleibt nutzbar', () async {
      final errors = <String>[];
      final repo = await open(errors: errors);
      // Ein Ordner an Stelle der Zieldatei lässt das Umbenennen scheitern.
      Directory(dataFile().path).createSync();
      final h = await repo.addAt(berlin);
      await repo.flush();
      expect(errors.any((m) => m.contains('geschrieben')), isTrue);
      expect((await repo.all()).single.id, h.id);
    });
  });

  group('watch', () {
    test(
      'liefert sofort den Stand, danach jede Änderung, mehrere Abonnenten',
      () async {
        final repo = await open();
        await repo.addAt(berlin);

        final first = <int>[];
        final second = <int>[];
        final s1 = repo.watch().listen((l) => first.add(l.length));
        final s2 = repo.watch().listen((l) => second.add(l.length));
        await Future<void>.delayed(Duration.zero);
        expect(first, [1]);
        expect(second, [1]);

        clock.advance(const Duration(minutes: 1));
        final b = await repo.addAt(berlin100);
        await repo.remove(b.id);
        await Future<void>.delayed(Duration.zero);
        expect(first, [1, 2, 1]);
        expect(second, [1, 2, 1]);

        await s1.cancel();
        await repo.addAt(const GeoPoint(53, 10));
        await Future<void>.delayed(Duration.zero);
        expect(first, [1, 2, 1]);
        expect(second, [1, 2, 1, 2]);
        await s2.cancel();
      },
    );
  });

  group('viele schnelle addAt', () {
    test(
      '300 Aufrufe ohne await verlieren nichts, auch nach Neuinstanz',
      () async {
        final repo = await open();
        final futures = <Future<Hotspot>>[];
        for (var i = 0; i < 300; i++) {
          // 0.001° ≈ 111 m Abstand, damit der Doppel-Tap-Schutz nicht greift.
          futures.add(repo.addAt(GeoPoint(50 + i * 0.001, 8)));
        }
        final created = await Future.wait(futures);
        await repo.flush();

        expect(created.map((h) => h.id).toSet(), hasLength(300));
        expect(await repo.all(), hasLength(300));

        final again = await open();
        final loaded = await again.all();
        expect(loaded, hasLength(300));
        expect(
          loaded.map((h) => h.id).toSet(),
          created.map((h) => h.id).toSet(),
        );
      },
    );

    test('Add und Remove im Wechsel enden im richtigen Stand', () async {
      final repo = await open();
      final keep = <String>[];
      for (var i = 0; i < 40; i++) {
        final h = await repo.addAt(GeoPoint(51 + i * 0.001, 9));
        if (i.isEven) {
          keep.add(h.id);
        } else {
          unawaited(repo.remove(h.id));
        }
      }
      await repo.flush();
      final again = await open();
      expect((await again.all()).map((h) => h.id).toSet(), keep.toSet());
    });
  });
}
