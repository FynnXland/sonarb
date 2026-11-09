import '../../core/geo/geo.dart';
import '../../core/model/position_fix.dart';
import 'location_service.dart' show minHeadingSpeedMps;

/// Kürzester Abstand zum Referenzpunkt, ab dem ein Kurs aus Positionen taugt.
const double minHeadingDistanceMeters = 15;

/// Gemeldetes Tempo darunter gilt als unzuverlässig (Emulatoren melden z. B. 5e-16 m/s statt
/// "fehlt"), dann zählt das aus den Positionen geschätzte.
const double _trustedSpeedMps = 0.5;

/// So lange bleibt der letzte Kurs im Stillstand oder bei kurzen Schritten erhalten.
const Duration headingHold = Duration(seconds: 10);

/// Liefert einen Kurs, wenn das GPS keinen (brauchbaren) meldet: Er wird aus dem Weg zwischen
/// aufeinanderfolgenden Fixes berechnet. Ohne Bewegung hält er den letzten Kurs [headingHold] lang.
/// Eine Instanz gehört zu genau einer Fahrt.
class HeadingEstimator {
  PositionFix? _previous;
  GeoPoint? _reference;
  double? _heading;
  DateTime? _headingTime;

  /// Gibt [fix] mit Kurs zurück. Ein gemeldeter Kurs bleibt unverändert. Fehlt das Tempo,
  /// steht das aus den Positionen geschätzte im Ergebnis.
  PositionFix apply(PositionFix input) {
    final speed = _speedOf(input);
    final fix = speed == input.speedMps ? input : _copy(input, speed: speed);
    final moving = speed >= minHeadingSpeedMps;
    _previous = input;

    if (fix.headingDeg != null) {
      _remember(fix.headingDeg!, fix);
      _reference = fix.position;
      return fix;
    }
    if (!moving) {
      _reference = fix.position;
      return _copy(fix, heading: _held(fix.time));
    }

    final reference = _reference ??= fix.position;
    if (distanceMeters(reference, fix.position) >= _neededDistance(fix)) {
      _remember(bearingDegrees(reference, fix.position), fix);
      _reference = fix.position;
    }
    return _copy(fix, heading: _held(fix.time));
  }

  /// Gemeldetes Tempo, sonst das aus dem letzten Schritt geschätzte. Ein Schritt, der nicht
  /// größer ist als die Genauigkeit, gilt als Rauschen und ergibt kein Tempo.
  double _speedOf(PositionFix fix) {
    if (fix.speedMps >= _trustedSpeedMps) return fix.speedMps;
    final prev = _previous;
    if (prev == null) return fix.speedMps;
    final seconds = fix.time.difference(prev.time).inMilliseconds / 1000;
    if (seconds <= 0) return fix.speedMps;
    final step = distanceMeters(prev.position, fix.position);
    return step > fix.accuracyMeters ? step / seconds : fix.speedMps;
  }

  double _neededDistance(PositionFix fix) =>
      fix.accuracyMeters * 2 > minHeadingDistanceMeters
      ? fix.accuracyMeters * 2
      : minHeadingDistanceMeters;

  void _remember(double heading, PositionFix fix) {
    _heading = heading;
    _headingTime = fix.time;
  }

  double? _held(DateTime now) {
    final at = _headingTime;
    if (_heading == null || at == null) return null;
    return now.difference(at) <= headingHold ? _heading : null;
  }

  PositionFix _copy(PositionFix fix, {double? speed, double? heading}) =>
      PositionFix(
        position: fix.position,
        speedMps: speed ?? fix.speedMps,
        accuracyMeters: fix.accuracyMeters,
        time: fix.time,
        headingDeg: heading ?? fix.headingDeg,
      );
}
