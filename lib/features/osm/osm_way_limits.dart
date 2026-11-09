import '../../core/geo/geo.dart';
import 'osm_speed.dart';
import 'osm_tile.dart';

/// Wege, die für Tempolimits gelten: Angaben je Tag-Satz, ohne Bezug auf Overpass.
/// Die Abfragen, der Parser und das Offline-Paket benutzen alle dieselben Regeln.

/// Rangniedrige Straßen, die nur bei langsamer Fahrt gebraucht werden.
const Set<String> minorRoadTypes = {
  'unclassified',
  'residential',
  'living_street',
};

/// Rampen: Sie tragen selten ein `maxspeed`, werden aber für die Linie voraus gebraucht (nach
/// einer Abfahrt ist das die Rampe, nicht die Autobahn). Die Abfrage holt sie auch ohne Limit.
const Set<String> rampRoadTypes = {
  'motorway_link',
  'trunk_link',
  'primary_link',
  'secondary_link',
  'tertiary_link',
};

/// Gehört der Weg zu den Tempolimit-Wegen, mit Limit oder als Rampe ohne?
bool keepsWay(Map<String, String> tags) =>
    hasLimitTag(tags) || rampRoadTypes.contains(tags['highway']);

/// Hat der Weg eine Tempoangabe (oder ist ein verkehrsberuhigter Bereich)?
bool hasLimitTag(Map<String, String> tags) =>
    tags.containsKey('maxspeed') ||
    tags.containsKey('maxspeed:forward') ||
    tags.containsKey('maxspeed:backward') ||
    tags['highway'] == 'living_street'; // Schrittgeschwindigkeit

/// 1 = Einbahn in Wegrichtung, -1 = dagegen, 0 = beidseitig.
int onewayOf(Map<String, String> tags) {
  switch (tags['oneway']) {
    case 'yes' || 'true' || '1':
      return 1;
    case '-1' || 'reverse':
      return -1;
  }
  // Autobahnen und Kreisverkehre gelten auch ohne Tag als Einbahn.
  if (tags['junction'] == 'roundabout' || tags['highway'] == 'motorway') {
    return tags['oneway'] == 'no' ? 0 : 1;
  }
  return 0;
}

/// Limits (vorwärts, rückwärts) in km/h aus den Tags; null = keines oder unbekannt.
(int?, int?) limitsOf(Map<String, String> tags) {
  // Ohne Angabe gilt im verkehrsberuhigten Bereich (Zeichen 325, `living_street`) Schrittgeschwindigkeit.
  final base =
      parseMaxspeed(tags['maxspeed']) ??
      (tags['highway'] == 'living_street' && !tags.containsKey('maxspeed')
          ? 7
          : null);
  return (
    tags.containsKey('maxspeed:forward')
        ? parseMaxspeed(tags['maxspeed:forward'])
        : base,
    tags.containsKey('maxspeed:backward')
        ? parseMaxspeed(tags['maxspeed:backward'])
        : base,
  );
}

/// Gilt je Richtung ausdrücklich kein Limit ([isNoSpeedLimit])? Neben [limitsOf], das dafür
/// null liefert und im Abgleich mit dem Paket-Generator so bleibt. Auf Nebenstraßen ist
/// `maxspeed=none` ein Tagging-Fehler und zählt nicht.
(bool, bool) noLimitOf(Map<String, String> tags) {
  if (minorRoadTypes.contains(tags['highway'])) return (false, false);
  final base = isNoSpeedLimit(tags['maxspeed']);
  return (
    tags.containsKey('maxspeed:forward')
        ? isNoSpeedLimit(tags['maxspeed:forward'])
        : base,
    tags.containsKey('maxspeed:backward')
        ? isNoSpeedLimit(tags['maxspeed:backward'])
        : base,
  );
}

/// Der Weg mit seinen Limits je Richtung aus den Tags und der Geometrie ([points] ab zwei Punkten).
/// Ohne Limit steht [speedWayNoLimit] statt der Zahl. [rank] ist der Rang der Straßenart; dazu
/// kommen Name und ref für die Linie voraus.
SpeedWay speedWayOf(
  Map<String, String> tags,
  List<GeoPoint> points, {
  int? rank,
}) {
  final (forward, backward) = limitsOf(tags);
  final (noForward, noBackward) = noLimitOf(tags);
  return SpeedWay(
    points: points,
    forward: forward ?? (noForward ? speedWayNoLimit : null),
    backward: backward ?? (noBackward ? speedWayNoLimit : null),
    oneway: onewayOf(tags),
    rank: rank,
    minor: rank == null ? null : minorRoadTypes.contains(tags['highway']),
    name: _text(tags['name']),
    ref: _text(tags['ref']),
    limitTagged: hasLimitTag(tags),
  );
}

String? _text(String? v) {
  final t = v?.trim();
  return t == null || t.isEmpty ? null : t;
}
