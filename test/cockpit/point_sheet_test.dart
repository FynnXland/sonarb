import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/hotspot_repository.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/cockpit_screen.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/instruments.dart';
import 'package:sonarb/features/cockpit/point_details.dart';
import 'package:sonarb/features/cockpit/point_sheet.dart';
import 'package:sonarb/features/cockpit/upcoming_panel.dart';

import 'fakes.dart';

/// Ein fester Blitzer, wie ihn mehrere Quellen kennen.
final _rich = AlertPoint(
  id: 'osm:node/42',
  kind: AlertKind.speedCamera,
  position: const GeoPoint(52.5, 13.41),
  source: 'osm',
  maxSpeed: 50,
  details: const [
    PointDetail('Erlaubt', '50 km/h'),
    PointDetail('Richtung', 'nach Osten'),
    PointDetail('Seit', 'März 2021'),
    PointDetail('Betreiber', 'Polizei Berlin'),
    PointDetail('Art', 'Starenkasten'),
    PointDetail('Hinweis', 'Misst nur die rechte Spur'),
  ],
  sources: [
    PointSource(
      id: 'osm',
      name: 'OpenStreetMap',
      attribution: '© OpenStreetMap-Mitwirkende, ODbL',
      updatedAt: DateTime(2025, 3, 12),
      url: 'https://www.openstreetmap.org/node/42',
    ),
    const PointSource(id: 'plugin:feed', name: 'Beispiel-Feed'),
  ],
);

final _sheetScroll = find
    .descendant(of: find.byType(PointSheet), matching: find.byType(Scrollable))
    .first;

const _bare = AlertPoint(
  id: 'osm:node/7',
  kind: AlertKind.redLightCamera,
  position: GeoPoint(52.5, 13.42),
  source: 'osm',
);

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  Future<void> open(
    WidgetTester tester,
    List<AlertPoint> points, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: rig.overrides,
        child: MaterialApp(
          theme: buildSonarTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showPointSheet(context, points),
                  child: const Text('öffnen'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
  }

  testWidgets('viele Angaben und mehrere Quellen', (tester) async {
    await open(tester, [_rich]);
    expect(find.text('Fester Blitzer'), findsOneWidget);
    expect(find.byType(SpeedLimitSign), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Starenkasten'),
      80,
      scrollable: _sheetScroll,
    );
    await tester.scrollUntilVisible(
      find.text('Beispiel-Feed'),
      80,
      scrollable: _sheetScroll,
    );
    expect(find.text('Quellen'), findsOneWidget);
    expect(find.text('OpenStreetMap'), findsOneWidget);
    expect(find.text('Stand 12.03.2025'), findsOneWidget);
    expect(find.text('© OpenStreetMap-Mitwirkende, ODbL'), findsOneWidget);
    expect(find.text('https://www.openstreetmap.org/node/42'), findsOneWidget);
    expect(find.byTooltip('Adresse kopieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ohne Angaben: sachlicher Hinweis, Quelle aus dem Punkt', (
    tester,
  ) async {
    await open(tester, [_bare]);
    expect(find.text('Fester Rotlichtblitzer'), findsOneWidget);
    expect(find.byType(SpeedLimitSign), findsNothing);
    expect(
      find.text('Die Quelle nennt zu diesem Punkt keine weiteren Angaben.'),
      findsOneWidget,
    );
    expect(find.text('Quelle'), findsOneWidget);
    expect(find.text('OpenStreetMap'), findsOneWidget);
  });

  testWidgets('Abstand zur eigenen Position, wenn ein Standort da ist', (
    tester,
  ) async {
    await open(tester, [_rich]);
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(PointDetails)),
    );
    await scope.read(driveControllerProvider.notifier).start();
    rig.location.emit(fixAt(52.5, 13.40, speedKmh: 0));
    await tester.pump();
    await tester.pump();
    // 0,01° Länge in Berlin sind rund 680 m.
    expect(find.text('680 m'), findsOneWidget);
    expect(find.text('Luftlinie von hier'), findsOneWidget);
  });

  testWidgets('Schließen-Knopf schließt das Blatt', (tester) async {
    await open(tester, [_bare]);
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(find.byType(PointSheet), findsNothing);
  });

  testWidgets(
    'Bündel: kurze Liste, Antippen zeigt den Punkt, Zurück zur Liste',
    (tester) async {
      await open(tester, [_rich, _bare]);
      expect(find.text('2 Punkte an dieser Stelle'), findsOneWidget);
      expect(find.text('Fester Blitzer, 50 km/h'), findsOneWidget);

      await tester.tap(find.text('Fester Rotlichtblitzer'));
      await tester.pumpAndSettle();
      expect(find.byType(PointDetails), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück zur Liste'));
      await tester.pumpAndSettle();
      expect(find.text('2 Punkte an dieser Stelle'), findsOneWidget);
    },
  );

  testWidgets('eigene Meldung: Angaben und Löschen nach Rückfrage', (
    tester,
  ) async {
    rig.hotspots.items.add(
      Hotspot(
        id: 'h1',
        position: const GeoPoint(52.5, 13.41),
        createdAt: DateTime(2026, 10, 28, 9, 5),
        headingDeg: 90,
        note: 'hinter der Brücke',
      ),
    );
    const point = AlertPoint(
      id: 'hotspot:h1',
      kind: AlertKind.hotspot,
      position: GeoPoint(52.5, 13.41),
      source: 'hotspot',
      reportKind: HotspotKind.mobileCamera,
    );
    await open(tester, [point]);
    expect(find.text('Mobiler Blitzer'), findsOneWidget);
    expect(find.text('28.10.2026, 09:05 Uhr'), findsOneWidget);
    expect(find.text('Fahrt nach Osten'), findsOneWidget);
    expect(find.text('hinter der Brücke'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Meldung löschen'),
      80,
      scrollable: _sheetScroll,
    );
    await tester.tap(find.text('Meldung löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(rig.hotspots.items, hasLength(1));

    await tester.tap(find.text('Meldung löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Löschen'));
    await tester.pumpAndSettle();
    expect(rig.hotspots.items, isEmpty);
    expect(find.byType(PointSheet), findsNothing);
  });

  testWidgets('große Schrift bei 360 × 640: kein Überlauf, alles erreichbar', (
    tester,
  ) async {
    await open(tester, [_rich], textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Beispiel-Feed'),
      120,
      scrollable: _sheetScroll,
    );
    expect(tester.takeException(), isNull);
    final sheet = tester.getRect(find.byType(PointSheet));
    expect(sheet.height, lessThanOrEqualTo(640 * pointSheetMaxHeight + 1));
  });

  testWidgets('Hinweisfeld wächst bei großer Schrift, statt abzuschneiden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final upcoming in [
      const <ActiveWarning>[],
      const [
        ActiveWarning(
          point: _bare,
          distanceMeters: 280,
          level: WarningLevel.pre,
        ),
      ],
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildSonarTheme(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: UpcomingPanel(
                  upcoming: upcoming,
                  coverage: const DataCoverage(CoverageState.failed),
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    }
  });

  test('Himmelsrichtungen', () {
    expect(compassName(0), 'Norden');
    expect(compassName(91), 'Osten');
    expect(compassName(359), 'Norden');
    expect(compassName(-90), 'Westen');
    expect(compassName(200), 'Süden');
  });

  group('im Cockpit', () {
    const camera = AlertPoint(
      id: 'osm:node/9',
      kind: AlertKind.speedCamera,
      position: GeoPoint(52.5, 13.41),
      source: 'osm',
      maxSpeed: 60,
    );

    void warn(WarningLevel level) => rig.engine.respond = (_, points, limit) =>
        WarningUpdate(
          active: [
            ActiveWarning(point: camera, distanceMeters: 500, level: level),
          ],
        );

    Future<void> pumpCockpit(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      // Wie auf dem Gerät: Statusleiste oben, Gestenleiste unten.
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      rig.alerts.points = [camera];
      await tester.pumpWidget(
        ProviderScope(
          overrides: rig.overrides,
          child: MaterialApp(
            theme: buildSonarTheme(),
            home: CockpitScreen(onOpenSettings: () async {}),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    Future<void> drive(WidgetTester tester) async {
      rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 50));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('Tippen auf das Hinweisfeld öffnet das Blatt zum Punkt', (
      tester,
    ) async {
      warn(WarningLevel.pre);
      await pumpCockpit(tester);
      await drive(tester);
      await tester.tap(find.text('Vorwarnung'));
      await settle(tester);
      expect(find.byType(PointDetails), findsOneWidget);
      // Tempo und Hinweisfeld bleiben über dem Blatt sichtbar.
      final sheetTop = tester.getTopLeft(find.byType(PointSheet)).dy;
      // Die ganze Fläche des Hinweisfelds, nicht nur ihr Text.
      final panel = tester.getBottomLeft(
        find
            .ancestor(
              of: find.text('Vorwarnung'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(panel.dy, lessThanOrEqualTo(sheetTop));
    });

    testWidgets('eine beginnende Hauptwarnung schließt das Blatt', (
      tester,
    ) async {
      warn(WarningLevel.pre);
      await pumpCockpit(tester);
      await drive(tester);
      await tester.tap(find.text('Vorwarnung'));
      await settle(tester);
      expect(find.byType(PointSheet), findsOneWidget);

      warn(WarningLevel.main);
      await drive(tester);
      await settle(tester);
      expect(find.byType(PointSheet), findsNothing);
    });

    testWidgets('bei der Fahrt keine Löschfunktion im Blatt', (tester) async {
      rig.hotspots.items.add(
        Hotspot(
          id: 'h2',
          position: const GeoPoint(52.5, 13.41),
          createdAt: DateTime(2026, 10, 28),
        ),
      );
      const report = AlertPoint(
        id: 'hotspot:h2',
        kind: AlertKind.hotspot,
        position: GeoPoint(52.5, 13.41),
        source: 'hotspot',
        reportKind: HotspotKind.mobileCamera,
      );
      rig.engine.respond = (_, points, limit) => const WarningUpdate(
        active: [
          ActiveWarning(
            point: report,
            distanceMeters: 500,
            level: WarningLevel.pre,
          ),
        ],
      );
      await pumpCockpit(tester);
      await drive(tester);
      await tester.tap(find.text('Vorwarnung'));
      await settle(tester);
      expect(find.byType(PointDetails), findsOneWidget);
      expect(find.text('Meldung löschen'), findsNothing);
    });
  });
}
