import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_settings.dart';
import '../../app/map_layer_settings.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/geo/geo.dart';
import '../../core/contracts/alert_repository.dart';
import '../../core/model/alert_point.dart';
import 'data_coverage.dart';
import 'drive_controller.dart';
import 'drive_state.dart';
import 'drive_zoom.dart';
import 'follow_glide.dart';
import 'loaded_area_layer.dart';
import 'map_attribution.dart';
import 'map_controls.dart';
import 'heat_sheet.dart';
import 'map_data_notice.dart';
import 'map_heat.dart';
import 'map_heat_dots.dart';
import 'map_heat_spots.dart';
import 'map_markers.dart';
import 'map_pins.dart';
import 'map_point_layers.dart';
import 'map_tilt.dart';
import 'point_hits.dart';
import 'point_sheet.dart';
import 'standby_panel.dart';

/// Baut die Karte. Widget-Tests ersetzen das durch einen Platzhalter ohne Netz-Tiles.
final cockpitMapProvider = Provider<WidgetBuilder>(
  (ref) =>
      (_) => const DriveMap(),
);

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _pointsRadius = 3000.0;

/// Ab dieser Strecke seit der letzten Abfrage werden die Kartenpunkte neu geholt.
const _refetchAfterMeters = 250.0;
const _followZoom = 15.5;

/// So lange nach der letzten Kamerabewegung wartet die Karte, bevor sie den Ausschnitt abfragt.
const _viewDebounce = Duration(milliseconds: 350);

/// Solange Punkte oder Kacheln fehlen, fragt die Karte in diesem Takt erneut nach. Die Quellen
/// entscheiden selbst, ob ein neuer Abruf fällig ist (nach einem Fehler frühestens nach einer Minute).
const _retryEvery = Duration(seconds: 30);

/// Übergang zwischen flacher und geneigter Karte: ruhig, nicht verspielt.
const _tiltDuration = Duration(milliseconds: 1100);

/// Graustufen und invertiert, leicht abgedunkelt: helle OSM-Tiles blenden nachts sonst.
const _darkTiles = ColorFilter.matrix(<double>[
  -0.19, -0.64, -0.065, 0, 230, //
  -0.19, -0.64, -0.065, 0, 230, //
  -0.19, -0.64, -0.065, 0, 230, //
  0, 0, 0, 1, 0, //
]);

/// Neigt die Karte gerade: Fahrt, Mitführen, Fahrtrichtung oben und Schalter an.
bool wantsTilt({
  required DriveState drive,
  required AppSettings settings,
  required bool following,
}) =>
    settings.tiltWhileDriving &&
    settings.headingUp &&
    following &&
    drive.running &&
    // Nur die Fahrterkennung zählt, nicht das Tempo: an der Ampel bleibt sie bei „Fahrt“,
    // die Ansicht kippt nicht.
    drive.motion == MotionState.driving;

/// Punkte für den neuen Ausschnitt. Solange er nicht fertig geladen ist, bleiben bisher
/// gezeigte Punkte darin stehen, bis die Abfrage sie liefert: keine Leerphase, kein Flackern.
/// Eigene Hotspots liegen immer vollständig vor; gelöschte verschwinden sofort.
List<AlertPoint> keepWhileLoading({
  required List<AlertPoint> previous,
  required List<AlertPoint> next,
  required GeoBounds view,
  required bool ready,
}) {
  if (ready || previous.isEmpty) return next;
  final known = {for (final p in next) p.id};
  return [
    ...next,
    for (final p in previous)
      if (!known.contains(p.id) &&
          p.source != 'hotspot' &&
          view.contains(p.position))
        p,
  ];
}

class DriveMap extends ConsumerStatefulWidget {
  const DriveMap({super.key});

  @override
  ConsumerState<DriveMap> createState() => _DriveMapState();
}

class _DriveMapState extends ConsumerState<DriveMap>
    with SingleTickerProviderStateMixin {
  final _map = MapController();
  final _heat = HeatCache();
  final _driveZoom = DriveZoom();
  final _glide = FollowGlide();
  final _heading = HeadingSmoother();
  Timer? _glideTimer;
  final _raster = RasterAverage();

  /// Sichtbare Lage zwischen den Fixes; das eigene Symbol der flachen Karte folgt ihr.
  final _pose = ValueNotifier<GlidePose?>(null);

  /// Letzter bekannter Kurs. Im Stand liefert GPS keinen; der Pfeil zeigt dann weiter dorthin.
  double? _lastHeading;
  bool _ready = false;

  /// Die Karte folgt der Position, bis der Nutzer sie anfasst.
  bool _following = true;
  List<AlertPoint> _points = const [];

  /// Blitzer-Hotspots zu [_points], wie sie die Warnlogik bildet; neu nur, wenn sich die
  /// Punkte ändern.
  List<AlertPoint> _spots = const [];
  List<AlertPoint>? _spotsOf;
  GeoPoint? _fetchedAround;
  StreamSubscription<void>? _changes;
  StreamSubscription<void>? _status;
  Timer? _viewTimer;
  Timer? _retry;

  /// Letzter abgefragter Ausschnitt der Übersicht und sein Ladestand.
  GeoBounds? _view;
  DataCoverage? _viewCoverage;

  /// Kartenkacheln kommen nicht an (zuletzt Fehler, seitdem keine geladen).
  bool _tilesFailing = false;
  final _tileReset = StreamController<void>.broadcast();

  late final AnimationController _tilt = AnimationController(
    vsync: this,
    duration: _tiltDuration,
  )..addListener(_onTiltTick);
  bool _tiltTarget = false;
  Size _viewport = Size.zero;

  /// Zuletzt gezeichnete Geometrie; beim nächsten Schritt der Neigung bleibt ihr Drehpunkt fest.
  TiltGeometry? _drawn;

  @override
  void initState() {
    super.initState();
    _changes = ref
        .read(servicesProvider)
        .alerts
        .changes
        .listen((_) => _refresh());
    _status = ref
        .read(servicesProvider)
        .alerts
        .watchStatus()
        .listen((_) => _updateViewCoverage(), onError: (_) {});
    _retry = Timer.periodic(_retryEvery, (_) => _retryMissing());
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  List<AlertPoint> _heatSpots() {
    if (!identical(_points, _spotsOf)) {
      _spotsOf = _points;
      _spots = ref.read(servicesProvider).heatSpots(_points, DateTime.now());
    }
    return _spots;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _raster.add(t.rasterDuration);
    }
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    _retry?.cancel();
    _glideTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _pose.dispose();
    _changes?.cancel();
    _status?.cancel();
    _tileReset.close();
    _tilt.dispose();
    _map.dispose();
    super.dispose();
  }

  TiltGeometry _geometry() => TiltGeometry(
    _viewport,
    Curves.easeInOutCubic.transform(_tilt.value),
    // Beim Mitführen mit Fahrtrichtung oben liegt die Position unter der Mitte: mehr voraus.
    flatPivot: _following && ref.read(appSettingsProvider).headingUp
        ? followPivotFraction
        : 0.5,
  );

  void _fetch(GeoPoint center) {
    if (!mounted) return;
    setState(() {
      _fetchedAround = center;
      _points = ref
          .read(servicesProvider)
          .alerts
          // Mit den vergangenen Beobachtungen: daraus kommen Wärme, rote Punkte und Hotspots.
          // Ohne sie fehlten die drei beim Mitfahren ganz.
          .pointsAround(center, radiusMeters: _pointsRadius, withHistory: true);
    });
  }

  /// Holt die Punkte neu: beim Mitführen rund um die Position, sonst für den sichtbaren
  /// Ausschnitt (Übersicht).
  void _refresh() {
    if (!mounted) return;
    if (_following || !_ready) {
      final at = _fetchedAround;
      if (at != null) _fetch(at);
      return;
    }
    final b = _map.camera.visibleBounds;
    final view = GeoBounds(
      south: b.south,
      west: b.west,
      north: b.north,
      east: b.east,
    );
    final alerts = ref.read(servicesProvider).alerts;
    final coverage = alerts.coverageInView(view);
    final next = alerts.pointsInView(view);
    setState(() {
      _points = keepWhileLoading(
        previous: _points,
        next: next,
        view: view,
        ready: coverage.state == CoverageState.ready,
      );
      _view = view;
      _viewCoverage = coverage;
    });
  }

  void _updateViewCoverage() {
    final view = _view;
    if (!mounted || _following || view == null) return;
    final next = ref.read(servicesProvider).alerts.coverageInView(view);
    if (next != _viewCoverage) setState(() => _viewCoverage = next);
  }

  /// Fehlt noch etwas, erneut nachfragen: Punkte über [_refresh], Kacheln über einen Neuaufbau.
  void _retryMissing() {
    if (!mounted) return;
    if (_tilesFailing) _tileReset.add(null);
    final coverage = _following
        ? ref.read(coverageAroundProvider)
        : _viewCoverage;
    final state = coverage?.state;
    if (state != null && state != CoverageState.ready) _refresh();
  }

  /// Kachelfehler und -erfolge kommen auch während des Aufbaus; der Zustand wechselt danach.
  void _setTilesFailing(bool failing) {
    if (failing == _tilesFailing) return;
    _tilesFailing = failing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _scheduleViewQuery() {
    _viewTimer?.cancel();
    _viewTimer = Timer(_viewDebounce, _refresh);
  }

  /// Setzt [at] auf den Drehpunkt der aktuellen Geometrie (flach: Kartenmitte).
  void _place(LatLng at, double zoom, double rotation) {
    final offset = _geometry().cameraOffset;
    if (offset == Offset.zero) {
      _map.moveAndRotate(at, zoom, rotation);
      return;
    }
    _map.rotate(rotation);
    _map.move(at, zoom, offset: offset);
  }

  void _follow(
    DriveState drive,
    bool headingUp, {
    double? zoom,
    bool newFix = false,
  }) {
    final fix = drive.fix;
    if (fix == null) return;
    final at = _fetchedAround;
    if (_following &&
        (at == null ||
            distanceMeters(at, fix.position) > _refetchAfterMeters)) {
      _fetch(fix.position);
    }
    final z = _ready && _following
        ? _targetZoom(drive, fix.speedMps * 3.6, zoom: zoom, newFix: newFix)
        : _ready
        ? _map.camera.zoom
        : _followZoom;
    final now = DateTime.now();
    if (newFix) {
      final gliding = _glide.onFix(
        position: fix.position,
        headingDeg: fix.headingDeg,
        viewHeadingDeg: _heading.update(fix.headingDeg, fix.speedKmh),
        speedMps: fix.speedMps,
        zoom: z,
        now: now,
        glide: _mayGlide(drive),
      );
      if (gliding) {
        _startGlide(fix.speedKmh);
      } else {
        _stopGlide();
      }
    } else if (_glide.at(now) == null) {
      _glide.jumpTo(
        GlidePose(fix.position, _heading.value ?? fix.headingDeg, z),
      );
    } else {
      // Neigung, Zoom-Sprung, Umschalten der Ausrichtung: Ort bleibt, nur der Zoom folgt.
      _glide.setZoom(z);
    }
    _applyPose(headingUp);
  }

  double _targetZoom(
    DriveState drive,
    double speedKmh, {
    double? zoom,
    required bool newFix,
  }) {
    if (zoom != null) return zoom;
    final camera = _map.camera;
    if (wantsTilt(
      drive: drive,
      settings: ref.read(appSettingsProvider),
      following: true,
    )) {
      // Fahrtansicht: Zoom nach Tempo, nur mit neuem Fix weiter (nicht bei jedem Neige-Frame).
      return newFix
          ? _driveZoom.step(speedKmh, from: camera.zoom)
          : _driveZoom.current ?? camera.zoom;
    }
    _driveZoom.reset();
    // Erster Fix nach der Übersichtskarte: auf Fahrzoom springen, danach Nutzerzoom behalten.
    return camera.zoom < 10 ? _followZoom : camera.zoom;
  }

  /// Gleiten nur bei Fahrt, im Vordergrund und mit Animationen.
  bool _mayGlide(DriveState drive) =>
      drive.driving &&
      (drive.fix?.speedKmh ?? 0) >= GlideRates.minKmh &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      !MediaQuery.disableAnimationsOf(context);

  void _startGlide(double speedKmh) {
    _glideTimer?.cancel();
    final every = glideFrameInterval(
      speedKmh,
      turnDegPerSec: _glide.turnDegPerSec,
      raster: _raster.value,
    );
    _glideTimer = Timer.periodic(every, (_) {
      if (!mounted) return _stopGlide();
      _applyPose(ref.read(appSettingsProvider).headingUp);
      if (!_glide.active(DateTime.now())) _stopGlide();
    });
  }

  void _stopGlide() {
    _glideTimer?.cancel();
    _glideTimer = null;
  }

  /// Setzt Karte und eigenes Symbol auf die Lage, die [_glide] gerade vorgibt.
  void _applyPose(bool headingUp) {
    final pose = _glide.at(DateTime.now());
    if (pose == null) return;
    _pose.value = pose;
    if (!_ready || !_following) return;
    final rotation = !headingUp
        ? 0.0
        : pose.headingDeg != null
        ? -pose.headingDeg!
        : _map.camera.rotation;
    _place(LatLng(pose.position.lat, pose.position.lon), pose.zoom, rotation);
  }

  /// Jeder Schritt der Neigung ändert Größe und Drehpunkt der Karte. Der Punkt am Drehpunkt
  /// bleibt dabei stehen: beim Mitführen die eigene Position, sonst die Stelle der Übersicht.
  void _onTiltTick() {
    if (!mounted) return;
    if (_ready) {
      final drive = ref.read(driveControllerProvider);
      if (_following && drive.fix != null) {
        _follow(drive, ref.read(appSettingsProvider).headingUp);
      } else if (_drawn case final old?) {
        final camera = _map.camera;
        _place(
          camera.screenOffsetToLatLng(old.pivotInMap),
          camera.zoom,
          camera.rotation,
        );
      }
    }
    setState(() {});
  }

  void _syncTilt(bool want) {
    if (want == _tiltTarget) return;
    _tiltTarget = want;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _tiltTarget ? 1.0 : 0.0;
      if (MediaQuery.disableAnimationsOf(context)) {
        _tilt.value = target;
      } else {
        _tilt.animateTo(target);
      }
    });
  }

  /// Tippen auf ein Symbol oder eine Nadel öffnet das Detailblatt, auf ein Bündel dessen Liste.
  void _openAt(TapPosition tap) {
    final geo = _drawn;
    final box = context.findRenderObject();
    if (!_ready || geo == null || box is! RenderBox) return;
    final layers = ref.read(mapLayersProvider);
    // Ab halber Neigung stehen die Nadeln; davor gelten die flachen Symbole.
    final hits = geo.t >= 0.5
        ? tiltedHits(
            points: _points,
            layers: layers,
            camera: _map.camera.withNonRotatedSize(geo.mapRect.size),
            tilt: geo,
            tap: box.globalToLocal(tap.global),
          )
        : flatHits(
            points: _points,
            layers: layers,
            camera: _map.camera,
            tap: tap.relative ?? box.globalToLocal(tap.global),
          );
    if (hits.isNotEmpty) {
      showPointSheet(context, hits);
      return;
    }
    // Kein Symbol getroffen: vielleicht ein roter Punkt oder ein Wärmefleck (nur flach, dort
    // liegen sie lesbar). Am Punkt zählt das Blatt um genau diese Stelle.
    if (geo.t >= 0.5) return;
    final now = DateTime.now();
    final at = tap.relative ?? box.globalToLocal(tap.global);
    final heat = _heat.pointsFor(_points, layers, now);
    final dot = heatDotAt(heatDots(heat, _map.camera), at);
    if (dot != null) {
      showHeatSheet(context, heatCellAround(dot.point.position, heat, now));
      return;
    }
    final spot = heatCellAt(
      cells: _heat.cellsFor(_points, layers, now),
      camera: _map.camera,
      tap: at,
    );
    if (spot != null) showHeatSheet(context, spot);
  }

  void _recenter() {
    _viewTimer?.cancel();
    _fetchedAround = null;
    _view = null;
    _viewCoverage = null;
    setState(() => _following = true);
    // Zentrieren richtet auch nach Fahrtrichtung aus, wie beim Fahren gewünscht.
    if (!ref.read(appSettingsProvider).headingUp) {
      ref
          .read(appSettingsProvider.notifier)
          .change((s) => s.copyWith(headingUp: true));
    }
    final drive = ref.read(driveControllerProvider);
    final settings = ref.read(appSettingsProvider);
    final tilts = wantsTilt(drive: drive, settings: settings, following: true);
    _follow(
      drive,
      true,
      zoom: tilts && drive.fix != null
          ? _driveZoom.jump(drive.fix!.speedMps * 3.6)
          : null,
    );
  }

  /// Kompass: Karte nach Norden. Beim Mitführen heißt das „Norden oben“ (wie im Menü), sonst
  /// dreht nur der Ausschnitt zurück.
  void _northUp() {
    if (_following) {
      ref
          .read(appSettingsProvider.notifier)
          .change((s) => s.copyWith(headingUp: false));
    } else {
      _map.rotate(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drive = ref.watch(driveControllerProvider);
    final settings = ref.watch(appSettingsProvider);
    final headingUp = settings.headingUp;
    ref.listen(driveControllerProvider, (prev, next) {
      if (!identical(prev?.fix, next.fix)) {
        _follow(next, headingUp, newFix: true);
      }
    });
    ref.listen(appSettingsProvider.select((s) => s.headingUp), (_, up) {
      _follow(ref.read(driveControllerProvider), up);
    });
    _syncTilt(
      wantsTilt(drive: drive, settings: settings, following: _following),
    );

    final layers = ref.watch(mapLayersProvider);
    final aroundCoverage = ref.watch(coverageAroundProvider);
    final fix = drive.fix;
    if (fix?.headingDeg case final h?) _lastHeading = h;
    final heading = fix?.headingDeg ?? _lastHeading;
    // Den Ladestand der eigenen Umgebung zeigt das Hinweisfeld über der Karte. Die Karte sagt
    // nur, was dort fehlt: beim Mitführen Kartenbild und Zusatzquellen, in der Übersicht den
    // Stand des Ausschnitts.
    final notice = !drive.running
        ? null
        : _following
        ? followingMapNotice(
            coverage: aroundCoverage,
            tilesFailing: _tilesFailing,
          )
        : mapNoticeFor(
            coverage: _viewCoverage,
            following: false,
            tilesFailing: _tilesFailing,
          );
    // Ruhig bei der Fahrt: der Keil steht dann still.
    final still = isDriving(drive);
    // Der Keil zeigt, dass die eigene Umgebung lädt; er hängt an der Position, nicht am Bildschirm.
    final sweep =
        drive.running &&
        fix != null &&
        aroundCoverage?.state == CoverageState.loading;
    final start = fix == null
        ? const LatLng(51.16, 10.45)
        : LatLng(fix.position.lat, fix.position.lon);

    return LayoutBuilder(
      builder: (context, box) {
        _viewport = box.biggest;
        final geo = _geometry();
        _drawn = geo;
        final rect = geo.mapRect;
        final map = FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: start,
            initialZoom: fix == null ? 6 : _followZoom,
            backgroundColor: SonarColors.bg,
            interactionOptions: const InteractionOptions(
              flags:
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.doubleTapDragZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.pinchMove |
                  InteractiveFlag.rotate |
                  InteractiveFlag.flingAnimation,
              // Drehen erst ab 15°: beim Zoomen mit zwei Fingern dreht die Karte nicht mit.
              rotationThreshold: 15,
            ),
            onPositionChanged: (_, hasGesture) {
              if (hasGesture && _following) {
                setState(() => _following = false);
              }
              if (!_following) _scheduleViewQuery();
            },
            onTap: (tap, _) => _openAt(tap),
            onMapReady: () {
              _ready = true;
              _follow(ref.read(driveControllerProvider), headingUp);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: 'de.fynn.handy.sonarb',
              reset: _tileReset.stream,
              evictErrorTileStrategy:
                  EvictErrorTileStrategy.notVisibleRespectMargin,
              errorTileCallback: (_, _, _) => _setTilesFailing(true),
              tileBuilder: (context, tile, image) {
                if (_tilesFailing &&
                    image.loadFinishedAt != null &&
                    !image.loadError) {
                  _setTilesFailing(false);
                }
                return ColorFiltered(colorFilter: _darkTiles, child: tile);
              },
            ),
            // Umkreis, in dem alle Daten vorliegen; wandert mit der Position. Nur flach: in der
            // Neigung lenkt er von der Straße ab.
            if (layers.contains(MapLayer.loadedAreas) &&
                geo.t < 1 &&
                fix != null)
              Opacity(
                opacity: 1 - geo.t,
                child: DataRadiusLayer(
                  center: fix.position,
                  radiusMeters: settings.detailRadiusMeters,
                  loading: aroundCoverage?.state == CoverageState.loading,
                ),
              ),
            HeatLayer(cells: _heat.cellsFor(_points, layers, DateTime.now())),
            // Genaue Stellen über der Wärme; in der Neigung nur die Wärme, das lenkt weniger ab.
            if (geo.t < 1)
              Opacity(
                opacity: 1 - geo.t,
                child: HeatDotLayer(
                  heat: _heat.pointsFor(_points, layers, DateTime.now()),
                  driving: still,
                ),
              ),
            // Blitzer-Hotspots flach auf der Straße, nur in der Neigung: dort fehlen die roten
            // Punkte, und die Ansage „Blitzer-Hotspot“ soll eine sichtbare Stelle haben.
            if (geo.t > 0 && layers.contains(MapLayer.mobile))
              Opacity(
                opacity: geo.t,
                child: HeatSpotLayer(spots: _heatSpots()),
              ),
            // Flach liegende Symbole weichen in der Neigung den aufrechten Nadeln.
            Opacity(
              opacity: 1 - geo.t,
              child: MapPointLayer(points: _points, layers: layers),
            ),
            // Liegt flach auf der Karte und geht mit Verschieben, Zoom, Drehung und Neigung mit.
            if (sweep)
              _PoseMarkers(
                pose: _pose,
                fallback: fix.position,
                markers: (at, _) => [
                  Marker(
                    point: at,
                    width: box.biggest.shortestSide * 0.84,
                    height: box.biggest.shortestSide * 0.84,
                    child: IgnorePointer(
                      child: SonarSweep(
                        key: const ValueKey('position-sweep'),
                        size: box.biggest.shortestSide * 0.84,
                        still: still,
                        maxAlpha: 0.22,
                        ring: false,
                      ),
                    ),
                  ),
                ],
              ),
            if (fix != null)
              Opacity(
                opacity: 1 - geo.t,
                child: _PoseMarkers(
                  pose: _pose,
                  fallback: fix.position,
                  markers: (at, poseHeading) => [
                    Marker(
                      point: at,
                      width: 76,
                      height: 76,
                      child: OwnPositionMarker(
                        rotationDeg: poseHeading ?? heading,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

        return ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: rect.left,
                top: rect.top,
                width: rect.width,
                height: rect.height,
                child: Transform(transform: geo.matrix, child: map),
              ),
              if (_ready && geo.t > 0) ...[
                TiltHaze(geometry: geo),
                Opacity(
                  opacity: geo.t,
                  child: StreamBuilder<MapEvent>(
                    stream: _map.mapEventStream,
                    builder: (context, _) => PinOverlay(
                      pins: placePins(
                        points: _points,
                        layers: layers,
                        camera: _map.camera.withNonRotatedSize(rect.size),
                        tilt: geo,
                      ),
                    ),
                  ),
                ),
                // Die eigene Position liegt in der Neigung immer am Drehpunkt, Fahrtrichtung
                // oben. Über den Nadeln, damit nahe Punkte sie nicht verdecken.
                if (fix != null)
                  Positioned(
                    left: geo.pivot.dx - 38,
                    top: geo.pivot.dy - 38,
                    width: 76,
                    height: 76,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: geo.t,
                        child: OwnPositionMarker(
                          rotationDeg: heading == null ? null : 0,
                        ),
                      ),
                    ),
                  ),
              ],
              const Positioned.fill(child: MapAttribution()),
              Positioned(
                top: SonarSpace.s,
                right: SonarSpace.s,
                child: const MapMenuButton(),
              ),
              if (_ready)
                Positioned(
                  top: SonarSpace.s * 2 + 48,
                  right: SonarSpace.s,
                  child: StreamBuilder<MapEvent>(
                    stream: _map.mapEventStream,
                    builder: (context, _) {
                      final r = _map.camera.rotation;
                      final off = (((r % 360) + 540) % 360 - 180).abs();
                      return off < 1
                          ? const SizedBox.shrink()
                          : NorthButton(rotationDeg: r, onPressed: _northUp);
                    },
                  ),
                ),
              if (notice != null)
                Positioned(
                  top: SonarSpace.s,
                  left: SonarSpace.s,
                  // Platz für den Schalter rechts daneben.
                  width: (box.maxWidth - 160).clamp(140.0, 320.0),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: MapNoticeBadge(notice: notice, still: still),
                  ),
                ),
              if (!_following)
                Positioned(
                  left: SonarSpace.s,
                  bottom: SonarSpace.xl,
                  child: RecenterButton(onPressed: _recenter),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Marker an der gleitenden Lage; vor dem ersten Fix an [fallback].
class _PoseMarkers extends StatelessWidget {
  const _PoseMarkers({
    required this.pose,
    required this.fallback,
    required this.markers,
  });

  final ValueListenable<GlidePose?> pose;
  final GeoPoint fallback;
  final List<Marker> Function(LatLng at, double? headingDeg) markers;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: pose,
    builder: (context, p, _) {
      final at = p?.position ?? fallback;
      return MarkerLayer(
        markers: markers(LatLng(at.lat, at.lon), p?.headingDeg),
      );
    },
  );
}
