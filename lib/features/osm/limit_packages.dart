import 'dart:collection';
import 'dart:io';

import 'limits_format.dart';
import 'osm_log.dart';
import 'osm_tile.dart';

/// Ein installiertes Tempolimit-Paket, wie die Einstellungen es anzeigen.
class InstalledLimitPackage {
  const InstalledLimitPackage({
    required this.id,
    required this.date,
    required this.bytes,
    required this.cells,
  });

  final String id;

  /// Stand der Karten-Daten (JJJJMMTT).
  final int date;
  final int bytes;
  final int cells;
}

/// Die auf dem Gerät gespeicherten Tempolimit-Pakete (`<kennung>.sblp` in [dir]) und der Zugriff auf
/// ihre Zellen. Pakete werden nur auf ausdrücklichen Wunsch geladen (siehe `LimitDownloader`) und
/// überleben das Leeren des Kachel-Caches.
class LimitPackages {
  LimitPackages(this.dir, {this.maxCachedCells = 80});

  final Directory dir;
  final int maxCachedCells;

  final List<LimitPackage> _open = [];
  final Map<String, int> _sizes = {};
  final LinkedHashMap<TileId, List<LimitWay>> _cells = LinkedHashMap();
  Future<void>? _loading;

  /// Vollendet, sobald die Köpfe aller Dateien gelesen sind. Ohne Pakete sofort.
  Future<void> get ready => _loading ??= _load();

  Future<void> _load() async {
    _open.clear();
    _sizes.clear();
    _cells.clear();
    try {
      if (!await dir.exists()) return;
      await for (final e in dir.list()) {
        if (e is! File || !e.path.endsWith(_suffix)) continue;
        try {
          final pkg = await LimitPackage.open(e);
          _open.add(pkg);
          _sizes[pkg.id] = await e.length();
        } catch (err) {
          osmLog('Tempolimit-Paket ${e.path} unbrauchbar: $err');
        }
      }
    } catch (_) {}
    _open.sort((a, b) => a.id.compareTo(b.id));
  }

  static const _suffix = '.sblp';

  /// Liest die Dateien neu (nach Installieren, Löschen oder Ersetzen).
  Future<void> reload() => _loading = _load();

  List<InstalledLimitPackage> get installed => [
    for (final p in _open)
      InstalledLimitPackage(
        id: p.id,
        date: p.date,
        bytes: _sizes[p.id] ?? 0,
        cells: p.cellCount,
      ),
  ];

  bool get isEmpty => _open.isEmpty;

  /// Liegt die Zelle ganz im Gebiet eines Pakets? Dann braucht es für sie keine Overpass-Abfrage.
  /// Erst nach [ready] gültig.
  bool isComplete(TileId id) => _open.any((p) => p.isComplete(id));

  /// Hat ein Paket diese Zelle (auch am Rand)?
  bool hasCell(TileId id) => _open.any((p) => p.hasCell(id));

  /// Wege der Zelle aus allen Paketen. Beschädigte Zellen zählen als leer.
  Future<List<LimitWay>> cell(TileId id) async {
    final cached = _cells.remove(id);
    if (cached != null) {
      _cells[id] = cached;
      return cached;
    }
    final out = <LimitWay>[];
    for (final p in _open) {
      if (!p.hasCell(id)) continue;
      try {
        out.addAll(await p.readCell(id));
      } catch (err) {
        osmLog('Zelle ${id.key} in ${p.id} unlesbar: $err');
      }
    }
    _cells[id] = out;
    while (_cells.length > maxCachedCells) {
      _cells.remove(_cells.keys.first);
    }
    return out;
  }

  /// Wege rund um eine Position: erst alle Hauptstraßen, dann (wenn [withMinor]) alle Nebenstraßen.
  /// Die Reihenfolge entscheidet Gleichstände an Kreuzungen wie bei den Overpass-Schichten.
  Future<List<LimitWay>> around(
    Iterable<TileId> ids, {
    bool withMinor = true,
  }) async {
    final all = [for (final id in ids) ...await cell(id)];
    return [
      for (final w in all)
        if (!w.minor) w,
      if (withMinor)
        for (final w in all)
          if (w.minor) w,
    ];
  }

  File _file(String id) =>
      File('${dir.path}${Platform.pathSeparator}$id$_suffix');

  /// Nimmt eine geprüfte Paketdatei auf: Kopf lesen, unter ihrer Kennung ablegen (ersetzt eine
  /// ältere Fassung) und neu einlesen. [file] wird dabei verschoben.
  Future<InstalledLimitPackage> install(File file) async {
    final pkg = await LimitPackage.open(file);
    if (!RegExp(r'^[a-z0-9_-]{1,40}$').hasMatch(pkg.id)) {
      throw FormatException('Kennung "${pkg.id}" ungültig');
    }
    await dir.create(recursive: true);
    await file.rename(_file(pkg.id).path);
    await reload();
    return installed.firstWhere((p) => p.id == pkg.id);
  }

  Future<void> remove(String id) async {
    try {
      final f = _file(id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await reload();
  }
}
