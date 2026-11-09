import 'package:sonarb/core/contracts/alert_audio.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/core/model/position_fix.dart';

/// Gerade Teststrecke ab [origin] Richtung [bearing]; Positionen als Meter entlang der Strecke.
class DriveSim {
  DriveSim({this.origin = const GeoPoint(48.1, 9.2), this.bearing = 90});

  final GeoPoint origin;
  final double bearing;
  DateTime _time = DateTime.utc(2026, 1, 1, 12);

  /// Punkt bei [along] Metern Strecke, [lateral] Meter rechts davon.
  GeoPoint at(double along, {double lateral = 0}) {
    final base = destinationPoint(origin, bearing, along);
    return lateral == 0 ? base : destinationPoint(base, bearing + 90, lateral);
  }

  /// Ein Fix pro Sekunde von [from] nach [to]; Rückwärtsfahrt dreht den Kurs um.
  List<PositionFix> drive(
    double from,
    double to, {
    double speed = 20,
    double accuracy = 5,
    bool withHeading = true,
    GeoPoint Function(GeoPoint)? jitter,
  }) {
    final forward = to >= from;
    final course = forward ? bearing : bearing + 180;
    final total = (to - from).abs();
    final steps = (total / speed).ceil();
    final fixes = <PositionFix>[];
    for (var i = 0; i <= steps; i++) {
      final s = from + (forward ? 1 : -1) * (i * speed).clamp(0, total);
      var pos = at(s);
      if (jitter != null) pos = jitter(pos);
      fixes.add(
        PositionFix(
          position: pos,
          headingDeg: withHeading ? normalizeDegrees(course) : null,
          speedMps: speed,
          accuracyMeters: accuracy,
          time: _time = _time.add(const Duration(seconds: 1)),
        ),
      );
    }
    return fixes;
  }

  /// Fahrt über Abschnitte (Kurs in Grad, Länge in Metern) ab dem Streckenpunkt [from],
  /// ein Fix pro Sekunde. Der Kurs ist der des Abschnitts, in dem man gerade fährt.
  List<PositionFix> route(
    double from,
    List<(double, double)> legs, {
    double speed = 20,
  }) {
    final fixes = <PositionFix>[];
    var start = at(from);
    var carry = 0.0;
    for (final (course, length) in legs) {
      var s = carry;
      while (s <= length) {
        fixes.add(
          PositionFix(
            position: destinationPoint(start, course, s),
            headingDeg: normalizeDegrees(course),
            speedMps: speed,
            accuracyMeters: 5,
            time: _time = _time.add(const Duration(seconds: 1)),
          ),
        );
        s += speed;
      }
      carry = s - length;
      start = destinationPoint(start, course, length);
    }
    return fixes;
  }

  /// Stillstand bei [along]: Tempo 0, kein Kurs (wie bei geolocator).
  List<PositionFix> stand(double along, int seconds, {double accuracy = 5}) => [
    for (var i = 0; i < seconds; i++)
      PositionFix(
        position: at(along),
        speedMps: 0,
        accuracyMeters: accuracy,
        time: _time = _time.add(const Duration(seconds: 1)),
      ),
  ];
}

AlertPoint cam(
  GeoPoint pos, {
  String id = 'cam',
  AlertKind kind = AlertKind.speedCamera,
  List<double> bearings = const [],
  int? maxSpeed,
  HotspotKind? report,
  double? radius,
}) => AlertPoint(
  id: id,
  kind: kind,
  position: pos,
  source: 'test',
  travelBearings: bearings,
  maxSpeed: maxSpeed,
  reportKind: report,
  radiusMeters: radius,
);

/// Eigene Meldung der Art [report].
AlertPoint report(
  GeoPoint pos,
  HotspotKind report, {
  String id = 'hs',
  List<double> bearings = const [],
  double? radius,
}) => cam(
  pos,
  id: id,
  kind: AlertKind.hotspot,
  bearings: bearings,
  report: report,
  radius: radius,
);

const allStages = WarningStage.values;

/// Ergebnis einer simulierten Fahrt.
class Run {
  Run(this.fixes, this.updates);

  final List<PositionFix> fixes;
  final List<WarningUpdate> updates;

  List<WarningSound> get sounds => [for (final u in updates) ...u.sounds];

  List<WarningEvent> get events => [for (final u in updates) ...u.events];

  /// Gemeldete Stufen, optional nur für Punkt [id].
  List<WarningStage> stages([String? id]) => [
    for (final e in events)
      if (id == null || e.point.id == id) e.stage,
  ];

  /// Index des Updates, das [stage] meldet, sonst -1.
  int indexOfStage(WarningStage stage, [String? id]) => updates.indexWhere(
    (u) => u.events.any(
      (e) => e.stage == stage && (id == null || e.point.id == id),
    ),
  );

  /// Abstand zum Punkt bei der Meldung von [stage].
  double distanceAt(WarningStage stage, [String? id]) => events
      .firstWhere((e) => e.stage == stage && (id == null || e.point.id == id))
      .distanceMeters;

  /// Index des ersten Updates mit [sound], sonst -1.
  int indexOf(WarningSound sound) =>
      updates.indexWhere((u) => u.sounds.contains(sound));
}

Run run(
  WarningEngine engine,
  List<PositionFix> fixes,
  List<AlertPoint> points, {
  int? road,
}) {
  final updates = [
    for (final f in fixes) engine.update(f, points, roadSpeedLimitKmh: road),
  ];
  return Run(fixes, updates);
}
