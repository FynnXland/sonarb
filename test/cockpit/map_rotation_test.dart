import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_map.dart';
import 'package:sonarb/features/cockpit/follow_glide.dart';
import 'package:sonarb/features/cockpit/map_controls.dart';
import 'package:sonarb/features/cockpit/map_tilt.dart';

import 'fakes.dart';

void main() {
  group('Kurs für die Ausrichtung', () {
    test('hält im Stand und bei langsamer Fahrt', () {
      final h = HeadingSmoother();
      expect(h.update(90, 2), isNull);
      expect(h.update(90, 50), 90);
      expect(h.update(200, HeadingRules.holdBelowKmh - 1), 90);
      expect(h.update(null, 50), 90);
    });

    test('übergeht kleines Rauschen', () {
      final h = HeadingSmoother()..update(90, 50);
      expect(h.update(92, 50), 90);
      expect(h.update(88, 50), 90);
    });

    test('folgt Kurven geglättet über den kürzeren Winkel', () {
      final h = HeadingSmoother()..update(350, 50);
      expect(h.update(10, 50), closeTo(0, 1e-9));
      final turn = HeadingSmoother()..update(0, 50);
      var v = 0.0;
      for (var i = 0; i < 3; i++) {
        v = turn.update(90, 50)!;
      }
      expect(v, greaterThan(75), reason: 'nach drei Fixes fast herum');
      expect(v, lessThan(90));
    });

    test(
      'Gleiten dreht nach dem geglätteten Kurs, sagt mit dem gemessenen voraus',
      () {
        final g = FollowGlide();
        final t0 = DateTime(2026, 11, 3, 12);
        const a = GeoPoint(52.5, 13.4);
        final b = destinationPoint(a, 90, 25);
        g.onFix(
          position: a,
          headingDeg: 90,
          speedMps: 25,
          zoom: 16,
          now: t0,
          viewHeadingDeg: 80,
        );
        g.onFix(
          position: b,
          headingDeg: 90,
          speedMps: 25,
          zoom: 16,
          now: t0.add(const Duration(seconds: 1)),
          viewHeadingDeg: 85,
        );
        final end = g.at(t0.add(const Duration(seconds: 2)))!;
        expect(end.headingDeg, closeTo(85, 1e-9));
        expect(
          distanceMeters(end.position, destinationPoint(b, 90, 25)),
          lessThan(1),
        );
      },
    );
  });

  test('flach beim Mitführen: Position unter der Mitte', () {
    const size = Size(400, 600);
    final g = TiltGeometry(size, 0, flatPivot: followPivotFraction);
    expect(g.pivot.dy, closeTo(600 * followPivotFraction, 1e-9));
    expect(g.cameraOffset.dy, closeTo(600 * (followPivotFraction - 0.5), 1e-9));
    expect(TiltGeometry(size, 0).cameraOffset, Offset.zero);
    // Voll geneigt wie bisher.
    expect(
      TiltGeometry(size, 1, flatPivot: followPivotFraction).pivot,
      TiltGeometry(size, 1).pivot,
    );
  });

  testWidgets('Kompass: Nadel zeigt nach Norden, Tippen meldet sich', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NorthButton(rotationDeg: -90, onPressed: () => taps++),
        ),
      ),
    );
    final turn = tester.widget<Transform>(
      find.descendant(
        of: find.byType(NorthButton),
        matching: find.byType(Transform),
      ),
    );
    // Karte um −90° gedreht: Norden liegt links.
    final north = MatrixUtils.transformPoint(
      turn.transform,
      const Offset(0, -1),
    );
    expect(north.dx, lessThan(-0.9));
    expect(tester.getSize(find.byType(IconButton)).shortestSide, 48);
    await tester.tap(find.byTooltip('Norden oben'));
    expect(taps, 1);
  });

  group('Karte', () {
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
      rig.location.emit(fixAt(52.5, 13.4, speedKmh: 50, heading: 90));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      return container;
    }

    testWidgets('mit zwei Fingern drehbar', (tester) async {
      await pumpMap(tester);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final flags = map.options.interactionOptions.flags;
      expect(flags & InteractiveFlag.rotate, isNonZero);
      expect(flags & InteractiveFlag.pinchZoom, isNonZero);
    });

    testWidgets(
      'Fahrtrichtung oben: Kompass erscheint, Tippen stellt Norden oben',
      (tester) async {
        final c = await pumpMap(tester);
        expect(c.read(appSettingsProvider).headingUp, isTrue);
        expect(find.byType(NorthButton), findsOneWidget);
        await tester.tap(find.byTooltip('Norden oben'));
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(c.read(appSettingsProvider).headingUp, isFalse);
        expect(find.byType(NorthButton), findsNothing);
      },
    );

    testWidgets('Zentrieren stellt wieder Fahrtrichtung oben ein', (
      tester,
    ) async {
      final c = await pumpMap(tester);
      await c
          .read(appSettingsProvider.notifier)
          .change((s) => s.copyWith(headingUp: false));
      await tester.pump();
      await tester.drag(find.byType(FlutterMap), const Offset(80, 40));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Zentrieren'), findsOneWidget);
      await tester.tap(find.text('Zentrieren'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(c.read(appSettingsProvider).headingUp, isTrue);
      expect(find.text('Zentrieren'), findsNothing);
    });
  });
}
