import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/instruments.dart';
import 'package:sonarb/features/cockpit/symbols/category_symbol.dart';
import 'package:sonarb/features/settings/legend_screen.dart';

Widget _app({double textScale = 1, Size size = const Size(360, 640)}) =>
    MaterialApp(
      theme: buildSonarTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: LegendScreen(
          symbol: (c, {speed, required size}) =>
              CategorySymbol(c, speed: speed, size: size),
        ),
      ),
    );

void main() {
  testWidgets('Tempolimit im Cockpit: Zahl, kein Limit, unbekannt', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 3200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildSonarTheme(),
        home: LegendScreen(
          symbol: (c, {speed, required size}) =>
              CategorySymbol(c, speed: speed, size: size),
          limitSign: ({kmh, none = false, required size}) => kmh != null
              ? SpeedLimitSign(limitKmh: kmh, size: size)
              : NoSpeedLimitSign(size: size),
        ),
      ),
    );
    expect(find.text('Tempolimit im Cockpit'), findsOneWidget);
    expect(find.byType(SpeedLimitSign), findsOneWidget);
    expect(find.byType(NoSpeedLimitSign), findsOneWidget);
    expect(find.textContaining('Kein Tempolimit'), findsOneWidget);
    expect(find.text('Keine Angabe in den Daten'), findsOneWidget);
  });

  testWidgets('Tempo über dem Limit: fünf Stufen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 3600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(size: const Size(360, 3600)));
    expect(find.text('Tempo über dem Limit'), findsOneWidget);
    for (final kmh in ['52', '58', '65', '72']) {
      expect(find.text(kmh), findsOneWidget, reason: kmh);
    }
    expect(find.textContaining('Punkt in Flensburg'), findsOneWidget);
  });

  testWidgets('zeigt jede Art mit Bezeichnung', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(size: const Size(360, 2400)));
    for (final group in CategoryGroup.values) {
      expect(find.text(group.label), findsOneWidget);
    }
    for (final c in AlertCategory.values) {
      expect(find.text(c.label), findsOneWidget, reason: c.name);
    }
    expect(
      find.byType(CategorySymbol),
      findsNWidgets(AlertCategory.values.length),
    );
  });

  testWidgets('läuft bei 360 dp und doppelter Schrift nicht über', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(textScale: 2));
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    // Zuletzt steht die Stufe „Punkt in Flensburg“.
    expect(find.textContaining('Punkt in Flensburg'), findsOneWidget);
  });

  testWidgets(
    'Beispielzahlen in den Nadeln, Zeile liest sich als Bezeichnung',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app());
      expect(find.bySemanticsLabel('Fester Blitzer'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Fester Blitzer, 50')),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CategorySymbol &&
              w.category == AlertCategory.fixedSpeed &&
              w.speed == 50,
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );
}
