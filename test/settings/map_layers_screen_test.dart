import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('sechs Schalter untereinander, je mit Kartensymbol', (
    tester,
  ) async {
    await pump(tester, const MapLayersScreen(symbol: _symbol));
    final ys = [for (final l in _labels) tester.getCenter(find.text(l)).dy];
    expect(ys, [...ys]..sort());
    expect(find.byType(SwitchListTile), findsNWidgets(6));
    expect(find.byType(LayerSymbol), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Schalter ändern nur die Karte und werden gespeichert', (
    tester,
  ) async {
    final container = await pump(
      tester,
      const MapLayersScreen(symbol: _symbol),
    );
    expect(container.read(mapLayersProvider), defaultMapLayers);

    await tester.tap(find.text('Baustellen'));
    await tester.pump();
    expect(
      container.read(mapLayersProvider),
      isNot(contains(MapLayer.construction)),
    );
    expect(rig.prefs.getBool('map.layer.construction'), isFalse);

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

  testWidgets('Einstellungen: Kartenebenen öffnen und Neigung abschalten', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen(mapLayerSymbol: _symbol));
    await tester.scrollUntilVisible(find.text('Kartenebenen'), 100);
    await tester.tap(find.text('Kartenebenen'));
    await tester.pumpAndSettle();
    expect(find.byType(MapLayersScreen), findsOneWidget);
    expect(find.byType(LayerSymbol), findsNWidgets(6));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Karte bei Fahrt neigen'), 100);
    final tilt = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Karte bei Fahrt neigen'),
    );
    expect(tilt.value, isTrue, reason: 'an als Standard');
    await tester.tap(find.text('Karte bei Fahrt neigen'));
    await tester.pumpAndSettle();
    expect(rig.prefs.getBool('settings.tiltWhileDriving'), isFalse);
  });
}
