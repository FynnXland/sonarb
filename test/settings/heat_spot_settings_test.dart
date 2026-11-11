import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/alert_audio.dart';
import 'package:sonarb/features/settings/warning_section.dart';

import '../cockpit/fakes.dart';

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: rig.overrides,
        child: MaterialApp(
          theme: buildSonarTheme(),
          home: const WarningScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder option(String title) =>
      find.widgetWithText(RadioListTile<HeatSpotAlert>, title);

  Future<void> choose(WidgetTester tester, String title) async {
    await tester.scrollUntilVisible(option(title), 100);
    await tester.ensureVisible(option(title));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: option(title), matching: find.text(title)),
    );
    await tester.pumpAndSettle();
  }

  test('Standard: nur Signalton, jede gemeldete Stelle', () {
    final s = AppSettings.load(rig.prefs);
    expect(s.heatSpotAlert, HeatSpotAlert.beep);
    expect(s.heatSpotMinReports, 1);
  });

  test(
    'Stufe an Warnlogik und Karte, gespeichert, Unbekanntes auf die nächste',
    () async {
      for (final n in heatSpotReportChoices) {
        await AppSettings(heatSpotMinReports: n).applyTo(rig.services);
        expect(rig.engine.settings.heatSpotMinReports, n);
        await AppSettings(heatSpotMinReports: n).save(rig.prefs);
        expect(AppSettings.load(rig.prefs).heatSpotMinReports, n);
      }
      await rig.prefs.setInt('settings.heatSpotMinReports', 4);
      expect(AppSettings.load(rig.prefs).heatSpotMinReports, 3);
      await rig.prefs.setInt('settings.heatSpotMinReports', 99);
      expect(AppSettings.load(rig.prefs).heatSpotMinReports, 5);
    },
  );

  testWidgets('Stufe wählen: „Ab 3“ gespeichert und an die Warnlogik', (
    tester,
  ) async {
    await pump(tester);
    final three = find.widgetWithText(SegmentedButton<int>, 'Ab 3');
    await tester.scrollUntilVisible(three, 100);
    await tester.ensureVisible(three);
    await tester.pumpAndSettle();
    expect(find.text('Jede gemeldete Stelle'), findsOneWidget);
    await tester.tap(find.text('Ab 3'));
    await tester.pumpAndSettle();
    expect(rig.prefs.getInt('settings.heatSpotMinReports'), 3);
    expect(rig.engine.settings.heatSpotMinReports, 3);
    expect(find.text('Ab 3 Meldungen'), findsOneWidget);
  });

  test('drei Stufen an Warnlogik und Ton', () async {
    final cases = {
      HeatSpotAlert.off: (false, true),
      HeatSpotAlert.speech: (true, false),
      HeatSpotAlert.beep: (true, true),
    };
    for (final MapEntry(key: mode, value: (warn, silent)) in cases.entries) {
      await AppSettings(heatSpotAlert: mode).applyTo(rig.services);
      expect(rig.engine.settings.heatSpotsEnabled, warn, reason: '$mode');
      expect(
        rig.audio.silenced.contains(Announcement.heatSpot),
        silent,
        reason: '$mode',
      );
    }
  });

  test(
    'gespeichert und wieder geladen, Unbekanntes fällt auf den Standard',
    () async {
      await const AppSettings(heatSpotAlert: HeatSpotAlert.off).save(rig.prefs);
      expect(AppSettings.load(rig.prefs).heatSpotAlert, HeatSpotAlert.off);
      await rig.prefs.setString('settings.heatSpotAlert', 'gibtEsNicht');
      expect(AppSettings.load(rig.prefs).heatSpotAlert, HeatSpotAlert.beep);
    },
  );

  test(
    'der Hotspot-Satz landet nie in den einzeln abgeschalteten Sätzen',
    () async {
      await rig.prefs.setStringList('settings.silencedAnnouncements', [
        'heatSpot',
        'danger',
      ]);
      final s = AppSettings.load(rig.prefs)
          .copyWith(heatSpotAlert: HeatSpotAlert.speech);
      expect(s.silenced, {Announcement.danger});
      expect(s.audioSilenced, {Announcement.danger});
    },
  );

  testWidgets(
    'Auswahl unter „Warnungen“: wählen, speichern, an den Ton geben',
    (tester) async {
      await pump(tester);
      await choose(tester, 'Ansage');
      expect(rig.prefs.getString('settings.heatSpotAlert'), 'speech');
      expect(rig.audio.silenced, isNot(contains(Announcement.heatSpot)));
      expect(rig.engine.settings.heatSpotsEnabled, isTrue);

      await choose(tester, 'Aus');
      expect(rig.prefs.getString('settings.heatSpotAlert'), 'off');
      expect(rig.engine.settings.heatSpotsEnabled, isFalse);

      await choose(tester, 'Nur Signalton');
      expect(rig.prefs.getString('settings.heatSpotAlert'), 'beep');
      expect(rig.audio.silenced, contains(Announcement.heatSpot));
    },
  );

  testWidgets('Proben: Satz mit Signal oder nur das Signal', (tester) async {
    await pump(tester);
    Future<void> tapTip(String tip) async {
      await tester.scrollUntilVisible(find.byTooltip(tip), 100);
      await tester.ensureVisible(find.byTooltip(tip));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(tip));
      await tester.pump();
    }

    await tapTip('Ansage anhören');
    expect(rig.audio.previews, [Announcement.heatSpot]);
    await tapTip('Nur Signalton anhören');
    expect(rig.audio.played, [WarningSound.heatSpotPreview]);
  });
}
