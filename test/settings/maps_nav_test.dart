import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/legal.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/features/maps_nav/maps_nav.dart';
import 'package:sonarb/features/settings/maps_nav_tile.dart';

import '../cockpit/fakes.dart';

final _at = DateTime(2026, 11, 9, 14, 32);

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
          home: const Scaffold(body: MapsNavTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder toggle() => find.byType(Switch);

  group('Lesen', () {
    test('Ereignis des Dienstes: Felder, leere Texte, Ende', () {
      final r = MapsReading.fromMap({
        'title': 'In 300 m',
        'text': 'Rechts abbiegen auf B72',
        'subText': '  ',
        'bigText': 'Rechts abbiegen auf B72',
        'ongoing': true,
        'category': 'navigation',
        'active': true,
        'at': _at.millisecondsSinceEpoch,
      });
      expect(r.parts, ['In 300 m', 'Rechts abbiegen auf B72']);
      expect(r.readable, isTrue);
      expect(r.ongoing, isTrue);
      expect(r.at, _at);
      final empty = MapsReading.fromMap({'ongoing': true, 'active': false});
      expect(empty.readable, isFalse);
      expect(empty.active, isFalse);
    });

    test('Zeile unter dem Schalter', () {
      expect(
        mapsReadingLine(null),
        'Noch keine Navigation von Google Maps gesehen',
      );
      expect(
        mapsReadingLine(MapsReading(title: '300 m', text: 'B72', at: _at)),
        'Zuletzt von Maps gelesen (14:32): 300 m · B72',
      );
      expect(
        mapsReadingLine(MapsReading(ongoing: true, at: _at)),
        'Mitteilung erkannt, aber ohne lesbaren Text (14:32)',
      );
    });

    test('ohne Android: kein Zugriff, nie etwas gelesen', () async {
      const none = NoMapsNavigation();
      expect(await none.granted(), isFalse);
      expect(await none.latest(), isNull);
      expect(await none.readings.isEmpty, isTrue);
    });
  });

  group('Einstellung', () {
    test('Standard aus, beim Anwenden wird der Dienst abgeschaltet', () async {
      final s = AppSettings.load(rig.prefs);
      expect(s.mapsNavigation, isFalse);
      await s.applyTo(rig.services);
      expect(rig.mapsNav.enabledCalls.last, isFalse);
    });

    test('gespeichert und geladen', () async {
      await const AppSettings(mapsNavigation: true).save(rig.prefs);
      expect(AppSettings.load(rig.prefs).mapsNavigation, isTrue);
    });

    test('Datenschutzhinweise nennen die Funktion', () {
      final section = privacySections.firstWhere(
        (s) => s.title == 'Navigationshinweise von Google Maps',
      );
      expect(section.body, contains('nicht gespeichert und nicht übertragen'));
      expect(
        section.body,
        contains('Mitteilungen anderer Apps liest Sonarb nicht'),
      );
    });
  });

  group('Schalter', () {
    testWidgets(
      '„Nicht jetzt“: bleibt aus, der Dienst wird nicht eingeschaltet',
      (tester) async {
        await pump(tester);
        expect(tester.widget<Switch>(toggle()).value, isFalse);
        await tester.tap(toggle());
        await tester.pumpAndSettle();
        expect(find.text(mapsNavDisclosure), findsOneWidget);
        await tester.tap(find.text('Nicht jetzt'));
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(toggle()).value, isFalse);
        expect(rig.mapsNav.enabledCalls, isNot(contains(true)));
        expect(rig.mapsNav.settingsOpened, 0);
      },
    );

    testWidgets(
      '„Erlauben“ ohne Freigabe: Systemseite, zurück ohne Freigabe springt aus',
      (tester) async {
        await pump(tester);
        await tester.tap(toggle());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Erlauben'));
        await tester.pumpAndSettle();
        expect(rig.mapsNav.enabledCalls.last, isTrue);
        expect(rig.mapsNav.settingsOpened, 1);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(toggle()).value, isFalse);
        expect(rig.mapsNav.enabledCalls.last, isFalse);
        expect(rig.prefs.getBool('settings.mapsNavigation'), isFalse);
        expect(find.text('Zugriff nicht erteilt'), findsOneWidget);
      },
    );

    testWidgets('mit Freigabe: zeigt, was zuletzt von Maps kam', (
      tester,
    ) async {
      rig.mapsNav.access = true;
      await pump(tester);
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erlauben'));
      await tester.pumpAndSettle();
      expect(rig.mapsNav.settingsOpened, 0, reason: 'Freigabe war schon da');
      expect(
        find.text('Noch keine Navigation von Google Maps gesehen'),
        findsOneWidget,
      );

      rig.mapsNav.post(
        MapsReading(title: 'In 300 m', text: 'Rechts auf B72', at: _at),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Zuletzt von Maps gelesen (14:32): In 300 m · Rechts auf B72',
        ),
        findsOneWidget,
      );

      rig.mapsNav.post(MapsReading(ongoing: true, at: _at));
      await tester.pumpAndSettle();
      expect(
        find.text('Mitteilung erkannt, aber ohne lesbaren Text (14:32)'),
        findsOneWidget,
      );
    });

    testWidgets('an, aber Zugriff entzogen: Hinweis und Knopf zur Freigabe', (
      tester,
    ) async {
      await rig.prefs.setBool('settings.mapsNavigation', true);
      await pump(tester);
      expect(find.text('Zugriff in Android nicht erteilt'), findsOneWidget);
      await tester.tap(find.text('Zugriff in Android erteilen'));
      await tester.pumpAndSettle();
      expect(rig.mapsNav.settingsOpened, 1);
    });
  });
}
