import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/hotspot_repository.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/settings/hotspot_files.dart';
import 'package:sonarb/features/settings/hotspots_screen.dart';
import 'package:sonarb/features/settings/settings_screen.dart';

import '../cockpit/fakes.dart';

class FakeFiles implements HotspotFiles {
  String? picked = '{"version":1,"hotspots":[]}';
  final shared = <(String, String)>[];

  @override
  Future<String?> pickText() async => picked;

  @override
  Future<void> shareJson(String json, String fileName) async =>
      shared.add((json, fileName));
}

void main() {
  late TestRig rig;
  late FakeFiles files;

  setUp(() async {
    rig = await TestRig.create();
    files = FakeFiles();
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...rig.overrides,
          hotspotFilesProvider.overrideWithValue(files),
        ],
        child: MaterialApp(theme: buildSonarTheme(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  Hotspot hotspot(String id, {String? note, double? heading}) => Hotspot(
    id: id,
    position: const GeoPoint(52.52, 13.405),
    createdAt: DateTime(2026, 10, 28, 9, 5),
    headingDeg: heading,
    note: note,
  );

  testWidgets('Import zeigt das Ergebnis', (tester) async {
    await pump(tester, const HotspotsScreen());
    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();
    expect(rig.hotspots.lastImported, files.picked);
    expect(find.text('3 übernommen, 1 doppelt, 0 ungültig'), findsOneWidget);
  });

  testWidgets('ungültige Datei: Fehlertext aus HotspotFormatException', (
    tester,
  ) async {
    rig.hotspots.importError = const HotspotFormatException(
      'Unbekannte Version 9.',
    );
    await pump(tester, const HotspotsScreen());
    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();
    expect(
      find.text('Datei nicht importiert: Unbekannte Version 9.'),
      findsOneWidget,
    );
  });

  testWidgets('Abbruch der Dateiauswahl importiert nichts', (tester) async {
    files.picked = null;
    await pump(tester, const HotspotsScreen());
    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();
    expect(rig.hotspots.lastImported, isNull);
  });

  testWidgets('Export teilt eine datierte JSON-Datei', (tester) async {
    rig.hotspots.items.add(hotspot('a'));
    await pump(tester, const HotspotsScreen());
    await tester.tap(find.text('Exportieren'));
    await tester.pumpAndSettle();
    final (json, name) = files.shared.single;
    expect(json, contains('"version"'));
    expect(name, matches(RegExp(r'^sonarb-hotspots-\d{4}-\d{2}-\d{2}\.json$')));
  });

  testWidgets('Liste zeigt Art, Datum, Koordinate und Notiz', (tester) async {
    rig.hotspots.items.add(hotspot('a', note: 'Brücke Ortsausgang'));
    await pump(tester, const HotspotsScreen());
    expect(find.text('Mobiler Blitzer · 28.10.2026, 09:05'), findsOneWidget);
    expect(find.text('52,5200 / 13,4050\nBrücke Ortsausgang'), findsOneWidget);
  });

  testWidgets('Löschen nur nach Bestätigung', (tester) async {
    rig.hotspots.items.add(hotspot('a'));
    await pump(tester, const HotspotsScreen());
    await tester.tap(find.byTooltip('Löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(rig.hotspots.items, hasLength(1));

    await tester.tap(find.byTooltip('Löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Löschen'));
    await tester.pumpAndSettle();
    expect(rig.hotspots.items, isEmpty);
    expect(find.textContaining('Noch keine Hotspots'), findsOneWidget);
  });

  testWidgets('Bearbeiten: Art, Notiz, Richtung löschen', (tester) async {
    rig.hotspots.items.add(hotspot('a', heading: 90, note: 'alt'));
    await pump(tester, const HotspotsScreen());
    await tester.tap(find.textContaining('Mobiler Blitzer'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gefahrenstelle'));
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Richtung löschen'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final h = rig.hotspots.items.single;
    expect(h.kind, HotspotKind.danger);
    expect(h.note, isNull);
    expect(h.headingDeg, isNull);
  });

  testWidgets('Einstellungen: ohne Zusatzquellen kein Plugin-Hinweis', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.text('OSM-Cache'), 200);
    expect(find.text('2,0 MB'), findsOneWidget);
    expect(find.textContaining('Plugin'), findsNothing);
    expect(find.text('Zusatzquelle'), findsNothing);
  });

  testWidgets('Über: Datenschutz und Lizenzen öffnen sich', (tester) async {
    await pump(tester, const SettingsScreen());
    final privacy = find.text('Datenschutz');
    await tester.scrollUntilVisible(privacy, 200);
    await tester.ensureVisible(privacy);
    await tester.pumpAndSettle();
    expect(find.textContaining('§ 23 Abs. 1c StVO'), findsOneWidget);
    expect(find.text('Sonarb · Version 1.0.0'), findsOneWidget);

    await tester.tap(privacy);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('overpass-api.de'),
      100,
    );
    expect(find.text('Kartendaten'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Lizenzen'), 100);
    await tester.tap(find.text('Lizenzen'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('Stumm wird gespeichert und an den Ton gegeben', (tester) async {
    await pump(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.text('Stumm'), 100);
    await tester.ensureVisible(find.text('Stumm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stumm'));
    await tester.pumpAndSettle();
    expect(rig.audio.muted, isTrue);
    expect(rig.prefs.getBool('settings.muted'), isTrue);
  });

  test('Dateiname des Exports', () {
    expect(
      exportFileName(DateTime(2026, 3, 7)),
      'sonarb-hotspots-2026-03-07.json',
    );
  });

  testWidgets('Ortung: Hinweis nur nach Ablehnung, Knopf fragt erneut an', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());
    expect(find.text('Ortung ohne Google-Standortgenauigkeit'), findsNothing);

    var retries = 0;
    await pump(
      tester,
      SettingsScreen(
        googleAccuracyDeclined: true,
        onRetryGoogleAccuracy: () => retries++,
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Erneut anfragen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Erneut anfragen'));
    await tester.pumpAndSettle();
    expect(find.text('Ortung ohne Google-Standortgenauigkeit'), findsOneWidget);
    await tester.tap(find.text('Erneut anfragen'));
    expect(retries, 1);
  });
}
