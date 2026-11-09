import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/features/osm/limit_download.dart';
import 'package:sonarb/features/osm/limit_packages.dart';
import 'package:sonarb/features/osm/limits_format.dart';

Uint8List package({String id = 'hamburg', int date = 20261028}) => buildPackage(
  id: id,
  date: date,
  cells: {
    (1071, 201): (
      encodeCell(1071, 201, [
        RawWay(
          lat: [535500000, 535500100],
          lon: [100550000, 100550100],
          forward: 50,
          backward: 50,
        ),
      ]),
      cellComplete,
    ),
  },
);

/// Kleiner Server mit Verzeichnis und Dateien; zählt die Abrufe je Pfad.
class Hosting {
  final files = <String, List<int>>{};
  final hits = <String, int>{};
  int status = 200;
  late HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      hits[req.uri.path] = (hits[req.uri.path] ?? 0) + 1;
      final body = files[req.uri.path];
      if (status != 200 || body == null) {
        req.response.statusCode = status != 200 ? status : 404;
      } else {
        req.response.add(body);
      }
      await req.response.close();
    });
  }

  Uri url(String path) =>
      Uri.parse('http://${server.address.host}:${server.port}$path');

  /// Trägt [bytes] unter /pkg/[file] ein und liefert den passenden Katalogeintrag.
  Map<String, Object> publish(
    String id,
    List<int> bytes, {
    String? file,
    int? date,
    int? declaredBytes,
    String? sha,
  }) {
    final name = file ?? '$id.sblp';
    files['/pkg/$name'] = bytes;
    return {
      'id': id,
      'name': id,
      'date': date ?? 20261028,
      'bytes': declaredBytes ?? bytes.length,
      'sha256': sha ?? sha256.convert(bytes).toString(),
      'file': name,
    };
  }

  void catalog(List<Map<String, Object>> packages, {int format = 1}) {
    files['/pkg/packages.json'] = utf8.encode(
      jsonEncode({'format': format, 'packages': packages}),
    );
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  late Hosting host;
  late Directory dir;
  late LimitPackages packages;
  late LimitDownloader downloader;

  setUp(() async {
    host = Hosting();
    await host.start();
    dir = Directory.systemTemp.createTempSync('limit_dl');
    packages = LimitPackages(Directory('${dir.path}/limit_packages'));
    downloader = LimitDownloader(catalogUrl: host.url('/pkg/packages.json'));
  });

  tearDown(() async {
    downloader.close();
    await host.stop();
    dir.deleteSync(recursive: true);
  });

  Future<LimitCatalogEntry> entryOf(Map<String, Object> p) async {
    host.catalog([p]);
    return (await downloader.catalog()).single;
  }

  test('Verzeichnis lesen, Paket laden, prüfen, installieren', () async {
    final bytes = package();
    host.catalog([host.publish('hamburg', bytes)]);
    final catalog = await downloader.catalog();
    expect(catalog.single.id, 'hamburg');
    expect(catalog.single.url, host.url('/pkg/hamburg.sblp'));
    expect(catalog.single.isNewerThan(null), isTrue);

    final progress = <int>[];
    final info = await downloader.download(
      catalog.single,
      packages,
      onProgress: (got, total) => progress.add(got),
    );
    expect((info.id, info.date), ('hamburg', 20261028));
    expect(progress.last, bytes.length);
    expect(packages.installed.single.id, 'hamburg');
    expect(
      Directory('${dir.path}/limit_packages')
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last),
      ['hamburg.sblp'],
      reason: 'keine Reste der Teil-Datei',
    );
    expect(catalog.single.isNewerThan(packages.installed.single), isFalse);
    expect(
      LimitCatalogEntry(
        id: 'hamburg',
        name: 'Hamburg',
        date: 20261105,
        bytes: 1,
        sha256: '',
        url: Uri(),
      ).isNewerThan(packages.installed.single),
      isTrue,
    );
  });

  group('wird abgelehnt, und die ältere Fassung bleibt', () {
    late LimitCatalogEntry good;

    setUp(() async {
      host.catalog([host.publish('hamburg', package())]);
      good = (await downloader.catalog()).single;
      await downloader.download(good, packages);
    });

    Future<void> rejects(
      Map<String, Object> published,
      LimitDownloadProblem problem,
    ) async {
      final entry = await entryOf(published);
      await expectLater(
        downloader.download(entry, packages),
        throwsA(
          isA<LimitDownloadException>().having(
            (e) => e.problem,
            'problem',
            problem,
          ),
        ),
      );
      expect(packages.installed.single.date, 20261028);
      expect(
        Directory('${dir.path}/limit_packages').listSync(),
        hasLength(1),
        reason: 'Teil-Datei entfernt',
      );
    }

    test('falsche Prüfsumme', () async {
      final bytes = package(date: 20261105);
      await rejects(
        host.publish(
          'hamburg',
          bytes,
          sha: sha256.convert([1, 2, 3]).toString(),
          date: 20261105,
        ),
        LimitDownloadProblem.checksum,
      );
    });

    test('verändertes Paket (richtige Größe, falsche Prüfsumme)', () async {
      final bytes = package(date: 20261105);
      final tampered = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;
      await rejects(
        host.publish(
          'hamburg',
          tampered,
          sha: sha256.convert(bytes).toString(),
          date: 20261105,
        ),
        LimitDownloadProblem.checksum,
      );
    });

    test('größer als angegeben', () async {
      final bytes = package(date: 20261105);
      await rejects(
        host.publish(
          'hamburg',
          bytes,
          declaredBytes: bytes.length - 5,
          date: 20261105,
        ),
        LimitDownloadProblem.tooBig,
      );
    });

    test('kleiner als angegeben', () async {
      final bytes = package(date: 20261105);
      await rejects(
        host.publish(
          'hamburg',
          bytes,
          declaredBytes: bytes.length + 5,
          date: 20261105,
        ),
        LimitDownloadProblem.checksum,
      );
    });

    test('Datei mit richtiger Prüfsumme, aber kein Paket', () async {
      final junk = utf8.encode('das ist kein Paket, nur Text');
      await rejects(
        host.publish('hamburg', junk, date: 20261105),
        LimitDownloadProblem.notAPackage,
      );
    });

    test(
      'Paket gehört zu einer anderen Kennung oder einem anderen Stand',
      () async {
        await rejects(
          host.publish(
            'hamburg',
            package(id: 'bremen', date: 20261105),
            date: 20261105,
          ),
          LimitDownloadProblem.notAPackage,
        );
        await rejects(
          host.publish('hamburg', package(date: 20260101), date: 20261105),
          LimitDownloadProblem.notAPackage,
        );
      },
    );

    test('Server antwortet mit Fehler', () async {
      final entry = await entryOf(
        host.publish('hamburg', package(date: 20261105), date: 20261105),
      );
      host.status = 503;
      await expectLater(
        downloader.download(entry, packages),
        throwsA(
          isA<LimitDownloadException>().having(
            (e) => e.problem,
            'problem',
            LimitDownloadProblem.unreachable,
          ),
        ),
      );
      expect(packages.installed.single.date, 20261028);
    });
  });

  group('Verzeichnis', () {
    test('liest das Verzeichnis, das der Generator schreibt (parity/catalog_sample.json)', () async {
      host.files['/pkg/packages.json'] = File(
        'test/osm/parity/catalog_sample.json',
      ).readAsBytesSync();
      final catalog = await downloader.catalog();
      expect(catalog.map((e) => e.id), ['bremen', 'hamburg']);
      expect(catalog.last.name, 'Hamburg');
      expect(catalog.last.date, 20261029);
      expect(catalog.last.url, host.url('/pkg/hamburg.sblp'));
      expect(catalog.last.sha256, hasLength(64));
    });

    test('unbekanntes Format, kaputtes JSON, Server weg', () async {
      Future<void> fails(LimitDownloadProblem p) => expectLater(
        downloader.catalog(),
        throwsA(
          isA<LimitDownloadException>().having((e) => e.problem, 'problem', p),
        ),
      );
      host.catalog([], format: 2);
      await fails(LimitDownloadProblem.badCatalog);
      host.files['/pkg/packages.json'] = utf8.encode(
        '{"format":1,"packages":[{"id":1}]}',
      );
      await fails(LimitDownloadProblem.badCatalog);
      host.files['/pkg/packages.json'] = utf8.encode('kein json');
      await fails(LimitDownloadProblem.badCatalog);
      host.status = 500;
      await fails(LimitDownloadProblem.unreachable);
      await host.stop();
      await fails(LimitDownloadProblem.unreachable);
      host = Hosting()
        ..server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    test('nichts wird ohne Aufruf geladen', () async {
      host.catalog([host.publish('hamburg', package())]);
      expect(host.hits, isEmpty);
    });
  });
}
