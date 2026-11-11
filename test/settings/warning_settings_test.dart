import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/features/settings/settings_screen.dart';
import 'package:sonarb/features/settings/warning_controls.dart';

import '../cockpit/fakes.dart';

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: rig.overrides,
        child: MaterialApp(
          theme: buildSonarTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Von der Übersicht auf die Seite „Warnungen“.
    await tester.tap(find.text('Warnungen'));
    await tester.pumpAndSettle();
  }

  ChoiceSliderTile slider(WidgetTester tester, String title) => tester
      .widget<ChoiceSliderTile>(find.widgetWithText(ChoiceSliderTile, title));

  testWidgets(
    'Standard: Erklärung, Ansage 600 m, Erinnerung 250 m, nur bei zu schnell',
    (tester) async {
      await pump(tester);
      expect(
        find.text(
          'Mindestens 600 m vor jeder Messstelle kommt eine Ansage mit '
          'Signalton. Weitere Signaltöne nur, wenn du zu schnell bist.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('600 m vorher, bei schneller Fahrt 30 s'),
        findsOneWidget,
      );
      expect(
        find.text('250 m vorher, bei schneller Fahrt früher'),
        findsOneWidget,
      );
      final only = tester.widget<SwitchListTile>(
        find.widgetWithText(
          SwitchListTile,
          'Signalton nur, wenn ich zu schnell bin',
        ),
      );
      expect(only.value, isTrue);
      expect(find.text('Vorwarnzeit'), findsNothing);
      // Kein Aufklappen mehr: alles steht offen auf der Seite.
      expect(find.byType(ExpansionTile), findsNothing);
    },
  );

  testWidgets('Erste Ansage bis 5 km: gespeichert und an die Warnlogik', (
    tester,
  ) async {
    await pump(tester);
    final tile = slider(tester, 'Ansage ab');
    expect(tile.choices.last, 5000);
    await tester.drag(
      find.descendant(
        of: find.widgetWithText(ChoiceSliderTile, 'Ansage ab'),
        matching: find.byType(Slider),
      ),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    expect(rig.engine.settings.announceMeters, 5000);
    expect(rig.prefs.getDouble('settings.announceMeters'), 5000);
    expect(find.text('5 km vorher, bei schneller Fahrt 30 s'), findsOneWidget);
  });

  testWidgets(
    'Erinnerung aus: Abstand verschwindet, Warnlogik ohne Erinnerung',
    (tester) async {
      await pump(tester);
      await tester.ensureVisible(
        find.widgetWithText(SwitchListTile, 'Signalton zum Ausrollen'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Signalton zum Ausrollen'),
      );
      await tester.pumpAndSettle();
      expect(rig.engine.settings.reminderEnabled, isFalse);
      expect(rig.prefs.getBool('settings.reminderEnabled'), isFalse);
      expect(
        find.widgetWithText(ChoiceSliderTile, 'Ausrollen frühestens'),
        findsNothing,
      );
    },
  );

  testWidgets('Nur bei zu schnell aus: Text sagt, dass alles kommt', (
    tester,
  ) async {
    await pump(tester);
    await tester.ensureVisible(
      find.widgetWithText(
        SwitchListTile,
        'Signalton nur, wenn ich zu schnell bin',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        SwitchListTile,
        'Signalton nur, wenn ich zu schnell bin',
      ),
    );
    await tester.pumpAndSettle();
    expect(rig.engine.settings.onlyWhenSpeeding, isFalse);
    expect(rig.prefs.getBool('settings.onlyWhenSpeeding'), isFalse);
    expect(find.text('Die Signaltöne kommen bei jedem Tempo'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('danach Signaltöne bei jedem Tempo'),
      findsOneWidget,
    );
  });

  testWidgets(
    'ohne Blitzer-Funktionen: nur, was Baustellen und Gefahren betrifft',
    (tester) async {
      await rig.prefs.setBool('settings.enforcementFeatures', false);
      await pump(tester);
      expect(
        find.text(
          'Mindestens 600 m vor Baustellen und Gefahren kommt eine Ansage mit '
          'Signalton. Die Blitzer-Funktionen sind aus.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ChoiceSliderTile, 'Ansage ab'),
        findsOneWidget,
      );
      expect(find.text('Vor eigenen Meldungen warnen'), findsOneWidget);
      for (final gone in const [
        'Signalton nur, wenn ich zu schnell bin',
        'Signalton zum Ausrollen',
        'Ausrollen frühestens',
        'Blitzer-Hotspots',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    },
  );

  testWidgets('Erinnerungsabstand wird weitergegeben', (tester) async {
    await pump(tester);
    slider(tester, 'Ausrollen frühestens').onChanged(500);
    await tester.pumpAndSettle();
    expect(rig.engine.settings.reminderMeters, 500);
    expect(rig.prefs.getDouble('settings.reminderMeters'), 500);
  });

  test('gespeicherte Werte außerhalb der Grenzen werden begrenzt', () async {
    await rig.prefs.setDouble('settings.announceMeters', 90000);
    await rig.prefs.setDouble('settings.reminderMeters', 10);
    final s = AppSettings.load(rig.prefs);
    expect(s.announceMeters, 5000);
    expect(s.reminderMeters, 150);
  });

  test('Standardwerte stimmen mit der Warnlogik überein', () {
    const app = AppSettings();
    expect(app.announceMeters, 600);
    expect(app.reminderEnabled, isTrue);
    expect(app.reminderMeters, 250);
    expect(app.onlyWhenSpeeding, isTrue);
  });

  test('Abstände lesbar', () {
    expect(distanceText(250), '250 m');
    expect(distanceText(1000), '1 km');
    expect(distanceText(1500), '1,5 km');
    expect(distanceText(5000), '5 km');
  });
}
