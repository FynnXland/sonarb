import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/cockpit_screen.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_map.dart';
import 'package:sonarb/features/cockpit/map_data_notice.dart';
import 'package:sonarb/features/cockpit/map_point_layers.dart';
import 'package:sonarb/features/cockpit/upcoming_panel.dart';

import 'fakes.dart';

void main() {
  group('mapNoticeFor', () {
    MapNotice? notice(
      CoverageState? state, {
      bool following = true,
      bool tiles = false,
      List<String> plugins = const [],
    }) => mapNoticeFor(
      coverage: state == null
          ? null
          : DataCoverage(state, loadingPlugins: plugins),
      following: following,
      tilesFailing: tiles,
    );

    test('geladen: kein Hinweis, die leere Karte stimmt', () {
      expect(notice(CoverageState.ready), isNull);
    });

    test('lädt: eigene Umgebung oder Ausschnitt', () {
      expect(
        notice(CoverageState.loading)!.title,
        'Lädt Blitzer in der Umgebung',
      );
      expect(
        notice(CoverageState.loading, following: false)!.title,
        'Lädt Blitzer im Ausschnitt',
      );
      expect(notice(CoverageState.loading)!.kind, MapNoticeKind.loading);
    });

    test('ohne Standort: sucht, in der Übersicht still', () {
      expect(notice(null)!.title, 'Sucht Standort');
      expect(notice(null, following: false), isNull);
    });

    test('Fehlschlag: offline, wenn auch die Kacheln fehlen', () {
      final server = notice(CoverageState.failed)!;
      expect(server.kind, MapNoticeKind.failed);
      expect(server.title, 'Blitzer nicht geladen');
      expect(server.detail, startsWith('Server nicht erreichbar'));
      expect(
        notice(CoverageState.failed, tiles: true)!.detail,
        startsWith('Keine Verbindung'),
      );
    });

    test('gespeicherte Daten, zu großer Ausschnitt, Kacheln offline', () {
      expect(notice(CoverageState.stale)!.kind, MapNoticeKind.stale);
      expect(
        notice(CoverageState.tooWide, following: false)!.title,
        'Zum Laden näher heranzoomen',
      );
      expect(
        notice(CoverageState.ready, tiles: true)!.title,
        'Kartenbild offline',
      );
    });

    test('Blitzer da, Plugin lädt noch: nur beim Mitführen', () {
      expect(
        notice(CoverageState.ready, plugins: ['Feed'])!.title,
        'Lädt weitere Quellen',
      );
      expect(
        notice(CoverageState.ready, plugins: ['Feed'], following: false),
        isNull,
      );
    });

    test('kein Gedankenstrich in den Texten', () {
      for (final state in [...CoverageState.values, null]) {
        for (final tiles in [false, true]) {
          final n = notice(state, tiles: tiles);
          expect('${n?.title}${n?.detail}', isNot(contains('—')));
        }
      }
    });
  });

  group('UpcomingPanel ohne Punkte', () {
    Future<void> pumpPanel(WidgetTester tester, DataCoverage? coverage) =>
        tester.pumpWidget(
          MaterialApp(
            theme: buildSonarTheme(),
            home: Scaffold(
              body: UpcomingPanel(upcoming: const [], coverage: coverage),
            ),
          ),
        );

    testWidgets('behauptet „nichts voraus“ erst, wenn geladen ist', (
      tester,
    ) async {
      await pumpPanel(tester, DataCoverage.loading);
      expect(find.text('Lädt Blitzer in der Umgebung'), findsOneWidget);
      expect(find.text('Keine Messstelle voraus'), findsNothing);
      expect(find.byType(SonarSweep), findsOneWidget);

      await pumpPanel(tester, DataCoverage.ready);
      expect(find.text('Keine Messstelle voraus'), findsOneWidget);
      expect(find.byType(SonarSweep), findsNothing);
    });

    testWidgets('Fehlschlag und gespeicherter Stand bleiben erkennbar', (
      tester,
    ) async {
      await pumpPanel(tester, const DataCoverage(CoverageState.failed));
      expect(find.text('Keine Blitzerdaten für diese Gegend'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);

      await pumpPanel(tester, const DataCoverage(CoverageState.stale));
      expect(find.text('Keine Messstelle voraus'), findsOneWidget);
      expect(
        find.text('laut gespeicherten Daten, nicht aktuell'),
        findsOneWidget,
      );
    });

    testWidgets('ohne Standort', (tester) async {
      await pumpPanel(tester, null);
      expect(find.text('Wartet auf Standort'), findsOneWidget);
    });
  });

  group('Karte', () {
    late TestRig rig;

    setUp(() async {
      rig = await TestRig.create();
    });

    Future<void> pumpMap(WidgetTester tester, {bool noMotion = false}) async {
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: rig.overrides,
          child: MaterialApp(
            theme: buildSonarTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(360, 480),
                disableAnimations: noMotion,
              ),
              child: const Scaffold(body: DriveMap()),
            ),
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
    }

    testWidgets('beim Mitfahren mit Wärme aus vergangenen Beobachtungen', (
      tester,
    ) async {
      final now = DateTime.now();
      rig.alerts.points = [
        for (var i = 0; i < 4; i++)
          AlertPoint(
            id: 'v$i',
            kind: AlertKind.live,
            position: GeoPoint(52.5, 13.4 + i * 0.0002),
            source: 'verlauf',
            category: AlertCategory.mobileSpeed,
            observedAt: now.subtract(Duration(days: 10 + i)),
            historical: true,
          ),
      ];
      await pumpMap(tester);
      expect(rig.alerts.historyCalls, contains(true));
      final heat = tester.widget<HeatLayer>(find.byType(HeatLayer));
      expect(heat.cells, isNotEmpty);
    });

    testWidgets('lädt: nur der Keil, das Schild steht im Hinweisfeld', (
      tester,
    ) async {
      rig.alerts.coverage = DataCoverage.loading;
      await pumpMap(tester);
      expect(find.text('Lädt Blitzer in der Umgebung'), findsNothing);
      expect(find.byType(MapNoticeBadge), findsNothing);
      expect(find.byType(SonarSweep), findsOneWidget);
      expect(
        tester.state<SonarSweepState>(find.byType(SonarSweep)).turning,
        isTrue,
      );

      rig.alerts.coverage = DataCoverage.ready;
      rig.alerts.statusController.add(const []);
      await tester.pump();
      await tester.pump();
      expect(find.byType(SonarSweep), findsNothing);
    });

    testWidgets('Animationen aus: der Keil steht still', (tester) async {
      rig.alerts.coverage = DataCoverage.loading;
      await pumpMap(tester, noMotion: true);
      expect(find.byType(SonarSweep), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
      expect(
        tester.state<SonarSweepState>(find.byType(SonarSweep)).turning,
        isFalse,
      );
    });

    testWidgets(
      'Fehlschlag steht im Hinweisfeld, nicht doppelt auf der Karte',
      (tester) async {
        rig.alerts.coverage = const DataCoverage(CoverageState.failed);
        await pumpMap(tester);
        expect(find.text('Blitzer nicht geladen'), findsNothing);
        expect(find.byType(SonarSweep), findsNothing);
      },
    );

    testWidgets('fragt nach, solange Daten fehlen', (tester) async {
      rig.alerts.coverage = const DataCoverage(CoverageState.failed);
      await pumpMap(tester);
      final calls = rig.alerts.pointCalls.length;
      await tester.pump(const Duration(seconds: 31));
      expect(rig.alerts.pointCalls.length, greaterThan(calls));

      rig.alerts.coverage = DataCoverage.ready;
      rig.alerts.statusController.add(const []);
      await tester.pump();
      final after = rig.alerts.pointCalls.length;
      await tester.pump(const Duration(seconds: 31));
      expect(rig.alerts.pointCalls.length, after, reason: 'geladen: Ruhe');
    });
  });

  group('Schild beim Mitführen', () {
    test('nur was das Hinweisfeld nicht sagt', () {
      expect(
        followingMapNotice(coverage: DataCoverage.loading, tilesFailing: false),
        isNull,
      );
      expect(
        followingMapNotice(
          coverage: const DataCoverage(CoverageState.failed),
          tilesFailing: false,
        ),
        isNull,
      );
      expect(
        followingMapNotice(coverage: DataCoverage.ready, tilesFailing: true),
        const MapNotice(
          MapNoticeKind.stale,
          'Kartenbild offline',
          detail: 'Blitzer sind geladen',
        ),
      );
      expect(
        followingMapNotice(
          coverage: DataCoverage.loading,
          tilesFailing: true,
        )?.detail,
        isNull,
        reason: 'keine Behauptung, Blitzer seien geladen',
      );
      expect(
        followingMapNotice(
          coverage: const DataCoverage(
            CoverageState.ready,
            loadingPlugins: ['Feed'],
          ),
          tilesFailing: false,
        )?.title,
        'Lädt weitere Quellen',
      );
    });
  });

  testWidgets('Cockpit: Hinweisfeld folgt dem Ladestand', (tester) async {
    final rig = await TestRig.create();
    rig.alerts.coverage = DataCoverage.loading;
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: rig.overrides,
        child: MaterialApp(
          theme: buildSonarTheme(),
          home: CockpitScreen(onOpenSettings: () async {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Wartet auf Standort'), findsOneWidget);

    rig.location.emit(fixAt(52.5, 13.4, speedKmh: 0));
    await tester.pump();
    await tester.pump();
    expect(find.text('Lädt Blitzer in der Umgebung'), findsOneWidget);
    expect(find.text('Keine Messstelle voraus'), findsNothing);

    rig.alerts.coverage = DataCoverage.ready;
    rig.alerts.changesController.add(null);
    await tester.pump();
    await tester.pump();
    expect(find.text('Keine Messstelle voraus'), findsOneWidget);
  });
}
