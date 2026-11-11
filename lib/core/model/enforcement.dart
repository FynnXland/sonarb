import 'alert_point.dart';

/// Was als Verkehrsüberwachung gilt (§ 23 Abs. 1c StVO): alle Blitzer und Abstandsmessungen,
/// dazu Einfahrts-, Höhen- und Gewichtskontrollen. Baustellen, Gefahren, Busspur, Überholverbot
/// und Sperrung sind Hinweise zur Strecke, keine Überwachung.
extension AlertCategoryEnforcement on AlertCategory {
  bool get isEnforcement =>
      group == CategoryGroup.camera ||
      this == AlertCategory.accessControl ||
      this == AlertCategory.heightControl ||
      this == AlertCategory.weightControl;
}

/// Zeigt [p] Verkehrsüberwachung an? Vergangene Beobachtungen ([AlertPoint.historical]) sind
/// immer frühere Blitzer: aus ihnen entstehen Wärme-Ebene und Blitzer-Hotspots.
bool showsEnforcement(AlertPoint p) =>
    p.historical || p.effectiveCategory.isEnforcement;

/// [points] ohne Verkehrsüberwachung, wenn [enforcement] aus ist; sonst unverändert (dieselbe
/// Liste, damit Vergleiche auf Identität weiter greifen).
List<AlertPoint> filterEnforcement(
  List<AlertPoint> points, {
  required bool enforcement,
}) {
  if (enforcement || !points.any(showsEnforcement)) return points;
  return [
    for (final p in points)
      if (!showsEnforcement(p)) p,
  ];
}

/// Meldungsarten, die Verkehrsüberwachung melden.
bool reportKindIsEnforcement(HotspotKind kind) =>
    kind == HotspotKind.mobileCamera || kind == HotspotKind.distanceCheck;
