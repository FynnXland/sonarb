import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'limit_packages.dart';
import 'limits_format.dart';
import 'overpass_client.dart' show overpassUserAgent;

/// Feste Adresse des Verzeichnisses der Tempolimit-Pakete: das jeweils neueste Release des
/// Paket-Repositorys. Das ist noch nicht öffentlich; bis dahin bleibt die Auswahl verborgen
/// ([limitPackagesPublished]). Geladen wird nur auf Wunsch in den Einstellungen.
const String limitCatalogUrl =
    'https://github.com/FynnXland/sonarb-tempolimits/releases/latest/download/packages.json';

/// Ob die Pakete schon veröffentlicht sind. Bis zum ersten Release liefert [limitCatalogUrl] 404;
/// solange bleibt die Auswahl in den Einstellungen verborgen. Schon installierte Pakete gelten weiter.
const bool limitPackagesPublished = false;

/// Ein Eintrag im Verzeichnis der Pakete (`packages.json`).
///
///     {"format": 1, "packages": [
///       {"id": "hamburg", "name": "Hamburg", "date": 20261028, "bytes": 991549,
///        "sha256": "…", "file": "hamburg.sblp"}]}
///
/// `file` ist ein Pfad relativ zum Verzeichnis.
class LimitCatalogEntry {
  const LimitCatalogEntry({
    required this.id,
    required this.name,
    required this.date,
    required this.bytes,
    required this.sha256,
    required this.url,
  });

  final String id;
  final String name;
  final int date;
  final int bytes;
  final String sha256;
  final Uri url;

  /// Ist dieses Paket neuer als das installierte (oder gar keins installiert)?
  bool isNewerThan(InstalledLimitPackage? installed) =>
      installed == null || date > installed.date;
}

enum LimitDownloadProblem {
  unreachable,
  badCatalog,
  tooBig,
  checksum,
  notAPackage,
}

class LimitDownloadException implements Exception {
  const LimitDownloadException(this.problem, [this.detail]);

  final LimitDownloadProblem problem;
  final String? detail;

  @override
  String toString() =>
      'LimitDownloadException($problem${detail == null ? '' : ': $detail'})';
}

/// Lädt das Verzeichnis und einzelne Pakete. Das Paket wird beim Laden gezählt und gehasht, mit
/// Größe und SHA-256 aus dem Verzeichnis verglichen und erst dann installiert; bei jedem Fehler
/// bleibt eine vorhandene ältere Fassung unberührt.
class LimitDownloader {
  LimitDownloader({
    required this.catalogUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final Uri catalogUrl;
  final Duration timeout;
  final http.Client _client;

  static const _headers = {'User-Agent': overpassUserAgent};

  Future<List<LimitCatalogEntry>> catalog() async {
    try {
      final r = await _client
          .get(catalogUrl, headers: _headers)
          .timeout(timeout);
      if (r.statusCode != 200) {
        throw LimitDownloadException(
          LimitDownloadProblem.unreachable,
          'HTTP ${r.statusCode}',
        );
      }
      return _parse(utf8.decode(r.bodyBytes));
    } on LimitDownloadException {
      rethrow;
    } on FormatException catch (e) {
      throw LimitDownloadException(LimitDownloadProblem.badCatalog, e.message);
    } catch (e) {
      throw LimitDownloadException(LimitDownloadProblem.unreachable, '$e');
    }
  }

  List<LimitCatalogEntry> _parse(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['format'] != 1) {
        throw const FormatException('Verzeichnisformat unbekannt');
      }
      return [
        for (final p in (json['packages'] as List).cast<Map<String, dynamic>>())
          LimitCatalogEntry(
            id: p['id'] as String,
            name: p['name'] as String,
            date: p['date'] as int,
            bytes: p['bytes'] as int,
            sha256: (p['sha256'] as String).toLowerCase(),
            url: catalogUrl.resolve(p['file'] as String),
          ),
      ];
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Verzeichnis unlesbar: $e');
    }
  }

  /// Lädt [entry] und installiert es in [target]. [onProgress] bekommt (geladen, gesamt).
  Future<InstalledLimitPackage> download(
    LimitCatalogEntry entry,
    LimitPackages target, {
    void Function(int received, int total)? onProgress,
  }) async {
    await target.dir.create(recursive: true);
    final part = File(
      '${target.dir.path}${Platform.pathSeparator}${entry.id}.sblp.part',
    );
    try {
      final request = http.Request('GET', entry.url)..headers.addAll(_headers);
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        throw LimitDownloadException(
          LimitDownloadProblem.unreachable,
          'HTTP ${response.statusCode}',
        );
      }
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(timeout)) {
          received += chunk.length;
          if (received > entry.bytes) {
            throw const LimitDownloadException(LimitDownloadProblem.tooBig);
          }
          hash.add(chunk);
          sink.add(chunk);
          onProgress?.call(received, entry.bytes);
        }
        hash.close();
      } finally {
        await sink.close();
      }
      if (received != entry.bytes) {
        throw LimitDownloadException(
          LimitDownloadProblem.checksum,
          '$received statt ${entry.bytes} Byte',
        );
      }
      if (digest.value.toString() != entry.sha256) {
        throw const LimitDownloadException(
          LimitDownloadProblem.checksum,
          'SHA-256 weicht ab',
        );
      }
      final head = await LimitPackage.open(part);
      if (head.id != entry.id || head.date != entry.date) {
        throw LimitDownloadException(
          LimitDownloadProblem.notAPackage,
          'Paket ${head.id}/${head.date} statt ${entry.id}/${entry.date}',
        );
      }
      return await target.install(part);
    } on LimitDownloadException {
      await _drop(part);
      rethrow;
    } on FormatException catch (e) {
      await _drop(part);
      throw LimitDownloadException(LimitDownloadProblem.notAPackage, e.message);
    } catch (e) {
      await _drop(part);
      throw LimitDownloadException(LimitDownloadProblem.unreachable, '$e');
    }
  }

  Future<void> _drop(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  void close() => _client.close();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
