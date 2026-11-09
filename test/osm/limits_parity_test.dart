// Abgleich mit der App. Gegenstück im Paket-Repository der Tempolimits (noch nicht öffentlich), dort mit
// anderen Importen und denselben Dateien (dort test/fixtures). Sie hält fest, was beide Seiten gleich
// verstehen müssen: die Regeln „Tags → Limits“, das Paketformat und das Verzeichnis packages.json.
// Ändert sich eines davon, ändern sich die Fixtures in beiden Repos, sonst schlägt ein Test fehl.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sonarb/features/osm/limits_format.dart';
import 'package:sonarb/features/osm/osm_way_limits.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtures = 'test/osm/parity';

Map<String, String> _tags(Map<String, dynamic> m) => {
  for (final e in m.entries) e.key: '${e.value}',
};

String _show(LimitWay w) =>
    '${w.way.forward}/${w.way.backward}/${w.way.oneway}/${w.minor ? 'N' : 'H'} '
    '${w.way.points.map((p) => '${p.lat},${p.lon}').join(' ')}';

/// Zwei Zellen, Raster 10; die zweite ist leer und vollständig.
Uint8List _golden() => buildPackage(
  id: 'golden',
  date: 20260101,
  grid: 10,
  cells: {
    (1071, 201): (
      encodeCell(1071, 201, [
        RawWay(
          lat: [535512340, 535512990, 535513000],
          lon: [100550010, 100551230, 100559990],
          forward: 50,
          backward: 50,
          oneway: 1,
        ),
        RawWay(
          lat: [535500000, 535500100],
          lon: [100600000, 100600100],
          forward: 30,
          backward: 20,
          minor: true,
        ),
        RawWay(
          lat: [535540000, 535540500],
          lon: [100570000, 100570500],
          forward: null,
          backward: 130,
          oneway: -1,
        ),
      ], grid: 10),
      cellComplete,
    ),
    (1070, 201): (Uint8List(0), cellComplete),
  },
);

void main() {
  test(
    'Regeln: Tags → Limits, Einbahn, Nebenstraße (fixtures/limit_rules.json)',
    () {
      final cases = (jsonDecode(
        File('$_fixtures/limit_rules.json').readAsStringSync(),
      ) as List).cast<Map<String, dynamic>>();
      expect(cases.length, greaterThan(20));
      for (final c in cases) {
        final tags = _tags(c['tags'] as Map<String, dynamic>);
        final (forward, backward) = limitsOf(tags);
        final got = {
          'forward': forward,
          'backward': backward,
          'oneway': onewayOf(tags),
          'hasLimitTag': hasLimitTag(tags),
          'minor': minorRoadTypes.contains(tags['highway']),
        };
        expect(got, c['expect'], reason: '${c['tags']}');
      }
    },
  );

  test(
    'Format: das Paket aus den Fixtures wird Byte für Byte so geschrieben',
    () {
      final file = File('$_fixtures/golden.sblp');
      if (Platform.environment['UPDATE_GOLDEN'] == '1') {
        file.writeAsBytesSync(_golden());
      }
      expect(file.readAsBytesSync(), _golden());
      expect(limitPackageFormat, 1);
    },
  );

  test('Format: das Paket aus den Fixtures wird richtig gelesen', () async {
    final pkg = await LimitPackage.open(File('$_fixtures/golden.sblp'));
    expect(
      (pkg.id, pkg.date, pkg.grid, pkg.cellCount),
      ('golden', 20260101, 10, 2),
    );
    final cells = pkg.cells.toList();
    final full = cells.firstWhere((c) => c.iy == 1071);
    final empty = cells.firstWhere((c) => c.iy == 1070);
    expect(pkg.isComplete(full) && pkg.isComplete(empty), isTrue);
    expect(await pkg.readCell(empty), isEmpty);
    expect((await pkg.readCell(full)).map(_show).toList(), [
      '50/50/1/H 53.551234,10.055001 53.551299,10.055123 53.5513,10.055999',
      '30/20/0/N 53.55,10.06 53.55001,10.06001',
      'null/130/-1/H 53.554,10.057 53.55405,10.05705',
    ]);
  });

  test(
    'Verzeichnis: Aufbau von packages.json (fixtures/catalog_sample.json)',
    () {
      final json = jsonDecode(
        File('$_fixtures/catalog_sample.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['format'], 1);
      for (final p in (json['packages'] as List).cast<Map<String, dynamic>>()) {
        expect(p.keys.toSet(), {
          'id',
          'name',
          'date',
          'bytes',
          'sha256',
          'file',
        });
        expect(p['file'], '${p['id']}.sblp');
        expect(p['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(p['date'], isA<int>());
        expect(p['bytes'], isA<int>());
      }
    },
  );
}
