// Bindet lokale Plugins aus lib/plugins/local/<name>/plugin.dart ein.
//
//   dart run tool/plugins.dart          installed_plugins.dart neu schreiben
//   dart run tool/plugins.dart --reset  leere Fassung wiederherstellen
//   dart run tool/plugins.dart --help
//
// Siehe docs/PLUGINS.md.
import 'dart:io';

const installedPluginsPath = 'lib/plugins/installed_plugins.dart';
const localPluginsPath = 'lib/plugins/local';

final _dirName = RegExp(r'^[A-Za-z0-9_-]+$');
final _createPlugin = RegExp(
  r'^DataSourcePlugin\s+createPlugin\s*\(\s*\)',
  multiLine: true,
);

/// Enthält [source] die Top-Level-Funktion `DataSourcePlugin createPlugin()`?
bool declaresCreatePlugin(String source) => _createPlugin.hasMatch(source);

/// Ordnername geeignet für einen Import-Pfad?
bool isValidPluginDir(String name) => _dirName.hasMatch(name);

/// Quelltext von `installed_plugins.dart` für die Plugin-Ordner [dirs] (sortiert, ohne Duplikate).
/// Ohne Plugins entsteht die Fassung, die im Repository liegt.
String generateInstalledPlugins(Iterable<String> dirs) {
  final names = dirs.toSet().toList()..sort();
  if (names.isEmpty) {
    return '''
import '../core/contracts/data_source_plugin.dart';

/// Liste der eingesteckten Plugins. Im Repository immer leer.
/// Lokale, nicht mitgesicherte Plugins: docs/PLUGINS.md (`dart run tool/plugins.dart`).
List<DataSourcePlugin> installedPlugins() => const [];
''';
  }
  final b = StringBuffer()
    ..writeln(
      '// GENERIERT von tool/plugins.dart. Nicht committen (git skip-worktree).',
    )
    ..writeln('// Zurücksetzen: dart run tool/plugins.dart --reset')
    ..writeln("import '../core/contracts/data_source_plugin.dart';");
  for (var i = 0; i < names.length; i++) {
    b.writeln("import 'local/${names[i]}/plugin.dart' as p$i;");
  }
  b
    ..writeln()
    ..writeln('List<DataSourcePlugin> installedPlugins() => [');
  for (var i = 0; i < names.length; i++) {
    b.writeln('      p$i.createPlugin(),');
  }
  b.writeln('    ];');
  return b.toString();
}

const _usage = '''
Verwendung: dart run tool/plugins.dart [--reset]

  (ohne)   lib/plugins/local/*/plugin.dart suchen und lib/plugins/installed_plugins.dart schreiben
  --reset  leere Fassung wiederherstellen
  --help   diese Hilfe

Die Datei installed_plugins.dart wird per "git update-index --skip-worktree" vor
versehentlichem Commit geschützt; --reset hebt das wieder auf.''';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }
  final reset = args.contains('--reset');
  final unknown = args.where((a) => a != '--reset').toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('Unbekannte Option: ${unknown.join(' ')}\n\n$_usage');
    exitCode = 64;
    return;
  }

  final root = File.fromUri(Platform.script).parent.parent.path;
  final names = reset ? <String>[] : _findPlugins(root);
  final target = File('$root/$installedPluginsPath');
  target.writeAsStringSync(generateInstalledPlugins(names));

  if (reset) {
    stdout.writeln('$installedPluginsPath zurückgesetzt (leere Liste).');
  } else {
    stdout.writeln(
      '$installedPluginsPath geschrieben: '
      '${names.isEmpty ? 'keine Plugins gefunden' : names.join(', ')}.',
    );
  }
  await _setSkipWorktree(root, skip: !reset && names.isNotEmpty);
}

List<String> _findPlugins(String root) {
  final dir = Directory('$root/$localPluginsPath');
  if (!dir.existsSync()) return [];
  final found = <String>[];
  for (final entry in dir.listSync().whereType<Directory>()) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final file = File('${entry.path}/plugin.dart');
    if (!file.existsSync()) continue;
    if (!isValidPluginDir(name)) {
      stderr.writeln(
        'Übersprungen: "$name" (Ordnername nur aus A-Z, a-z, 0-9, _ und -).',
      );
    } else if (!declaresCreatePlugin(file.readAsStringSync())) {
      stderr.writeln(
        'Übersprungen: $name/plugin.dart enthält kein '
        '"DataSourcePlugin createPlugin()".',
      );
    } else {
      found.add(name);
    }
  }
  return found;
}

/// Setzt oder löscht das Git-Flag, damit die erzeugte Datei nicht versehentlich committet wird.
Future<void> _setSkipWorktree(String root, {required bool skip}) async {
  final flag = skip ? '--skip-worktree' : '--no-skip-worktree';
  try {
    final r = await Process.run('git', [
      'update-index',
      flag,
      installedPluginsPath,
    ], workingDirectory: root);
    if (r.exitCode == 0) {
      stdout.writeln(
        skip
            ? 'Git: $installedPluginsPath ist jetzt skip-worktree '
                  '(Änderungen erscheinen nicht in git status).'
            : 'Git: skip-worktree für $installedPluginsPath aufgehoben.',
      );
    } else {
      stderr.writeln(
        'Git-Flag nicht gesetzt (${r.stderr.toString().trim()}). '
        'Datei nicht committen.',
      );
    }
  } on ProcessException {
    stderr.writeln(
      'Git nicht gefunden, Flag nicht gesetzt. Datei nicht committen.',
    );
  }
}
