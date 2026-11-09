import 'dart:math' as math;

import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import '../../core/model/heat_spot.dart';
import 'point_class.dart';

/// Umkreis, in dem vergangene Blitzer zusammen zählen. Derselbe Wert wie die Wärme auf der
/// Karte (`heatNeighbourMeters`): etwa ein Straßenabschnitt, auf dem die Messstelle wechselt.
/// Zwei Hotspots liegen nie näher beieinander.
const double heatSpotRadiusMeters = 300;

/// Nach einem Jahr zählt eine Meldung halb, wie auf der Karte (`heatHalfLife`). Das Alter
/// entscheidet nur, welcher von zwei nahen Hotspots bleibt, nicht ob eine Stelle zählt.
const double heatSpotHalfLifeDays = 365;

/// Gleiche Stelle und gleicher Zeitpunkt: dieselbe Meldung aus zwei Quellen, zählt einmal.
const double _duplicateMeters = 5;

/// Feste Breite für das Zählraster: Die Zellen bleiben beim Fahren dieselben, die IDs der
/// Hotspots damit auch. In Deutschland weichen die Zellen höchstens um ein Zehntel ab.
const double _gridLatDeg = 51;
const double _metersPerDegree = earthRadiusMeters * math.pi / 180;

/// Gewicht einer Meldung nach Alter; ohne Datum oder aus der Zukunft voll.
double heatSpotWeight(DateTime? observedAt, DateTime now) {
  if (observedAt == null) return 1;
  final days = now.difference(observedAt).inHours / 24;
  if (days <= 0) return 1;
  return math.pow(0.5, days / heatSpotHalfLifeDays).toDouble();
}

/// Arten, die in vergangenen Meldungen für eine Tempo- oder Abstandskontrolle stehen können.
/// Auch allgemeine Angaben zählen: Ohne Kategorie gilt die der groben Art (meist mobiler
/// Blitzer), „Sonstiges“ zählt mit. Draußen bleibt nur, was eindeutig etwas anderes ist.
bool mayBeSpeedCheck(AlertCategory c) => switch (c) {
  AlertCategory.fixedSpeed ||
  AlertCategory.tunnelSpeed ||
  AlertCategory.fixedRedLightSpeed ||
  AlertCategory.sectionStart ||
  AlertCategory.semiStationary ||
  AlertCategory.mobileSpeed ||
  AlertCategory.mobileDistance ||
  AlertCategory.otherReport => true,
  AlertCategory.fixedRedLight ||
  AlertCategory.mobileRedLight ||
  AlertCategory.sectionEnd ||
  AlertCategory.longTermRoadworks ||
  AlertCategory.dayRoadworks ||
  AlertCategory.trafficJamEnd ||
  AlertCategory.obstacle ||
  AlertCategory.accident ||
  AlertCategory.slipperyRoad ||
  AlertCategory.poorVisibility ||
  AlertCategory.breakdown ||
  AlertCategory.officialNotice ||
  AlertCategory.accessControl ||
  AlertCategory.heightControl ||
  AlertCategory.weightControl ||
  AlertCategory.busLane ||
  AlertCategory.noOvertaking ||
  AlertCategory.closure ||
  AlertCategory.trafficSignal => false,
};

/// Zählt bei Hotspots mit: vergangene Meldungen aus den Datenquellen, die eine Tempo- oder
/// Abstandskontrolle sein können. Keine eigenen Meldungen, keine schon gebildeten Hotspots.
bool countsForHeatSpot(AlertPoint p) =>
    p.historical &&
    !isHeatSpot(p) &&
    p.kind != AlertKind.hotspot &&
    mayBeSpeedCheck(p.effectiveCategory);

/// Bildet Hotspots aus vergangenen Meldungen. Wie auf der Karte: ein Raster mit Zellen von
/// [heatSpotRadiusMeters], je Zelle alle Meldungen im Umkreis um ihren Mittelpunkt. Ein
/// Hotspot braucht dort mindestens [minReports] Meldungen. Liegen zwei näher als der Umkreis,
/// bleibt der mit mehr und jüngeren Meldungen. Ein Hotspot steht an der Meldung, die dem
/// Mittelpunkt am nächsten liegt, also auf einer Straße.
List<AlertPoint> findHeatSpots(
  List<AlertPoint> points,
  DateTime now, {
  int minReports = defaultHeatSpotReports,
}) {
  final cos = math.cos(_gridLatDeg * math.pi / 180);
  final raw = <(int, int), List<AlertPoint>>{};
  for (final p in points) {
    if (!countsForHeatSpot(p)) continue;
    final y = (p.position.lat * _metersPerDegree / heatSpotRadiusMeters)
        .floor();
    final x = (p.position.lon * _metersPerDegree * cos / heatSpotRadiusMeters)
        .floor();
    final cell = raw[(y, x)] ??= [];
    if (!cell.any((o) => _duplicate(o, p))) cell.add(p);
  }
  final found = <({(int, int) key, double weight, AlertPoint at, int count})>[];
  raw.forEach((key, members) {
    final center = _mean(members);
    var count = 0;
    var weight = 0.0;
    AlertPoint? nearest;
    var best = double.infinity;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final cell = raw[(key.$1 + dy, key.$2 + dx)];
        for (final p in cell ?? const <AlertPoint>[]) {
          final d = distanceMeters(center, p.position);
          if (d > heatSpotRadiusMeters) continue;
          count++;
          weight += heatSpotWeight(p.observedAt, now);
          if (d < best) {
            best = d;
            nearest = p;
          }
        }
      }
    }
    if (count < minReports) return;
    found.add((key: key, weight: weight, at: nearest!, count: count));
  });
  found.sort((a, b) {
    final w = b.weight.compareTo(a.weight);
    if (w != 0) return w;
    final y = a.key.$1.compareTo(b.key.$1);
    return y != 0 ? y : a.key.$2.compareTo(b.key.$2);
  });
  final spots = <AlertPoint>[];
  for (final f in found) {
    final pos = f.at.position;
    if (spots.any(
      (s) => distanceMeters(s.position, pos) < heatSpotRadiusMeters,
    )) {
      continue;
    }
    spots.add(
      AlertPoint(
        id: '$heatSpotIdPrefix${f.key.$1}_${f.key.$2}',
        kind: AlertKind.live,
        position: pos,
        source: f.at.source,
        category: AlertCategory.mobileSpeed,
        label: 'Blitzer-Hotspot',
        details: [PointDetail('Meldungen', '${f.count}')],
        historical: true,
      ),
    );
  }
  return spots;
}

bool _duplicate(AlertPoint a, AlertPoint b) =>
    a.observedAt != null &&
    a.observedAt == b.observedAt &&
    distanceMeters(a.position, b.position) <= _duplicateMeters;

GeoPoint _mean(List<AlertPoint> members) {
  var lat = 0.0;
  var lon = 0.0;
  for (final p in members) {
    lat += p.position.lat;
    lon += p.position.lon;
  }
  return GeoPoint(lat / members.length, lon / members.length);
}

/// Merkt sich die Hotspots zur letzten Punktmenge und Stufe: Die Kandidaten kommen jeden Fix
/// neu, die vergangenen Meldungen darin ändern sich selten.
class HeatSpotCache {
  int? _signature;
  DateTime? _day;
  List<AlertPoint> _spots = const [];

  List<AlertPoint> spotsIn(
    List<AlertPoint> candidates,
    DateTime now, {
    int minReports = defaultHeatSpotReports,
  }) {
    var count = 0;
    var hash = 0;
    for (final p in candidates) {
      if (!countsForHeatSpot(p)) continue;
      count++;
      hash = (hash + p.id.hashCode) & 0x3fffffff;
    }
    if (count == 0) return const [];
    final signature = Object.hash(count, hash, minReports);
    final day = DateTime(now.year, now.month, now.day);
    if (signature != _signature || day != _day) {
      _signature = signature;
      _day = day;
      _spots = findHeatSpots(candidates, now, minReports: minReports);
    }
    return _spots;
  }
}

/// Hotspots ohne aktuellen Blitzer im Umkreis: Dort warnt schon der Blitzer selbst.
/// [applies] prüft, ob ein Blitzer in die eigene Fahrtrichtung gilt.
List<AlertPoint> heatSpotsWithoutCamera(
  List<AlertPoint> spots,
  List<AlertPoint> candidates,
  bool Function(AlertPoint camera) applies,
) {
  if (spots.isEmpty) return spots;
  final cameras = [
    for (final p in candidates)
      if (trackingOf(p) == Tracking.staged && applies(p)) p,
  ];
  return [
    for (final s in spots)
      if (!cameras.any(
        (c) => distanceMeters(c.position, s.position) <= heatSpotRadiusMeters,
      ))
        s,
  ];
}
