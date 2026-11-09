import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/upcoming_panel.dart';

AlertPoint _point(String id, {int? maxSpeed}) => AlertPoint(
  id: id,
  kind: AlertKind.speedCamera,
  position: const GeoPoint(52.5, 13.4),
  source: 'osm',
  maxSpeed: maxSpeed,
);

ActiveWarning _warn(
  AlertPoint p,
  double meters, [
  WarningLevel level = WarningLevel.none,
]) => ActiveWarning(point: p, distanceMeters: meters, level: level);

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<ActiveWarning> upcoming, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildSonarTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 640),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: UpcomingPanel(upcoming: upcoming, onOpen: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Schild mit dem Tempo des Blitzers rechts neben Art und Stufe', (
    tester,
  ) async {
    await pump(tester, [
      _warn(_point('a', maxSpeed: 50), 280, WarningLevel.pre),
    ]);
    final sign = find.byType(PointLimitSign);
    expect(sign, findsOneWidget);
    expect(tester.widget<PointLimitSign>(sign).limitKmh, 50);
    expect(
      find.descendant(of: sign, matching: find.text('50')),
      findsOneWidget,
    );
    // Links der Text, dann das Schild, rechts der Abstand.
    final level = tester.getRect(find.text('Vorwarnung'));
    final at = tester.getRect(sign);
    final distance = tester.getRect(find.text('280 m'));
    expect(at.left, greaterThanOrEqualTo(level.right));
    expect(at.right, lessThanOrEqualTo(distance.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ohne bekanntes Limit kein Schild und keine Lücke', (
    tester,
  ) async {
    await pump(tester, [_warn(_point('a'), 280, WarningLevel.pre)]);
    expect(find.byType(PointLimitSign), findsNothing);
  });

  testWidgets('jeder Punkt trägt sein Schild, die unteren kleiner', (
    tester,
  ) async {
    await pump(tester, [
      _warn(_point('a', maxSpeed: 50), 280, WarningLevel.pre),
      _warn(_point('b', maxSpeed: 30), 900),
      _warn(_point('c'), 1400),
    ]);
    final signs = tester
        .widgetList<PointLimitSign>(find.byType(PointLimitSign))
        .toList();
    expect([for (final s in signs) s.limitKmh], [50, 30]);
    expect(signs.last.size, lessThan(signs.first.size));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Screenreader hört das Limit mit', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, [
      _warn(_point('a', maxSpeed: 50), 280, WarningLevel.pre),
    ]);
    expect(
      find.bySemanticsLabel(
        'Vorwarnung: Fester Blitzer in 280 m, Limit 50 km/h',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets(
    'große Schrift bei 360 × 640: kein Überlauf, Abstand bleibt lesbar',
    (tester) async {
      await pump(tester, [
        _warn(_point('a', maxSpeed: 100), 1200, WarningLevel.main),
        _warn(_point('b', maxSpeed: 30), 2400),
      ], textScale: 2);
      expect(tester.takeException(), isNull);
      // Gezeichnete Höhe des Abstands nach dem Verkleinern: nicht unter der Grundgröße der
      // kleinen Zeilen (15) bei einfacher Schrift, also deutlich lesbar.
      final drawn = tester.getSize(
        find.ancestor(
          of: find.text('1,2 km'),
          matching: find.byType(FittedBox),
        ),
      );
      expect(drawn.height, greaterThan(15));
      expect(find.byType(PointLimitSign), findsNWidgets(2));
    },
  );
}
