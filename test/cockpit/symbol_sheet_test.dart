// Schreibt Übersichtsbilder des Zeichensatzes als PNG, zum Ansehen statt zum Vergleichen:
//   flutter test test/cockpit/symbol_sheet_test.dart --dart-define=SYMBOL_SHEET_DIR=<Ordner>
// Ohne Ordner wird der Test übersprungen.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/symbols/category_symbol.dart';
import 'package:sonarb/features/settings/legend_screen.dart';

const _dir = String.fromEnvironment('SYMBOL_SHEET_DIR');

void main() {
  setUpAll(_loadRoboto);

  testWidgets('Übersichtsbilder', skip: _dir.isEmpty, (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 4000);
    addTearDown(tester.view.reset);

    for (final (name, ground, ink) in [
      ('dunkel', const Color(0xFF0E1114), SonarColors.text),
      ('hell', const Color(0xFFF2F0EA), const Color(0xFF1A1E23)),
    ]) {
      await _shoot(
        tester,
        'legende-$name-gross.png',
        _Sheet(ground: ground, ink: ink, size: 40),
        pixelRatio: 2,
      );
      await _shoot(
        tester,
        'legende-$name-karte.png',
        _Sheet(ground: ground, ink: ink, size: 20),
        pixelRatio: 3,
      );
    }

    tester.view.physicalSize = const Size(360, 2000);
    await _shoot(
      tester,
      'legende-bildschirm-360dp.png',
      MaterialApp(
        theme: buildSonarTheme(),
        debugShowCheckedModeBanner: false,
        home: LegendScreen(
          symbol: (c, {speed, required size}) =>
              CategorySymbol(c, speed: speed, size: size),
        ),
      ),
      pixelRatio: 2,
      whole: true,
    );
  });
}

Future<void> _shoot(
  WidgetTester tester,
  String file,
  Widget child, {
  required double pixelRatio,
  bool whole = false,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    whole
        ? RepaintBoundary(key: key, child: child)
        : Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(key: key, child: child),
            ),
          ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_dir/$file').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Alle Arten nach Gruppen: mit Zahl, ohne Zahl, aufrecht, Bezeichnung.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.ground, required this.ink, required this.size});

  final Color ground;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cell = size * 1.9;
    final label = TextStyle(fontFamily: 'Roboto', fontSize: 14, color: ink);
    Widget symbolCell(Widget? child) => SizedBox(
      width: cell,
      height: cell * 1.2,
      child: Center(child: child),
    );
    return Container(
      width: cell * 3 + 280,
      color: ground,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zeichensatz bei $size dp: mit Zahl, ohne Zahl, aufrecht',
            style: label.copyWith(fontWeight: FontWeight.w700),
          ),
          for (final group in CategoryGroup.values) ...[
            const SizedBox(height: 12),
            Text(
              group.label,
              style: label.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            for (final c in AlertCategory.values)
              if (c.group == group)
                Row(
                  children: [
                    symbolCell(
                      CategorySymbol(
                        c,
                        speed: LegendScreen.sampleSpeeds[c],
                        size: size,
                      ),
                    ),
                    symbolCell(
                      c.showsSpeed ? CategorySymbol(c, size: size) : null,
                    ),
                    symbolCell(
                      CategorySymbol(
                        c,
                        speed: LegendScreen.sampleSpeeds[c],
                        size: size,
                        upright: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c.label, style: label)),
                  ],
                ),
          ],
        ],
      ),
    );
  }
}

/// Roboto aus dem Flutter-SDK, damit Zahlen und Text wie auf dem Gerät aussehen.
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
