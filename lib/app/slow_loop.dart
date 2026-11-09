import 'dart:async';

import 'package:flutter/foundation.dart';

/// Wie ein wiederholter AnimationController, schaltet aber höchstens [fps]-mal je Sekunde
/// weiter. Für ruhige Schleifen (Lade-Keil, Rand einer Warnung, Puls), die sonst mit voller
/// Bildrate neu zeichnen würden. [value] läuft je [period] von 0 bis 1, mit [reverse] hin und
/// zurück.
class SlowLoop extends ChangeNotifier implements ValueListenable<double> {
  SlowLoop({required this.period, this.fps = 10, this.reverse = false});

  final Duration period;
  final int fps;
  final bool reverse;

  Timer? _timer;
  int _ticks = 0;
  int? _count;
  double _value = 0;
  bool _finished = false;

  @override
  double get value => _value;

  bool get running => _timer != null;

  /// Mit `count` gestartet und alle Durchläufe gezeigt.
  bool get finished => _finished;

  Duration get _step => Duration(microseconds: 1000000 ~/ fps);

  /// Startet die Schleife; mit [count] endet sie nach so vielen Durchläufen.
  void start({int? count}) {
    if (_timer != null || _finished) return;
    _count = count;
    _ticks = 0;
    _timer = Timer.periodic(_step, (_) => _tick());
  }

  void _tick() {
    _ticks++;
    final cycles = _ticks * _step.inMicroseconds / period.inMicroseconds;
    final count = _count;
    if (count != null && cycles >= count) {
      _finished = true;
      stop();
      return;
    }
    final f = cycles % 1;
    _value = !reverse ? f : (f < 0.5 ? f * 2 : 2 - f * 2);
    notifyListeners();
  }

  /// Hält an und setzt [value] auf [rest].
  void stop({double rest = 0}) {
    _timer?.cancel();
    _timer = null;
    if (_value != rest) {
      _value = rest;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
