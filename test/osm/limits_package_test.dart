import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/limits_format.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

// Zelle 1071/201: 53,55–53,60 N / 10,05–10,10 O (Hamburg-Wandsbek).
const _cell = TileId(201, 1071, 20);

RawWay raw(
  List<(int, int)> pts, {
  int? forward = 50,
  int? backward = 50,
  int oneway = 0,
  bool minor = false,
}) => RawWay(
  lat: [for (final p in pts) p.$1],
  lon: [for (final p in pts) p.$2],
  forward: forward,
  backward: backward,
  oneway: oneway,
  minor: minor,
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('limits_pkg'));
  tearDown(() => dir.deleteSync(recursive: true));

  File write(Uint8List bytes) =>
      File('${dir.path}/p.sblp')..writeAsBytesSync(bytes);

  group('Zellblock', () {
    final ways = [
      raw(
        [
          (535512345, 100123456),
          (535512999, 100124567),
          (535513001, 100120000),
        ],
        forward: 30,
        backward: 50,
        oneway: 1,
        minor: true,
      ),
      raw(
        [(535500000, 100550000), (535500100, 100550100)],
        forward: null,
        backward: null,
      ),
      raw(
        [(535700000, 100600000), (535700500, 100600500)],
        forward: 130,
        backward: 130,
        oneway: -1,
      ),
    ];

    test('Rundreise ohne Verlust (Raster 1)', () {
      final back = decodeCell(1071, 201, encodeCell(1071, 201, ways));
      expect(back, hasLength(3));
      final a = back[0];
      expect(a.way.points.first, const GeoPoint(53.5512345, 10.0123456));
      expect(a.way.points.last, const GeoPoint(53.5513001, 10.012));
      expect(
        (a.way.forward, a.way.backward, a.way.oneway, a.minor),
        (30, 50, 1, true),
      );
      final b = back[1];
      expect(
        (b.way.forward, b.way.backward, b.way.oneway, b.minor),
        (null, null, 0, false),
      );
      final c = back[2];
      expect((c.way.forward, c.way.backward, c.way.oneway), (130, 130, -1));
      expect(
        c.way.points,
        hasLength(2),
        reason: 'Punkte außerhalb der Zelle sind möglich',
      );
    });

    test('größeres Raster rundet auf Vielfache und spart Platz', () {
      final fine = encodeCell(1071, 201, ways).length;
      final coarse = encodeCell(1071, 201, ways, grid: 100);
      expect(coarse.length, lessThan(fine));
      final back = decodeCell(1071, 201, coarse, grid: 100);
      expect(back[0].way.points.first.lat, closeTo(53.5512345, 0.000006));
      expect(
        back[0].way.points.first.lat * 1e5,
        closeTo((53.5512345 * 1e5).round(), 1e-6),
      );
    });
  });

  group('Datei', () {
    final cells = {
      (1071, 201): (
        encodeCell(1071, 201, [
          raw([(535500000, 100550000), (535500100, 100550100)]),
        ]),
        cellComplete,
      ),
      (1070, 201): (Uint8List(0), 0),
    };

    test('Kopf, Index und Zellen lesen', () async {
      final bytes = buildPackage(id: 'hamburg', date: 20261028, cells: cells);
      final pkg = await LimitPackage.open(write(bytes));
      expect(
        (pkg.id, pkg.date, pkg.grid, pkg.cellCount),
        ('hamburg', 20261028, 1, 2),
      );
      expect(pkg.hasCell(_cell), isTrue);
      expect(pkg.isComplete(_cell), isTrue);
      expect(pkg.hasCell(const TileId(201, 1070, 20)), isTrue);
      expect(pkg.isComplete(const TileId(201, 1070, 20)), isFalse);
      expect(pkg.hasCell(const TileId(5, 5, 20)), isFalse);
      expect(await pkg.readCell(_cell), hasLength(1));
      expect(
        await pkg.readCell(const TileId(201, 1070, 20)),
        isEmpty,
        reason: 'Zelle ohne Wege',
      );
      expect(
        await pkg.readCell(const TileId(5, 5, 20)),
        isEmpty,
        reason: 'unbekannte Zelle',
      );
      expect(pkg.bounds!.south, 53.5);
    });

    test('ungültige Dateien werden abgelehnt', () async {
      final good = buildPackage(id: 'x', date: 1, cells: cells);
      Future<void> rejects(List<int> bytes) => expectLater(
        LimitPackage.open(write(Uint8List.fromList(bytes))),
        throwsA(isA<FormatException>()),
      );
      await rejects([1, 2, 3]);
      await rejects([...'XXXX'.codeUnits, ...good.skip(4)]);
      await rejects([...good.take(4), 99, ...good.skip(5)]);
      await rejects(
        good.take(good.length - 3).toList(),
      ); // Zelle hinter dem Dateiende
      await rejects(good.take(20).toList());
    });
  });
}
