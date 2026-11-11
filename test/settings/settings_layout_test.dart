import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_info.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/map_layer_settings.dart';
import 'package:sonarb/app/privacy_screen.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/hotspot_repository.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/settings/announcements_screen.dart';
import 'package:sonarb/features/settings/hotspots_screen.dart';
import 'package:sonarb/features/settings/legend_screen.dart';
import 'package:sonarb/features/settings/map_layers_screen.dart';
import 'package:sonarb/features/settings/enforcement_tile.dart';
import 'package:sonarb/features/settings/settings_pages.dart';
import 'package:sonarb/features/settings/settings_screen.dart';
import 'package:sonarb/features/settings/sources_section.dart';
import 'package:sonarb/features/settings/warning_section.dart';

import '../cockpit/fakes.dart';

SourceStatus _s(String name, PluginStatus status) =>
    SourceStatus(id: name, name: name, status: status);

/// Unten liegt die Gesten-Leiste wie auf dem Handy (48 px bei Dichte 1).
const _gestureBar = 48.0;

void main() {
  group('Texte', () {
    test('Ablauf in einem Satz, folgt den Einstellungen', () {
      const s = AppSettings();
      expect(
        warningFlow(s),
        'Mindestens 600 m vor jeder Messstelle kommt eine Ansage mit Signalton. '
        'Weitere Signaltöne nur, wenn du zu schnell bist.',
      );
      expect(
        warningFlow(s.copyWith(onlyWhenSpeeding: false, announceMeters: 1500)),
        'Mindestens 1,5 km vor jeder Messstelle kommt eine Ansage mit Signalton, '
        'danach Signaltöne bei jedem Tempo.',
      );
      expect(
        warningFlow(s.copyWith(enforcementFeatures: false)),
        'Mindestens 600 m vor Baustellen und Gefahren kommt eine Ansage mit '
        'Signalton. Die Blitzer-Funktionen sind aus.',
      );
    });

    test('Kurzfassungen der Übersicht: höchstens zwei Angaben, kurz', () {
      const s = AppSettings();
      final lines = {
        warningSummary(s): '600 m vorher · ab +3 km/h',
        warningSummary(s.copyWith(overspeedToleranceKmh: 0)):
            '600 m vorher · ab dem Limit',
        warningSummary(s.copyWith(onlyWhenSpeeding: false)):
            '600 m vorher · Signalton immer',
        warningSummary(s.copyWith(enforcementFeatures: false)):
            '600 m vorher · ohne Blitzer',
        soundSummary(s): '100 % · Sprachansagen an',
        soundSummary(s.copyWith(voiceEnabled: false, volume: 0.6)):
            '60 % · nur Signaltöne',
        soundSummary(s.copyWith(muted: true)): 'Stumm',
      };
      for (final MapEntry(key: actual, value: expected) in lines.entries) {
        expect(actual, expected);
        expect(actual.length, lessThanOrEqualTo(32), reason: actual);
        expect('·'.allMatches(actual).length, lessThanOrEqualTo(1));
      }
    });

    test('Stand einer Quelle in einer Zeile', () {
      expect(
        sourceLine(
          SourceStatus(
            id: 'osm',
            name: 'OpenStreetMap',
            status: PluginStatus.ok,
            pointCount: 1234,
            updatedAt: DateTime(2026, 10, 30, 9, 12),
          ),
        ),
        '1234 Punkte · Stand 30.10.2026, 09:12',
      );
      expect(sourceLine(_s('A', PluginStatus.loading)), 'Lädt · 0 Punkte');
    });

    test('Version mit Build', () {
      expect(versionLabel('1.0.0', '10'), 'Version 1.0.0 (10)');
      expect(versionLabel('1.0.0', ''), 'Version 1.0.0');
    });
  });

  group('Einstellungen', () {
    late TestRig rig;

    setUp(() async {
      rig = await TestRig.create();
      rig.alerts.statuses = [
        _s('OpenStreetMap', PluginStatus.ok),
        _s('Eigene Hotspots', PluginStatus.ok),
      ];
    });

    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      double textScale = 1,
      ProviderContainer? container,
    }) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: _gestureBar);
      addTearDown(tester.view.reset);
      final app = MaterialApp(
        theme: buildSonarTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      );
      await tester.pumpWidget(
        container == null
            ? ProviderScope(overrides: rig.overrides, child: app)
            : UncontrolledProviderScope(container: container, child: app),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Übersicht: Blitzer-Schalter oben, dann die Gruppen, keine Regler',
      (tester) async {
        tester.view.physicalSize = const Size(360, 2400);
        await pump(tester, const SettingsScreen());
        tester.view.physicalSize = const Size(360, 2400);
        await tester.pumpAndSettle();
        const order = [
          'Blitzer-Funktionen',
          'Unterwegs',
          'Warnungen',
          'Ton und Sprache',
          'Karte',
          'Daten und App',
          'Fahrstatistik',
          'Eigene Meldungen',
          'Daten und Quellen',
          'Google Maps (Probe)',
          'Über Sonarb',
        ];
        final ys = [for (final t in order) tester.getRect(find.text(t)).top];
        expect(ys, [...ys]..sort());
        // Details liegen eine Ebene tiefer: auf der Übersicht kein Regler, kein Aufklappen.
        expect(find.byType(Slider), findsNothing);
        expect(find.byType(ExpansionTile), findsNothing);
        expect(find.byType(SwitchListTile), findsOneWidget);
      },
    );

    testWidgets('Ton und Sprache: Lautstärke, darunter gleich Stumm', (
      tester,
    ) async {
      await pump(tester, const SoundScreen());
      final volume = tester.getRect(find.text('Lautstärke')).top;
      final mute = tester.getRect(find.text('Stumm')).top;
      final voice = tester.getRect(find.text('Sprachansagen')).top;
      expect(volume, lessThan(mute));
      expect(mute, lessThan(voice));
    });

    testWidgets(
      'Daten und Quellen: Schalter, darunter der Stand mit Kartendaten',
      (tester) async {
        await pump(tester, const DataScreen());
        await tester.scrollUntilVisible(find.text('Umkreis für Daten'), 200);
        expect(find.text('Blitzer für ganz Deutschland'), findsOneWidget);
        await tester.scrollUntilVisible(find.text(osmCacheTitle), 200);
        expect(find.text('Stand der Quellen'), findsOneWidget);
        expect(find.text('Eigene Hotspots'), findsOneWidget);
        expect(find.text('Leeren'), findsOneWidget);
      },
    );

    testWidgets('Quelle mit Fehler: Übersicht zeigt es in der Zeile', (
      tester,
    ) async {
      rig.alerts.statuses = [_s('OpenStreetMap', PluginStatus.error)];
      await pump(tester, const SettingsScreen());
      await tester.scrollUntilVisible(find.text('Daten und Quellen'), 200);
      expect(find.text('OpenStreetMap: Fehler'), findsOneWidget);
    });

    testWidgets('Über: Version mit Build', (tester) async {
      await pump(tester, const AboutScreen());
      expect(find.textContaining('Sonarb ·'), findsOneWidget);
      expect(find.textContaining('Version'), findsWidgets);
    });

    testWidgets('Blitzer-Schalter: Unterzeile folgt, Übersicht und Speicher', (
      tester,
    ) async {
      await pump(tester, const SettingsScreen());
      expect(find.text(enforcementSubtitle(on: true)), findsOneWidget);
      await tester.tap(find.text('Blitzer-Funktionen'));
      await tester.pumpAndSettle();
      expect(find.text(enforcementSubtitle(on: false)), findsOneWidget);
      expect(find.text('600 m vorher · ohne Blitzer'), findsOneWidget);
      expect(rig.prefs.getBool('settings.enforcementFeatures'), isFalse);
      expect(find.byIcon(Icons.no_photography_outlined), findsOneWidget);
    });

    testWidgets(
      'Tippziele der Übersicht mindestens 48 hoch, bei Schrift 1 und 2',
      (tester) async {
        for (final scale in [1.0, 2.0]) {
          await pump(tester, const SettingsScreen(), textScale: scale);
          for (final tile in tester.widgetList<ListTile>(
            find.byType(ListTile),
          )) {
            final size = tester.getSize(find.byWidget(tile));
            expect(size.height, greaterThanOrEqualTo(48), reason: '$scale');
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    /// Scrollt ganz nach unten und prüft, dass [last] über der Gesten-Leiste endet.
    Future<void> expectReachable(
      WidgetTester tester,
      Finder last, {
      String? reason,
    }) async {
      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(last, 300, scrollable: scroll);
      final position = tester.state<ScrollableState>(scroll).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final bottom = tester.getRect(last).bottom;
      expect(bottom, lessThanOrEqualTo(640 - _gestureBar), reason: reason);
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Einstellungen bei Schrift $scale: letzte Zeile ganz erreichbar',
        (tester) async {
          await pump(tester, const SettingsScreen(), textScale: scale);
          await expectReachable(tester, find.text('Über Sonarb'));
          await tester.pumpWidget(const SizedBox());
          await pump(tester, const AboutScreen(), textScale: scale);
          await expectReachable(tester, find.text('Lizenzen'));
        },
      );
    }

    testWidgets('Unterseiten bei großer Schrift: letzter Eintrag erreichbar', (
      tester,
    ) async {
      final pages = <(Widget, Finder)>[
        (
          const AnnouncementsScreen(),
          find.text(announcementTitle(announcementGroups.last.$2.last)),
        ),
        (const MapLayersScreen(), find.text(MapLayer.values.last.label)),
        (const WarningScreen(), find.text('Ab 3')),
        (const SoundScreen(), find.text('Sprachansagen')),
        (const DataScreen(), find.text('Leeren')),
        (const MapsNavScreen(), find.text('Navigation von Google Maps nutzen')),
        (
          LegendScreen(
            symbol: (c, {speed, required size}) =>
                SizedBox.square(dimension: size),
          ),
          // Zuletzt stehen die Farbstufen des Tempos.
          find.textContaining('Punkt in Flensburg'),
        ),
        (const PrivacyScreen(), find.byType(Text).last),
      ];
      for (final (page, last) in pages) {
        await pump(tester, page, textScale: 2);
        await expectReachable(tester, last, reason: '${page.runtimeType}');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Hotspots verwalten: letzter Hotspot über der Gesten-Leiste', (
      tester,
    ) async {
      for (var i = 0; i < 12; i++) {
        rig.hotspots.items.add(
          Hotspot(
            id: 'h$i',
            position: GeoPoint(52.5 + i * 0.001, 13.4),
            createdAt: DateTime(2026, 10, 1 + i, 9),
            note: i == 11 ? 'letzter' : null,
          ),
        );
      }
      await pump(tester, const HotspotsScreen(), textScale: 2);
      await expectReachable(tester, find.textContaining('letzter'));
    });
  });
}
