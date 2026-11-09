import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Dateiauswahl und Teilen. Hinter einem Interface, damit Widget-Tests ohne Plattform laufen.
abstract interface class HotspotFiles {
  /// Inhalt der gewählten Datei, null bei Abbruch.
  Future<String?> pickText();

  /// Schreibt [json] als [fileName] in den Temp-Ordner und öffnet das Teilen-Menü.
  Future<void> shareJson(String json, String fileName);
}

/// `sonarb-hotspots-JJJJ-MM-TT.json`
String exportFileName(DateTime day) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'sonarb-hotspots-${day.year}-${two(day.month)}-${two(day.day)}.json';
}

class PlatformHotspotFiles implements HotspotFiles {
  @override
  Future<String?> pickText() async {
    // FileType.any: geteilte JSON-Dateien kommen auf Android oft ohne passenden MIME-Typ an.
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Hotspot-Datei wählen',
    );
    if (files.isEmpty) return null;
    final bytes = await files.first.readAsBytes();
    return utf8.decode(bytes, allowMalformed: false);
  }

  @override
  Future<void> shareJson(String json, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(json, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: fileName,
      ),
    );
  }
}

final hotspotFilesProvider = Provider<HotspotFiles>(
  (ref) => PlatformHotspotFiles(),
);
