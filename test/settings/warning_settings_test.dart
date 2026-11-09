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
    // Die Ausroll-Piepe liegen unter „Mehr“.
    await tester.ensureVisible(find.text('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mehr'));
    await tester.pumpAndSettle();
    // Zurück nach oben, damit die Regler der Tests im Bild liegen.
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
  }

  ChoiceSliderTile slider(WidgetTester tester, String title) => tester
      .widget<ChoiceSliderTile>(find.widgetWithText(ChoiceSliderTile, title));

  testWidgets(
    'Standard: Erklärung, Ansage 600 m, Erinnerung 250 m, nur bei zu schnell',
    (tester) async {
      await pump(tester);
      expect(
        find.textContaining('Vor jeder Messstelle kommt eine Ansage mit Piep'),
        findsOneWidget,
      );
      expect(
        find.text('600 m vor der Messstelle, bei schneller Fahrt 30 s'),
        findsOneWidget,
      );
      expect(
        find.text('250 m vor der Messstelle, bei schneller Fahrt früher'),
        findsOneWidget,
      );
      final only = tester.widget<SwitchListTile>(
        find.widgetWithText(
          SwitchListTile,
          'Piepen nur, wenn ich zu schnell bin',
        ),
      );
      expect(only.value, isTrue);
      expect(find.text('Vorwarnzeit'), findsNothing);
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
    expect(find.textContaining('5 km vor der Messstelle'), findsOneWidget);
  });

  testWidgets(
    'Erinnerung aus: Abstand verschwindet, Warnlogik ohne Erinnerung',
    (tester) async {
      await pump(tester);
      await tester.ensureVisible(
        find.widgetWithText(SwitchListTile, 'Piepe zum Ausrollen'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Piepe zum Ausrollen'),
      );
      await tester.pumpAndSettle();
      expect(rig.engine.settings.reminderEnabled, isFalse);
      expect(rig.prefs.getBool('settings.reminderEnabled'), isFalse);
      expect(
        find.widgetWithText(ChoiceSliderTile, 'Piepe zum Ausrollen frühestens'),
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
        'Piepen nur, wenn ich zu schnell bin',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        SwitchListTile,
        'Piepen nur, wenn ich zu schnell bin',
      ),
    );
    await tester.pumpAndSettle();
    expect(rig.engine.settings.onlyWhenSpeeding, isFalse);
    expect(rig.prefs.getBool('settings.onlyWhenSpeeding'), isFalse);
    expect(find.text('Die Piepe kommen bei jedem Tempo'), findsOneWidget);
  });

  testWidgets('Erinnerungsabstand wird weitergegeben', (tester) async {
    await pump(tester);
    slider(tester, 'Piepe zum Ausrollen frühestens').onChanged(500);
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
