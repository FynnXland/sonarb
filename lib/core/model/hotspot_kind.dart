/// Art einer eigenen Meldung (Hotspot). Gespeichert wird der Name, neue Werte nur anhängen.
enum HotspotKind {
  /// Mobiler Blitzer.
  mobileCamera,

  /// Abstandsmessung.
  distanceCheck,

  /// Baustelle.
  construction,

  /// Sonstige Gefahrenstelle (Unfall, Hindernis).
  danger,

  other,
}
