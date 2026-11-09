import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/cockpit/symbols/category_symbol.dart';

void main() {
  group('CategorySymbol', () {
    for (final size in [18.0, 22.0, 44.0]) {
      testWidgets('malt jede Art bei $size dp, flach und aufrecht', (
        tester,
      ) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              children: [
                for (final c in AlertCategory.values)
                  for (final upright in [false, true])
                    for (final speed in [null, 50, 100])
                      CategorySymbol(
                        c,
                        speed: speed,
                        size: size,
                        upright: upright,
                      ),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final c in AlertCategory.values) {
          final box = categorySymbolLayout(c, size: size).box;
          expect(
            tester.getSize(find.bySemanticsLabel(RegExp(c.label)).first),
            box,
            reason: c.name,
          );
        }
      });
    }

    test('Zahl nur bei Arten mit Tempo und plausiblem Wert', () {
      expect(shownSpeed(AlertCategory.fixedSpeed, 50), 50);
      expect(shownSpeed(AlertCategory.sectionStart, 100), 100);
      expect(shownSpeed(AlertCategory.fixedRedLight, 50), isNull);
      expect(shownSpeed(AlertCategory.fixedSpeed, null), isNull);
      expect(shownSpeed(AlertCategory.fixedSpeed, 0), isNull);
      expect(shownSpeed(AlertCategory.fixedSpeed, 1200), isNull);
    });

    testWidgets('Bezeichnung mit Tempo für Vorleser', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: CategorySymbol(AlertCategory.mobileSpeed, speed: 30),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Mobiler Blitzer, 30'), findsOneWidget);
    });

    test(
      'Nadeln stehen mit der Spitze, Zeichen flach mit der Mitte am Ort',
      () {
        final pin = categorySymbolLayout(AlertCategory.fixedSpeed);
        expect(pin.ground, Offset(pin.box.width / 2, pin.box.height));
        expect(pin.markerAlignment, const Alignment(0, -1));

        final flat = categorySymbolLayout(AlertCategory.accident);
        expect(flat.markerAlignment, Alignment.center);
        final upright = categorySymbolLayout(
          AlertCategory.accident,
          upright: true,
        );
        expect(upright.markerAlignment, const Alignment(0, -1));
        expect(upright.box.height, greaterThan(flat.box.height));

        // Rotlicht mit Tempo: Spitze unter dem Schild, nicht unter der Mitte der Fläche.
        final light = categorySymbolLayout(AlertCategory.fixedRedLightSpeed);
        expect(light.markerAlignment.x, lessThan(0));
        expect(light.markerAlignment.y, -1);
      },
    );

    testWidgets('jede Art unterscheidet sich auch in Graustufen', (
      tester,
    ) async {
      // Kartengröße, ohne Zahl: Form und Piktogramm müssen allein tragen.
      const size = 22.0;
      final images = <AlertCategory, Float64List>{};
      for (final c in AlertCategory.values) {
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: Container(
                  width: 40,
                  height: 40,
                  color: const Color(0xFF0E1114),
                  alignment: Alignment.center,
                  child: CategorySymbol(c, size: size),
                ),
              ),
            ),
          ),
        );
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        images[c] = (await tester.runAsync(() => _luminance(boundary)))!;
      }
      final cats = AlertCategory.values;
      var closest = double.infinity;
      String? pair;
      for (var i = 0; i < cats.length; i++) {
        for (var j = i + 1; j < cats.length; j++) {
          final d = _difference(images[cats[i]]!, images[cats[j]]!);
          if (d < closest) {
            closest = d;
            pair = '${cats[i].name} / ${cats[j].name}';
          }
        }
      }
      // Gleiche Grundform: nur das Piktogramm trennt, gut 2 % der Fläche. Zwei gleiche Symbole
      // lägen bei 0.
      expect(closest, greaterThan(0.015), reason: 'am ähnlichsten: $pair');
    });
  });
}

/// Helligkeit je Pixel (0..1) bei doppelter Auflösung.
Future<Float64List> _luminance(RenderRepaintBoundary boundary) async {
  final image = await boundary.toImage(pixelRatio: 2);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  final out = Float64List(data.lengthInBytes ~/ 4);
  for (var i = 0; i < out.length; i++) {
    final r = data.getUint8(i * 4) / 255;
    final g = data.getUint8(i * 4 + 1) / 255;
    final b = data.getUint8(i * 4 + 2) / 255;
    out[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
  return out;
}

/// Anteil der Pixel, deren Helligkeit sich um mehr als 0,2 unterscheidet.
double _difference(Float64List a, Float64List b) {
  var n = 0;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 0.2) n++;
  }
  return n / a.length;
}
