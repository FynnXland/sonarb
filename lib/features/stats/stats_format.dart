import 'trip_summary.dart';

String _comma(String s) => s.replaceAll('.', ',');

String _two(int v) => v.toString().padLeft(2, '0');

/// „12,4 km“, unter 10 km mit einer Stelle, darüber ganze Kilometer; unter 1 km in Metern.
String formatKm(double meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10} m';
  final km = meters / 1000;
  return km < 100 ? '${_comma(km.toStringAsFixed(1))} km' : '${km.round()} km';
}

/// „45 min“, ab einer Stunde „1 h 05 min“, unter einer Minute „40 s“.
String formatSeconds(double seconds) {
  final s = seconds.round();
  if (s < 60) return '$s s';
  final minutes = (s / 60).round();
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${_two(minutes % 60)} min';
}

String formatKmh(double? kmh) => kmh == null ? '–' : '${kmh.round()} km/h';

/// „23 %“; unter 1 % aber über 0 „< 1 %“.
String formatShare(double? share) {
  if (share == null) return '–';
  final p = share * 100;
  if (p > 0 && p < 1) return '< 1 %';
  return '${p.round()} %';
}

String formatMps2(double v) => '${_comma(v.toStringAsFixed(1))} m/s²';

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// „Mo 02.11.2026, 14:03“
String formatTripStart(DateTime t) {
  final l = t.toLocal();
  return '${_weekdays[l.weekday - 1]} ${_two(l.day)}.${_two(l.month)}.${l.year}, '
      '${_two(l.hour)}:${_two(l.minute)}';
}

/// „14:03“
String formatClock(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// „50 bis 59 km/h“, die letzte Stufe „ab 250 km/h“.
String formatSpeedBin(int fromKmh) =>
    fromKmh >= (StatsLimits.bins - 1) * StatsLimits.binKmh
    ? 'ab $fromKmh km/h'
    : '$fromKmh bis ${fromKmh + StatsLimits.binKmh - 1} km/h';

String roadClassLabel(RoadClass c) => switch (c) {
  RoadClass.urban => 'Innerorts',
  RoadClass.rural => 'Außerorts',
  RoadClass.motorway => 'Autobahn',
  RoadClass.unknown => 'Straßenart unbekannt',
};

String overLimitLabel(OverLimit o) => switch (o) {
  OverLimit.within => 'bis +3',
  OverLimit.upTo10 => '+4 bis +10',
  OverLimit.upTo20 => '+11 bis +20',
  OverLimit.above20 => 'ab +21',
};

/// „1 Fahrt“, „12 Fahrten“
String formatTripCount(int n) => n == 1 ? '1 Fahrt' : '$n Fahrten';

/// Zahl mit [digits] Nachkommastellen und Komma.
String formatNumber(double v, [int digits = 1]) =>
    _comma(v.toStringAsFixed(digits));

/// „± 1,8 km/h“
String formatSwing(double? kmh) =>
    kmh == null ? '–' : '± ${formatNumber(kmh)} km/h';

/// m/s² als Tempoänderung je Sekunde, ganze km/h: „11 km/h/s“.
String formatKmhPerS(double mps2) => '${(mps2 * 3.6).round()} km/h/s';
