import 'dart:math' as math;

import '../../core/contracts/warning_engine.dart';
import '../../core/model/alert_point.dart';
import 'point_class.dart';

/// Frühere Ansage bei [isUrgentHazard]: mindestens so weit, bei Tempo so viele Sekunden vorher.
const double _hazardMeters = 1000;
const double _hazardSeconds = 40;

/// Ende der Abschnittskontrolle: erst unmittelbar davor, damit niemand in der Messstrecke
/// schon beschleunigt. Bei 130 km/h liegt so mindestens ein Fix in der Zone.
const double _endNoticeMeters = 50;
const double _endNoticeSeconds = 2.5;

/// Zonen eines Punkts in Metern, jede höchstens so groß wie die vorige. Formeln siehe
/// [WarningSettings].
class StageZones {
  const StageZones(this.announce, this.reminder, this.imminent);

  final double announce;

  /// Null, wenn die Erinnerung ausgeschaltet ist.
  final double? reminder;
  final double imminent;

  /// Tiefste Stufe, deren Zone [d] enthält.
  WarningStage? stageAt(double d) {
    if (d < imminent) return WarningStage.imminent;
    final r = reminder;
    if (r != null && d < r) return WarningStage.reminder;
    return d < announce ? WarningStage.announce : null;
  }

  @override
  String toString() => 'StageZones($announce, $reminder, $imminent)';
}

StageZones stageZones(
  WarningSettings s,
  double speedMps, {
  int? limitKmh,
  double? radiusMeters,
}) {
  final timed = math.min(
    s.announceSeconds * speedMps,
    WarningSettings.maxTimedAnnounceMeters,
  );
  var announce = math.max(s.announceMeters, timed);
  // Ein eigener Radius kann die erste Ansage nur früher machen.
  if (radiusMeters != null) {
    announce = math.max(announce, math.min(radiusMeters, s.maxAnnounceMeters));
  }

  double? reminder;
  if (s.reminderEnabled) {
    var r = math.max(s.reminderMeters, s.reminderSeconds * speedMps);
    if (limitKmh != null) r = math.max(r, coastMeters(s, speedMps, limitKmh));
    reminder = math.min(r, announce);
  }

  final imminent = math.min(
    math.max(s.imminentMeters, s.imminentSeconds * speedMps),
    reminder ?? announce,
  );
  return StageZones(announce, reminder, imminent);
}

/// Strecke, um vom aktuellen Tempo durch Ausrollen auf [limitKmh] zu kommen, mit Reaktionszeit.
double coastMeters(WarningSettings s, double speedMps, int limitKmh) {
  final target = limitKmh / 3.6;
  final slowDown = speedMps > target
      ? (speedMps * speedMps - target * target) / (2 * s.coastDecelMps2)
      : 0.0;
  return s.reactionSeconds * speedMps + slowDown;
}

/// Zonen für [p] je nach Behandlung: Ende der Abschnittskontrolle erst unmittelbar davor,
/// dringende Gefahren früher.
StageZones zonesFor(
  Tracking tracking,
  AlertPoint p,
  WarningSettings s,
  double speedMps,
  int? limit,
) {
  if (tracking == Tracking.endNotice) {
    final z = math.max(_endNoticeMeters, _endNoticeSeconds * speedMps);
    return StageZones(z, null, 0);
  }
  final base = stageZones(
    s,
    speedMps,
    limitKmh: limit,
    radiusMeters: p.radiusMeters,
  );
  if (tracking != Tracking.announceOnly || !isUrgentHazard(p)) return base;
  final early = math.max(
    _hazardMeters,
    math.min(_hazardSeconds * speedMps, WarningSettings.maxTimedAnnounceMeters),
  );
  if (early <= base.announce) return base;
  return StageZones(early, base.reminder, base.imminent);
}
