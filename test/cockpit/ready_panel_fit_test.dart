import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/features/cockpit/cockpit_screen.dart';
import 'package:sonarb/features/cockpit/standby_panel.dart';

import 'fakes.dart';

/// Eigene Datei, weil hier Roboto geladen wird: Die Testschrift hat kleinere Zeilenhöhen und
/// zeigt den Überlauf nicht, den das Gerät zeigt.
void main() {
  late TestRig rig;

  setUpAll(_loadRoboto);
  setUp(() async {
    rig = await TestRig.create();
  });

  for (final (size, scale) in const [
    (Size(320, 568), 1.3),
    (Size(320, 568), 1.5),
    (Size(320, 568), 2.0),
    (Size(360, 640), 1.5),
  ]) {
    testWidgets(
      'Bereit passt ganz bei ${size.width.toInt()}×${size.height.toInt()}, '
      'Schrift $scale',
      (tester) async {
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
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: CockpitScreen(onOpenSettings: () async {}),
            ),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
        final panel = tester.getRect(find.byType(ReadyPanel));
        for (final text in ['Bereit', 'erkennt Fahrt automatisch']) {
          final r = tester.getRect(find.text(text));
          expect(r.top, greaterThanOrEqualTo(panel.top - 0.5), reason: text);
          expect(
            r.bottom,
            lessThanOrEqualTo(panel.bottom + 0.5),
            reason: '$text ragt unten aus dem Feld',
          );
        }
      },
    );
  }
}

/// Roboto aus dem Flutter-SDK, damit Zeilenhöhen wie auf dem Gerät sind.
Future<void> _loadRoboto() async {
  // flutter_tester liegt unter bin/cache/artifacts/engine/<Plattform>/.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final fonts = Directory('${artifacts.path}/material_fonts');
  if (!fonts.existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final f in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]) {
    final file = File('${fonts.path}/$f');
    if (file.existsSync()) {
      loader.addFont(file.readAsBytes().then((b) => b.buffer.asByteData()));
    }
  }
  await loader.load();
}
