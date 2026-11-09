import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/position_fix.dart';
import 'package:sonarb/features/cockpit/drive_state.dart';
import 'package:sonarb/features/cockpit/location_service.dart';
import 'package:sonarb/features/cockpit/motion_detector.dart';
import 'package:sonarb/features/cockpit/screen_wake.dart';
import 'package:sonarb/features/cockpit/status_latch.dart';

import 'fakes.dart';

void main() {
  final t0 = DateTime(2026, 10, 29, 12);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  group('MotionDetector', () {
    test('ohne Fix nach dem Prüffenster: Stand, Sparmodus', () {
      final d = MotionDetector()..begin(t0);
      expect(d.mode, LocationMode.precise);
      d.onTick(at(29));
      expect(d.motion, MotionState.unknown);
      d.onTick(at(31));
      expect(d.motion, MotionState.stationary);
      expect(d.mode, LocationMode.economy);
    });

    test('Fahrt bleibt bei GPS-Ausfall, nach 5 min ohne Fix Sparmodus', () {
      final d = MotionDetector()..begin(t0);
      for (var i = 0; i < MotionLimits.confirmFixes; i++) {
        d.onFix(fixAt(52.5, 13.4, speedKmh: 60), at(i));
      }
      expect(d.motion, MotionState.driving);
      d.onTick(at(240));
      expect(d.motion, MotionState.driving);
      d.onTick(at(2 + 300));
      expect(d.motion, MotionState.stationary);
      expect(d.mode, LocationMode.economy);
    });

    test('kleiner Versatz im Sparmodus (Funkzellen-Rauschen) prüft nicht', () {
      final d = MotionDetector()..begin(t0);
      d.onTick(at(31));
      d.onFix(fixAt(52.5, 13.4, speedKmh: 0, accuracy: 150), at(40));
      // ~250 m, aber kleiner als die doppelte Ungenauigkeit
      d.onFix(fixAt(52.5, 13.4037, speedKmh: 0, accuracy: 150), at(60));
      expect(d.mode, LocationMode.economy);
    });
  });

  group('GPS-Prüfung ohne Netz-Ortung', () {
    /// Detektor im Sparmodus ab Sekunde 31 (Start-Prüfung ohne Fix abgelaufen, also schon
    /// einmal verlängert).
    MotionDetector economy() {
      final d = MotionDetector()..begin(t0);
      d.onTick(at(31));
      expect(d.mode, LocationMode.economy);
      return d;
    }

    /// Wie im Emulator beobachtet: dieselbe Position, 100 m, jedes Mal neu gestempelt.
    PositionFix stuck(DateTime time) => PositionFix(
      position: const GeoPoint(52.5, 13.4),
      speedMps: 0,
      accuracyMeters: 100,
      time: time,
    );

    test(
      'stumme Sparphase: GPS prüft, ohne Empfang seltener, höchstens 4 min',
      () {
        final d = MotionDetector()..begin(t0);
        d.onFix(fixAt(52.5, 13.4, speedKmh: 0, accuracy: 8), at(2));
        d.onTick(at(31)); // Start-Prüfung mit Empfang: Pause 2 min
        expect(d.checkAfter, GpsCheck.after);
        d.onTick(at(31 + 119));
        expect(d.mode, LocationMode.economy);
        d.onTick(at(31 + 120));
        expect(d.mode, LocationMode.precise);

        d.onTick(at(151 + 31)); // drinnen, kein Fix
        expect(d.mode, LocationMode.economy);
        expect(d.checkAfter, const Duration(minutes: 4));
        d.onTick(at(182 + 239));
        expect(d.mode, LocationMode.economy);
        d.onTick(at(182 + 240));
        expect(d.mode, LocationMode.precise);
        d.onTick(at(422 + 31));
        expect(d.checkAfter, GpsCheck.maxAfter);
      },
    );

    test('immer dieselbe alte Position zählt nicht als frisch', () {
      final d = economy();
      // Die erste Messung zählt (Pause wieder 2 min), die Wiederholungen nicht.
      for (var s = 40; s <= 160; s += 20) {
        expect(d.mode, LocationMode.economy, reason: 'Sekunde $s');
        d.onFix(stuck(at(s)), at(s));
        d.onTick(at(s));
      }
      expect(d.mode, LocationMode.precise);
    });

    test('alternde Genauigkeit an derselben Stelle zählt nicht als frisch', () {
      final d = economy();
      const aging = [5.0, 47.0, 89.0, 100.0, 100.0, 100.0, 100.0];
      for (var i = 0; i < aging.length; i++) {
        final s = 40 + i * 20;
        d.onFix(
          PositionFix(
            position: const GeoPoint(52.5, 13.4),
            speedMps: 0,
            accuracyMeters: aging[i],
            time: at(s),
          ),
          at(s),
        );
        d.onTick(at(s));
      }
      expect(d.mode, LocationMode.precise);
    });

    test('frische Sparmessungen alle 20 s: keine GPS-Prüfung', () {
      final d = economy();
      for (var s = 40; s < 600; s += 20) {
        d.onFix(
          PositionFix(
            position: GeoPoint(52.5, 13.4 + s * 1e-6),
            speedMps: 0,
            accuracyMeters: 40,
            time: t0.add(Duration(seconds: s)),
          ),
          at(s),
        );
        d.onTick(at(s));
        expect(d.mode, LocationMode.economy, reason: 'Sekunde $s');
      }
    });

    test('Funkzelle allein zählt nicht als frisch', () {
      final d = economy();
      for (var s = 40; s <= 300; s += 20) {
        d.onFix(
          PositionFix(
            position: GeoPoint(52.5, 13.4 + s * 1e-6),
            speedMps: 0,
            accuracyMeters: 1500,
            time: t0.add(Duration(seconds: s)),
          ),
          at(s),
        );
        d.onTick(at(s));
      }
      expect(d.mode, LocationMode.precise);
    });

    test(
      'ruhige genaue Fixes beenden die Prüfung früh, Pause wieder 2 min',
      () {
        final d = economy();
        d.onTick(at(31 + 240)); // Prüfung beginnt (Pause war 4 min)
        expect(d.mode, LocationMode.precise);
        for (var i = 0; i < GpsCheck.calmFixes; i++) {
          d.onFix(fixAt(52.5, 13.4, speedKmh: 1, accuracy: 6), at(275 + i));
        }
        expect(d.mode, LocationMode.economy);
        expect(d.checkAfter, GpsCheck.after);
      },
    );

    test('Prüfung findet die Fahrt', () {
      final d = economy();
      d.onTick(at(31 + 240));
      for (var i = 0; i < MotionLimits.confirmFixes; i++) {
        d.onFix(fixAt(52.5, 13.4, speedKmh: 60), at(275 + i));
      }
      expect(d.motion, MotionState.driving);
    });
  });

  group('StatusLatch', () {
    test('meldet erst nach der Haltezeit, je Wechsel einmal', () {
      final l = StatusLatch(
        raiseAfter: const Duration(seconds: 5),
        clearAfter: const Duration(seconds: 3),
      );
      expect(l.update(true, at(0)), isNull);
      expect(l.update(true, at(4)), isNull);
      expect(l.update(true, at(5)), isTrue);
      expect(l.update(true, at(6)), isNull);
      expect(l.update(false, at(7)), isNull);
      expect(l.update(true, at(8)), isNull);
      expect(l.update(false, at(9)), isNull);
      expect(l.update(false, at(12)), isFalse);
      expect(l.active, isFalse);
    });

    test('reset vergisst ohne Meldung', () {
      final l = StatusLatch(
        raiseAfter: Duration.zero,
        clearAfter: Duration.zero,
      );
      expect(l.update(true, at(0)), isTrue);
      l.reset();
      expect(l.active, isFalse);
      expect(l.update(false, at(1)), isNull);
    });
  });

  group('DrivingScreenWake', () {
    test('nur an, wenn verlangt und gefahren wird', () async {
      final inner = FakeWake();
      final wake = DrivingScreenWake(inner);
      await wake.setOn(true);
      expect(inner.calls, [false]);
      wake.driving = true;
      expect(inner.calls, [false, true]);
      await wake.setOn(false); // App im Hintergrund
      wake.driving = true;
      expect(inner.calls, [false, true, false]);
      await wake.setOn(true);
      wake.driving = false; // Fahrt zu Ende
      expect(inner.calls, [false, true, false, true, false]);
    });
  });
}
