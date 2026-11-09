import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app.dart';
import 'package:sonarb/app/legal.dart';
import 'package:sonarb/app/privacy_screen.dart';
import 'package:sonarb/app/services.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/app/welcome.dart';

import '../cockpit/fakes.dart';

void main() {
  late TestRig rig;

  setUp(() async => rig = await TestRig.create());

  Future<void> pumpStart(
    WidgetTester tester, {
    Size size = const Size(360, 640),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...rig.overrides,
          bootstrapProvider.overrideWith((ref) async => rig.services),
        ],
        child: MaterialApp(
          theme: buildSonarTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const StartGate(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(SonarMotion.fade);
  }

  testWidgets('erster Start: Erklärung vor der Standortabfrage', (
    tester,
  ) async {
    await pumpStart(tester);

    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text(stvoNotice), 100);
    expect(find.text(stvoNotice), findsOneWidget);
    expect(rig.location.checks, 0, reason: 'Abfrage erst nach dem Knopf');

    await tester.tap(find.text('Weiter zur Standortfreigabe'));
    await tester.pump();
    await tester.pump(SonarMotion.fade);

    expect(find.byType(WelcomeScreen), findsNothing);
    expect(rig.location.checks, greaterThan(0));
    expect(rig.prefs.getBool('app.welcomeSeen'), isTrue);
  });

  testWidgets('bestätigt: direkt ins Cockpit', (tester) async {
    await rig.prefs.setBool('app.welcomeSeen', true);
    await pumpStart(tester);

    expect(find.byType(WelcomeScreen), findsNothing);
    expect(rig.location.checks, greaterThan(0));
  });

  testWidgets('Datenschutzhinweise aus dem Startbildschirm', (tester) async {
    await pumpStart(tester);
    final link = find.text('Datenschutzhinweise lesen');
    await tester.scrollUntilVisible(link, 100);
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('tile.openstreetmap.org'),
      100,
    );
    expect(find.text('Kartendaten'), findsOneWidget);
  });

  testWidgets(
    'kleiner Bildschirm mit großer Schrift: Knopf bleibt erreichbar',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpStart(tester, size: const Size(320, 560));

      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.byType(FilledButton));
      expect(button.bottom, lessThanOrEqualTo(560));
      expect(button.height, greaterThanOrEqualTo(48));
    },
  );

  test('Texte ohne Gedankenstrich', () {
    final all = [
      stvoNotice,
      for (final s in privacySections) ...[s.title, s.body],
    ];
    for (final t in all) {
      expect(t.contains('—'), isFalse, reason: t);
    }
  });
}
