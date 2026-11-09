import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/map_layer_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_map.dart';
import 'package:sonarb/features/cockpit/loaded_area_layer.dart';
import 'package:sonarb/features/cockpit/map_data_notice.dart';
import 'package:sonarb/features/cockpit/map_markers.dart';

import 'fakes.dart';

void main() {
  group('gestrichelter Kreis', () {
    const view = Rect.fromLTWH(0, 0, 360, 480);

    test('kleiner Kreis ganz im Bild: Striche rundherum', () {
      final dashes = dashSegments(const Offset(180, 240), 100, view);
      // Umfang 628 px, Strich 10 und Lücke 8: rund 34 Striche.
      expect(dashes.length, inInclusiveRange(30, 36));
    });

    test('riesiger Kreis: nur die Striche im Bild, Rechenaufwand begrenzt', () {
      // 50 km bei Zoom 16: rund 34 000 px Radius, Rand gerade im Bild.
      final dashes = dashSegments(const Offset(180, 34240), 34000, view);
      expect(dashes, isNotEmpty);
      for (final (a, _) in dashes) {
        expect(view.inflate(10).contains(a), isTrue);
      }
    });

    test('Mittelpunkt im Bild, Rand weit draußen: keine Striche', () {
      expect(dashSegments(const Offset(180, 240), 34000, view), isEmpty);
    });
  });

  group('auf der Karte', () {
    late TestRig rig;

    setUp(() async {
      rig = await TestRig.create();
    });

    Future<ProviderContainer> pumpMap(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: rig.overrides,
          child: MaterialApp(
            theme: buildSonarTheme(),
            home: const Scaffold(body: DriveMap()),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DriveMap)),
      );
      await container.read(driveControllerProvider.notifier).start();
      await tester.pump();
      rig.location.emit(fixAt(52.5, 13.4, speedKmh: 0));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      return container;
    }

    final sweep = find.byKey(const ValueKey('position-sweep'));

    testWidgets('Keil bleibt beim Verschieben an der eigenen Position', (
      tester,
    ) async {
      rig.alerts.coverage = DataCoverage.loading;
      rig.alerts.viewCoverage = DataCoverage.loading;
      await pumpMap(tester);
      final own = find.byType(OwnPositionMarker);
      expect(sweep, findsOneWidget);
      // Gleiche Stelle bis auf Rundung (die Position liegt unter der Mitte).
      expect(
        (tester.getCenter(sweep) - tester.getCenter(own)).distance,
        lessThan(0.01),
      );

      await tester.drag(find.byType(DriveMap), const Offset(-90, 60));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Zentrieren'), findsOneWidget);
      final moved = tester.getCenter(own);
      expect(moved, isNot(const Offset(180, 240)), reason: 'Karte verschoben');
      expect((tester.getCenter(sweep) - moved).distance, lessThan(0.01));
    });

    testWidgets(
      'Position außerhalb des Ausschnitts: kein Keil, Schild nur für den Ausschnitt',
      (tester) async {
        rig.alerts.coverage = DataCoverage.loading;
        rig.alerts.viewCoverage = DataCoverage.loading;
        await pumpMap(tester);
        // Mitführend sagt das Hinweisfeld über der Karte, dass die Umgebung lädt, nicht die Karte.
        expect(find.text('Lädt Blitzer in der Umgebung'), findsNothing);
        for (var i = 0; i < 3; i++) {
          await tester.drag(find.byType(DriveMap), const Offset(-600, 0));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(sweep, findsNothing);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Lädt Blitzer im Ausschnitt'), findsOneWidget);

        // Ausschnitt geladen: kein Schild mehr, auch wenn die eigene Umgebung noch lädt.
        rig.alerts.viewCoverage = DataCoverage.ready;
        rig.alerts.statusController.add(const []);
        await tester.pump();
        await tester.pump();
        expect(find.byType(MapNoticeBadge), findsNothing);
      },
    );

    DataRadiusPainter radiusPainter(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<DataRadiusPainter>()
        .single;

    testWidgets('blauer Kreis um die Position mit dem eingestellten Radius', (
      tester,
    ) async {
      await rig.prefs.setDouble('settings.detailRadiusMeters', 10000);
      final container = await pumpMap(tester);
      final own = tester.getCenter(find.byType(OwnPositionMarker));
      final painter = radiusPainter(tester);
      // Kreis und Pfeil sitzen auf derselben Stelle (Pfeil auf ganze Pixel gerundet).
      expect((painter.center - own).distance, lessThan(2));
      // 10 km bei Zoom 15,5 in Berlin: 2,06 m je Bildpunkt.
      expect(painter.radius, closeTo(10000 / 2.056, 30));
      expect(painter.loading, isFalse);

      await container
          .read(mapLayersProvider.notifier)
          .toggle(MapLayer.loadedAreas);
      await tester.pump();
      expect(find.byType(DataRadiusLayer), findsNothing);
    });

    testWidgets('gestrichelt, solange die Umgebung lädt', (tester) async {
      rig.alerts.coverage = DataCoverage.loading;
      await pumpMap(tester);
      expect(radiusPainter(tester).loading, isTrue);
    });

    testWidgets('wandert mit der Position', (tester) async {
      await pumpMap(tester);
      final before = radiusPainter(tester).center;
      rig.location.emit(fixAt(52.5, 13.401, speedKmh: 0));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      final own = tester.getCenter(find.byType(OwnPositionMarker));
      expect((radiusPainter(tester).center - own).distance, lessThan(2));
      expect(own, isNot(before), reason: 'mitführend: Karte folgt');
    });
  });
}
