import 'alert_point.dart';

/// Gruppe in der Legende.
enum CategoryGroup {
  /// Messstellen für Tempo, Rotlicht, Abstand.
  camera('Blitzer'),

  /// Baustellen und Gefahren auf der Strecke.
  hazard('Gefahrenstellen'),

  /// Andere Kontrollen und Einschränkungen.
  other('Weitere');

  const CategoryGroup(this.label);
  final String label;
}

/// Feine Art eines Punkts für Symbol, Bezeichnung und Legende. [AlertKind] bleibt die grobe Art
/// für die Warnlogik. Gespeichert wird der Name, neue Werte nur anhängen.
enum AlertCategory {
  // Blitzer
  fixedSpeed('Fester Blitzer', CategoryGroup.camera, showsSpeed: true),
  tunnelSpeed('Tunnel mit Blitzer', CategoryGroup.camera, showsSpeed: true),
  fixedRedLightSpeed(
    'Fester Blitzer für Rotlicht und Tempo',
    CategoryGroup.camera,
    showsSpeed: true,
  ),
  fixedRedLight('Fester Rotlichtblitzer', CategoryGroup.camera),
  sectionStart(
    'Abschnittskontrolle Anfang',
    CategoryGroup.camera,
    showsSpeed: true,
  ),
  sectionEnd('Abschnittskontrolle Ende', CategoryGroup.camera),
  semiStationary('Blitzeranhänger', CategoryGroup.camera, showsSpeed: true),
  mobileSpeed('Mobiler Blitzer', CategoryGroup.camera, showsSpeed: true),
  mobileRedLight('Mobiler Rotlichtblitzer', CategoryGroup.camera),
  mobileDistance('Abstandsmessung', CategoryGroup.camera),

  // Gefahrenstellen
  longTermRoadworks('Dauerbaustelle', CategoryGroup.hazard),
  dayRoadworks('Tagesbaustelle', CategoryGroup.hazard),
  trafficJamEnd('Stauende', CategoryGroup.hazard),
  obstacle('Hindernis auf der Fahrbahn', CategoryGroup.hazard),
  accident('Unfall', CategoryGroup.hazard),
  slipperyRoad('Glätte', CategoryGroup.hazard),
  poorVisibility('Schlechte Sicht', CategoryGroup.hazard),
  breakdown('Pannenfahrzeug', CategoryGroup.hazard),
  officialNotice('Amtliche Verkehrsmeldung', CategoryGroup.hazard),

  // Weitere
  accessControl('Einfahrtskontrolle', CategoryGroup.other),
  heightControl('Höhenkontrolle', CategoryGroup.other),
  weightControl('Gewichtskontrolle', CategoryGroup.other),
  busLane('Busspur', CategoryGroup.other),
  noOvertaking('Überholverbot', CategoryGroup.other),
  closure('Sperrung', CategoryGroup.other),

  // Ohne Gruppe in der Legende der Warnpunkte
  trafficSignal('Ampel', CategoryGroup.other),
  otherReport('Gemeldete Stelle', CategoryGroup.hazard);

  const AlertCategory(this.label, this.group, {this.showsSpeed = false});

  /// Deutsche Bezeichnung für Legende, Detailblatt und Hinweisfeld.
  final String label;
  final CategoryGroup group;

  /// Das Symbol trägt das Tempolimit ([AlertPoint.maxSpeed]), wenn es bekannt ist.
  final bool showsSpeed;

  /// Mobil bzw. vorübergehend: eigene Farbfamilie im Symbol.
  bool get isMobile =>
      this == mobileSpeed || this == mobileRedLight || this == mobileDistance;
}

/// Kategorie für Punkte, deren Quelle keine feine Art setzt.
AlertCategory defaultCategory(AlertKind kind, HotspotKind? reportKind) =>
    switch (kind) {
      AlertKind.speedCamera => AlertCategory.fixedSpeed,
      AlertKind.redLightCamera => AlertCategory.fixedRedLight,
      AlertKind.sectionControl => AlertCategory.sectionStart,
      AlertKind.trafficSignal => AlertCategory.trafficSignal,
      AlertKind.live => AlertCategory.mobileSpeed,
      AlertKind.construction => AlertCategory.longTermRoadworks,
      AlertKind.hotspot => switch (reportKind) {
        HotspotKind.mobileCamera || null => AlertCategory.mobileSpeed,
        HotspotKind.distanceCheck => AlertCategory.mobileDistance,
        HotspotKind.construction => AlertCategory.dayRoadworks,
        HotspotKind.danger => AlertCategory.obstacle,
        HotspotKind.other => AlertCategory.otherReport,
      },
    };
