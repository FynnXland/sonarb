import 'dart:math' as math;

import '../../core/contracts/warning_engine.dart';
import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import '../../core/model/heat_spot.dart';
import '../../core/model/position_fix.dart';
import 'point_class.dart';
import 'course_line.dart';
import 'heat_spots.dart';
import 'point_state.dart';
import 'road_course.dart';
import 'stage_zones.dart';

export 'course_line.dart' show offCourse, signedTurn;
export 'stage_zones.dart';

/// Ungenauer als das, oder eine Lücke seit dem letzten Fix: das Tempo gilt als unsicher.
const double _speedAccuracyMeters = 30;
const Duration _speedGap = Duration(seconds: 4);

/// Dicht folgende Hotspots: höchstens eine Ansage je so viele Sekunden, die übrigen still.
/// Bei 50 km/h liegen zwei Hotspots (mindestens 300 m) gut 20 s auseinander.
const Duration _heatSpotGap = Duration(seconds: 20);

/// Abstand steigt um so viel über das Minimum und der Punkt liegt neben oder hinter einem:
/// abgebogen. Nach [_awayFixes] Fixes in Folge endet die Warnung still.
const double _awayRiseMeters = 10;
const double _awayDeg = 70;
const int _awayFixes = 2;

/// So viele Fixes in Folge neben der Strecke voraus, dann endet eine Hinweis-Warnung still.
const int _offRoadFixes = 2;

/// Punkte derselben Art so nah beieinander gelten als eine Stelle (zwei Quellen, oder ein
/// Paar je Fahrtrichtung, bei dem einem die Richtung fehlt).
const double _sameSpotMeters = 50;

const double _minCourseSpeedMps = 2;
const double _maxAccuracyMeters = 50;
const double _nearMeters = 40;
const double _nearConeDeg = 90;
const double _trackedConeBonusDeg = 20;
const double _passedBehindDeg = 100;
const double _passedBehindMeters = 60;
const double _passedRecedeMeters = 50;

/// So viele Fixes in Folge muss ein Hinweis auf der Linie liegen, bevor er angesagt wird. In
/// Kurven und beim Abbiegen streift die gerade Kurslinie fremde Straßen nur kurz.
const int _hintFixes = 3;

const double _metersPerDegree = earthRadiusMeters * math.pi / 180;

class DefaultWarningEngine implements WarningEngine {
  DefaultWarningEngine(this.settings);

  @override
  WarningSettings settings;

  final Map<String, PointState> _states = {};

  /// Hinweise, die noch nicht angesagt sind: (Treffer in Folge, letzter Schritt).
  final Map<String, (int, int)> _hintHits = {};

  /// Letzte Fixes der Fahrt (Position, Kurs) für die Krümmung.
  final List<(GeoPoint, double)> _trail = [];
  final HeatSpotCache _heatSpots = HeatSpotCache();
  final RoadCourse _road = RoadCourse();
  int _tick = 0;
  DateTime? _lastFix;
  DateTime? _lastHeatSpot;

  /// Anzahl gehaltener Punktzustände (für Tests).
  int get trackedPointCount => _states.length;

  @override
  void reset() {
    _states.clear();
    _hintHits.clear();
    _trail.clear();
    _road.reset();
    _lastFix = null;
    _lastHeatSpot = null;
  }

  @override
  WarningUpdate update(
    PositionFix fix,
    List<AlertPoint> candidates, {
    int? roadSpeedLimitKmh,
    List<GeoPoint>? roadAhead,
  }) {
    // Lücke = es kamen keine Fixes. Stillstand an der Ampel zählt nicht, die Fixes kommen weiter.
    final last = _lastFix;
    _lastFix = fix.time;
    final gap = last != null && fix.time.difference(last) > _speedGap;
    final heading = fix.headingDeg;
    final hold =
        fix.accuracyMeters > _maxAccuracyMeters ||
        heading == null ||
        fix.speedMps < _minCourseSpeedMps;
    if (hold) return _hold(fix, candidates, roadSpeedLimitKmh);
    _road.update(fix.position, roadAhead);
    return _step(fix, heading, candidates, roadSpeedLimitKmh, gap: gap);
  }

  /// Keine neuen Warnungen, bisherige Anzeige bleibt (Ampel, schwaches GPS).
  WarningUpdate _hold(PositionFix fix, List<AlertPoint> candidates, int? road) {
    final active = <ActiveWarning>[];
    for (final p in candidates) {
      final st = _states[p.id];
      if (st == null || !st.shown || st.passed) continue;
      if (trackingOf(p) == Tracking.none) continue;
      if (p.kind == AlertKind.hotspot && !settings.hotspotsEnabled) continue;
      active.add(_active(p, distanceMeters(fix.position, p.position), st));
    }
    return _result(fix, active, road);
  }

  WarningUpdate _step(
    PositionFix fix,
    double heading,
    List<AlertPoint> candidates,
    int? road, {
    required bool gap,
  }) {
    final s = settings;
    final pos = fix.position;
    _tick++;
    // Lieber eine Erinnerung zu viel: nach einer GPS-Lücke ist das Tempo dazwischen unbekannt.
    final speedUnsure = gap || fix.accuracyMeters > _speedAccuracyMeters;
    // Wer weiter weg war, wird bei erneuter Annäherung wieder angesagt (Hysterese).
    final rearm = s.lookAheadMeters;
    if (gap) _trail.clear();
    _trail.add((pos, heading));
    if (_trail.length > trailFixes) _trail.removeAt(0);
    final curvature = curvatureOf(_trail);
    final cosLat = math.cos(pos.lat * math.pi / 180);
    final recede = math.max(_passedRecedeMeters, 2 * fix.accuracyMeters);

    final active = <ActiveWarning>[];
    final events = <WarningEvent>[];

    // Hotspots kommen zu den Kandidaten, außer wo schon ein Blitzer steht.
    final spots = s.heatSpotsEnabled
        ? heatSpotsWithoutCamera(
            _heatSpots.spotsIn(
              candidates,
              fix.time,
              minReports: s.heatSpotMinReports,
            ),
            candidates,
            (c) => _directionOk(c, heading),
          )
        : const <AlertPoint>[];

    for (final p in [...candidates, ...spots]) {
      final tracking = trackingOf(p);
      if (tracking == Tracking.none) continue;
      if (p.kind == AlertKind.hotspot && !s.hotspotsEnabled) continue;

      // Grober Vorfilter ohne trigonometrische Funktionen pro Punkt.
      var dLon = p.position.lon - pos.lon;
      if (dLon > 180) {
        dLon -= 360;
      } else if (dLon < -180) {
        dLon += 360;
      }
      final dx = dLon * cosLat * _metersPerDegree;
      final dy = (p.position.lat - pos.lat) * _metersPerDegree;
      if (dx.abs() > rearm || dy.abs() > rearm) continue;
      final d = distanceMeters(pos, p.position);
      if (d > rearm) continue;

      final limit = p.maxSpeed ?? road;
      final zones = zonesFor(tracking, p, s, fix.speedMps, limit);
      final announceZone = zones.announce;
      var st = _states[p.id];
      if (st == null) {
        // Hinweise werden schon kurz vor ihrer Zone beobachtet, damit die Treffer in Folge
        // die Ansage nicht verspäten.
        final watch = tracking == Tracking.announceOnly
            ? announceZone + _hintFixes * fix.speedMps
            : announceZone;
        if (d >= watch) continue;
      } else {
        st.seenTick = _tick;
        if (st.passed) {
          st.shown = false;
          continue;
        }
      }

      final diff = angleDifference(heading, bearingDegrees(pos, p.position));
      final lateral = d * math.sin(math.min(diff, 90) * math.pi / 180);
      final fast = isFast(fix.speedMps);
      // Hinweise nach der Strecke voraus, wenn es Straßendaten gibt; Blitzer wie bisher.
      final onLine = tracking == Tracking.announceOnly
          ? _road.verdict(p.position, d, tracked: st != null)
          : RoadVerdict.unknown;
      if (st != null) {
        // Neben der Strecke, der man folgt (abgefahren, Vorfahrt knickt ab): still beenden.
        st.offRoadCount = onLine == RoadVerdict.offRoad
            ? st.offRoadCount + 1
            : 0;
        if (st.offRoadCount >= _offRoadFixes) {
          st.passed = true;
          st.shown = false;
          continue;
        }
        if (d < st.minDistance) st.minDistance = d;
        // Kurs führt klar weg (abgebogen): still beenden, ohne Ansage.
        final rising = d > st.minDistance + _awayRiseMeters;
        final aside =
            diff > _awayDeg ||
            lateral > lineTolerance(tracking, d, fast: fast, hide: true);
        st.awayCount = rising && aside ? st.awayCount + 1 : 0;
        if ((diff > _passedBehindDeg && d < _passedBehindMeters) ||
            d > st.minDistance + recede ||
            st.awayCount >= _awayFixes) {
          st.passed = true;
          st.shown = false;
          continue;
        }
      }

      if (!_directionOk(p, heading)) {
        st?.shown = false;
        continue;
      }
      var cone = d < _nearMeters
          ? math.max(s.aheadConeDeg, _nearConeDeg)
          : s.aheadConeDeg;
      if (st != null) cone = math.min(180, cone + _trackedConeBonusDeg);
      if (diff > cone && onLine != RoadVerdict.onRoad) {
        st?.shown = false;
        continue;
      }

      if (st == null) {
        // Seitlich an einer Kreuzung, nicht auf der Fahrtlinie: (noch) nicht ansagen.
        if (onLine == RoadVerdict.offRoad) continue;
        final off = tracking == Tracking.announceOnly
            ? offCourse(d, bearingDegrees(pos, p.position), heading, curvature)
            : lateral;
        if (onLine != RoadVerdict.onRoad &&
            off > lineTolerance(tracking, d, fast: fast)) {
          continue;
        }
        if (tracking == Tracking.announceOnly &&
            !_hintSteady(p.id, d, announceZone)) {
          continue;
        }
        st = PointState(p, d)
          ..seenTick = _tick
          ..follows = _sameSpotAs(p, tracking);
        _states[p.id] = st;
      } else if (onLine != RoadVerdict.onRoad &&
          lateral > lineTolerance(tracking, d, fast: fast, hide: true)) {
        st.shown = false;
        continue;
      }
      st
        ..point = p
        ..distance = d;
      // An derselben Stelle warnt schon ein anderer Punkt.
      if (st.follows != null) {
        st.shown = false;
        continue;
      }

      final reached = zones.stageAt(d);
      final before = st.stage;
      if (reached != null && (before == null || reached.index > before.index)) {
        st.stage = reached;
      }
      if (before == null) {
        // Die erste Meldung ist immer announce, damit die Sprachansage kommt. Sie steht
        // für die schon erreichte Stufe; die kommt nicht noch einmal hinterher.
        st.fired = st.stage!;
        if (!isHeatSpot(p) || _heatSpotDue(fix.time)) {
          events.add(_event(p, WarningStage.announce, d));
        }
      } else if (tracking == Tracking.staged) {
        final due = st.stage!;
        final speeding =
            limit != null &&
            (speedUnsure || fix.speedKmh > limit + s.overspeedToleranceKmh);
        // Nur die tiefste erreichte Stufe zählt, übersprungene werden nicht nachgeholt.
        if (due != WarningStage.announce &&
            due.index > st.fired.index &&
            (!s.onlyWhenSpeeding || speeding)) {
          st.fired = due;
          events.add(_event(p, due, d));
        }
      }

      st.shown = true;
      // Hotspots nur als Ton, die Anzeige bleibt aktuellen Punkten vorbehalten.
      if (!isHeatSpot(p)) active.add(_active(p, d, st));
    }

    _hintHits.removeWhere((_, hit) => hit.$2 < _tick);
    _cleanUp(pos, rearm);
    events.sort(compareEvents);
    return _result(fix, active, road, events: events);
  }

  /// True, wenn die letzte Hotspot-Ansage mindestens [_heatSpotGap] zurückliegt; merkt sich
  /// dann diese.
  bool _heatSpotDue(DateTime now) {
    final last = _lastHeatSpot;
    if (last != null && now.difference(last) < _heatSpotGap) return false;
    _lastHeatSpot = now;
    return true;
  }

  /// Zählt einen Treffer auf der Linie; true, wenn der Hinweis [_hintFixes] Fixes in Folge
  /// auf der Linie lag und in seiner Zone ist.
  bool _hintSteady(String id, double d, double zone) {
    final last = _hintHits[id];
    final hits = last != null && last.$2 == _tick - 1 ? last.$1 + 1 : 1;
    _hintHits[id] = (hits, _tick);
    if (hits < _hintFixes || d >= zone) return false;
    _hintHits.remove(id);
    return true;
  }

  /// ID eines schon verfolgten Punkts derselben Art an derselben Stelle, sonst null.
  /// Blitzer gelten untereinander als gleich, Hinweise nur bei gleicher Kategorie.
  String? _sameSpotAs(AlertPoint p, Tracking tracking) {
    final category = p.effectiveCategory;
    for (final MapEntry(key: id, value: other) in _states.entries) {
      if (id == p.id || other.follows != null) continue;
      final o = other.point;
      if (trackingOf(o) != tracking) continue;
      if (tracking != Tracking.staged && o.effectiveCategory != category) {
        continue;
      }
      if (distanceMeters(o.position, p.position) <= _sameSpotMeters) return id;
    }
    return null;
  }

  static WarningEvent _event(AlertPoint p, WarningStage stage, double d) =>
      WarningEvent(point: p, stage: stage, distanceMeters: d);

  static ActiveWarning _active(AlertPoint p, double d, PointState st) =>
      ActiveWarning(
        point: p,
        distanceMeters: d,
        level: st.level,
        stage: st.stage,
      );

  /// Zustände von Punkten, die diesen Schritt nicht gesehen wurden: weit weg → vergessen.
  void _cleanUp(GeoPoint pos, double rearm) {
    _states.removeWhere((_, st) {
      if (st.seenTick == _tick) return false;
      st.shown = false;
      return distanceMeters(pos, st.point.position) > rearm;
    });
  }

  bool _directionOk(AlertPoint p, double heading) {
    if (p.travelBearings.isEmpty) return true;
    for (final b in p.travelBearings) {
      if (angleDifference(heading, b) <= settings.headingToleranceDeg) {
        return true;
      }
    }
    return false;
  }

  WarningUpdate _result(
    PositionFix fix,
    List<ActiveWarning> active,
    int? road, {
    List<WarningEvent> events = const [],
  }) {
    active.sort(compareActive);
    final first = active.isEmpty ? null : active.first;
    int? limit;
    if (first != null && isMainCamera(first)) limit = first.point.maxSpeed;
    limit ??= road;
    final over =
        limit != null && fix.speedKmh > limit + settings.overspeedToleranceKmh;
    return WarningUpdate(
      active: active,
      events: events,
      speedLimitKmh: limit,
      overspeed: over,
    );
  }
}
