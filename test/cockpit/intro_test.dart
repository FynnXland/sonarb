import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/intro.dart';
import 'package:sonarb/app/sonar_mark.dart';
import 'package:sonarb/app/theme.dart';

Widget _app({required bool ready, bool disableAnimations = false}) =>
    MaterialApp(
      theme: buildSonarTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: IntroGate(
        ready: ready,
        child: const Scaffold(body: Text('Cockpit')),
      ),
    );

void main() {
  testWidgets('Logo dreht sich etwa 1,3 s, dann folgt das Cockpit', (
    tester,
  ) async {
    await tester.pumpWidget(_app(ready: true));
    expect(find.byType(SonarMark), findsOneWidget);
    expect(find.text('Cockpit'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Cockpit'), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Cockpit'), findsOneWidget);
    expect(find.byType(SonarMark), findsNothing);
  });

  testWidgets('solange die Module laden, bleibt das Logo', (tester) async {
    await tester.pumpWidget(_app(ready: false));
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(SonarMark), findsOneWidget);
    expect(find.text('Cockpit'), findsNothing);

    await tester.pumpWidget(_app(ready: true));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(SonarMotion.fade);
    expect(find.text('Cockpit'), findsOneWidget);
  });

  testWidgets('ohne Animationen direkt ins Cockpit', (tester) async {
    await tester.pumpWidget(_app(ready: true, disableAnimations: true));
    await tester.pump();
    await tester.pump(SonarMotion.fade);
    expect(find.text('Cockpit'), findsOneWidget);
  });
}
