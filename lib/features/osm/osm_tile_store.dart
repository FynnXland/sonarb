import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'osm_layer.dart';
import 'osm_tile.dart';

/// Kachel-Cache auf der Platte: eine JSON-Datei je Schicht und Kachel direkt in `cacheDir`
/// (`<schicht>_<iy>_<ix>.json`).
class OsmTileStore {
  OsmTileStore(this._dir);

  final Directory _dir;

  static const int _isolateThreshold = 200 * 1024;

  Future<void>? _legacyPurged;

  File _file(OsmLayer layer, TileId id) =>
      File('${_dir.path}${Platform.pathSeparator}${layer.name}_${id.key}.json');

  bool _isOurs(String path) {
    final name = path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);
    return name.endsWith('.json') &&
        OsmLayer.values.any((l) => name.startsWith('${l.name}_'));
  }

  /// Frühere Fassungen legten eine Kachel je 0,1° als `t_*.json` in einen Unterordner `osm/` ab.
  /// Beides ist unbrauchbar und wird einmal entfernt.
  Future<void> _purgeLegacy() => _legacyPurged ??= () async {
    try {
      final nested = Directory('${_dir.path}${Platform.pathSeparator}osm');
      if (await nested.exists()) await nested.delete(recursive: true);
      if (!await _dir.exists()) return;
      await for (final e in _dir.list()) {
        final name = e.path.substring(
          e.path.lastIndexOf(Platform.pathSeparator) + 1,
        );
        if (e is File && name.startsWith('t_') && name.endsWith('.json')) {
          await e.delete();
        }
      }
    } catch (_) {}
  }();

  /// Null, wenn die Datei fehlt oder nicht lesbar ist (kaputte Dateien werden entfernt).
  Future<TileData?> read(OsmLayer layer, TileId id) async {
    await _purgeLegacy();
    final file = _file(layer, id);
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      return text.length < _isolateThreshold
          ? _decode(text)
          : await Isolate.run(() => _decode(text));
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
  }

  /// Atomar: erst in eine tmp-Datei schreiben, dann umbenennen. Fehler werden verschluckt,
  /// ein nicht schreibbarer Cache darf die Abfrage nicht kippen.
  Future<void> write(OsmLayer layer, TileId id, TileData data) async {
    try {
      await _purgeLegacy();
      await _dir.create(recursive: true);
      final file = _file(layer, id);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(data.toJson()), flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
  }

  /// Kacheln von [layer], für die eine Datei vorliegt (nur aus den Dateinamen, ohne zu lesen).
  Future<List<TileId>> list(OsmLayer layer) async {
    final out = <TileId>[];
    try {
      await _purgeLegacy();
      if (!await _dir.exists()) return out;
      final prefix = '${layer.name}_';
      await for (final e in _dir.list()) {
        if (e is! File) continue;
        final name = e.path.substring(
          e.path.lastIndexOf(Platform.pathSeparator) + 1,
        );
        if (!name.startsWith(prefix) || !name.endsWith('.json')) continue;
        final parts = name
            .substring(prefix.length, name.length - '.json'.length)
            .split('_');
        if (parts.length != 2) continue;
        final iy = int.tryParse(parts[0]);
        final ix = int.tryParse(parts[1]);
        if (iy != null && ix != null) out.add(TileId(ix, iy, layer.perDegree));
      }
    } catch (_) {}
    return out;
  }

  /// Löscht nur die eigenen Kachel-Dateien, nicht den Ordner.
  Future<void> clear() async {
    try {
      if (!await _dir.exists()) return;
      await for (final e in _dir.list()) {
        if (e is File && _isOurs(e.path)) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    await _purgeLegacy();
  }

  Future<int> sizeBytes() async {
    var total = 0;
    try {
      await _purgeLegacy();
      if (!await _dir.exists()) return 0;
      await for (final e in _dir.list()) {
        if (e is File && _isOurs(e.path)) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }
}

TileData _decode(String text) {
  final json = jsonDecode(text);
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Kachel-Cache kein Objekt');
  }
  return TileData.fromJson(json);
}
