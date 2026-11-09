import 'dart:developer' as developer;
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../core/contracts/hotspot_repository.dart';
import 'hotspot_codec.dart';

typedef HotspotErrorLogger = void Function(
  String message,
  Object error,
  StackTrace stack,
);

void defaultHotspotLogger(String message, Object error, StackTrace stack) =>
    developer.log(
      message,
      name: 'sonarb.hotspots',
      level: 1000,
      error: error,
      stackTrace: stack,
    );

/// Datei `hotspots.json` im Datenordner: Laden mit Schutz vor Defekten, atomares Schreiben.
class HotspotFileStore {
  HotspotFileStore(this.dir, {HotspotErrorLogger? onError})
    : _onError = onError ?? defaultHotspotLogger;

  final Directory dir;
  final HotspotErrorLogger _onError;

  String get _sep => Platform.pathSeparator;
  File get file => File('${dir.path}${_sep}hotspots.json');
  File get _tmp => File('${dir.path}${_sep}hotspots.json.tmp');

  /// Fehlende Datei = leer. Unlesbare oder teilweise ungültige Datei wird beiseitegelegt
  /// (nie überschrieben); bei Teildefekt bleiben die gültigen Einträge erhalten.
  Future<List<Hotspot>> load() async {
    final f = file;
    String text;
    try {
      if (!await f.exists()) return [];
      text = await f.readAsString();
    } catch (e, st) {
      _onError('hotspots.json nicht lesbar', e, st);
      await _setAside(copyOnly: false);
      return [];
    }

    try {
      final raw = parseHotspotDocument(text);
      final now = DateTime.now();
      const uuid = Uuid();
      final seen = <String>{};
      final items = <Hotspot>[];
      var invalid = 0;
      for (final entry in raw) {
        final h = hotspotFromJson(entry, newId: uuid.v4, now: now);
        if (h == null || !seen.add(h.id)) {
          invalid++;
          continue;
        }
        items.add(h);
      }
      if (invalid > 0) {
        _onError(
          'hotspots.json: $invalid ungültige Einträge, Kopie gesichert',
          const FormatException('ungültige Einträge'),
          StackTrace.current,
        );
        await _setAside(copyOnly: true);
        try {
          // Bereinigte Fassung sofort speichern, sonst entsteht bei jedem Start eine neue Kopie.
          await write(sortNewestFirst(items));
        } catch (e, st) {
          _onError('Bereinigte hotspots.json nicht geschrieben', e, st);
        }
      }
      return sortNewestFirst(items);
    } on HotspotFormatException catch (e, st) {
      _onError('hotspots.json defekt: ${e.message}', e, st);
      await _setAside(copyOnly: false);
      return [];
    }
  }

  /// Schreibt in eine Temp-Datei und benennt sie über die Zieldatei.
  Future<void> write(List<Hotspot> items) async {
    await dir.create(recursive: true);
    final text = encodeHotspotDocument(items, DateTime.now());
    final tmp = _tmp;
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _setAside({required bool copyOnly}) async {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9T]'),
      '',
    );
    var target = '${file.path}.defekt-$stamp';
    var n = 1;
    while (await File(target).exists()) {
      target = '${file.path}.defekt-$stamp-${n++}';
    }
    try {
      if (copyOnly) {
        await file.copy(target);
      } else {
        await file.rename(target);
      }
    } catch (e, st) {
      _onError('Defekte Datei konnte nicht beiseitegelegt werden', e, st);
    }
  }
}
