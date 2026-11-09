import 'dart:async';

import '../../core/contracts/hotspot_repository.dart';
import '../../core/model/alert_point.dart';

/// Hotspot als Warnpunkt. Ein gesetzter Kurs wird zur einzigen gültigen Fahrtrichtung.
AlertPoint hotspotToAlertPoint(Hotspot h) => AlertPoint(
  id: 'hotspot:${h.id}',
  kind: AlertKind.hotspot,
  position: h.position,
  source: 'hotspot',
  travelBearings: h.headingDeg == null ? const [] : [h.headingDeg!],
  label: h.note,
  radiusMeters: h.radiusMeters,
  reportKind: h.kind,
);

/// Ergebnis der Prüfung von Plugin-Punkten.
class PluginPointCheck {
  const PluginPointCheck(this.accepted, this.rejected);
  final List<AlertPoint> accepted;
  final int rejected;
}

/// Lässt nur Punkte mit der ID `plugin:<pluginId>:…` durch (Plugins dürfen keine Core-Punkte
/// überschreiben) und setzt [AlertPoint.source] auf die Plugin-ID.
PluginPointCheck checkPluginPoints(String pluginId, Iterable<AlertPoint> raw) {
  final prefix = 'plugin:$pluginId:';
  final accepted = <AlertPoint>[];
  var rejected = 0;
  for (final p in raw) {
    if (!p.id.startsWith(prefix) || p.id.length == prefix.length) {
      rejected++;
    } else if (p.source == pluginId) {
      accepted.add(p);
    } else {
      accepted.add(
        AlertPoint(
          id: p.id,
          kind: p.kind,
          position: p.position,
          source: pluginId,
          travelBearings: p.travelBearings,
          maxSpeed: p.maxSpeed,
          label: p.label,
          radiusMeters: p.radiusMeters,
        ),
      );
    }
  }
  return PluginPointCheck(accepted, rejected);
}

/// Kurzer Fehlertext für die Statusanzeige.
String errorText(Object e) =>
    e is TimeoutException ? 'Zeitüberschreitung' : shortenError(e);

String shortenError(Object e) {
  var t = e.toString().replaceFirst(RegExp(r'^\w*Exception: '), '').trim();
  if (t.isEmpty) t = e.runtimeType.toString();
  return t.length > 80 ? '${t.substring(0, 80)}…' : t;
}
