import '../geo/geo.dart';

/// Eine GPS-Messung, unabhängig von geolocator.
class PositionFix {
  const PositionFix({
    required this.position,
    required this.speedMps,
    required this.accuracyMeters,
    required this.time,
    this.headingDeg,
  });

  final GeoPoint position;

  /// Kurs über Grund in Grad. Null, wenn unbekannt oder zu langsam für einen verlässlichen Kurs.
  final double? headingDeg;

  /// Geschwindigkeit in m/s, ≥ 0.
  final double speedMps;
  final double accuracyMeters;
  final DateTime time;

  double get speedKmh => speedMps * 3.6;
}
