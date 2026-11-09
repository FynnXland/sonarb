import '../../core/geo/geo.dart';
import '../../core/model/position_fix.dart';

/// Wann ein Fix im Stand nichts Neues bringt.
abstract final class StandstillLimits {
  /// Darunter steht das Auto. Das GPS-Tempo zittert im Stand um 0,1–0,3 m/s.
  static const speedMps = 0.8;

  /// So weit springt die Position im Stand, ohne dass sich das Auto bewegt.
  static const meters = 3.0;

  /// Spätestens so oft wird auch im Stand voll verarbeitet und angezeigt, etwa damit neu
  /// geladene Punkte in die Warnlogik kommen.
  static const refresh = Duration(seconds: 10);
}

/// Lässt einen Fix nur durch, wenn er sichtbar etwas ändert: anderes Tempo auf der Anzeige
/// (ganze km/h), Bewegung, oder [StandstillLimits.refresh] ist um. Bei Fahrt ändert sich die
/// Position mit jedem Fix, dort kommt alles durch; gespart wird an Ampel und im Stau.
/// Warnungen kommen dadurch nicht später: Ohne Bewegung ändert sich kein Abstand.
class StandstillGate {
  PositionFix? _last;
  DateTime? _at;

  bool admit(PositionFix fix, DateTime now) {
    final last = _last;
    final at = _at;
    final pass =
        last == null ||
        at == null ||
        fix.speedMps >= StandstillLimits.speedMps ||
        fix.speedKmh.round() != last.speedKmh.round() ||
        distanceMeters(last.position, fix.position) >=
            StandstillLimits.meters ||
        now.difference(at) >= StandstillLimits.refresh;
    if (pass) {
      _last = fix;
      _at = now;
    }
    return pass;
  }

  void reset() {
    _last = null;
    _at = null;
  }
}
