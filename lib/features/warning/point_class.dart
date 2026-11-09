import '../../core/contracts/warning_engine.dart';
import '../../core/model/alert_point.dart';
import '../../core/model/heat_spot.dart';

/// Wie die Warnlogik einen Punkt behandelt.
enum Tracking {
  /// Keine Warnung: Ampeln und vergangene Beobachtungen ([AlertPoint.historical]).
  none,

  /// Alle Annäherungsstufen: alle Blitzer und Abstandsmessungen.
  staged,

  /// Nur die erste Ansage: Baustellen, Gefahrenstellen, weitere Kontrollen, Blitzer-Hotspots.
  announceOnly,

  /// Ende einer Abschnittskontrolle: eine kurze Ansage unmittelbar davor, keine Stufen.
  endNotice,
}

Tracking trackingOf(AlertPoint p) {
  // Ein Hotspot aus vergangenen Beobachtungen wird wie eine Baustelle bewertet: eng auf der
  // Linie, eine Ansage je Durchfahrt.
  if (p.historical) {
    return isHeatSpot(p) ? Tracking.announceOnly : Tracking.none;
  }
  final c = p.effectiveCategory;
  if (c == AlertCategory.trafficSignal) return Tracking.none;
  if (c == AlertCategory.sectionEnd) return Tracking.endNotice;
  if (c.group == CategoryGroup.camera) return Tracking.staged;
  return Tracking.announceOnly;
}

/// Gefahren, vor denen man stark bremsen muss: Ansage etwas früher.
bool isUrgentHazard(AlertPoint p) => switch (p.effectiveCategory) {
  AlertCategory.trafficJamEnd ||
  AlertCategory.accident ||
  AlertCategory.obstacle ||
  AlertCategory.breakdown ||
  AlertCategory.slipperyRoad ||
  AlertCategory.poorVisibility => true,
  _ => false,
};

/// Gewicht bei gleicher Stufe: Messstellen vor Hinweisen.
int importanceOf(AlertPoint p) => switch (trackingOf(p)) {
  Tracking.staged => p.effectiveCategory.isMobile ? 2 : 3,
  Tracking.announceOnly => 1,
  Tracking.none || Tracking.endNotice => 0,
};

/// Anzeige-Stufe zur Annäherungsstufe: announce = pre, reminder/imminent = main.
WarningLevel levelFor(WarningStage? stage) => switch (stage) {
  null => WarningLevel.none,
  WarningStage.announce => WarningLevel.pre,
  WarningStage.reminder || WarningStage.imminent => WarningLevel.main,
};

/// Wichtigstes Ereignis zuerst: nähere Stufe, dann Art, dann Abstand.
int compareEvents(WarningEvent a, WarningEvent b) {
  final stage = b.stage.index.compareTo(a.stage.index);
  if (stage != 0) return stage;
  final weight = importanceOf(b.point).compareTo(importanceOf(a.point));
  if (weight != 0) return weight;
  return a.distanceMeters.compareTo(b.distanceMeters);
}

/// Messstelle in Erinnerung oder unmittelbar: Ihr Limit gilt im Cockpit.
bool isMainCamera(ActiveWarning w) =>
    w.level == WarningLevel.main && trackingOf(w.point) == Tracking.staged;

/// Messstellen in Erinnerung oder unmittelbar zuerst, sonst nach Distanz.
int compareActive(ActiveWarning a, ActiveWarning b) {
  final am = isMainCamera(a);
  final bm = isMainCamera(b);
  if (am != bm) return am ? -1 : 1;
  return a.distanceMeters.compareTo(b.distanceMeters);
}
