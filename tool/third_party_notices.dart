// Schreibt THIRD-PARTY-NOTICES.md aus den Abhängigkeiten (ohne Entwicklungswerkzeuge).
//
//   dart run tool/third_party_notices.dart          Datei neu schreiben
//   dart run tool/third_party_notices.dart --check  nur prüfen (Exit 1, wenn sie veraltet ist)
//
// Vorher `flutter pub get`, damit .dart_tool/package_config.json die Paketordner kennt.
import 'dart:convert';
import 'dart:io';

const outputPath = 'THIRD-PARTY-NOTICES.md';

/// Grobe Einordnung eines Lizenztexts. Unbekanntes bleibt sichtbar „unbekannt“.
String classifyLicense(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ');
  if (t.contains('GNU LESSER GENERAL PUBLIC')) return 'LGPL';
  if (t.contains('GNU GENERAL PUBLIC')) return 'GPL';
  if (t.contains('Mozilla Public License')) return 'MPL-2.0';
  if (t.contains('Apache License')) return 'Apache-2.0';
  if (t.contains('Redistribution and use in source and binary forms')) {
    return t.contains('Neither the name') || t.contains('names of its')
        ? 'BSD-3-Clause'
        : 'BSD-2-Clause';
  }
  if (t.contains('Permission is hereby granted, free of charge')) return 'MIT';
  return 'unbekannt';
}

/// Pakete, die von den Laufzeit-Abhängigkeiten der App aus erreichbar sind.
Set<String> runtimePackages(Map<String, dynamic> deps) =>
    _reachable(deps, 'directDependencies');

/// Pakete, die nur Tests und Werkzeuge brauchen (nicht in der App).
Set<String> devOnlyPackages(Map<String, dynamic> deps) =>
    _reachable(deps, 'devDependencies').difference(runtimePackages(deps));

Set<String> _reachable(Map<String, dynamic> deps, String start) {
  final byName = {
    for (final p in (deps['packages'] as List).cast<Map<String, dynamic>>())
      p['name'] as String: p,
  };
  final root = byName.values.firstWhere((p) => p['kind'] == 'root');
  final seen = <String>{};
  final queue = [...((root[start] as List?) ?? []).cast<String>()];
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    if (!seen.add(name)) continue;
    queue.addAll(
      ((byName[name]?['dependencies'] as List?) ?? []).cast<String>(),
    );
  }
  return seen;
}

typedef Row = ({
  String name,
  String version,
  String license,
  bool sdk,
  bool dev,
});

String render(List<Row> rows) {
  final b = StringBuffer()
    ..writeln('# Fremdlizenzen')
    ..writeln()
    ..writeln(
      'Sonarb selbst steht unter der [MIT-Lizenz](LICENSE). Die App enthält Pakete und nutzt Daten',
    )
    ..writeln(
      'anderer, deren Lizenzen hier stehen. In der App zeigt Einstellungen → Über → „Lizenzen“ die',
    )
    ..writeln('vollständigen Lizenztexte der eingebauten Pakete.')
    ..writeln()
    ..writeln(
      'Diese Datei erzeugt `dart run tool/third_party_notices.dart`; bitte nicht von Hand ändern.',
    )
    ..writeln()
    ..writeln('## Kartendaten')
    ..writeln()
    ..writeln(
      '- **OpenStreetMap:** Blitzer, Ampeln und Tempolimits kommen zur Laufzeit aus OpenStreetMap.',
    )
    ..writeln('  Daten © OpenStreetMap-Mitwirkende, verfügbar unter der')
    ..writeln(
      '  [Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/),',
    )
    ..writeln(
      '  siehe [openstreetmap.org/copyright](https://www.openstreetmap.org/copyright).',
    )
    ..writeln(
      '- **Ausnahme von der MIT-Lizenz:** Diese Dateien im Repository stammen aus OpenStreetMap und',
    )
    ..writeln(
      '  stehen unter der ODbL, © OpenStreetMap-Mitwirkende: die Testdaten `test/osm/*.json` und',
    )
    ..writeln(
      '  `test/osm/parity/*` (darunter `golden.sblp`), die Teststrecke `tool/media/route.json` und das',
    )
    ..writeln('  Länderraster `lib/features/osm/land_grid.dart`.')
    ..writeln(
      '- **Dienste:** Die App fragt die öffentlichen Overpass-Server `overpass-api.de` (FOSSGIS e. V.)',
    )
    ..writeln(
      '  und `overpass.private.coffee` sowie den Kachelserver `tile.openstreetmap.org`',
    )
    ..writeln(
      '  (OpenStreetMap Foundation) ab. Für sie gelten deren Nutzungsregeln.',
    )
    ..writeln()
    ..writeln('## Flutter')
    ..writeln()
    ..writeln(
      '- **Flutter SDK** (BSD-3-Clause), https://github.com/flutter/flutter',
    )
    ..writeln('- **Material Icons** (Apache-2.0), mit Flutter ausgeliefert')
    ..writeln()
    ..writeln('## Verwendete Pakete')
    ..writeln()
    ..writeln(
      'Alle Pakete, die in der App stecken, einschließlich indirekter Abhängigkeiten.',
    )
    ..writeln(
      'Plattform-Implementierungen für Web, Windows, Linux und macOS landen nicht in der Android-App.',
    )
    ..writeln()
    ..writeln('| Paket | Version | Lizenz |')
    ..writeln('|---|---|---|');
  void table(Iterable<Row> list) {
    for (final r in list) {
      b.writeln(
        '| [${r.name}](https://pub.dev/packages/${r.name}) | ${r.version} | ${r.license} |',
      );
    }
  }

  table(rows.where((r) => !r.sdk && !r.dev));
  b
    ..writeln()
    ..writeln('## Nur für Tests und Entwicklung')
    ..writeln()
    ..writeln(
      'Diese Pakete braucht nur `flutter test`; in der App sind sie nicht enthalten.',
    )
    ..writeln()
    ..writeln('| Paket | Version | Lizenz |')
    ..writeln('|---|---|---|');
  table(rows.where((r) => !r.sdk && r.dev));
  return b.toString();
}

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final result = await Process.run('dart', [
    'pub',
    'deps',
    '--json',
  ], runInShell: true);
  if (result.exitCode != 0) {
    stderr.writeln('dart pub deps fehlgeschlagen:\n${result.stderr}');
    exitCode = 2;
    return;
  }
  final deps = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final roots = {
    for (final p in (config['packages'] as List).cast<Map<String, dynamic>>())
      p['name'] as String: p['rootUri'] as String,
  };
  final info = {
    for (final p in (deps['packages'] as List).cast<Map<String, dynamic>>())
      p['name'] as String: p,
  };

  final rows = <Row>[];
  final unknown = <String>[];
  final dev = devOnlyPackages(deps);
  for (final name in {...runtimePackages(deps), ...dev}.toList()..sort()) {
    final p = info[name]!;
    final sdk = p['source'] == 'sdk';
    var license = 'BSD-3-Clause';
    if (!sdk) {
      final dir = Directory.fromUri(Uri.parse(roots[name]!));
      // Sortiert, weil die Reihenfolge von listSync je nach System verschieden ist
      // (archive hat LICENSE und LICENSE-other.md).
      final file =
          (dir
                  .listSync()
                  .whereType<File>()
                  .where(
                    (f) => RegExp(
                      r'^(LICENSE|LICENCE|COPYING)',
                      caseSensitive: false,
                    ).hasMatch(f.uri.pathSegments.last),
                  )
                  .toList()
                ..sort(
                  (a, b) => a.uri.pathSegments.last.compareTo(
                    b.uri.pathSegments.last,
                  ),
                ))
              .firstOrNull;
      license = file == null
          ? 'unbekannt'
          : classifyLicense(file.readAsStringSync());
      if (license == 'unbekannt' || license.contains('GPL')) {
        unknown.add('$name: $license');
      }
    }
    rows.add((
      name: name,
      version: p['version'] as String,
      license: license,
      sdk: sdk,
      dev: dev.contains(name),
    ));
  }

  final text = render(rows);
  final file = File(outputPath);
  final current = file.existsSync()
      ? file.readAsStringSync().replaceAll('\r\n', '\n')
      : '';
  if (check) {
    if (current != text) {
      stderr.writeln(
        '$outputPath ist veraltet: dart run tool/third_party_notices.dart',
      );
      // Erste abweichende Zeile zeigen, damit ein Unterschied in der CI lesbar ist.
      final a = current.split('\n');
      final b = text.split('\n');
      for (var i = 0; i < a.length || i < b.length; i++) {
        final x = i < a.length ? a[i] : '';
        final y = i < b.length ? b[i] : '';
        if (x != y) {
          stderr.writeln('Zeile ${i + 1}\n  Datei:  $x\n  erwartet: $y');
          break;
        }
      }
      exitCode = 1;
    }
  } else {
    file.writeAsStringSync(text);
    stdout.writeln(
      '$outputPath geschrieben (${rows.where((r) => !r.sdk).length} Pakete).',
    );
  }
  if (unknown.isNotEmpty) {
    stderr.writeln('Lizenz prüfen:\n  ${unknown.join('\n  ')}');
    exitCode = 1;
  }
}
