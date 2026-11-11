import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/map_layer_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/features/cockpit/layer_symbol.dart';
import 'package:sonarb/features/settings/map_layers_screen.dart';
import 'package:sonarb/features/settings/settings_screen.dart';

import '../cockpit/fakes.dart';

Widget _symbol(MapLayer layer, bool on) => LayerSymbol(layer: layer, on: on);

const _labels = [
  'Blitzer',
  'Mobile Blitzer',
  'Baustellen',
  'Gefahrenstellen',
  'Ampeln',
  'Umkreis',
];

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget home, {
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
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byWidget(home)));
  }

  testWidgets('Neigen oben, darunter sechs Ebenen, je mit Kartensymbol', (
    tester,
  ) async {
    await pump(tester, const MapLayersScreen(symbol: _symbol));
    tester.view.physicalSize = const Size(360, 1400);
    await tester.pumpAndSettle();
    final ys = [
      tester.getCenter(find.text('Karte bei Fahrt neigen')).dy,
      for (final l in _labels) tester.getCenter(find.text(l)).dy,
    ];
    expect(ys, [...ys]..sort());
    expect(find.byType(SwitchListTile), findsNWidgets(7));
    expect(find.byType(LayerSymbol), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ohne Blitzer-Funktionen fehlen die Blitzer-Ebenen', (
    tester,
  ) async {
    await rig.prefs.setBool('settings.enforcementFeatures', false);
    await pump(tester, const MapLayersScreen(symbol: _symbol));
    tester.view.physicalSize = const Size(360, 1400);
    await tester.pumpAndSettle();
    expect(find.text('Blitzer'), findsNothing);
    expect(find.text('Mobile Blitzer'), findsNothing);
    expect(find.text('Baustellen'), findsOneWidget);
    expect(find.byType(LayerSymbol), findsNWidgets(4));
    expect(
      mapLayersSummary(defaultMapLayers, enforcement: false),
      'Baustellen, Gefahrenstellen, Umkreis',
      reason: 'ohne die Blitzer-Ebenen',
    );
  });

  testWidgets('Schalter ändern nur die Karte und werden gespeichert', (
    tester,
  ) async {
    final container = await pump(
      tester,
      const MapLayersScreen(symbol: _symbol),
    );
    expect(container.read(mapLayersProvider), defaultMapLayers);

    await tester.ensureVisible(find.text('Baustellen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Baustellen'));
    await tester.pump();
    expect(
      container.read(mapLayersProvider),
      isNot(contains(MapLayer.construction)),
    );
    expect(rig.prefs.getBool('map.layer.construction'), isFalse);

    await tester.ensureVisible(find.text('Ampeln'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ampeln'));
    await tester.pump();
    expect(container.read(mapLayersProvider), contains(MapLayer.signals));
    expect(rig.prefs.getBool('map.layer.signals'), isTrue);

    // Warnlogik und Ton bleiben unberührt.
    expect(rig.engine.settings.hotspotsEnabled, isTrue);
    expect(rig.audio.muted, isFalse);
  });

  test('gespeicherte Schalter gelten beim nächsten Start', () async {
    await rig.prefs.setBool('map.layer.danger', false);
    await rig.prefs.setBool('map.layer.signals', true);
    final container = rig.container();
    addTearDown(container.dispose);
    expect(container.read(mapLayersProvider), {
      MapLayer.fixedCameras,
      MapLayer.mobile,
      MapLayer.construction,
      MapLayer.signals,
      MapLayer.loadedAreas,
    });
  });

  testWidgets('an und aus sind für Screenreader zu erkennen', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const MapLayersScreen(symbol: _symbol));
    // Titel und Schalter bilden einen zusammengeführten Knoten.
    Finder toggle(String label) => find.text(label);
    final on = tester.getSemantics(toggle('Blitzer')).getSemanticsData();
    final off = tester.getSemantics(toggle('Ampeln')).getSemanticsData();
    expect(on.flagsCollection.isToggled, ui.Tristate.isTrue);
    expect(off.flagsCollection.isToggled, ui.Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('große Schrift: kein Überlauf, Zeilen mindestens 48 hoch', (
    tester,
  ) async {
    await pump(tester, const MapLayersScreen(symbol: _symbol), textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Mobile Blitzer'), 100);
    expect(tester.takeException(), isNull);
    final row = tester.getSize(
      find.widgetWithText(SwitchListTile, 'Mobile Blitzer'),
    );
    expect(row.height, greaterThanOrEqualTo(48));
  });

  test('Kurzfassung für die Einstellungsliste', () {
    expect(mapLayersSummary(MapLayer.values.toSet()), 'Alle an');
    expect(mapLayersSummary({}), 'Keine Ebene an');
    expect(
      mapLayersSummary({MapLayer.fixedCameras, MapLayer.mobile}),
      'Blitzer, Mobile Blitzer',
    );
  });

  test('Kurzfassung auf der Übersicht', () {
    const s = AppSettings();
    expect(mapSummary(defaultMapLayers, s), '5 von 6 Ebenen · neigt bei Fahrt');
    expect(
      mapSummary(MapLayer.values.toSet(), s.copyWith(tiltWhileDriving: false)),
      'Alle Ebenen · flach',
    );
    expect(
      mapSummary(defaultMapLayers, s.copyWith(enforcementFeatures: false)),
      '3 von 4 Ebenen · neigt bei Fahrt',
    );
  });

  testWidgets('Einstellungen: Karte öffnen und Neigung abschalten', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen(mapLayerSymbol: _symbol));
    expect(find.text('5 von 6 Ebenen · neigt bei Fahrt'), findsOneWidget);
    await tester.tap(find.text('Karte'));
    await tester.pumpAndSettle();
    expect(find.byType(MapLayersScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Umkreis'), 100);
    expect(find.byType(LayerSymbol), findsWidgets);
    await tester.scrollUntilVisible(find.text('Karte bei Fahrt neigen'), -100);
    final tilt = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Karte bei Fahrt neigen'),
    );
    expect(tilt.value, isTrue, reason: 'an als Standard');
    await tester.ensureVisible(find.text('Karte bei Fahrt neigen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karte bei Fahrt neigen'));
    await tester.pumpAndSettle();
    expect(rig.prefs.getBool('settings.tiltWhileDriving'), isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('5 von 6 Ebenen · flach'), findsOneWidget);
  });
}
