import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/cockpit_screen.dart';
import 'package:sonarb/features/cockpit/location_service.dart';
import 'package:sonarb/features/cockpit/upcoming_panel.dart';

import 'fakes.dart';

const _section = AlertPoint(
  id: 'osm:way/7',
  kind: AlertKind.sectionControl,
  position: GeoPoint(52.5, 13.41),
  source: 'osm',
);

const _construction = AlertPoint(
  id: 'hotspot:1',
  kind: AlertKind.hotspot,
  position: GeoPoint(52.5, 13.42),
  source: 'hotspot',
  reportKind: HotspotKind.construction,
);

const _mobile = AlertPoint(
  id: 'hotspot:2',
  kind: AlertKind.hotspot,
  position: GeoPoint(52.5, 13.43),
  source: 'hotspot',
  reportKind: HotspotKind.mobileCamera,
);

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  Future<void> pumpCockpit(
    WidgetTester tester, {
    Size size = const Size(360, 640),
    double textScale = 1,
    Future<void> Function()? onOpenSettings,
  }) async {
    tester.view.physicalSize = size;
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
          home: CockpitScreen(onOpenSettings: onOpenSettings ?? () async {}),
        ),
      ),
    );
    await flush(tester);
  }

  /// Die Warnfläche atmet und das Blatt hat einen Zeitbalken: pumpAndSettle würde nie enden.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  void mainWarning() {
    rig.alerts.points = [_section];
    rig.alerts.limit = 60;
    rig.engine.respond = (_, points, limit) => WarningUpdate(
      active: [
        ActiveWarning(
          point: points.first,
          distanceMeters: 1234,
          level: WarningLevel.main,
        ),
      ],
      sounds: const [],
      speedLimitKmh: limit,
      overspeed: true,
    );
  }

  void threeAhead() {
    rig.alerts.points = [camera, _construction, _mobile];
    rig.engine.respond = (_, points, limit) => WarningUpdate(
      active: [
        ActiveWarning(
          point: points[0],
          distanceMeters: 347,
          level: WarningLevel.pre,
        ),
        ActiveWarning(
          point: points[1],
          distanceMeters: 820,
          level: WarningLevel.none,
        ),
        ActiveWarning(
          point: points[2],
          distanceMeters: 1900,
          level: WarningLevel.none,
        ),
      ],
      sounds: const [],
    );
  }

  testWidgets('prüft den Standort beim Öffnen, ohne Start-Knopf', (
    tester,
  ) async {
    await pumpCockpit(tester);
    expect(rig.location.checks, 1);
    expect(find.text('Fahrt starten'), findsNothing);
    expect(find.text('Beenden'), findsNothing);
  });

  testWidgets('Kopfzeile: GPS links, Ton und Einstellungen rechts', (
    tester,
  ) async {
    await pumpCockpit(tester);
    final gps = tester.getCenter(find.text('Kein GPS')).dx;
    final sound = tester.getCenter(find.text('Ton an')).dx;
    final settings = tester.getCenter(find.byTooltip('Einstellungen')).dx;
    expect(gps, lessThan(sound));
    expect(sound, lessThan(settings));
    expect(settings, greaterThan(300));
  });

  testWidgets('im Stand: bereit, erkennt Fahrt automatisch', (tester) async {
    await pumpCockpit(tester);
    rig.location.emit(fixAt(52.5, 13.4, speedKmh: 0));
    await flush(tester);

    expect(find.text('Bereit'), findsOneWidget);
    expect(find.text('erkennt Fahrt automatisch'), findsOneWidget);
    expect(find.text('Keine Messstelle voraus'), findsOneWidget);
  });

  testWidgets('im Stand bekommt die Karte mehr Platz als bei der Fahrt', (
    tester,
  ) async {
    await pumpCockpit(tester);
    rig.location.emit(fixAt(52.5, 13.4, speedKmh: 0));
    await flush(tester);
    await settle(tester);
    final standing = tester.getSize(find.byKey(const Key('map-placeholder')));

    rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 72));
    await flush(tester);
    await settle(tester);
    final driving = tester.getSize(find.byKey(const Key('map-placeholder')));
    expect(find.text('72'), findsOneWidget);
    expect(standing.height, greaterThan(driving.height));
    expect(driving.height, greaterThan(120));
  });

  testWidgets('zeigt Tempo, Tempolimit und Warnung', (tester) async {
    mainWarning();
    await pumpCockpit(tester);
    rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 72));
    await flush(tester);
    await settle(tester);

    expect(find.text('Bereit'), findsNothing);
    expect(find.text('72'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('Abschnittskontrolle Anfang'), findsOneWidget);
    expect(find.text('Hauptwarnung'), findsOneWidget);
    expect(find.text('1,2 km'), findsOneWidget);
    expect(find.byKey(const Key('map-placeholder')), findsOneWidget);

    // 12 km/h über 60: zweite Stufe.
    final speed = tester.widget<Text>(find.text('72'));
    expect(speed.style?.color, SonarColors.speedHigh);
  });

  testWidgets('nächster Punkt groß, weitere klein darunter', (tester) async {
    threeAhead();
    await pumpCockpit(tester);
    rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 48));
    await flush(tester);
    await settle(tester);

    final lead = find.byType(UpcomingPanel);
    expect(
      find.descendant(of: lead, matching: find.text('Fester Blitzer')),
      findsOneWidget,
    );
    expect(find.text('Vorwarnung'), findsOneWidget);
    expect(find.text('350 m'), findsOneWidget);
    expect(find.text('Tagesbaustelle'), findsOneWidget);
    expect(find.text('820 m'), findsOneWidget);
    expect(find.text('Mobiler Blitzer'), findsOneWidget);
    expect(find.text('1,9 km'), findsOneWidget);
    expect(find.text('Limit\nunbekannt'), findsOneWidget);

    final big = tester
        .getSize(
          find.descendant(of: lead, matching: find.text('Fester Blitzer')),
        )
        .height;
    final small = tester.getSize(find.text('Tagesbaustelle')).height;
    expect(big, greaterThan(small));
  });

  testWidgets('Melden öffnet ein Blatt, erst die Wahl speichert', (
    tester,
  ) async {
    await pumpCockpit(tester);
    rig.location.emit(fixAt(52.5, 13.4, heading: 270));
    await flush(tester);

    await tester.tap(find.text('Melden'));
    await settle(tester);
    expect(find.text('Was melden?'), findsOneWidget);
    expect(rig.hotspots.added, isEmpty);
    for (final label in const [
      'Mobiler Blitzer',
      'Abstandsmessung',
      'Baustelle',
      'Gefahrenstelle',
      'Abbrechen',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    // Das Auto fährt weiter, während man wählt: gespeichert wird die Position vom Tippen.
    rig.location.emit(fixAt(52.5, 13.41, heading: 270));
    await flush(tester);
    await tester.tap(find.text('Baustelle'));
    await settle(tester);

    expect(rig.hotspots.added.single.$1, const GeoPoint(52.5, 13.4));
    expect(rig.hotspots.added.single.$2, 270);
    expect(rig.hotspots.kinds.single, HotspotKind.construction);
    expect(find.text('Gemeldet: Baustelle'), findsOneWidget);

    await tester.tap(find.text('Rückgängig'));
    await flush(tester);
    expect(rig.hotspots.undos, 1);
    expect(find.text('Melden'), findsOneWidget);
  });

  testWidgets('Abbrechen speichert nichts', (tester) async {
    await pumpCockpit(tester);
    rig.location.emit(fixAt(52.5, 13.4));
    await flush(tester);

    await tester.tap(find.text('Melden'));
    await settle(tester);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);

    expect(find.text('Was melden?'), findsNothing);
    expect(rig.hotspots.added, isEmpty);
  });

  testWidgets('ohne Wahl schließt sich das Blatt nach 8 s', (tester) async {
    await pumpCockpit(tester);
    rig.location.emit(fixAt(52.5, 13.4));
    await flush(tester);

    await tester.tap(find.text('Melden'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Was melden?'), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Was melden?'), findsNothing);
    expect(rig.hotspots.added, isEmpty);
  });

  testWidgets('Rückgängig verschwindet nach 5 s', (tester) async {
    await pumpCockpit(tester);
    rig.location.emit(fixAt(52.5, 13.4));
    await flush(tester);
    await tester.tap(find.text('Melden'));
    await settle(tester);
    await tester.tap(find.text('Gefahrenstelle'));
    await settle(tester);
    expect(find.text('Rückgängig'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Rückgängig'), findsNothing);
    expect(rig.hotspots.undos, 0);
  });

  testWidgets('ohne GPS-Fix ist Melden gesperrt', (tester) async {
    await pumpCockpit(tester);
    expect(find.text('Kein GPS-Fix'), findsOneWidget);
    await tester.tap(find.text('Melden'));
    await flush(tester);
    expect(find.text('Was melden?'), findsNothing);
    expect(rig.hotspots.added, isEmpty);
  });

  testWidgets('GPS aus: Grund und Weg in die Einstellungen', (tester) async {
    rig.location.access = LocationAccess.serviceOff;
    await pumpCockpit(tester);
    expect(
      find.text('GPS aus. In den Systemeinstellungen einschalten.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Standort-Einstellungen'));
    expect(rig.location.locationSettingsOpened, 1);
  });

  testWidgets('dauerhaft verweigert: Einstellungen öffnen', (tester) async {
    rig.location.access = LocationAccess.deniedForever;
    await pumpCockpit(tester);
    await tester.tap(find.text('Einstellungen öffnen'));
    expect(rig.location.appSettingsOpened, 1);
  });

  testWidgets('abgelehnt: erneut prüfen fragt noch einmal', (tester) async {
    rig.location.access = LocationAccess.denied;
    await pumpCockpit(tester);
    await tester.tap(find.text('Erneut prüfen'));
    await flush(tester);
    expect(rig.location.checks, 2);
  });

  testWidgets('abgelehnt: Rückkehr in die App fragt nicht erneut', (
    tester,
  ) async {
    rig.location.access = LocationAccess.denied;
    await pumpCockpit(tester);
    expect(rig.location.requests, 1);

    // Der Systemdialog pausiert die App; nach „Nicht erlauben“ kommt sie zurück.
    for (var i = 0; i < 3; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester);
    }
    expect(rig.location.requests, 1);
    expect(find.text('Erneut prüfen'), findsOneWidget);

    // In den Systemeinstellungen erlaubt: Rückkehr startet die Überwachung ohne Dialog.
    rig.location.access = LocationAccess.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
    expect(find.text('Erneut prüfen'), findsNothing);
  });

  testWidgets('Stummschalter zeigt Zustand und schaltet Ton', (tester) async {
    await pumpCockpit(tester);
    expect(find.text('Ton an'), findsOneWidget);
    await tester.tap(find.text('Ton an'));
    await flush(tester);
    expect(rig.audio.muted, isTrue);
    expect(find.text('Stumm'), findsOneWidget);
  });

  testWidgets('Bildschirm bleibt wach, außer in den Einstellungen', (
    tester,
  ) async {
    final back = Completer<void>();
    await pumpCockpit(tester, onOpenSettings: () => back.future);
    expect(rig.wake.calls, [true]);

    await tester.tap(find.byTooltip('Einstellungen'));
    await tester.pump();
    expect(rig.wake.calls, [true, false]);

    back.complete();
    await flush(tester);
    expect(rig.wake.calls, [true, false, true]);

    await tester.pumpWidget(const SizedBox());
    expect(rig.wake.calls.last, isFalse);
  });

  testWidgets(
    'Hochformat bei Fahrt: Karte bekommt die Hälfte, Tempo bleibt groß',
    (tester) async {
      threeAhead();
      await pumpCockpit(tester, size: const Size(411, 891));
      rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 48));
      await flush(tester);
      await settle(tester);
      final map = tester.getSize(find.byKey(const Key('map-placeholder')));
      final speed = tester.getSize(find.text('48'));
      expect(map.height, greaterThan(891 * 0.45));
      expect(
        speed.height,
        greaterThanOrEqualTo(100),
        reason: 'auf einen Blick lesbar',
      );
    },
  );

  test(
    'Tempozeile: so hoch wie nötig, auf großen Bildschirmen höchstens 132',
    () {
      expect(speedRowHeight(640), 104);
      expect(speedRowHeight(891), 132);
      expect(speedRowHeight(1400), 132);
      expect(upcomingRowsFor(640, 1.5), 1);
      expect(upcomingRowsFor(891, 1.5), upcomingExtraRows);
      expect(upcomingRowsFor(640, 1), upcomingExtraRows);
    },
  );

  for (final size in const [Size(360, 640), Size(640, 360)]) {
    for (final scale in const [1.0, 1.5]) {
      testWidgets(
        'kein Überlauf bei ${size.width.toInt()}×${size.height.toInt()}, '
        'Schrift $scale',
        (tester) async {
          threeAhead();
          await pumpCockpit(tester, size: size, textScale: scale);
          expect(tester.takeException(), isNull);

          rig.location.emit(fixAt(52.5, 13.4, speedKmh: 128, accuracy: 45));
          await flush(tester);
          await settle(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('128'), findsOneWidget);

          await tester.tap(find.text('Melden'));
          await settle(tester);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Gefahrenstelle'));
          await settle(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('Rückgängig'), findsOneWidget);
        },
      );
    }
  }
}
