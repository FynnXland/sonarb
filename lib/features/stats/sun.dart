import 'dart:math' as math;

import '../../core/geo/geo.dart';

/// Ab dieser Sonnenhöhe (Ende der bürgerlichen Dämmerung) gilt eine Fahrt als Nachtfahrt.
const double nightSunElevationDeg = -6;

double _rad(double d) => d * math.pi / 180;

/// Sonnenhöhe über dem Horizont in Grad bei [p] zur Zeit [time]. Näherung nach dem
/// Astronomical Almanac, auf etwa 0,5° genau; reicht für Tag und Nacht auf wenige Minuten.
double sunElevationDeg(GeoPoint p, DateTime time) {
  final days = time.toUtc().millisecondsSinceEpoch / 86400000.0 - 10957.5;
  final meanLon = (280.460 + 0.9856474 * days) % 360;
  final anomaly = _rad((357.528 + 0.9856003 * days) % 360);
  final eclipticLon = _rad(
    meanLon + 1.915 * math.sin(anomaly) + 0.020 * math.sin(2 * anomaly),
  );
  final obliquity = _rad(23.439 - 0.0000004 * days);
  final rightAscension = math.atan2(
    math.cos(obliquity) * math.sin(eclipticLon),
    math.cos(eclipticLon),
  );
  final declination = math.asin(math.sin(obliquity) * math.sin(eclipticLon));
  final siderealHours = (18.697374558 + 24.06570982441908 * days) % 24;
  final hourAngle = _rad(siderealHours * 15 + p.lon) - rightAscension;
  final lat = _rad(p.lat);
  final sinElevation =
      math.sin(lat) * math.sin(declination) +
      math.cos(lat) * math.cos(declination) * math.cos(hourAngle);
  return math.asin(sinElevation.clamp(-1.0, 1.0)) * 180 / math.pi;
}

bool isNight(GeoPoint p, DateTime time) =>
    sunElevationDeg(p, time) < nightSunElevationDeg;
