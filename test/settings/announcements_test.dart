import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/alert_audio.dart';
import 'package:sonarb/features/settings/announcements_screen.dart';
import 'package:sonarb/features/settings/settings_screen.dart';

import '../cockpit/fakes.dart';

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: rig.overrides,
        child: MaterialApp(theme: buildSonarTheme(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String title) => find.widgetWithText(SwitchListTile, title);

  testWidgets('Einstieg aus den Einstellungen', (tester) async {
    await pump(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.text('Sprachansagen'), 100);
    expect(find.text('An, alle Sätze'), findsOneWidget);
    await tester.tap(find.text('Sprachansagen'));
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementsScreen), findsOneWidget);
  });

  testWidgets('listet jeden Satz genau einmal', (tester) async {
    await pump(tester, const AnnouncementsScreen());
    final listed = [for (final (_, items) in announcementGroups) ...items];
    // Den Hotspot-Satz regelt die Auswahl „Blitzer-Hotspots“.
    final all = {...Announcement.values}..remove(Announcement.heatSpot);
    expect(listed.toSet(), all);
    expect(listed, hasLength(all.length));
    for (final a in listed) {
      final title = announcementTitle(a);
      await tester.scrollUntilVisible(row(title), 100);
      expect(row(title), findsOneWidget, reason: '$a');
    }
  });

  testWidgets('Satz abschalten: gespeichert und an den Ton gegeben', (
    tester,
  ) async {
    await pump(tester, const AnnouncementsScreen());
    await tester.scrollUntilVisible(row('Baustelle voraus'), 100);
    // Ganz ins Bild holen: am Rand träfe der Tipp sonst die Nachbarzeile.
    await tester.ensureVisible(row('Baustelle voraus'));
    await tester.pumpAndSettle();
    await tester.tap(row('Baustelle voraus'));
    await tester.pumpAndSettle();
    // Der Hotspot-Satz ist abgeschaltet, solange „Nur Signalton“ gewählt ist (Standard).
    expect(rig.audio.silenced, {
      Announcement.construction,
      Announcement.heatSpot,
    });
    expect(rig.prefs.getStringList('settings.silencedAnnouncements'), [
      'construction',
    ]);

    // Nach einem Neustart gilt der gespeicherte Stand.
    final reloaded = AppSettings.load(rig.prefs);
    expect(reloaded.silenced, {Announcement.construction});

    await tester.tap(row('Baustelle voraus'));
    await tester.pumpAndSettle();
    expect(rig.audio.silenced, {Announcement.heatSpot});
  });

  testWidgets('Hauptschalter aus: Sätze gesperrt, Anhören geht weiter', (
    tester,
  ) async {
    await pump(tester, const AnnouncementsScreen());
    await tester.tap(row('Sprachansagen'));
    await tester.pumpAndSettle();
    expect(rig.audio.voiceEnabled, isFalse);
    expect(rig.prefs.getBool('settings.voiceEnabled'), isFalse);

    final tile = tester.widget<SwitchListTile>(row('Fester Blitzer voraus'));
    expect(tile.onChanged, isNull);

    await tester.tap(find.byTooltip('Fester Blitzer voraus anhören'));
    await tester.pump();
    expect(rig.audio.previews, [Announcement.fixedCamera]);
  });

  testWidgets('Anhören spielt genau diesen Satz', (tester) async {
    await pump(tester, const AnnouncementsScreen());
    await tester.scrollUntilVisible(row('Tempo-Zusatz'), 100);
    await tester.ensureVisible(find.byTooltip('Tempo-Zusatz anhören'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tempo-Zusatz anhören'));
    await tester.pump();
    expect(rig.audio.previews, [Announcement.speedLimit]);
  });

  test('unbekannte gespeicherte Namen werden übergangen', () async {
    await rig.prefs.setStringList('settings.silencedAnnouncements', [
      'danger',
      'gibtEsNicht',
    ]);
    expect(AppSettings.load(rig.prefs).silenced, {Announcement.danger});
  });

  test('Zusammenfassung in den Einstellungen', () {
    const on = AppSettings();
    expect(voiceSummary(on), 'An, alle Sätze');
    expect(
      voiceSummary(on.withAnnouncement(Announcement.danger, on: false)),
      'An, 1 Satz abgeschaltet',
    );
    expect(
      voiceSummary(on.copyWith(voiceEnabled: false)),
      'Aus: nur Signaltöne',
    );
  });
}
