import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/limits_format.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_source.dart';
import 'package:sonarb/features/osm/osm_tile.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

/// Feine Zellen 52,05–52,10 N: West 8,00–8,05 (iy 1041, ix 160, im Paket ganz) und 8,05–8,10
/// (ix 161, Randzelle des Pakets).
const _whole = TileId(160, 1041, 20);
const _edge = TileId(161, 1041, 20);

RawWay _way(
  int lat,
  int lonA,
  int lonB, {
  int limit = 50,
  bool minor = false,
}) => RawWay(
  lat: [lat, lat],
  lon: [lonA, lonB],
  forward: limit,
  backward: limit,
  minor: minor,
);

/// Hauptstraße bei 52,07 durch die ganze Zelle, Nebenstraße bei 52,09 (30 km/h), und in der
/// Randzelle eine Straße mit 70.
Uint8List _package({String id = 'test', int date = 20261028}) => buildPackage(
  id: id,
  date: date,
  cells: {
    (1041, 160): (
      encodeCell(1041, 160, [
        _way(520700000, 80050000, 80450000),
        _way(520900000, 80100000, 80400000, limit: 30, minor: true),
      ]),
      cellComplete,
    ),
    (1041, 161): (
      encodeCell(1041, 161, [_way(520700000, 80550000, 80950000, limit: 70)]),
      0,
    ),
  },
);

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  late List<(OsmLayer, String, String)> seen;

  OsmSource make() {
    seen = [];
    return env.make(
      MockClient((req) async {
        seen.add((layerOf(req), westOf(req), southOf(req)));
        return ok(req);
      }),
      grace: const Duration(milliseconds: 20),
    );
  }

  Future<OsmSource> withPackage([Uint8List? bytes]) async {
    final source = make();
    final f = File('${env.dir.path}/in.sblp')
      ..writeAsBytesSync(bytes ?? _package());
    await source.packages.install(f);
    return source;
  }

  /// Wartet, bis die Quelle nichts mehr lädt (auch das Nachladen im Hintergrund).
  Future<void> settle() => env.whenIdle();

  Set<OsmLayer> limitLayers() => {
    for (final s in seen)
      if (s.$1.hasWays) s.$1,
  };

  group('Tempolimit aus dem Paket', () {
    test(
      'Limit ohne Netz, und keine Overpass-Abfrage für die ganze Zelle',
      () async {
        final source = await withPackage();
        expect(
          await source.speedLimitAt(const GeoPoint(52.0702, 8.02), 90),
          50,
        );
        expect(
          await source.speedLimitAt(const GeoPoint(52.0702, 8.02), 270),
          50,
        );
        await settle();
        // Nur die Zellen voraus und dahinter (Kurs Ost und West), nicht die ganze Zelle des Pakets.
        String edge(int i) => (i / 20 - 0.00002).toStringAsFixed(5);
        expect(
          seen.where((s) => s.$2 == edge(160) && s.$3 == edge(1041)),
          isEmpty,
          reason: 'das Paket kennt die Zelle ganz',
        );
      },
    );

    test(
      'Randzelle: Limit aus dem Paket, Overpass wird trotzdem gefragt',
      () async {
        final source = await withPackage();
        expect(
          await source.speedLimitAt(const GeoPoint(52.0702, 8.07), 90),
          70,
        );
        await settle();
        expect(limitLayers(), {OsmLayer.limits, OsmLayer.minorLimits});
      },
    );

    test('ohne Paket bleibt alles wie bisher', () async {
      final source = make();
      expect(
        await source.speedLimitAt(const GeoPoint(52.0702, 8.02), 90),
        isNull,
      );
      await settle();
      expect(limitLayers(), {OsmLayer.limits, OsmLayer.minorLimits});
    });

    test('load überspringt die Tempolimit-Zellen des Pakets, nicht Blitzer und Ampeln', () async {
      final source = await withPackage();
      final r = await source.load(
        const GeoBounds(south: 52.055, west: 8.01, north: 52.095, east: 8.09),
      );
      await settle();
      expect(r.error, isNull);
      String edge(int i) => (i / 20 - 0.00002).toStringAsFixed(5);
      final wholeCell = (edge(160), edge(1041));
      final limitCells = {
        for (final s in seen)
          if (s.$1 == OsmLayer.limits) (s.$2, s.$3),
      };
      expect(limitCells, isNot(contains(wholeCell)));
      expect(
        limitCells,
        contains((edge(161), edge(1041))),
        reason: 'Randzelle',
      );
      expect(seen.map((s) => s.$1), contains(OsmLayer.cameras));
      expect(seen.map((s) => s.$1), contains(OsmLayer.signals));
    });

    test('schnelle Fahrt nimmt keine Nebenstraßen aus dem Paket', () async {
      Future<int?> onMinorRoad(OsmSource source, {required bool fast}) async {
        var pos = const GeoPoint(52.0702, 8.005);
        if (fast) {
          for (var i = 0; i < 25; i++) {
            env.clock = env.clock.add(const Duration(seconds: 1));
            pos = GeoPoint(
              pos.lat,
              pos.lon + 28 / 68500,
            ); // ~100 km/h nach Osten
            await source.speedLimitAt(pos, 90);
          }
        }
        env.clock = env.clock.add(const Duration(seconds: 1));
        return source.speedLimitAt(const GeoPoint(52.0902, 8.02), 90);
      }

      expect(await onMinorRoad(await withPackage(), fast: false), 30);
      expect(await onMinorRoad(await withPackage(), fast: true), isNull);
    });

    test('Gleichstand an der Kreuzung: Hauptstraße vor Nebenstraße', () async {
      final source = await withPackage(
        buildPackage(
          id: 't',
          date: 1,
          cells: {
            (1041, 160): (
              encodeCell(1041, 160, [
                _way(520700000, 80050000, 80450000, limit: 30, minor: true),
                _way(520700000, 80050000, 80450000),
              ]),
              cellComplete,
            ),
          },
        ),
      );
      final around = await source.packages.around([_whole]);
      expect(around.map((w) => w.minor), [false, true]);
      expect(await source.speedLimitAt(const GeoPoint(52.07, 8.02), 90), 50);
    });

    test('das Paket überlebt das Leeren des Kachel-Caches', () async {
      final source = await withPackage();
      await source.speedLimitAt(const GeoPoint(52.0702, 8.07), 90);
      await settle();
      await source.clearCache();
      await source.packages.reload();
      expect(source.packages.installed.map((p) => p.id), ['test']);
      expect(await source.cacheSizeBytes(), 0);
    });
  });

  group('Paketverwaltung', () {
    test(
      'installieren, ersetzen, entfernen; Kaputtes wird übergangen',
      () async {
        final source = make();
        final p = source.packages;
        await p.ready;
        expect(p.isEmpty, isTrue);

        File put(String name, List<int> bytes) =>
            File('${env.dir.path}/$name')..writeAsBytesSync(bytes);

        final info = await p.install(put('a.sblp', _package()));
        expect((info.id, info.date, info.cells), ('test', 20261028, 2));
        expect(info.bytes, greaterThan(0));
        expect(p.isComplete(_whole), isTrue);
        expect(p.isComplete(_edge), isFalse);
        expect(p.hasCell(_edge), isTrue);

        await p.install(put('b.sblp', _package(date: 20261105)));
        expect(
          p.installed.single.date,
          20261105,
          reason: 'neuere Fassung ersetzt',
        );

        await expectLater(
          p.install(put('c.sblp', [1, 2, 3])),
          throwsA(isA<FormatException>()),
        );
        expect(p.installed, hasLength(1));

        // Beschädigte Datei im Ordner stört nicht.
        File('${p.dir.path}/kaputt.sblp').writeAsBytesSync([0, 1, 2]);
        await p.reload();
        expect(p.installed, hasLength(1));

        await p.remove('test');
        expect(p.installed, isEmpty);
        expect(p.isComplete(_whole), isFalse);
      },
    );

    test('beschädigte Zelle zählt als leer', () async {
      final source = await withPackage();
      final file = File('${source.packages.dir.path}/test.sblp');
      final bytes = file.readAsBytesSync();
      for (var i = bytes.length - 6; i < bytes.length; i++) {
        bytes[i] = 0xff; // Block der letzten Zelle zerstören
      }
      file.writeAsBytesSync(bytes);
      await source.packages.reload();
      expect(await source.packages.cell(_edge), isEmpty);
      expect(await source.packages.cell(_whole), hasLength(2));
    });
  });
}
