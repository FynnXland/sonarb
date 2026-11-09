import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'drive_controller.dart';

/// Bildschirm wach halten. Eigenes Interface, damit Widget-Tests keinen Plattformkanal brauchen.
abstract interface class ScreenWake {
  Future<void> setOn(bool on);
}

class WakelockPlusScreenWake implements ScreenWake {
  @override
  Future<void> setOn(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // Ohne Wakelock geht der Bildschirm nur früher aus; kein Grund, die Fahrt zu stören.
    }
  }
}

/// Hält den Bildschirm nur wach, wenn die Oberfläche es verlangt (Cockpit sichtbar)
/// und gerade gefahren wird. Im Stand und im Hintergrund geht er normal aus.
class DrivingScreenWake implements ScreenWake {
  DrivingScreenWake(this._inner);

  final ScreenWake _inner;
  bool _requested = false;
  bool _driving = false;
  bool? _applied;

  set driving(bool value) {
    _driving = value;
    _apply();
  }

  @override
  Future<void> setOn(bool on) {
    _requested = on;
    return _apply();
  }

  Future<void> _apply() {
    final on = _requested && _driving;
    if (on == _applied) return Future.value();
    _applied = on;
    return _inner.setOn(on);
  }
}

final platformScreenWakeProvider = Provider<ScreenWake>(
  (ref) => WakelockPlusScreenWake(),
);

final screenWakeProvider = Provider<ScreenWake>((ref) {
  final wake = DrivingScreenWake(ref.watch(platformScreenWakeProvider));
  ref.listen(
    driveControllerProvider.select((s) => s.driving),
    (_, driving) => wake.driving = driving,
    fireImmediately: true,
  );
  return wake;
});
