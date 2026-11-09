import '../../core/model/alert_point.dart';

/// Was die Benachrichtigung zeigt. Kommt von `app/`, unabhängig vom Cockpit.
class MonitorSnapshot {
  const MonitorSnapshot({
    this.driving = false,
    this.speedKmh,
    this.limitKmh,
    this.next,
    this.nextMeters,
    this.gpsLost = false,
    this.dataUnavailable = false,
  });

  final bool driving;
  final double? speedKmh;
  final int? limitKmh;

  /// Nächster Punkt voraus, nur während der Fahrt.
  final AlertPoint? next;
  final double? nextMeters;
  final bool gpsLost;
  final bool dataUnavailable;
}

/// Eine Zeile, z. B. „52 km/h · Limit 50 · Blitzer in 400 m“.
/// Gerundet, damit die Benachrichtigung nicht bei jedem Meter neu gesetzt wird.
String notificationLine(MonitorSnapshot s) {
  final parts = <String>[];
  if (!s.driving) {
    parts.add('Bereit');
    parts.add(
      s.dataUnavailable ? 'Daten offline' : 'erkennt Fahrt automatisch',
    );
    return parts.join(' · ');
  }
  if (s.gpsLost) {
    parts.add('Kein GPS-Signal');
  } else {
    final speed = s.speedKmh;
    if (speed != null) parts.add('${speed.round()} km/h');
    final limit = s.limitKmh;
    if (limit != null) parts.add('Limit $limit');
    final next = s.next;
    final meters = s.nextMeters;
    if (next != null && meters != null) {
      parts.add('${pointLabel(next)} in ${roughDistance(meters)}');
    }
  }
  if (s.dataUnavailable) parts.add('Daten offline');
  if (parts.isEmpty) parts.add('Fahrt erkannt');
  return parts.join(' · ');
}

/// Unter 1 km auf 50 m, darüber auf 100 m gerundet.
String roughDistance(double meters) {
  if (meters < 975) return '${(meters / 50).round() * 50} m';
  final km = (meters / 100).round() / 10;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Kurze Bezeichnung für die einzeilige Benachrichtigung: der feste Blitzer heißt dort nur
/// „Blitzer“, alles andere nach seiner feinen Art („Stauende“, „Mobiler Blitzer“).
String pointLabel(AlertPoint p) {
  final c = p.effectiveCategory;
  return c == AlertCategory.fixedSpeed ? 'Blitzer' : c.label;
}
