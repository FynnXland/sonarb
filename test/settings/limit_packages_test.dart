import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/app/services.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/features/osm/limit_download.dart';
import 'package:sonarb/features/osm/limit_packages.dart';
import 'package:sonarb/features/osm/limits_format.dart';
import 'package:sonarb/features/osm/osm_tile.dart';
import 'package:sonarb/features/settings/limit_packages_controller.dart';
import 'package:sonarb/features/settings/limit_packages_screen.dart';
import 'package:sonarb/features/settings/limit_packages_tile.dart';

import '../cockpit/fakes.dart';

Uint8List _package(String id, {int date = 20261029}) => buildPackage(
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

/// Server im Speicher: Verzeichnis und Pakete; Zustand lässt sich im Test umstellen.
class _Hosting {
  _Hosting() {
    publish('hamburg', 'Hamburg');
    publish('bayern', 'Bayern');
  }

  final files = <String, Uint8List>{};
  final catalog = <Map<String, Object>>[];
  int catalogStatus = 200;
  int fileStatus = 200;

  void publish(String id, String name, {int date = 20261029}) {
    final bytes = _package(id, date: date);
    files['/$id.sblp'] = bytes;
    catalog.removeWhere((e) => e['id'] == id);
    catalog.add({
      'id': id,
      'name': name,
      'date': date,
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'file': '$id.sblp',
    });
  }

  Future<http.Response> handle(http.Request r) async {
    if (r.url.path == '/packages.json') {
      return http.Response(
        jsonEncode({'format': 1, 'packages': catalog}),
        catalogStatus,
      );
    }
    final bytes = files[r.url.path];
    return bytes == null || fileStatus != 200
        ? http.Response('', fileStatus == 200 ? 404 : fileStatus)
        : http.Response.bytes(bytes, 200);
  }
}

void main() {
  late TestRig rig;
  late Directory dir;
  late _Hosting host;
  late LimitPackages packages;

  setUp(() async {
    rig = await TestRig.create();
    dir = Directory.systemTemp.createTempSync('limit_ui');
    host = _Hosting();
    packages = LimitPackages(Directory('${dir.path}/limit_packages'));
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<Override> overrides({String? land}) {
    final base = rig.services;
    final services = AppServices(
      osm: base.osm,
      hotspots: base.hotspots,
      audio: base.audio,
      engine: base.engine,
      alerts: base.alerts,
      prefs: base.prefs,
      limitPackages: packages,
      limitDownloader: LimitDownloader(
        catalogUrl: Uri.parse('https://example.test/packages.json'),
        client: MockClient(host.handle),
      ),
    );
    return [
      servicesProvider.overrideWithValue(services),
      currentLandProvider.overrideWithValue(land),
    ];
  }

  Future<void> pumpScreen(WidgetTester tester, {String? land}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(land: land),
        child: MaterialApp(
          theme: buildSonarTheme(),
          home: const LimitPackagesScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('Angebot, Laden mit Rückfrage, Fortschritt, Löschen', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('Hamburg'), findsOneWidget);
    expect(find.text('Bayern'), findsOneWidget);
    expect(
      find.textContaining(
        'Das Umland steht in Schleswig-Holstein und Niedersachsen.',
      ),
      findsOneWidget,
    );
    expect(find.text('Bundesländer'), findsOneWidget);
    expect(find.text('Geladen'), findsNothing);
    expect(find.textContaining('© OpenStreetMap-Mitwirkende'), findsOneWidget);
    expect(find.text('Laden'), findsNWidgets(2));
    expect(find.text('Pakete gerade nicht erreichbar'), findsNothing);

    await tester.tap(tileButton('Hamburg'));
    await tester.pumpAndSettle();
    expect(find.textContaining('am besten im WLAN'), findsOneWidget);
    await tester.tap(dialogButton('Abbrechen'));
    await tester.pumpAndSettle();
    expect(
      packages.installed,
      isEmpty,
      reason: 'ohne Zustimmung nichts geladen',
    );

    await tester.tap(tileButton('Hamburg'));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('Laden'));
    await settle(tester);
    expect(find.byTooltip('Hamburg löschen'), findsOneWidget);
    expect(find.textContaining('Stand 29.10.2026'), findsOneWidget);
    expect(find.text('Geladen'), findsOneWidget, reason: 'Geladenes oben');
    expect(find.text('Weitere Bundesländer'), findsOneWidget);
    expect(packages.installed.single.id, 'hamburg');
    expect(packages.isComplete(const TileLike().id), isTrue);

    await tester.tap(find.byTooltip('Hamburg löschen'));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('Löschen'));
    await settle(tester);
    expect(packages.installed, isEmpty);
    expect(find.text('Geladen'), findsNothing);
  });

  testWidgets(
    'Adresse noch nicht da (404): ruhiger Hinweis, Installiertes bleibt',
    (tester) async {
      await tester.runAsync(() async {
        await packages.install(
          File('${dir.path}/x.sblp')..writeAsBytesSync(_package('bremen')),
        );
      });
      host.catalogStatus = 404;
      await pumpScreen(tester);
      expect(find.text('Pakete gerade nicht erreichbar'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(
        find.text('Schon geladene Pakete funktionieren weiter.'),
        findsOneWidget,
      );
      expect(
        find.text('Bremen'),
        findsOneWidget,
        reason: 'geladenes Paket bleibt sichtbar',
      );
      expect(
        find.textContaining('Das Umland steht im Paket Niedersachsen.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error), findsNothing);

      host.catalogStatus = 200;
      await tester.tap(find.text('Erneut versuchen'));
      await settle(tester);
      expect(find.text('Pakete gerade nicht erreichbar'), findsNothing);
      expect(find.text('Bayern'), findsOneWidget);
    },
  );

  testWidgets('Download scheitert: Meldung, alte Fassung bleibt', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await packages.install(
        File('${dir.path}/x.sblp')
          ..writeAsBytesSync(_package('hamburg', date: 20261001)),
      );
    });
    host.publish('hamburg', 'Hamburg', date: 20261105);
    host.fileStatus = 503;
    await pumpScreen(tester);
    expect(find.textContaining('Neuer Stand 05.11.2026'), findsOneWidget);
    await tester.tap(find.text('Aktualisieren'));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('Aktualisieren'));
    await settle(tester);
    expect(
      find.textContaining('Download nicht möglich. Nichts wurde geändert.'),
      findsOneWidget,
    );
    expect(packages.installed.single.date, 20261001);
  });

  testWidgets('beschädigte Datei wird verworfen', (tester) async {
    host.publish('hamburg', 'Hamburg');
    final bytes = Uint8List.fromList(host.files['/hamburg.sblp']!)..[5] ^= 1;
    host.files['/hamburg.sblp'] = bytes;
    await pumpScreen(tester);
    await tester.tap(tileButton('Hamburg'));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('Laden'));
    await settle(tester);
    expect(
      find.textContaining('beschädigt und wurde verworfen'),
      findsOneWidget,
    );
    expect(packages.installed, isEmpty);
  });

  testWidgets('Vorschlag für das Land, in dem man gerade ist', (tester) async {
    await pumpScreen(tester, land: 'bayern');
    expect(find.text('Du bist in Bayern'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Card, 'Du bist in Bayern'),
        matching: find.text('Paket laden'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('Laden'));
    await settle(tester);
    expect(packages.installed.single.id, 'bayern');
    expect(
      find.text('Du bist in Bayern'),
      findsNothing,
      reason: 'nur solange nichts geladen ist',
    );
  });

  testWidgets('ohne Netz und ohne Paket: Tempolimits weiter aus dem Netz', (
    tester,
  ) async {
    host.catalogStatus = 404;
    await pumpScreen(tester, land: 'hamburg');
    expect(
      find.text('Ohne Paket kommen die Tempolimits weiter aus dem Netz.'),
      findsOneWidget,
    );
    expect(find.textContaining('Du bist in'), findsNothing);
  });

  testWidgets('kleiner Bildschirm, große Schrift: alles passt', (tester) async {
    await tester.runAsync(() async {
      await packages.install(
        File('${dir.path}/x.sblp')
          ..writeAsBytesSync(_package('hamburg', date: 20261001)),
      );
    });
    host.publish('mecklenburg-vorpommern', 'Mecklenburg-Vorpommern');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(land: 'bayern'),
        child: MaterialApp(
          theme: buildSonarTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const LimitPackagesScreen(),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    // Rechts nur ein Knopf: der Name hat Platz, „Aktualisieren“ steht darunter.
    await tester.scrollUntilVisible(find.text('Aktualisieren'), 200);
    await tester.pumpAndSettle();
    final title = tester.getRect(find.text('Hamburg'));
    final update = tester.getRect(find.text('Aktualisieren'));
    expect(update.top, greaterThan(title.bottom));
    // Tippfläche mindestens 48 dp (das sichtbare Symbol ist kleiner).
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.byTooltip('Hamburg löschen'),
              matching: find.byType(IconButton),
            ),
          )
          .width,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('kein Vorschlag außerhalb von Deutschland', (tester) async {
    await pumpScreen(tester);
    expect(find.textContaining('Du bist in'), findsNothing);
  });

  group('Kurzfassung in der Einstellungsliste', () {
    test('ohne Paket: Vorschlag oder Hinweis', () {
      const state = LimitPackagesState();
      expect(limitPackagesSummary(state, null), 'Noch kein Paket geladen');
      expect(
        limitPackagesSummary(state, 'hamburg'),
        'Du bist in Hamburg: Paket laden empfohlen',
      );
      expect(limitPackagesSummary(state, 'mars'), 'Noch kein Paket geladen');
    });

    test('mit Paketen: Namen und Größe', () {
      const state = LimitPackagesState(
        installed: [
          InstalledLimitPackage(
            id: 'bayern',
            date: 1,
            bytes: 11 * 1048576,
            cells: 1,
          ),
          InstalledLimitPackage(
            id: 'hamburg',
            date: 1,
            bytes: 1048576,
            cells: 1,
          ),
        ],
      );
      expect(limitPackagesSummary(state, null), 'Bayern, Hamburg · 12,0 MB');
    });

    test('Datum', () => expect(limitPackageDate(20261029), '29.10.2026'));
  });

  test('nichts wird ohne Aufruf geladen', () async {
    var requests = 0;
    final container = ProviderContainer(
      overrides: [
        servicesProvider.overrideWithValue(
          AppServices(
            osm: rig.services.osm,
            hotspots: rig.services.hotspots,
            audio: rig.services.audio,
            engine: rig.services.engine,
            alerts: rig.services.alerts,
            prefs: rig.services.prefs,
            limitPackages: packages,
            limitDownloader: LimitDownloader(
              catalogUrl: Uri.parse('https://example.test/packages.json'),
              client: MockClient((r) async {
                requests++;
                return http.Response('', 404);
              }),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(limitPackagesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(requests, 0);
  });
}

/// „Laden“ oder „Aktualisieren“ in der Zeile mit [title].
Finder tileButton(String title, [String label = 'Laden']) => find.descendant(
  of: find.widgetWithText(ListTile, title),
  matching: find.text(label),
);

/// Schaltfläche im Dialog.
Finder dialogButton(String label) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

/// Zelle des Testpakets (53,55–53,60 N / 10,05–10,10 O).
class TileLike {
  const TileLike();
  TileId get id => const TileId(201, 1071, 20);
}

/// Echte Datei-Ein-/Ausgabe läuft außerhalb der Test-Uhr: abwechselnd echte Zeit lassen und den
/// Bildschirm nachziehen, bis kein Download mehr läuft.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (i >= 10 && find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}
