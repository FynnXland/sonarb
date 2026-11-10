import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/app_settings.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_map.dart';

import 'fakes.dart';

void main() {
  late TestRig rig;
  late List<String> platformCalls;

  setUp(() async {
    rig = await TestRig.create();
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<ProviderContainer> pumpMap(
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
          home: const Scaffold(body: DriveMap()),
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
    return container;
  }

  Future<void> choose(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Kartenoptionen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(item));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Menü statt Umschalter: Ausrichtung wählen', (tester) async {
    final container = await pumpMap(tester);
    expect(find.text('Fahrtrichtung'), findsNothing);
    await choose(tester, 'Norden oben');
    expect(container.read(appSettingsProvider).headingUp, isFalse);
    expect(rig.prefs.getBool('settings.headingUp'), isFalse);
    await choose(tester, 'Fahrtrichtung oben');
    expect(container.read(appSettingsProvider).headingUp, isTrue);
  });

  testWidgets('Ansicht: flach oder bei Fahrt geneigt', (tester) async {
    final container = await pumpMap(tester);
    await choose(tester, 'Flach');
    expect(container.read(appSettingsProvider).tiltWhileDriving, isFalse);
    // Geneigt geht nur mit Fahrtrichtung oben: die Wahl stellt beides ein.
    await choose(tester, 'Norden oben');
    await choose(tester, 'Bei Fahrt geneigt');
    final s = container.read(appSettingsProvider);
    expect(s.tiltWhileDriving, isTrue);
    expect(s.headingUp, isTrue);
  });

  testWidgets('Aus-Knopf: Überwachung aus, App schließt', (tester) async {
    final container = await pumpMap(tester);
    expect(container.read(driveControllerProvider).running, isTrue);
    await tester.tap(find.byTooltip('Sonarb beenden'));
    await tester.pump();
    await tester.pump();
    expect(container.read(driveControllerProvider).running, isFalse);
    expect(platformCalls, contains('SystemNavigator.pop'));
  });

  testWidgets('Aus-Knopf links neben „⋯“, nicht im Menü', (tester) async {
    await pumpMap(tester);
    final quit = tester.getRect(find.byTooltip('Sonarb beenden'));
    final menu = tester.getRect(find.byTooltip('Kartenoptionen'));
    expect(quit.right, lessThanOrEqualTo(menu.left));
    expect(menu.left - quit.right, lessThan(20));
    expect((quit.center.dy - menu.center.dy).abs(), lessThan(1));
    expect(quit.width, greaterThanOrEqualTo(48));
    expect(quit.height, greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Kartenoptionen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sonarb beenden'), findsNothing);
  });

  testWidgets('Menü bei großer Schrift ohne Überlauf, Knopf 48 groß', (
    tester,
  ) async {
    await pumpMap(tester, textScale: 2);
    final button = tester.getSize(find.byTooltip('Kartenoptionen'));
    expect(button.width, greaterThanOrEqualTo(48));
    expect(button.height, greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Kartenoptionen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bei Fahrt geneigt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
