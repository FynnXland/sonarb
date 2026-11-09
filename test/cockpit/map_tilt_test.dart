import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_map.dart';
import 'package:sonarb/features/cockpit/map_markers.dart';
import 'package:sonarb/features/cockpit/symbols/category_symbol.dart';
import 'package:sonarb/features/cockpit/map_pins.dart';
import 'package:sonarb/features/cockpit/map_tilt.dart';

import 'fakes.dart';

const _viewport = Size(360, 320);

final _upright = find.byWidgetPredicate(
  (w) => w is CategorySymbol && w.upright,
);
final _flat = find.byWidgetPredicate((w) => w is CategorySymbol && !w.upright);

/// Die Neigung beginnt einen Frame nach dem Auslöser und dauert gut eine Sekunde.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 9; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('Geometrie', () {
    test('flach: Karte so groß wie der Ausschnitt, keine Verschiebung', () {
      final g = TiltGeometry(_viewport, 0);
      expect(g.isFlat, isTrue);
      expect(g.mapRect.top, closeTo(0, 0.001));
      expect(g.mapRect.height, closeTo(_viewport.height, 0.001));
      expect(g.cameraOffset, Offset.zero);
      expect(g.matrix.isIdentity(), isTrue);
    });

    test(
      'geneigt: eigene Position unten im Bild, Karte füllt den Ausschnitt',
      () {
        final g = TiltGeometry(_viewport, 1);
        expect(
          g.pivot.dy / _viewport.height,
          closeTo(tiltPivotFraction, 0.001),
        );
        expect(g.pivot.dy, greaterThan(_viewport.height * 2 / 3));
        // Die Kartenmitte liegt vor der eigenen Position, die eigene Position am Drehpunkt.
        expect(g.cameraOffset.dy, greaterThan(0));
        expect(g.project(g.pivotInMap), g.pivot);

        final w = g.mapRect.width;
        final h = g.mapRect.height;
        final topLeft = g.project(Offset.zero);
        final topRight = g.project(Offset(w, 0));
        final bottomLeft = g.project(Offset(0, h));
        final bottomRight = g.project(Offset(w, h));
        expect(topLeft.dx, lessThanOrEqualTo(0));
        expect(topRight.dx, greaterThanOrEqualTo(_viewport.width));
        expect(bottomLeft.dx, lessThanOrEqualTo(0));
        expect(bottomRight.dx, greaterThanOrEqualTo(_viewport.width));
        expect(bottomLeft.dy, greaterThanOrEqualTo(_viewport.height - 0.01));
        // Über der gerenderten Karte bleibt höchstens ein schmaler Streifen Dunst.
        expect(g.horizonY, inInclusiveRange(0, _viewport.height * 0.12));
      },
    );

    test('Matrix und Projektion stimmen überein', () {
      final g = TiltGeometry(_viewport, 0.6);
      for (final p in [
        Offset.zero,
        g.pivotInMap,
        Offset(g.mapRect.width * 0.3, g.mapRect.height * 0.2),
        Offset(g.mapRect.width, g.mapRect.height),
      ]) {
        final viaMatrix =
            MatrixUtils.transformPoint(g.matrix, p) + g.mapRect.topLeft;
        final direct = g.project(p);
        expect(viaMatrix.dx, closeTo(direct.dx, 0.01));
        expect(viaMatrix.dy, closeTo(direct.dy, 0.01));
      }
    });

    test('nach hinten wird alles kleiner', () {
      final g = TiltGeometry(_viewport, 1);
      final near = g.scaleAt(g.pivotInMap + const Offset(0, 50));
      final at = g.scaleAt(g.pivotInMap);
      final far = g.scaleAt(g.pivotInMap - const Offset(0, 400));
      expect(near, greaterThan(at));
      expect(at, closeTo(1, 0.0001));
      expect(far, lessThan(0.7));
    });

    test('vor dem ersten Layout flach statt kaputt', () {
      final g = TiltGeometry(Size.zero, 1);
      expect(g.isFlat, isTrue);
      expect(g.mapRect.width.isFinite, isTrue);
    });
  });

  test(
    'aufrechte Fläche: Bodenpunkt liegt auf der Spitze, auch verkleinert',
    () {
      const p = AlertPoint(
        id: 'x',
        kind: AlertKind.speedCamera,
        position: GeoPoint(52.5, 13.4),
        source: 'test',
      );
      const tip = Offset(120, 200);
      final l = uprightLayout(p);
      for (final scale in [1.0, 0.55]) {
        final r = uprightRect(p, tip, scale);
        expect(r.left + l.ground.dx * scale, closeTo(tip.dx, 0.001));
        expect(r.top + l.ground.dy * scale, closeTo(tip.dy, 0.001));
        expect(r.width, closeTo(l.box.width * scale, 0.001));
      }
    },
  );

  group('Karte bei Fahrt', () {
    late TestRig rig;

    // Blitzer 300 m voraus (Fahrt nach Osten), Baustelle daneben.
    const ahead = AlertPoint(
      id: 'osm:node/7',
      kind: AlertKind.speedCamera,
      position: GeoPoint(52.5, 13.4044),
      source: 'osm',
      maxSpeed: 50,
    );
    const work = AlertPoint(
      id: 'plugin:x:1',
      kind: AlertKind.construction,
      position: GeoPoint(52.5003, 13.4066),
      source: 'x',
    );

    setUp(() async {
      rig = await TestRig.create();
      rig.alerts.points = [ahead, work];
    });

    Future<ProviderContainer> pumpDriving(
      WidgetTester tester, {
      bool headingUp = true,
      bool tilt = true,
    }) async {
      await rig.prefs.setBool('settings.headingUp', headingUp);
      await rig.prefs.setBool('settings.tiltWhileDriving', tilt);
      tester.view.physicalSize = _viewport;
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
      rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 50, heading: 90));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      await settle(tester);
      return container;
    }

    testWidgets('neigt sich und zeigt Blitzer als Nadel mit Tempolimit', (
      tester,
    ) async {
      await pumpDriving(tester);
      expect(find.byType(PinOverlay), findsOneWidget);
      expect(_upright, findsNWidgets(2));
      // Die Zahl ist gemalt: Art und Tempo stehen am Symbol selbst.
      final camera = tester
          .widgetList<CategorySymbol>(_upright)
          .singleWhere((c) => c.category == AlertCategory.fixedSpeed);
      expect(shownSpeed(camera.category, camera.speed), 50);
      // Der Blitzer liegt voraus: über der eigenen Position.
      final pin = tester.getBottomLeft(_upright.first);
      expect(pin.dy, lessThan(_viewport.height * tiltPivotFraction));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Halt an der Ampel: bleibt geneigt, der Pfeil behält den Kurs',
      (tester) async {
        await pumpDriving(tester);
        expect(find.byType(PinOverlay), findsOneWidget);
        // Stehen ohne Kurs: die Fahrterkennung bleibt bei „Fahrt“ (erst nach 3 min Stand).
        rig.location.emit(fixAt(52.5, 13.4, speedKmh: 0, heading: null));
        await settle(tester);
        expect(find.byType(PinOverlay), findsOneWidget);
        final arrows = tester
            .widgetList<OwnPositionMarker>(find.byType(OwnPositionMarker))
            .map((m) => m.rotationDeg);
        expect(arrows, isNot(contains(null)), reason: 'Pfeil statt Punkt');
      },
    );

    testWidgets(
      'Verschieben macht die Karte flach, Zentrieren neigt sie wieder',
      (tester) async {
        await pumpDriving(tester);
        await tester.drag(find.byType(DriveMap), const Offset(80, 120));
        await settle(tester);
        expect(find.text('Zentrieren'), findsOneWidget);
        expect(find.byType(PinOverlay), findsNothing);
        // Flach zeigt die Karte wieder die Symbole.
        expect(_flat, findsWidgets);

        await tester.tap(find.text('Zentrieren'));
        await tester.pump();
        await settle(tester);
        expect(find.text('Zentrieren'), findsNothing);
        expect(find.byType(PinOverlay), findsOneWidget);
      },
    );

    testWidgets('ohne Fahrtrichtung oben bleibt die Karte flach', (
      tester,
    ) async {
      await pumpDriving(tester, headingUp: false);
      expect(find.byType(PinOverlay), findsNothing);
    });

    testWidgets('Schalter aus: flach auch bei Fahrt', (tester) async {
      final container = await pumpDriving(tester, tilt: false);
      expect(find.byType(PinOverlay), findsNothing);
      expect(container.read(appSettingsProvider).tiltWhileDriving, isFalse);
    });
  });
}
