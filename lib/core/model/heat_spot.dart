import 'alert_point.dart';

/// Wie Sonarb vor einem Blitzer-Hotspot warnt: einer Stelle, an der früher oft mobil geblitzt
/// wurde (Häufung vergangener Beobachtungen, [AlertPoint.historical]). Gespeichert wird der Name.
enum HeatSpotAlert {
  /// Keine Warnung.
  off,

  /// Satz „Blitzer-Hotspot voraus“, dann das Hotspot-Signal.
  speech,

  /// Nur das Hotspot-Signal.
  beep,
}

/// Wählbare Mindestzahl vergangener Meldungen im Umkreis von 300 m, ab der eine Stelle als
/// Hotspot gilt. 1 heißt: jede gemeldete Stelle.
const heatSpotReportChoices = <int>[1, 2, 3, 5];
const defaultHeatSpotReports = 1;

/// ID-Anfang der Hotspots, die die Warnlogik aus vergangenen Beobachtungen bildet.
const heatSpotIdPrefix = 'heatspot:';

/// Ein Hotspot aus der Warnlogik. Er bleibt [AlertPoint.historical]: Wer ihn nicht kennt,
/// behandelt ihn wie jede vergangene Beobachtung und bleibt still.
bool isHeatSpot(AlertPoint p) =>
    p.historical && p.id.startsWith(heatSpotIdPrefix);
