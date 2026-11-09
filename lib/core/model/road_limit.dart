/// Tempolimit der Straße, auf der man fährt: eine Zahl, ausdrücklich keins (Autobahn ohne
/// Limit) oder unbekannt. „Keins“ und „unbekannt“ sind für die Warnlogik gleich (kein Vergleich
/// mit dem Tempo), das Cockpit zeigt sie verschieden.
class RoadLimit {
  /// Limit in km/h.
  const RoadLimit.kmh(int this.kmh) : none = false;

  /// Hier gilt ausdrücklich kein Tempolimit (OSM `maxspeed=none`, `DE:motorway`).
  const RoadLimit.none() : kmh = null, none = true;

  /// Nichts bekannt.
  const RoadLimit.unknown() : kmh = null, none = false;

  final int? kmh;
  final bool none;

  bool get isUnknown => kmh == null && !none;

  @override
  bool operator ==(Object other) =>
      other is RoadLimit && other.kmh == kmh && other.none == none;

  @override
  int get hashCode => Object.hash(kmh, none);

  @override
  String toString() => none
      ? 'RoadLimit.none'
      : kmh == null
      ? 'RoadLimit.unknown'
      : 'RoadLimit($kmh)';
}
