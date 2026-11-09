import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/features/settings/data_scope_tiles.dart';
import 'package:sonarb/features/settings/settings_screen.dart';
import 'package:sonarb/features/settings/warning_controls.dart';

import '../cockpit/fakes.dart';

void main() {
  late TestRig rig;

  setUp(() async {
    rig = await TestRig.create();
  });

  test('Standard wie der Vertrag: 5 km Umkreis, Deutschland-Blitzer aus', () {
    const s = AppSettings();
    expect(s.dataScope, const DataScope());
    expect(s.dataScope.detailRadiusMeters, 5000);
    expect(s.dataScope.countryCameras, isFalse);
  });

  test('gespeichert, begrenzt und an die Datenquellen gegeben', () async {
    await rig.prefs.setDouble('settings.detailRadiusMeters', 900000);
    await rig.prefs.setBool('settings.countryCameras', false);
    final s = AppSettings.load(rig.prefs);
    expect(s.detailRadiusMeters, 50000);
    expect(s.countryCameras, isFalse);
    await s.applyTo(rig.services);
    expect(
      rig.alerts.dataScope,
      const DataScope(detailRadiusMeters: 50000, countryCameras: false),
    );
  });

  test('Zeile unter dem Schalter: aus, oder der Stand der OSM-Quelle', () {
    expect(
      countryCamerasText(on: false, sources: null),
      'Zeigt beim Herauszoomen alle festen Blitzer',
    );
    expect(
      countryCamerasText(on: true, sources: const []),
      'Zeigt beim Herauszoomen alle festen Blitzer\n'
      'Lädt im Hintergrund, Stand folgt',
    );
    expect(
      countryCamerasText(
        on: true,
        sources: const [
          SourceStatus(
            id: 'osm',
            name: 'OpenStreetMap',
            status: PluginStatus.loading,
            pointCount: 4210,
            message: 'Deutschland 40 %',
          ),
        ],
      ),
      'Zeigt beim Herauszoomen alle festen Blitzer\n'
      'Lädt · 4210 Punkte\nDeutschland 40 %',
    );
    expect(detailRadiusText(25000), '25 km um die Position');
    expect(detailRadiusDataHint, contains('0,4 MB pro Stunde'));
    expect(detailRadiusDataHint, contains('bis 4 MB'));
    expect(detailRadiusDataHint, contains('fast nichts'));
    expect(
      detailRadiusDataHint,
      isNot(contains('—')),
      reason: 'kein Gedankenstrich',
    );
  });

  testWidgets('Einstellungen: Umkreis und Schalter wirken auf die Quellen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: rig.overrides,
        child: MaterialApp(
          theme: buildSonarTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Blitzer für ganz Deutschland'),
      200,
    );
    expect(find.text('5 km um die Position'), findsOneWidget);
    // Ehrliche Datenmenge statt Platzhalter, für jeden Umkreis gleich.
    expect(find.text(detailRadiusDataHint), findsOneWidget);

    await tester.ensureVisible(find.text('Blitzer für ganz Deutschland'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blitzer für ganz Deutschland'));
    await tester.pumpAndSettle();
    expect(rig.alerts.dataScope.countryCameras, isTrue);
    expect(rig.prefs.getBool('settings.countryCameras'), isTrue);

    tester
        .widget<ChoiceSliderTile>(
          find.widgetWithText(ChoiceSliderTile, 'Umkreis für Daten'),
        )
        .onChanged(25000);
    await tester.pumpAndSettle();
    expect(rig.alerts.dataScope.detailRadiusMeters, 25000);
    expect(find.text('25 km um die Position'), findsOneWidget);
  });
}
