import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/slow_loop.dart';
import 'package:sonarb/app/sonar_mark.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/features/cockpit/map_markers.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  // Daueranimationen ließen die Karte mit voller Bildrate neu zeichnen, auch im Stand.
  testWidgets('eigene Position animiert nicht', (tester) async {
    await tester.pumpWidget(_wrap(const OwnPositionMarker(rotationDeg: 30)));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.bySemanticsLabel('Eigene Position'), findsOneWidget);
  });

  testWidgets('Bereit-Ringe: kein Ticker, nach zwei Pulsen still', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const SonarPulse()));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(SonarMotion.standbyRing * 2 + const Duration(seconds: 1));
    // Kein Timer mehr offen: sonst schlüge das Ende des Tests fehl.
  });

  testWidgets('SlowLoop schaltet höchstens 10-mal je Sekunde', (tester) async {
    {
      final loop = SlowLoop(period: const Duration(seconds: 2));
      var changes = 0;
      loop.addListener(() => changes++);
      loop.start();
      await tester.pump(const Duration(seconds: 3));
      expect(changes, lessThanOrEqualTo(30));
      expect(changes, greaterThanOrEqualTo(29));
      expect(loop.running, isTrue);
      loop.stop();
      expect(loop.running, isFalse);
      expect(loop.value, 0);
      loop.dispose();
    }
  });

  testWidgets('SlowLoop mit Anzahl endet von selbst', (tester) async {
    {
      final loop = SlowLoop(period: const Duration(seconds: 1))
        ..start(count: 2);
      await tester.pump(const Duration(milliseconds: 2500));
      expect(loop.running, isFalse);
      expect(loop.finished, isTrue);
      loop.start();
      expect(loop.running, isFalse, reason: 'beendet bleibt beendet');
      loop.dispose();
    }
  });

  testWidgets('SlowLoop hin und zurück', (tester) async {
    {
      final loop = SlowLoop(period: const Duration(seconds: 1), reverse: true)
        ..start();
      await tester.pump(const Duration(milliseconds: 500));
      expect(loop.value, closeTo(1, 1e-9));
      await tester.pump(const Duration(milliseconds: 400));
      expect(loop.value, closeTo(0.2, 1e-9));
      loop.dispose();
    }
  });
}
