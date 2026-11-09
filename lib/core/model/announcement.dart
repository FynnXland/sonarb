/// Ein Schalter im Bildschirm „Sprachansagen“. Er deckt eine oder mehrere feine Arten ab
/// (siehe `features/audio/cue.dart`); abgeschaltet entfällt nur die Sprache, der Piep bleibt.
/// Gespeichert wird der Name, neue Werte nur anhängen.
enum Announcement {
  fixedCamera('Fester Blitzer voraus'),
  redLightCamera('Rotlichtblitzer voraus'),
  sectionControl('Abschnittskontrolle voraus'),
  mobileCamera('Mobiler Blitzer voraus'),
  distanceCheck('Abstandsmessung voraus'),
  construction('Baustelle voraus'),
  danger('Gefahrenstelle voraus'),
  otherReport('Gemeldete Stelle voraus'),

  /// Zusatz hinter einer Blitzeransage, z. B. „…, Tempo 50“.
  speedLimit('Tempo'),

  gpsLost('GPS-Signal verloren'),
  gpsRestored('GPS-Signal wieder da'),
  dataUnavailable('Blitzerdaten nicht verfügbar'),
  dataRestored('Blitzerdaten wieder da'),
  positionFound('Position gefunden'),

  /// Kurz vor dem Ende der Messstrecke, ohne Piep.
  sectionEnd('Ende der Abschnittskontrolle'),
  trafficJamEnd('Stauende voraus'),
  accident('Unfall voraus'),

  /// Höhen-, Gewichts- und Einfahrtskontrolle.
  otherControls('Höhenkontrolle voraus'),
  noOvertaking('Überholverbot voraus'),
  closure('Sperrung voraus'),
  busLane('Busspur voraus'),

  /// Stelle, an der früher oft mobil geblitzt wurde. Ein- und ausgeschaltet über
  /// `HeatSpotAlert`, nicht über die Liste der Sätze.
  heatSpot('Blitzer-Hotspot voraus');

  const Announcement(this.text);

  /// Beispielsatz für die Probe; bei [speedLimit] folgt die Zahl.
  final String text;
}
