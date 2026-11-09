import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/model/speed_stage.dart';
import 'package:sonarb/features/cockpit/drive_state.dart';
import 'package:sonarb/features/cockpit/instruments.dart';

import 'fakes.dart';

Future<void> _show(
  WidgetTester tester,
  double kmh, {
  int? limit = 50,
  bool overspeed = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildSonarTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 120,
        child: SpeedReadout(
          drive: DriveState(
            phase: DrivePhase.running,
            fix: fixAt(52.5, 13.4, speedKmh: kmh),
            speedLimitKmh: limit,
            overspeed: overspeed,
          ),
        ),
      ),
    ),
  ),
);

Color? _numberColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

Finder _plate() => find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      (w.decoration as BoxDecoration).color == SonarColors.red,
);

void main() {
  testWidgets('Farbe je Stufe', (tester) async {
    final cases = [
      (50.0, false, SonarColors.text),
      (52.0, false, SonarColors.speedTolerance),
      (58.0, true, SonarColors.speedOver),
      (65.0, true, SonarColors.speedHigh),
      (71.0, true, SonarColors.onSignal),
    ];
    for (final (kmh, over, color) in cases) {
      await _show(tester, kmh, overspeed: over);
      expect(_numberColor(tester, '${kmh.round()}'), color, reason: '$kmh');
      expect(_plate(), kmh >= 71 ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('Stufe wird auch gesprochen', (tester) async {
    await _show(tester, 52);
    expect(
      find.bySemanticsLabel('52 Kilometer pro Stunde, knapp über dem Limit'),
      findsOneWidget,
    );
    await _show(tester, 72, overspeed: true);
    expect(
      find.bySemanticsLabel('72 Kilometer pro Stunde, mehr als 20 zu schnell'),
      findsOneWidget,
    );
  });

  testWidgets('ohne Limit normal, auch sehr schnell', (tester) async {
    await _show(tester, 210, limit: null);
    expect(_numberColor(tester, '210'), SonarColors.text);
    expect(_plate(), findsNothing);
  });

  test('Folge wird dunkler und röter, jede Schrift mindestens 4,5:1', () {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    var last = double.infinity;
    for (final stage in SpeedStage.values) {
      final c = speedStageColors(stage);
      final bg = c.fill ?? SonarColors.bg;
      expect(ratio(c.text, bg), greaterThanOrEqualTo(4.5), reason: '$stage');
      final lum = (c.fill ?? c.text).computeLuminance();
      if (stage != SpeedStage.points) {
        expect(lum, lessThan(last), reason: '$stage');
        last = lum;
      }
    }
  });
}
