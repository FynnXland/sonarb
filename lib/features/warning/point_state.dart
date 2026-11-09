import '../../core/contracts/warning_engine.dart';
import '../../core/model/alert_point.dart';
import 'point_class.dart';

/// Merkt sich je Punkt, was schon gemeldet wurde und wie die Annäherung verlief.
class PointState {
  PointState(this.point, double distance)
    : distance = distance,
      minDistance = distance;

  AlertPoint point;
  double distance;

  /// Kleinster bisher gesehener Abstand (für die „entfernt sich wieder“-Erkennung).
  double minDistance;

  /// Tiefste erreichte Stufe. Läuft nur vorwärts, auch wenn keine Meldung kam.
  WarningStage? stage;

  /// Zuletzt gemeldete Stufe.
  WarningStage fired = WarningStage.announce;

  /// Vorbeigefahren oder abgebogen: bleibt stumm und unsichtbar, bis man wieder weit genug
  /// weg war.
  bool passed = false;

  /// ID des Punkts an derselben Stelle, der schon warnt. Dann bleibt dieser hier still.
  String? follows;

  /// Fixes in Folge, in denen der Kurs vom Punkt wegführt.
  int awayCount = 0;

  /// Fixes in Folge, in denen ein Hinweis neben der Strecke voraus liegt (`RoadVerdict.offRoad`).
  int offRoadCount = 0;

  /// Zuletzt in `active` ausgegeben (Basis für das Halten bei Stillstand / schlechtem GPS).
  bool shown = false;

  int seenTick = 0;

  WarningLevel get level => levelFor(stage);
}
