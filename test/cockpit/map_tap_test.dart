import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:sonarb/app/map_layer_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_map.dart';
import 'package:sonarb/features/cockpit/heat_sheet.dart';
import 'package:sonarb/features/cockpit/map_heat_dots.dart';
import 'package:sonarb/features/cockpit/symbols/category_symbol.dart';
import 'package:sonarb/features/cockpit/point_details.dart';
import 'package:sonarb/features/cockpit/point_hits.dart';
import 'package:sonarb/features/cockpit/point_sheet.dart';

import 'fakes.dart';

final _upright = find.byWidgetPredicate(
  (w) => w is CategorySymbol && w.upright,
);
final _flat = find.byWidgetPredicate((w) => w is CategorySymbol && !w.upright);

const _camera = AlertPoint(
  id: 'osm:node/1',
  kind: AlertKind.speedCamera,
  position: GeoPoint(52.5, 13.4044),
  source: 'osm',
  maxSpeed: 50,
);

/// Fünf Meter neben dem Blitzer: auf dem Bildschirm dieselbe Stelle.
const _twin = AlertPoint(
  id: 'osm:node/2',
  kind: AlertKind.redLightCamera,
  position: GeoPoint(52.50004, 13.4044),
  source: 'osm',
);

const _size = Size(360, 320);

/// Die Karte wartet nach einem Tippen kurz, ob ein Doppeltippen folgt.
Future<void> settleTap(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  Future<void> pumpMap(
    WidgetTester tester, {
    required bool headingUp,
    bool driving = true,
  }) async {
    await rig.prefs.setBool('settings.headingUp', headingUp);
    tester.view.physicalSize = _size;
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
    final fix = fixAt(52.5, 13.4, speedKmh: driving ? 50 : 0, heading: 90);
    if (driving) {
      rig.location.emitDriving(fix);
    } else {
      rig.location.emit(fix);
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('flach: Tippen auf ein Symbol öffnet seine Angaben', (
    tester,
  ) async {
    rig.alerts.points = [_camera];
    await pumpMap(tester, headingUp: false);
    expect(_upright, findsNothing);
    await tester.tap(_flat.first);
    await settleTap(tester);
    expect(find.byType(PointDetails), findsOneWidget);
    expect(find.text('Fester Blitzer'), findsOneWidget);
  });

  testWidgets(
    'flach: der Kopf der Nadel trifft, ein Stück unter dem Ort nicht',
    (tester) async {
      rig.alerts.points = [_camera];
      await pumpMap(tester, headingUp: false);
      final rect = tester.getRect(_flat);
      // Unter dem Bodenpunkt (Spitze) liegt kein Symbol mehr.
      await tester.tapAt(rect.bottomCenter + const Offset(0, 40));
      await settleTap(tester);
      expect(find.byType(PointSheet), findsNothing);

      await tester.tapAt(rect.topCenter + const Offset(0, 6));
      await settleTap(tester);
      expect(find.byType(PointDetails), findsOneWidget);
    },
  );

  testWidgets('Wärmefleck antippen: wie oft und wann zuletzt', (tester) async {
    rig.alerts.points = [
      for (var i = 0; i < 7; i++)
        AlertPoint(
          id: 'plugin:x:$i',
          kind: AlertKind.live,
          position: GeoPoint(52.5, 13.4 + i * 0.0003),
          source: 'plugin:x',
          observedAt: DateTime(2026, 8, 12 - i),
          historical: true,
        ),
    ];
    await pumpMap(tester, headingUp: false);
    // Vergangene Beobachtungen: Fleck ja, Symbol nein.
    expect(_flat, findsNothing);
    final center = tester.getCenter(find.byType(DriveMap));
    await tester.tapAt(center + const Offset(25, 0));
    await settleTap(tester);
    expect(find.byType(HeatSheet), findsOneWidget);
    expect(find.text('Hier 7 mobile Blitzer gemeldet'), findsOneWidget);
    expect(find.text('vom 06.08.2026 bis 12.08.2026'), findsOneWidget);
  });

  const lone = AlertPoint(
    id: 'plugin:x:alt',
    kind: AlertKind.live,
    position: GeoPoint(52.5, 13.4005),
    source: 'plugin:x',
    observedAt: null,
    historical: true,
  );

  testWidgets('roter Punkt: neben dem Punkt antippen öffnet das Blatt', (
    tester,
  ) async {
    rig.alerts.points = [lone.copyWith(observedAt: DateTime(2026, 8, 12))];
    await pumpMap(tester, headingUp: false);
    final layer = find.byType(HeatDotLayer);
    expect(layer, findsOneWidget);
    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: layer,
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as HeatDotPainter;
    expect(painter.centers, hasLength(1));
    final dot = tester.getTopLeft(layer) + painter.centers.single;
    await tester.tapAt(dot + const Offset(20, 0));
    await settleTap(tester);
    expect(find.byType(HeatSheet), findsOneWidget);
    expect(find.text('Hier 1 mobiler Blitzer gemeldet'), findsOneWidget);
    expect(find.text('am 12.08.2026'), findsOneWidget);
  });

  testWidgets('Fahrtansicht geneigt: nur die Wärme, keine Punkte', (
    tester,
  ) async {
    rig.alerts.points = [lone];
    await pumpMap(tester, headingUp: true);
    expect(find.byType(HeatDotLayer), findsNothing);
  });

  testWidgets('flach: Tippen daneben öffnet nichts', (tester) async {
    rig.alerts.points = [_camera];
    await pumpMap(tester, headingUp: false);
    await tester.tapAt(const Offset(20, 300));
    await settleTap(tester);
    expect(find.byType(PointSheet), findsNothing);
  });

  testWidgets('Bündel: zwei Punkte an einer Stelle zeigen eine Liste', (
    tester,
  ) async {
    rig.alerts.points = [_camera, _twin];
    await pumpMap(tester, headingUp: false);
    await tester.tap(_flat.first);
    await settleTap(tester);
    expect(find.text('2 Punkte an dieser Stelle'), findsOneWidget);
  });

  testWidgets('geneigt: Tippen auf die Nadel öffnet ihre Angaben', (
    tester,
  ) async {
    rig.alerts.points = [_camera];
    await pumpMap(tester, headingUp: true);
    final pin = _upright;
    expect(pin, findsOneWidget);
    // Auf den Kopf der Nadel, nicht auf ihren Fußpunkt am Boden.
    await tester.tapAt(tester.getRect(pin).topCenter + const Offset(0, 8));
    await settleTap(tester);
    expect(find.byType(PointDetails), findsOneWidget);
    expect(find.text('Fester Blitzer'), findsOneWidget);
  });

  group('Trefferflächen', () {
    test('mindestens 48 × 48, auch bei kleinen Nadeln', () {
      final r = pinTapRect(_camera, const Offset(100, 200), 0.55);
      expect(r.width, greaterThanOrEqualTo(minTapSize));
      expect(r.height, greaterThanOrEqualTo(minTapSize));
      expect(r.bottom, greaterThanOrEqualTo(200 - 1));
    });

    test('ausgeschaltete Ebenen sind nicht antippbar', () {
      final camera = MapCamera(
        crs: const Epsg3857(),
        center: const LatLng(52.5, 13.4044),
        zoom: 15.5,
        rotation: 0,
        nonRotatedSize: _size,
      );
      final at = camera.latLngToScreenOffset(const LatLng(52.5, 13.4044));
      List<AlertPoint> hits(Set<MapLayer> layers) => flatHits(
        points: const [_camera],
        layers: layers,
        camera: camera,
        tap: at,
      );
      expect(hits({MapLayer.fixedCameras}), [_camera]);
      expect(hits({MapLayer.danger}), isEmpty);
    });
  });
}
