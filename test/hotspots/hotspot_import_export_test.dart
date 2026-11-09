import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/hotspot_repository.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/hotspots/file_hotspot_repository.dart';

void main() {
  late Directory dir;
  late Directory dir2;
  var now = DateTime.utc(2026, 5, 1, 12);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sonarb_hs_a_');
    dir2 = Directory.systemTemp.createTempSync('sonarb_hs_b_');
    now = DateTime.utc(2026, 5, 1, 12);
  });

  tearDown(() {
    for (final d in [dir, dir2]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<FileHotspotRepository> open([Directory? d]) =>
      FileHotspotRepository.open(
        d ?? dir,
        clock: () => now,
        onError: (m, e, s) {},
      );

  String doc(
    List<Object?> hotspots, {
    Object? format = 'sonarb-hotspots',
    Object? version = 1,
  }) =>
      jsonEncode({'format': format, 'version': version, 'hotspots': hotspots});

  group('Export und Import', () {
    test('Rundweg erhält alle Felder', () async {
      final a = await open();
      final h1 = await a.addAt(const GeoPoint(52.5, 13.4), headingDeg: 90);
      now = now.add(const Duration(minutes: 5));
      final h2 = await a.addAt(
        const GeoPoint(48.1, 11.5),
        kind: HotspotKind.danger,
      );
      await a.update(h2.copyWith(note: 'Tunnelausfahrt', radiusMeters: 450));

      final json = await a.exportJson();
      final map = jsonDecode(json) as Map<String, dynamic>;
      expect(map['format'], 'sonarb-hotspots');
      expect(map['version'], 1);
      expect(DateTime.parse(map['exportedAt'] as String).isUtc, isTrue);
      expect(
        (map['hotspots'] as List).first.keys,
        containsAll([
          'id',
          'lat',
          'lon',
          'kind',
          'headingDeg',
          'note',
          'radiusMeters',
          'createdAt',
        ]),
      );

      final b = await open(dir2);
      final result = await b.importJson(json);
      expect(result.added, 2);
      expect(result.skippedDuplicates, 0);
      expect(result.invalid, 0);

      final want = await a.all();
      final got = await b.all();
      expect(got.map((h) => h.id), want.map((h) => h.id));
      for (var i = 0; i < want.length; i++) {
        expect(got[i].position, want[i].position);
        expect(got[i].kind, want[i].kind);
        expect(got[i].headingDeg, want[i].headingDeg);
        expect(got[i].note, want[i].note);
        expect(got[i].radiusMeters, want[i].radiusMeters);
        expect(got[i].createdAt.isAtSameMomentAs(want[i].createdAt), isTrue);
      }
      expect(got.first.id, h2.id);
      expect(got.last.id, h1.id);
    });

    test('erneuter Import derselben Datei: alles Duplikate', () async {
      final a = await open();
      await a.addAt(const GeoPoint(52.5, 13.4));
      final json = await a.exportJson();
      final r = await a.importJson(json);
      expect((r.added, r.skippedDuplicates, r.invalid), (0, 1, 0));
      expect(await a.all(), hasLength(1));
    });

    test('Import wird gespeichert', () async {
      final a = await open();
      await a.importJson(
        doc([
          {'id': 'x1', 'lat': 50.0, 'lon': 8.0, 'kind': 'danger'},
        ]),
      );
      final again = await open();
      expect((await again.all()).single.id, 'x1');
    });
  });

  group('Fehlerfälle', () {
    Future<void> expectFormatError(String input, [Pattern? text]) async {
      final repo = await open();
      await expectLater(
        repo.importJson(input),
        throwsA(
          isA<HotspotFormatException>().having(
            (e) => e.message,
            'message',
            text == null ? isNotEmpty : contains(text),
          ),
        ),
      );
      expect(await repo.all(), isEmpty);
    }

    test('kein JSON', () => expectFormatError('das ist kein json', 'JSON'));
    test('leerer Text', () => expectFormatError(''));
    test('JSON ohne Objekt oder Array', () => expectFormatError('42'));
    test(
      'falsches format',
      () => expectFormatError(doc([], format: 'anderes'), 'Dateiformat'),
    );
    test(
      'fehlendes format',
      () => expectFormatError('{"version":1,"hotspots":[]}', 'Dateiformat'),
    );
    test(
      'höhere version',
      () => expectFormatError(doc([], version: 2), 'Version 2'),
    );
    test(
      'version fehlt',
      () => expectFormatError(
        '{"format":"sonarb-hotspots","hotspots":[]}',
        'Version',
      ),
    );
    test(
      'hotspots keine Liste',
      () => expectFormatError(
        '{"format":"sonarb-hotspots","version":1,"hotspots":5}',
        'Liste',
      ),
    );
  });

  group('Ungültige Einträge', () {
    test('zählen als invalid, der Rest wird übernommen', () async {
      final repo = await open();
      final r = await repo.importJson(
        doc([
          {'id': 'gut', 'lat': 52.5, 'lon': 13.4},
          {'lat': 91, 'lon': 0},
          {'lat': 0, 'lon': 181},
          {'lat': -91, 'lon': 0},
          {'lon': 5.0},
          {'lat': 5.0},
          {'lat': 'x', 'lon': 5.0},
          {'lat': 10.0, 'lon': 10.0, 'kind': 'unbekannt'},
          {'lat': 10.0, 'lon': 10.0, 'kind': 3},
          {'lat': 11.0, 'lon': 10.0, 'headingDeg': 'Nord'},
          {'lat': 12.0, 'lon': 10.0, 'radiusMeters': -5},
          {'lat': 13.0, 'lon': 10.0, 'createdAt': 'gestern'},
          {'lat': 14.0, 'lon': 10.0, 'id': ''},
          'text',
          null,
          [1, 2],
        ]),
      );
      expect(r.added, 1);
      expect(r.invalid, 15);
      expect(r.skippedDuplicates, 0);
      expect((await repo.all()).single.id, 'gut');
    });

    test(
      'Kurs wird auf 0..360 gebracht, fehlende Felder bekommen Standardwerte',
      () async {
        final repo = await open();
        await repo.importJson(
          doc([
            {'lat': 50.0, 'lon': 8.0, 'headingDeg': -90},
          ]),
        );
        final h = (await repo.all()).single;
        expect(h.headingDeg, 270);
        expect(h.kind, HotspotKind.mobileCamera);
        expect(h.radiusMeters, 300);
        expect(h.note, isNull);
        expect(h.id, isNotEmpty);
        expect(h.createdAt, now);
      },
    );
  });

  group('Duplikate', () {
    test('gleiche ID', () async {
      final repo = await open();
      await repo.importJson(
        doc([
          {'id': 'a', 'lat': 50.0, 'lon': 8.0},
        ]),
      );
      final r = await repo.importJson(
        doc([
          {'id': 'a', 'lat': 60.0, 'lon': 20.0},
        ]),
      );
      expect((r.added, r.skippedDuplicates), (0, 1));
      expect((await repo.all()).single.position, const GeoPoint(50.0, 8.0));
    });

    test(
      'gleiche Art unter 25 m, andere Art oder über 25 m zählt nicht',
      () async {
        final repo = await open();
        await repo.importJson(
          doc([
            {'id': 'a', 'lat': 50.0, 'lon': 8.0, 'kind': 'mobileCamera'},
          ]),
        );
        final r = await repo.importJson(
          doc([
            {
              'id': 'b',
              'lat': 50.0001,
              'lon': 8.0,
              'kind': 'mobileCamera',
            }, // ~11 m
            {'id': 'c', 'lat': 50.0001, 'lon': 8.0, 'kind': 'danger'},
            {
              'id': 'd',
              'lat': 50.0004,
              'lon': 8.0,
              'kind': 'mobileCamera',
            }, // ~44 m
          ]),
        );
        expect((r.added, r.skippedDuplicates, r.invalid), (2, 1, 0));
        expect((await repo.all()).map((h) => h.id).toSet(), {'a', 'c', 'd'});
      },
    );

    test('Duplikate innerhalb derselben Datei', () async {
      final repo = await open();
      final r = await repo.importJson(
        doc([
          {'id': 'a', 'lat': 50.0, 'lon': 8.0},
          {'id': 'a', 'lat': 51.0, 'lon': 9.0},
          {'id': 'b', 'lat': 50.00005, 'lon': 8.0},
        ]),
      );
      expect((r.added, r.skippedDuplicates), (1, 2));
    });
  });

  group('Minimalformat', () {
    test('reines Array aus {lat, lon}', () async {
      final repo = await open();
      final r = await repo.importJson(
        jsonEncode([
          {'lat': 52.5, 'lon': 13.4},
          {'lat': 48.1, 'lon': 11.5},
          {'lat': 99, 'lon': 11.5},
        ]),
      );
      expect((r.added, r.skippedDuplicates, r.invalid), (2, 0, 1));
      final all = await repo.all();
      expect(all.map((h) => h.id).toSet(), hasLength(2));
      // Gleicher Zeitstempel: Reihenfolge der Datei bleibt erhalten.
      expect(all.map((h) => h.position.lat), [52.5, 48.1]);
    });

    test('leeres Array ist gültig', () async {
      final repo = await open();
      final r = await repo.importJson('[]');
      expect((r.added, r.skippedDuplicates, r.invalid), (0, 0, 0));
    });

    test('Objekt mit Kopf, Einträge nur mit lat/lon', () async {
      final repo = await open();
      final r = await repo.importJson(
        doc([
          {'lat': 52.5, 'lon': 13.4},
        ]),
      );
      expect(r.added, 1);
    });
  });
}
