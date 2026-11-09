import 'dart:math' as math;

import '../../core/model/position_fix.dart';

/// Leichte Glättung des Tempos. Das GPS-Tempo (Doppler) ist schon gut; der Filter nimmt nur
/// das Zittern um ±1 km/h und verwirft physikalisch unmögliche Sprünge.
abstract final class SpeedFilterLimits {
  /// Zeitkonstante der Glättung. Bei 1 s Takt zeigt die Anzeige nach einer Messung etwa
  /// drei Viertel eines Tempowechsels, nach zwei Messungen über 90 %.
  static const tauSeconds = 0.7;

  /// Mehr Beschleunigung oder Bremsung schafft kein Auto (Vollbremsung um 10 m/s²).
  /// Größere Sprünge stammen aus Positionssprüngen ohne gemeldetes Tempo.
  static const maxAccelMps2 = 12.0;

  /// Längere Pause zwischen zwei Messungen: neu anfangen statt zu glätten.
  static const resetAfter = Duration(seconds: 3);
}

/// Glättet [PositionFix.speedMps] einer Messreihe. Eine Instanz je Positionsstrom.
class SpeedFilter {
  PositionFix? _last;
  double _speed = 0;

  PositionFix apply(PositionFix fix) {
    final last = _last;
    _last = fix;
    final dt = last == null
        ? null
        : fix.time.difference(last.time).inMilliseconds / 1000;
    if (dt == null ||
        dt <= 0 ||
        dt > SpeedFilterLimits.resetAfter.inMilliseconds / 1000) {
      _speed = fix.speedMps;
      return fix;
    }
    final maxStep = SpeedFilterLimits.maxAccelMps2 * dt;
    final target = fix.speedMps.clamp(_speed - maxStep, _speed + maxStep);
    final alpha = 1 - math.exp(-dt / SpeedFilterLimits.tauSeconds);
    _speed += (target - _speed) * alpha;
    if (_speed < 0) _speed = 0;
    if (_speed == fix.speedMps) return fix;
    return PositionFix(
      position: fix.position,
      speedMps: _speed,
      accuracyMeters: fix.accuracyMeters,
      time: fix.time,
      headingDeg: fix.headingDeg,
    );
  }
}
