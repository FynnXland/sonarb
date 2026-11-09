import '../../core/model/alert_point.dart';

/// Grobe und feine Art eines OSM-Punkts.
class OsmClass {
  const OsmClass(this.kind, this.category);

  final AlertKind kind;
  final AlertCategory category;
}

/// Werte von `enforcement` (Semikolon-Liste), ohne Leerraum. `weight` zählt wie `maxweight`,
/// `no_overtaking` wie `noovertaking`.
Set<String> enforcementValues(String? raw) => {
  for (final v in (raw ?? '').split(';'))
    if (v.trim().isNotEmpty)
      switch (v.trim()) {
        'weight' => 'maxweight',
        'no_overtaking' => 'noovertaking',
        'section_control' => 'average_speed',
        final other => other,
      },
};

/// Werte, bei denen eine Relation einen Punkt ergibt (neben den Tempo-, Rotlicht- und Abschnittsarten).
const String otherEnforcementPattern =
    'maxheight|maxweight|weight|access|mindistance|no_overtaking|noovertaking';

/// Ordnet eine Messstelle oder Kontrolle ein. [enforcement] kommt aus [enforcementValues],
/// [tags] sind die vereinigten Tags von Relation und Geräteknoten, [tunnel] gilt, wenn der Weg am
/// Gerät ein Tunnel ist. Ohne `enforcement` zählt [speedByDefault] (Knoten `highway=speed_camera`).
/// Null, wenn die Kontrollart nichts mit dem Straßenverkehr zu tun hat, die die App kennt
/// (`check`, `toll`, `seatbelt` …).
///
/// Reihenfolge bei mehreren Werten: Abschnitt, Rotlicht (mit Tempo, wenn auch `maxspeed` dabei ist),
/// Tempo, Abstand, Höhe, Gewicht, Einfahrt, Überholverbot. Höhe, Gewicht, Einfahrt und Überholverbot
/// sind grob [AlertKind.construction]: eine Ansage ohne Tempo-Stufen.
OsmClass? classifyEnforcement({
  required Set<String> enforcement,
  required Map<String, String> tags,
  bool tunnel = false,
  bool speedByDefault = false,
}) {
  final mobile = tags['camera:type']?.trim().toLowerCase() == 'mobile';
  final trailer = tags['camera:mount']?.trim().toLowerCase() == 'trailer';
  final speed =
      enforcement.contains('maxspeed') ||
      (enforcement.isEmpty && speedByDefault);

  if (enforcement.contains('average_speed')) {
    return const OsmClass(AlertKind.sectionControl, AlertCategory.sectionStart);
  }
  if (enforcement.contains('traffic_signals')) {
    return speed
        ? const OsmClass(
            AlertKind.speedCamera,
            AlertCategory.fixedRedLightSpeed,
          )
        : const OsmClass(AlertKind.redLightCamera, AlertCategory.fixedRedLight);
  }
  if (speed) {
    return OsmClass(
      AlertKind.speedCamera,
      trailer
          ? AlertCategory.semiStationary
          : mobile
          ? AlertCategory.mobileSpeed
          : tunnel
          ? AlertCategory.tunnelSpeed
          : AlertCategory.fixedSpeed,
    );
  }
  if (enforcement.contains('mindistance')) {
    // Mobile Abstandsmessung ist eigene Art; feste Anlagen warnen wie feste Messstellen.
    return mobile
        ? const OsmClass(AlertKind.live, AlertCategory.mobileDistance)
        : const OsmClass(AlertKind.speedCamera, AlertCategory.fixedSpeed);
  }
  if (enforcement.contains('maxheight')) {
    return const OsmClass(AlertKind.construction, AlertCategory.heightControl);
  }
  if (enforcement.contains('maxweight')) {
    return const OsmClass(AlertKind.construction, AlertCategory.weightControl);
  }
  if (enforcement.contains('access')) {
    return const OsmClass(AlertKind.construction, AlertCategory.accessControl);
  }
  if (enforcement.contains('noovertaking')) {
    return const OsmClass(AlertKind.construction, AlertCategory.noOvertaking);
  }
  return null;
}
