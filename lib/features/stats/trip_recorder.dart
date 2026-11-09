import 'dart:math' as math;

import '../../core/contracts/warning_engine.dart';
import '../../core/geo/geo.dart' as geo;
import '../../core/model/alert_point.dart';
import '../../core/model/position_fix.dart';
import '../../core/model/road_limit.dart';
import 'sun.dart';
import 'trip_summary.dart';
import 'trip_trace.dart';

/// Schwellen der Aufzeichnung. Herleitung in `docs/STATISTIK.md`.
abstract final class RecorderLimits {
  /// Ungenauere Fixes fallen heraus (wie `GpsQualityLimits.poorMeters`).
  static const maxAccuracyMeters = 30.0;

  /// Darunter (mittleres Tempo eines Schritts) gilt der Schritt als Stand.
  static const standMps = 1.0;

  /// Standphasen ab dieser Länge zählen als Halt.
  static const stopSeconds = 5.0;

  /// Längere Pausen zwischen Fixes brechen Beschleunigung und Kurven ab.
  static const chainGapSeconds = 2.5;

  /// Über eine Lücke zählt die Luftlinie nur bis zu diesem Tempo.
  static const maxGapMps = 70.0;

  /// Beginn und Ende einer Verzögerung bzw. Beschleunigung (m/s², Betrag).
  static const episodeStartMps2 = 0.5;
  static const episodeEndMps2 = 0.25;

  /// Mehr Beschleunigung oder Verzögerung (geglättet, über 2 s) ist ein Messfehler. Eine
  /// Vollbremsung erscheint so gemessen mit 6 bis 8 m/s².
  static const maxPlausibleMps2 = 11.0;

  /// Delle statt Bremsung: Innerhalb dieser Zeit nach der Verzögerung beginnt eine
  /// Beschleunigung mit mindestens [dipAccelMps2], die mindestens [dipRecovered] des Verlusts
  /// zurückholt. So kräftig beschleunigt im Alltag kein Auto.
  static const dipGapSeconds = 2.5;
  static const dipAccelMps2 = 5.0;
  static const dipRecovered = 0.7;

  /// Mindestens so viel Tempoänderung, damit eine Verzögerung oder Beschleunigung zählt.
  static const episodeMinDeltaMps = 2.0;

  /// Spitze darüber: Bremsung (Pedal), höchstens so viel und lange genug: sanft.
  static const gentleMaxMps2 = 1.5;
  static const gentleMinSeconds = 3.0;

  /// Harte Bremsung bzw. kräftige Beschleunigung ab dieser Spitze.
  static const hardMps2 = 3.0;

  /// Anfahren: Beschleunigung, die unter diesem Tempo beginnt (7,2 km/h).
  static const startFromMps = 2.0;

  /// Kurven erst ab diesem Tempo (18 km/h); darunter ist der Kurs zu unruhig.
  static const curveMinMps = 5.0;

  /// Mehr Kursänderung je Sekunde ist ein Sprung des Kurses, keine Kurve.
  static const maxTurnDegPerSecond = 45.0;

  /// Zügige Kurve ab, Ende unter dieser Querbeschleunigung.
  static const sharpCurveMps2 = 3.5;
  static const sharpCurveEndMps2 = 2.5;

  /// Ein Blitzer gilt als passiert, wenn er so nah kam und dann aus der Warnliste fiel.
  static const cameraPassMeters = 100.0;

  /// Am Fahrtende noch in der Liste: nur bei so wenig Abstand passiert.
  static const cameraPassAtEndMeters = 30.0;

  /// Kürzere Fahrten werden nicht gespeichert.
  static const minTripMeters = 500.0;
  static const minTripMovingSeconds = 60.0;

  /// Sonnenstand höchstens so oft neu rechnen.
  static const nightRecheck = Duration(minutes: 1);
}

class _Sample {
  const _Sample(this.time, this.speed);
  final DateTime time;
  final double speed;
}

/// Verzögerung oder Beschleunigung, solange sie läuft.
class _Episode {
  _Episode(this.startSpeed, this.startTime) : extremeSpeed = startSpeed;
  final double startSpeed;
  final DateTime startTime;
  double extremeSpeed;
  double peak = 0;
  DateTime? lastTime;
}

class _LimitAcc {
  final seconds = List<double>.filled(OverLimit.values.length, 0);
  double maxKmh = 0;
}

class _CameraPass {
  _CameraPass(this.minDistance, this.speedKmh, this.limitKmh);
  double minDistance;
  double speedKmh;
  int? limitKmh;
}

double _seconds(DateTime a, DateTime b) => b.difference(a).inMicroseconds / 1e6;

/// Kurs [to] − [from] in Grad, auf [−180, 180).
double _turn(double from, double to) {
  final d = (to - from) % 360;
  return d >= 180 ? d - 360 : d;
}

/// Straßenart aus dem Limit: ohne Limit oder über 100 Autobahn, bis 50 innerorts, sonst
/// außerorts. Eine Schätzung; Stadtstraßen mit 60 oder 70 gelten als außerorts.
RoadClass roadClassOf(RoadLimit road) {
  if (road.none) return RoadClass.motorway;
  final kmh = road.kmh;
  if (kmh == null) return RoadClass.unknown;
  if (kmh <= 50) return RoadClass.urban;
  if (kmh <= 100) return RoadClass.rural;
  return RoadClass.motorway;
}

bool _isCamera(AlertPoint p) =>
    p.kind.isFixedCamera ||
    (p.kind == AlertKind.hotspot && p.reportKind == HotspotKind.mobileCamera);

/// Rechnet eine Fahrt aus den Fixes, die ohnehin kommen. Reine Logik ohne Uhr und I/O:
/// Zeiten stammen aus den Fixes. Eine Instanz je Fahrt.
class TripRecorder {
  PositionFix? _last;
  DateTime? _start;
  DateTime? _lastMoving;

  /// Die letzten bis zu drei Fixes einer lückenlosen Kette, ältester zuerst.
  final _chain = <_Sample>[];

  /// Geglättetes Tempo: Median der letzten drei Fixe, mit der Zeit des mittleren. Die letzten
  /// bis zu drei Werte; daraus kommt die Beschleunigung.
  final _smooth = <_Sample>[];
  final _turns = <(double, double)>[];
  _Episode? _decel;
  _Episode? _accel;

  /// Abgeschlossene Verzögerung, die noch auf eine mögliche Delle wartet.
  _Episode? _pendingDecel;
  bool _inCurve = false;
  double _pendingStand = 0;
  DateTime? _nightCheckedAt;
  bool _night = false;
  final _cameras = <String, _CameraPass>{};
  final _passedCameras = <String>{};
  final _trace = TraceBuilder();

  /// Laufender gleichmäßiger Abschnitt: Dauer, Σ v·Δt, Σ v²·Δt. Die jüngsten zwei Schritte
  /// warten in [_runPending]: Eine Verzögerung wird erst gut eine Sekunde nach ihrem Beginn
  /// erkannt, ihre ersten Schritte sollen nicht als Schwankung zählen.
  final _runPending = <(double, double)>[];
  double _runSeconds = 0;
  double _runSum = 0;
  double _runSquares = 0;

  double _distance = 0;
  double _moving = 0;
  double _stand = 0;
  int _stops = 0;
  double _maxKmh = 0;
  final _speedSeconds = List<double>.filled(StatsLimits.bins, 0);
  final _roadSeconds = List<double>.filled(RoadClass.values.length, 0);
  final _over = {
    for (final c in RoadClass.values)
      c: List<double>.filled(OverLimit.values.length, 0),
  };
  double _nightSeconds = 0;
  int _decelerations = 0;
  int _brakes = 0;
  int _hardBrakes = 0;
  double _lost = 0;
  double _gentleLost = 0;
  int _accelerations = 0;
  int _starts = 0;
  int _strong = 0;
  int _curves = 0;
  double _maxLateral = 0;
  int _warnings = 0;
  int _camerasPassed = 0;
  int _camerasTooFast = 0;
  double _stopSum = 0;
  double _stopMax = 0;
  final _decelPeaks = List<double>.filled(StatsLimits.peakBins, 0);
  final _accelPeaks = List<double>.filled(StatsLimits.peakBins, 0);
  double _maxDecel = 0;
  double _maxAccel = 0;
  double _calm = 0;
  double _kinematic = 0;
  double _cruise = 0;
  double _cruiseVar = 0;
  final _limits = <int, _LimitAcc>{};

  /// Ein Fix der Fahrt mit Tempolimit [road] und dem Ergebnis der Warnlogik zu diesem Fix.
  void add(
    PositionFix fix, {
    RoadLimit road = const RoadLimit.unknown(),
    WarningUpdate? update,
  }) {
    if (update != null) warnings(fix, update);
    move(fix, road: road, limitKmh: update?.speedLimitKmh ?? road.kmh);
  }

  /// Bewegung: jeder Fix der Fahrt, auch im Stand. [road] und [limitKmh] gelten an dieser
  /// Stelle (Straße bzw. maßgebliches Limit, etwa das einer Messstelle).
  void move(
    PositionFix fix, {
    RoadLimit road = const RoadLimit.unknown(),
    int? limitKmh,
  }) {
    if (fix.accuracyMeters > RecorderLimits.maxAccuracyMeters) {
      _breakChain();
      return;
    }
    final last = _last;
    _last = fix;
    final start = _start ??= fix.time;
    final at = _seconds(start, fix.time);
    if (last == null) {
      _trace.add(at, fix.speedKmh);
      _trace.limit(at, _traceLimit(road, limitKmh));
      _chain.add(_Sample(fix.time, fix.speedMps));
      return;
    }
    final dt = _seconds(last.time, fix.time);
    if (dt <= 0) {
      _last = last;
      return;
    }
    _trace.limit(at, _traceLimit(road, limitKmh));
    if (dt > RecorderLimits.chainGapSeconds) {
      _gap(last, fix, dt, at);
      return;
    }
    _trace.add(at, fix.speedKmh);
    final mean = (last.speedMps + fix.speedMps) / 2;
    final moving = mean >= RecorderLimits.standMps;
    if (moving) {
      _movingStep(fix, dt, mean, road, limitKmh);
    } else {
      _pendingStand += dt;
    }
    final a = _kinematics(fix, limitKmh);
    final pending = _pendingDecel;
    if (pending != null &&
        _accel == null &&
        _seconds(pending.lastTime ?? pending.startTime, fix.time) >
            RecorderLimits.dipGapSeconds + 2) {
      _flushDecel();
    }
    if (moving && a != null) {
      _kinematic += dt;
      if (a.abs() < StatsLimits.calmMps2) _calm += dt;
    }
    // Schwankung aus dem geglätteten Tempo, damit Ausreißer nicht als Pendeln zählen.
    _cruiseStep(moving && a != null ? _smooth.last.speed : 0, dt);
    _curve(last, fix, dt, mean);
  }

  static int? _traceLimit(RoadLimit road, int? limitKmh) =>
      limitKmh ?? (road.none ? TraceLimit.none : null);

  /// Gleichmäßige Fahrt: keine Verzögerung oder Beschleunigung läuft, Tempo ab 30 km/h.
  /// [mean] ist das geglättete Tempo, 0 im Stand oder wenn es noch keines gibt.
  void _cruiseStep(double mean, double dt) {
    if (_decel != null ||
        _accel != null ||
        mean * 3.6 < StatsLimits.cruiseMinKmh) {
      _endCruise();
      return;
    }
    _runPending.add((mean, dt));
    if (_runPending.length <= 2) return;
    final (v, t) = _runPending.removeAt(0);
    _runSeconds += t;
    _runSum += v * t;
    _runSquares += v * v * t;
  }

  void _endCruise() {
    if (_runSeconds >= StatsLimits.cruiseMinSeconds) {
      final m = _runSum / _runSeconds;
      final variance = math.max(0.0, _runSquares / _runSeconds - m * m);
      _cruise += _runSeconds;
      _cruiseVar += variance * _runSeconds;
    }
    _runPending.clear();
    _runSeconds = 0;
    _runSum = 0;
    _runSquares = 0;
  }

  void _commitStand() {
    if (_pendingStand <= 0) return;
    _stand += _pendingStand;
    if (_pendingStand >= RecorderLimits.stopSeconds) {
      _stops++;
      _stopSum += _pendingStand;
      _stopMax = math.max(_stopMax, _pendingStand);
    }
    _pendingStand = 0;
  }

  void _movingStep(
    PositionFix fix,
    double dt,
    double mean,
    RoadLimit road,
    int? limit,
  ) {
    _commitStand();
    _lastMoving = fix.time;
    _moving += dt;
    _distance += mean * dt;
    final kmh = mean * 3.6;
    _speedSeconds[_bin(kmh)] += dt;
    final cls = roadClassOf(road);
    _roadSeconds[cls.index] += dt;
    if (limit != null) {
      final stage = overLimitOf(kmh - limit).index;
      _over[cls]![stage] += dt;
      _limits.putIfAbsent(limit, _LimitAcc.new).seconds[stage] += dt;
    }
    if (_nightAt(fix)) _nightSeconds += dt;
  }

  int _bin(double kmh) =>
      (kmh / StatsLimits.binKmh).floor().clamp(0, StatsLimits.bins - 1);

  bool _nightAt(PositionFix fix) {
    final checked = _nightCheckedAt;
    if (checked == null ||
        fix.time.difference(checked).abs() >= RecorderLimits.nightRecheck) {
      _nightCheckedAt = fix.time;
      _night = isNight(fix.position, fix.time);
    }
    return _night;
  }

  /// Lücke (Tunnel, Funkloch): Luftlinie, keine Beschleunigung.
  void _gap(PositionFix last, PositionFix fix, double dt, double at) {
    _breakChain();
    _chain.add(_Sample(fix.time, fix.speedMps));
    final straight = geo.distanceMeters(last.position, fix.position);
    final mps = straight / dt;
    final standing = mps < RecorderLimits.standMps;
    _trace.add(
      at,
      fix.speedKmh,
      fill: standing ? TraceFill.stand : TraceFill.gap,
    );
    if (mps > RecorderLimits.maxGapMps) return;
    if (standing) {
      _pendingStand += dt;
      return;
    }
    _commitStand();
    _lastMoving = fix.time;
    _moving += dt;
    _distance += straight;
    _speedSeconds[_bin(mps * 3.6)] += dt;
    _roadSeconds[RoadClass.unknown.index] += dt;
    if (_nightAt(fix)) _nightSeconds += dt;
  }

  void _breakChain() {
    _closeDecel();
    _closeAccel();
    _flushDecel();
    _endCruise();
    _chain.clear();
    _smooth.clear();
    _turns.clear();
    _inCurve = false;
  }

  /// Beschleunigung aus dem geglätteten Tempo über 2 s (also über vier Fixe), null solange
  /// die Kette dafür zu kurz ist. Der Median nimmt einzelne Ausreißer ganz heraus.
  double? _kinematics(PositionFix fix, int? limit) {
    _chain.add(_Sample(fix.time, fix.speedMps));
    if (_chain.length > 3) _chain.removeAt(0);
    if (_chain.length < 3) return null;
    final speeds = [for (final s in _chain) s.speed];
    final sustained = speeds.reduce(math.min) * 3.6;
    if (sustained > _maxKmh) _maxKmh = sustained;
    if (limit != null) {
      final acc = _limits.putIfAbsent(limit, _LimitAcc.new);
      acc.maxKmh = math.max(acc.maxKmh, sustained);
    }

    speeds.sort();
    _smooth.add(_Sample(_chain[1].time, speeds[1]));
    if (_smooth.length > 3) _smooth.removeAt(0);
    if (_smooth.length < 3) return null;
    final first = _smooth.first;
    final last = _smooth.last;
    final span = _seconds(first.time, last.time);
    if (span <= 0) return null;
    final a = (last.speed - first.speed) / span;
    if (a.abs() > RecorderLimits.maxPlausibleMps2) {
      // Auch geglättet unmöglich: Messfehler. Neu anfangen, nichts davon zählt.
      _breakChain();
      _chain.add(_Sample(fix.time, fix.speedMps));
      return null;
    }
    final middle = _smooth[1];

    final decel = _decel;
    if (decel == null) {
      if (a <= -RecorderLimits.episodeStartMps2) {
        _decel = _Episode(first.speed, first.time);
      }
    } else if (a > -RecorderLimits.episodeEndMps2) {
      _closeDecel();
    }
    final d = _decel;
    if (d != null) {
      d.peak = math.max(d.peak, -a);
      d.extremeSpeed = math.min(d.extremeSpeed, last.speed);
      d.lastTime = middle.time;
    }

    final accel = _accel;
    if (accel == null) {
      if (a >= RecorderLimits.episodeStartMps2) {
        _accel = _Episode(first.speed, first.time);
      }
    } else if (a < RecorderLimits.episodeEndMps2) {
      _closeAccel();
    }
    final u = _accel;
    if (u != null) {
      u.peak = math.max(u.peak, a);
      u.extremeSpeed = math.max(u.extremeSpeed, last.speed);
      u.lastTime = middle.time;
    }
    return a;
  }

  void _traceEvent(_Episode e, TraceEventKind kind) {
    final start = _start;
    if (start == null || e.peak <= RecorderLimits.gentleMaxMps2) return;
    _trace.event(
      TraceEvent(
        kind: kind,
        second: _seconds(start, e.startTime).round(),
        seconds: _seconds(e.startTime, e.lastTime ?? e.startTime).round(),
        peakMps2: e.peak,
        fromKmh: (e.startSpeed * 3.6).round(),
        toKmh: (e.extremeSpeed * 3.6).round(),
      ),
    );
  }

  /// Eine Verzögerung zählt erst, wenn feststeht, dass keine Delle folgt ([_isDip]).
  void _closeDecel() {
    final d = _decel;
    _decel = null;
    if (d == null) return;
    if (d.startSpeed - d.extremeSpeed < RecorderLimits.episodeMinDeltaMps) {
      return;
    }
    _flushDecel();
    _pendingDecel = d;
  }

  void _flushDecel() {
    final d = _pendingDecel;
    _pendingDecel = null;
    if (d != null) _countDecel(d);
  }

  /// Tempo fällt und ist sofort wieder da, schneller als ein Auto beschleunigen kann: ein
  /// Messfehler des GPS-Tempos, keine Bremsung.
  bool _isDip(_Episode d, _Episode u) {
    final lost = d.startSpeed - d.extremeSpeed;
    final gap = _seconds(d.lastTime ?? d.startTime, u.startTime);
    return gap <= RecorderLimits.dipGapSeconds &&
        u.peak >= RecorderLimits.dipAccelMps2 &&
        u.extremeSpeed - u.startSpeed >= RecorderLimits.dipRecovered * lost;
  }

  void _countDecel(_Episode d) {
    final lost = d.startSpeed - d.extremeSpeed;
    _decelerations++;
    _lost += lost;
    _decelPeaks[peakBinOf(d.peak)]++;
    _maxDecel = math.max(_maxDecel, d.peak);
    _traceEvent(d, TraceEventKind.decel);
    final seconds = _seconds(d.startTime, d.lastTime ?? d.startTime);
    if (d.peak > RecorderLimits.gentleMaxMps2) {
      _brakes++;
      if (d.peak >= RecorderLimits.hardMps2) _hardBrakes++;
    } else if (seconds >= RecorderLimits.gentleMinSeconds) {
      _gentleLost += lost;
    }
  }

  void _closeAccel() {
    final u = _accel;
    _accel = null;
    if (u == null) return;
    final d = _pendingDecel;
    if (d != null && _isDip(d, u)) {
      _pendingDecel = null;
      return;
    }
    _flushDecel();
    if (u.extremeSpeed - u.startSpeed < RecorderLimits.episodeMinDeltaMps) {
      return;
    }
    _accelerations++;
    _accelPeaks[peakBinOf(u.peak)]++;
    _maxAccel = math.max(_maxAccel, u.peak);
    _traceEvent(u, TraceEventKind.accel);
    if (u.startSpeed < RecorderLimits.startFromMps) _starts++;
    if (u.peak >= RecorderLimits.hardMps2) _strong++;
  }

  /// Querbeschleunigung v·ω, ω aus der Kursänderung der letzten zwei Schritte.
  void _curve(PositionFix last, PositionFix fix, double dt, double mean) {
    final h0 = last.headingDeg;
    final h1 = fix.headingDeg;
    if (h0 == null || h1 == null || mean < RecorderLimits.curveMinMps) {
      _turns.clear();
      _inCurve = false;
      return;
    }
    final turn = _turn(h0, h1);
    if (turn.abs() / dt > RecorderLimits.maxTurnDegPerSecond) {
      _turns.clear();
      return;
    }
    _turns.add((turn, dt));
    if (_turns.length > 2) _turns.removeAt(0);
    if (_turns.length < 2) return;
    final deg = _turns.fold(0.0, (s, t) => s + t.$1);
    final seconds = _turns.fold(0.0, (s, t) => s + t.$2);
    final lateral = mean * (deg * math.pi / 180 / seconds).abs();
    if (lateral > _maxLateral) _maxLateral = lateral;
    if (!_inCurve && lateral >= RecorderLimits.sharpCurveMps2) {
      _inCurve = true;
      _curves++;
    } else if (_inCurve && lateral < RecorderLimits.sharpCurveEndMps2) {
      _inCurve = false;
    }
  }

  /// Ergebnis der Warnlogik zu [fix]: erste Ansagen und passierte Blitzer.
  void warnings(PositionFix fix, WarningUpdate update) {
    for (final e in update.events) {
      if (e.stage == WarningStage.announce) _warnings++;
    }
    final present = <String>{};
    for (final w in update.active) {
      final p = w.point;
      if (!_isCamera(p) || _passedCameras.contains(p.id)) continue;
      present.add(p.id);
      final limit = p.maxSpeed ?? update.speedLimitKmh;
      final known = _cameras[p.id];
      if (known == null) {
        _cameras[p.id] = _CameraPass(w.distanceMeters, fix.speedKmh, limit);
      } else if (w.distanceMeters <= known.minDistance) {
        known
          ..minDistance = w.distanceMeters
          ..speedKmh = fix.speedKmh
          ..limitKmh = limit;
      }
    }
    final gone = [
      for (final id in _cameras.keys)
        if (!present.contains(id)) id,
    ];
    for (final id in gone) {
      _resolveCamera(id, RecorderLimits.cameraPassMeters);
    }
  }

  void _resolveCamera(String id, double within) {
    final c = _cameras.remove(id);
    if (c == null || c.minDistance > within) return;
    _passedCameras.add(id);
    _camerasPassed++;
    final limit = c.limitKmh;
    if (limit != null && c.speedKmh > limit + StatsLimits.toleranceKmh) {
      _camerasTooFast++;
    }
  }

  /// Schließt die Fahrt ab. Null, wenn sie zu kurz war. Der Stand am Ende zählt nicht.
  TripSummary? finish(String id) {
    _breakChain();
    for (final camera in [..._cameras.keys]) {
      _resolveCamera(camera, RecorderLimits.cameraPassAtEndMeters);
    }
    _pendingStand = 0;
    return _summary(id, open: false);
  }

  /// Stand der laufenden Fahrt zum Zwischenspeichern, ohne sie abzuschließen. Laufende
  /// Bremsungen, Kurven und Blitzer fehlen darin noch; Ende ist der letzte Fix in Bewegung.
  /// Null, solange die Fahrt zu kurz zum Speichern ist.
  TripSummary? snapshot(String id) => _summary(id, open: true);

  /// Tempoverlauf bis zum letzten Fix in Bewegung. Null, solange es keinen gibt. Nach [finish]
  /// mit allen Vorgängen; während der Fahrt fehlen die laufenden noch.
  TripTrace? trace() {
    final start = _start;
    final end = _lastMoving;
    if (start == null || end == null) return null;
    return _trace.build(_seconds(start, end).round());
  }

  /// So lange steht das Fahrzeug gerade (0 in Bewegung).
  double get standingSeconds => _pendingStand;

  TripSummary? _summary(String id, {required bool open}) {
    final start = _start;
    final end = _lastMoving;
    if (start == null ||
        end == null ||
        _distance < RecorderLimits.minTripMeters ||
        _moving < RecorderLimits.minTripMovingSeconds) {
      return null;
    }
    return TripSummary(
      id: id,
      start: start,
      end: end,
      open: open,
      figures: DriveFigures(
        distanceMeters: _distance,
        movingSeconds: _moving,
        standSeconds: _stand,
        stops: _stops,
        maxKmh: _maxKmh,
        speedSeconds: List.of(_speedSeconds),
        roadSeconds: List.of(_roadSeconds),
        overLimitSeconds: {
          for (final e in _over.entries) e.key: List.of(e.value),
        },
        nightSeconds: _nightSeconds,
        decelerations: _decelerations,
        brakes: _brakes,
        hardBrakes: _hardBrakes,
        speedLostMps: _lost,
        gentleSpeedLostMps: _gentleLost,
        accelerations: _accelerations,
        starts: _starts,
        strongAccelerations: _strong,
        sharpCurves: _curves,
        maxLateralMps2: _maxLateral,
        warnings: _warnings,
        camerasPassed: _camerasPassed,
        camerasTooFast: _camerasTooFast,
        detailSeconds: _moving,
        stopSeconds: _stopSum,
        longestStopSeconds: _stopMax,
        decelPeaks: List.of(_decelPeaks),
        accelPeaks: List.of(_accelPeaks),
        maxDecelMps2: _maxDecel,
        maxAccelMps2: _maxAccel,
        calmSeconds: _calm,
        kinematicSeconds: _kinematic,
        cruiseSeconds: _cruise,
        cruiseVariance: _cruiseVar,
        limits: {
          for (final e in _limits.entries)
            e.key: LimitFigures(
              seconds: List.of(e.value.seconds),
              maxKmh: e.value.maxKmh,
            ),
        },
      ),
    );
  }
}
