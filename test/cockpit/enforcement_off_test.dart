import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/app/welcome.dart';
import 'package:sonarb/core/contracts/alert_audio.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/core/model/enforcement.dart';
import 'package:sonarb/features/audio/cue.dart';
import 'package:sonarb/features/cockpit/cockpit_controls.dart';
import 'package:sonarb/features/cockpit/cockpit_screen.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_map.dart';
import 'package:sonarb/features/cockpit/map_point_layers.dart';
import 'package:sonarb/features/cockpit/report_sheet.dart';
import 'package:sonarb/features/cockpit/symbols/category_symbol.dart';
import 'package:sonarb/features/cockpit/upcoming_panel.dart';

import 'fakes.dart';

/// Schlüssel in SharedPreferences, wie ihn [AppSettings] schreibt.
const _key = 'settings.enforcementFeatures';

const _mobile = AlertPoint(
  id: 'hotspot:m',
  kind: AlertKind.hotspot,
  position: GeoPoint(52.5, 13.4),
  source: 'hotspot',
  reportKind: HotspotKind.mobileCamera,
);

const _distance = AlertPoint(
  id: 'hotspot:d',
  kind: AlertKind.hotspot,
  position: GeoPoint(52.4995, 13.3995),
  source: 'hotspot',
  reportKind: HotspotKind.distanceCheck,
);

const _work = AlertPoint(
  id: 'hotspot:w',
  kind: AlertKind.hotspot,
  position: GeoPoint(52.5003, 13.4003),
  source: 'hotspot',
  reportKind: HotspotKind.construction,
);

const _jam = AlertPoint(
  id: 'plugin:x:jam',
  kind: AlertKind.live,
  category: AlertCategory.trafficJamEnd,
  position: GeoPoint(52.5004, 13.4004),
  source: 'x',
);

const _weight = AlertPoint(
  id: 'plugin:x:weight',
  kind: AlertKind.live,
  category: AlertCategory.weightControl,
  position: GeoPoint(52.5005, 13.4005),
  source: 'x',
);

/// Früher hier geblitzt: Grundlage für Wärme-Ebene und Blitzer-Hotspots.
const _past = AlertPoint(
  id: 'plugin:x:past',
  kind: AlertKind.live,
  position: GeoPoint(52.5002, 13.4002),
  source: 'x',
  historical: true,
);

final _flat = find.byWidgetPredicate((w) => w is CategorySymbol && !w.upright);

void main() {
  group('Was als Blitzer-Funktion zählt', () {
    test(
      'Blitzer, Abstand, Kontrollen und Verlauf ja; Baustelle, Stau nein',
      () {
        expect(showsEnforcement(camera), isTrue);
        expect(showsEnforcement(_mobile), isTrue);
        expect(showsEnforcement(_distance), isTrue);
        expect(showsEnforcement(_weight), isTrue);
        expect(showsEnforcement(_past), isTrue);
        expect(showsEnforcement(_work), isFalse);
        expect(showsEnforcement(_jam), isFalse);
        for (final c in AlertCategory.values) {
          if (c.group == CategoryGroup.camera) {
            expect(c.isEnforcement, isTrue, reason: c.name);
          }
          if (c.group == CategoryGroup.hazard) {
            expect(c.isEnforcement, isFalse, reason: c.name);
          }
        }
      },
    );

    test('an: dieselbe Liste; aus: nur Hinweise zur Strecke', () {
      final all = [camera, _mobile, _work, _jam, _past];
      expect(identical(filterEnforcement(all, enforcement: true), all), isTrue);
      expect(filterEnforcement(all, enforcement: false), [_work, _jam]);
    });

    test(
      'aus: Blitzer-Sätze stumm, Baustelle nicht, keine Deutschland-Blitzer',
      () {
        const off = AppSettings(
          enforcementFeatures: false,
          countryCameras: true,
          heatSpotAlert: HeatSpotAlert.speech,
        );
        expect(
          off.audioSilenced,
          containsAll([
            Announcement.fixedCamera,
            Announcement.mobileCamera,
            Announcement.distanceCheck,
            Announcement.heatSpot,
          ]),
        );
        expect(off.audioSilenced, isNot(contains(Announcement.construction)));
        // Der Tempo-Zusatz bleibt: Er kann auch hinter einer Baustelle stehen.
        expect(off.audioSilenced, isNot(contains(Announcement.speedLimit)));
        expect(
          sentence(
            Announcement.construction,
            limit: 60,
            silenced: off.audioSilenced,
          ),
          'Baustelle voraus, Tempo 60',
        );
        expect(off.audioSilenced, isNot(contains(Announcement.trafficJamEnd)));
        expect(off.dataScope.countryCameras, isFalse);
        expect(
          off.copyWith(enforcementFeatures: true).dataScope.countryCameras,
          isTrue,
        );
      },
    );

    test('Einstellung wird gespeichert und geladen', () async {
      final rig = await TestRig.create();
      expect(AppSettings.load(rig.prefs).enforcementFeatures, isTrue);
      await const AppSettings(enforcementFeatures: false).save(rig.prefs);
      expect(AppSettings.load(rig.prefs).enforcementFeatures, isFalse);
    });
  });

  group('Überwachung ohne Blitzer-Funktionen', () {
    late TestRig rig;
    late ProviderContainer c;

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() async {
      rig = await TestRig.create();
      await rig.prefs.setBool(_key, false);
      c = rig.container();
      // Die Warnlogik sagt alles an, was sie bekommt: so zeigt sich, was durchkommt.
      rig.engine.respond = (fix, points, limit) => WarningUpdate(
        active: [
          for (final p in points)
            ActiveWarning(
              point: p,
              distanceMeters: 300,
              level: WarningLevel.pre,
            ),
        ],
        events: [
          for (final p in points)
            WarningEvent(
              point: p,
              stage: WarningStage.announce,
              distanceMeters: 300,
            ),
        ],
        speedLimitKmh: limit,
      );
    });

    test('keine Blitzer-Ansage, Baustelle und Stauende weiter', () async {
      rig.alerts.points = [camera, _mobile, _distance, _weight, _work, _jam];
      await c.read(driveControllerProvider.notifier).start();
      rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 58));
      await settle();

      final announced = rig.audio.announced.map((e) => e.point.id).toSet();
      expect(announced, {_work.id, _jam.id});
      expect(
        rig.engine.calls.expand((call) => call.$2).where(showsEnforcement),
        isEmpty,
      );
      expect(c.read(driveControllerProvider).upcoming.map((w) => w.point), [
        _work,
        _jam,
      ]);
      // Ohne Blitzer-Funktionen braucht die Warnlogik keine vergangenen Beobachtungen.
      expect(rig.alerts.historyCalls, everyElement(isFalse));
    });

    test('wieder an: Blitzer kommen zurück', () async {
      rig.alerts.points = [camera, _work];
      await c.read(driveControllerProvider.notifier).start();
      rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 58));
      await settle();
      await c
          .read(appSettingsProvider.notifier)
          .change((s) => s.copyWith(enforcementFeatures: true));
      rig.location.emitDriving(fixAt(52.501, 13.4, speedKmh: 58));
      await settle();
      expect(rig.audio.announced.map((e) => e.point.id), contains(camera.id));
    });
  });

  group('Karte ohne Blitzer-Funktionen', () {
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
      rig.location.emit(fixAt(52.5, 13.4, speedKmh: 50));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      return container;
    }

    bool heatPainted(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<HeatPainter>()
        .isNotEmpty;

    testWidgets('keine Blitzer-Pins und keine Wärme, die Baustelle bleibt', (
      tester,
    ) async {
      rig.alerts.points = [_mobile, _work, _past];
      final container = await pumpMap(tester);
      rig.alerts.changesController.add(null);
      await tester.pump();
      await tester.pump();
      expect(_flat, findsNWidgets(2), reason: 'an: Blitzer und Baustelle');
      expect(heatPainted(tester), isTrue, reason: 'an: Wärme aus dem Verlauf');

      await container
          .read(appSettingsProvider.notifier)
          .change((s) => s.copyWith(enforcementFeatures: false));
      await tester.pump();
      await tester.pump();
      expect(_flat, findsOneWidget);
      expect(heatPainted(tester), isFalse);
    });
  });

  group('Cockpit ohne Blitzer-Funktionen', () {
    late TestRig rig;

    setUp(() async {
      rig = await TestRig.create();
      await rig.prefs.setBool(_key, false);
    });

    Future<void> flush(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    Future<void> pumpCockpit(
      WidgetTester tester, {
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
            home: CockpitScreen(onOpenSettings: () async {}),
          ),
        ),
      );
      await flush(tester);
    }

    testWidgets('Melden-Blatt ohne mobilen Blitzer und Abstandsmessung', (
      tester,
    ) async {
      await pumpCockpit(tester);
      rig.location.emit(fixAt(52.5, 13.4, heading: 270));
      await flush(tester);
      await tester.tap(find.text('Melden'));
      // Nicht pumpAndSettle: das Blatt schließt sich nach 8 s von selbst.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Was melden?'), findsOneWidget);
      expect(find.text('Mobiler Blitzer'), findsNothing);
      expect(find.text('Abstandsmessung'), findsNothing);
      expect(find.text('Baustelle'), findsOneWidget);
      expect(find.text('Gefahrenstelle'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Abbrechen'));
      await tester.pump(const Duration(milliseconds: 400));
    });

    test('Arten im Melden-Blatt je nach Schalter', () {
      expect(reportKindsFor(enforcement: true), reportKinds);
      expect(reportKindsFor(enforcement: false), [
        HotspotKind.construction,
        HotspotKind.danger,
      ]);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Kopfzeile und Hinweisfeld sagen „Blitzer aus“ (Schrift $scale)',
        (tester) async {
          await pumpCockpit(tester, textScale: scale);
          expect(find.byType(EnforcementOffBadge), findsOneWidget);
          expect(
            find.bySemanticsLabel('Blitzer-Funktionen sind aus'),
            findsWidgets,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('Hinweisfeld bei Fahrt ohne Punkte voraus', (tester) async {
      await pumpCockpit(tester);
      for (var i = 0; i < 3; i++) {
        rig.location.emitDriving(fixAt(52.5, 13.4, speedKmh: 50));
        await flush(tester);
      }
      expect(
        find.descendant(
          of: find.byType(UpcomingPanel),
          matching: find.text(enforcementOffLine),
        ),
        findsOneWidget,
      );
      expect(find.text(enforcementOffEmpty), findsOneWidget);
      expect(find.text('Keine Messstelle voraus'), findsNothing);
      expect(find.text('Nichts voraus'), findsNothing);
    });

    test('Texte des leeren Hinweisfelds', () {
      expect(emptyUpcomingText(null).$1, 'Wartet auf Standort');
      expect(
        emptyUpcomingText(null, enforcement: false).$2,
        enforcementOffLine,
      );
    });
  });

  testWidgets('Startbildschirm bietet den Schalter an, Standard bleibt an', (
    tester,
  ) async {
    final rig = await TestRig.create();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: rig.overrides,
        child: MaterialApp(
          theme: buildSonarTheme(),
          home: const WelcomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(SwitchListTile, 'Blitzer-Funktionen');
    await tester.scrollUntilVisible(tile, 100);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(find.text(welcomeEnforcementLine), findsOneWidget);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(rig.prefs.getBool(_key), isFalse);
    expect(tester.takeException(), isNull);
  });
}
