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
    test('Ablauf folgt den Einstellungen', () {
      const s = AppSettings();
      expect(warningFlow(s), [
        'Vor jeder Messstelle kommt eine Ansage mit Piep, mindestens 600 m vorher, '
            'bei schneller Fahrt 30 s vorher.',
        'Bist du mehr als 3 km/h zu schnell, piept es zweimal, solange Ausrollen '
            'noch reicht, und kurz vor der Stelle schnell hintereinander.',
        'Ist das Limit unbekannt oder gilt keins (Autobahn), bleibt es bei der '
            'Ansage.',
      ]);
      expect(
        warningFlow(s.copyWith(onlyWhenSpeeding: false, reminderEnabled: false))
            .last,
        'Danach piept es bei jedem Tempo kurz vor der Stelle schnell hintereinander.',
      );
      expect(
        warningFlow(s.copyWith(overspeedToleranceKmh: 0))[1],
        startsWith('Bist du zu schnell, piept es zweimal'),
      );
    });

    test('Zeile unter „Mehr“', () {
      const s = AppSettings();
      expect(
        warningMoreSummary(s),
        'Piepe zum Ausrollen frühestens 250 m vorher',
      );
      expect(
        warningMoreSummary(s.copyWith(reminderEnabled: false)),
        'Ohne Piepe zum Ausrollen',
      );
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
      'Warnung: Ablauf und Regler direkt sichtbar, Feines unter Mehr',
      (tester) async {
        await pump(tester, const SettingsScreen());
        expect(
          find.textContaining('Vor jeder Messstelle kommt eine Ansage'),
          findsOneWidget,
        );
        expect(find.text('Ansage ab'), findsOneWidget);
        expect(
          find.text('Piepen nur, wenn ich zu schnell bin'),
          findsOneWidget,
        );
        expect(find.text('Piepe zum Ausrollen'), findsNothing);
        await tester.ensureVisible(find.text('Mehr'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mehr'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Piepe zum Ausrollen'), 200);
        expect(find.text('Piepe zum Ausrollen'), findsOneWidget);
      },
    );

    testWidgets('Ton und Sprache ohne Aufklappen', (tester) async {
      await pump(tester, const SettingsScreen());
      await tester.scrollUntilVisible(find.text('Stumm'), 200);
      expect(find.text('Lautstärke'), findsOneWidget);
      expect(find.text('Sprachansagen'), findsOneWidget);
    });

    testWidgets('Daten: Schalter direkt, darunter die Übersicht mit Cache', (
      tester,
    ) async {
      await pump(tester, const SettingsScreen());
      await tester.scrollUntilVisible(find.text('Umkreis für Daten'), 200);
      expect(find.text('Blitzer für ganz Deutschland'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('OSM-Cache'), 200);
      expect(find.text('Stand der Quellen'), findsOneWidget);
      expect(find.text('Eigene Hotspots'), findsOneWidget);
      expect(find.text('Leeren'), findsOneWidget);
    });

    testWidgets('Über: Version mit Build', (tester) async {
      await pump(tester, const SettingsScreen());
      await tester.scrollUntilVisible(find.textContaining('Sonarb ·'), 300);
      expect(find.textContaining('Version'), findsWidgets);
    });

    testWidgets('„Mehr“ bleibt offen, solange die App läuft', (tester) async {
      final container = ProviderContainer(overrides: rig.overrides);
      addTearDown(container.dispose);
      await pump(tester, const SettingsScreen(), container: container);
      await tester.ensureVisible(find.text('Mehr'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mehr'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Piepe zum Ausrollen'), 200);
      expect(find.text('Piepe zum Ausrollen'), findsOneWidget);

      // Einstellungen verlassen und wieder öffnen.
      await tester.pumpWidget(const SizedBox());
      await pump(tester, const SettingsScreen(), container: container);
      await tester.scrollUntilVisible(find.text('Piepe zum Ausrollen'), 200);
      expect(find.text('Piepe zum Ausrollen'), findsOneWidget);
    });

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
        'Einstellungen bei Schrift $scale: Lizenzen ganz erreichbar',
        (tester) async {
          await pump(tester, const SettingsScreen(), textScale: scale);
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
