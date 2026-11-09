import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/position_fix.dart';

/// Nachgestellte Fahrt mit einem Fix pro Sekunde: Tempo und Kurs folgen den Abschnitten, die
/// Position dem Weg. Unter 2 m/s fehlt der Kurs wie bei geolocator.
class TripSim {
  TripSim({
    this.origin = const GeoPoint(52.52, 13.40),
    this.heading = 90,
    DateTime? start,
    this.accuracy = 5,
  }) : _time = start ?? DateTime.utc(2026, 6, 10, 10);

  final GeoPoint origin;
  final double accuracy;
  late GeoPoint _pos = origin;

  /// Kurs in Grad, ändert sich mit den Abschnitten.
  double heading;
  double _speed = 0;
  DateTime _time;
  final fixes = <PositionFix>[];

  DateTime get time => _time;
  double get speedKmh => _speed * 3.6;

  void _step(double nextSpeed, {double turnDegPerSecond = 0, double? acc}) {
    final mean = (_speed + nextSpeed) / 2;
    _pos = destinationPoint(_pos, heading, mean);
    heading = normalizeDegrees(heading + turnDegPerSecond);
    _speed = nextSpeed;
    _time = _time.add(const Duration(seconds: 1));
    fixes.add(
      PositionFix(
        position: _pos,
        speedMps: _speed,
        accuracyMeters: acc ?? accuracy,
        time: _time,
        headingDeg: _speed >= 2 ? heading : null,
      ),
    );
  }

  /// Erster Fix am Start, ohne Bewegung.
  void begin({double kmh = 0}) {
    _speed = kmh / 3.6;
    fixes.add(
      PositionFix(
        position: _pos,
        speedMps: _speed,
        accuracyMeters: accuracy,
        time: _time,
        headingDeg: _speed >= 2 ? heading : null,
      ),
    );
  }

  /// [seconds] lang [kmh] halten, dabei um [turnDegPerSecond] je Sekunde drehen.
  void hold(double kmh, int seconds, {double turnDegPerSecond = 0}) {
    for (var i = 0; i < seconds; i++) {
      _step(kmh / 3.6, turnDegPerSecond: turnDegPerSecond);
    }
  }

  /// Mit [mps2] (Betrag) auf [kmh] beschleunigen oder verzögern.
  void ramp(double kmh, double mps2) {
    final target = kmh / 3.6;
    while ((_speed - target).abs() > 1e-9) {
      final next = _speed < target
          ? (_speed + mps2).clamp(0.0, target)
          : (_speed - mps2).clamp(target, double.infinity);
      _step(next.toDouble());
    }
  }

  void stand(int seconds) {
    for (var i = 0; i < seconds; i++) {
      _step(0);
    }
  }

  /// Ein Fix mit schlechter Genauigkeit bei gleichem Tempo.
  void poor({double accuracy = 60}) => _step(_speed, acc: accuracy);

  /// [seconds] ohne Fix (Tunnel), dann weiter mit gleichem Tempo.
  void gap(int seconds) {
    for (var i = 0; i < seconds - 1; i++) {
      _pos = destinationPoint(_pos, heading, _speed);
      _time = _time.add(const Duration(seconds: 1));
    }
    _step(_speed);
  }
}
