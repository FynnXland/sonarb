import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonarb/app/services.dart';
import 'package:sonarb/core/contracts/alert_audio.dart';
import 'package:sonarb/core/contracts/alert_repository.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/contracts/hotspot_repository.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/core/model/position_fix.dart';
import 'package:sonarb/core/model/road_limit.dart';
import 'package:sonarb/features/cockpit/car_link.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/drive_map.dart';
import 'package:sonarb/features/cockpit/drive_state.dart';
import 'package:sonarb/features/cockpit/location_service.dart';
import 'package:sonarb/features/cockpit/motion_detector.dart';
import 'package:sonarb/features/cockpit/screen_wake.dart';
import 'package:sonarb/features/osm/limit_download.dart';
import 'package:sonarb/features/osm/limit_packages.dart';

PositionFix fixAt(
  double lat,
  double lon, {
  double speedKmh = 50,
  double? heading = 90,
  double accuracy = 5,
}) => PositionFix(
  position: GeoPoint(lat, lon),
  speedMps: speedKmh / 3.6,
  accuracyMeters: accuracy,
  time: DateTime.utc(2026, 10, 29, 12),
  headingDeg: heading,
);

const camera = AlertPoint(
  id: 'osm:node/1',
  kind: AlertKind.speedCamera,
  position: GeoPoint(52.5, 13.41),
  source: 'osm',
  maxSpeed: 50,
);

class FakeLocation implements LocationService {
  LocationAccess access = LocationAccess.granted;
  final controller = StreamController<PositionFix>.broadcast();
  int checks = 0;

  /// Aufrufe mit `request: true`, also solche, die den Berechtigungsdialog zeigen dürfen.
  int requests = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;

  /// Bestellte Modi, in Reihenfolge.
  final modes = <LocationMode>[];

  void emit(PositionFix fix) => controller.add(fix);

  /// So oft [fix], dass die Fahrterkennung auf „driving“ wechselt; danach läuft die Warnlogik.
  /// [fix] muss schneller als [MotionLimits.driveKmh] sein.
  void emitDriving(PositionFix fix) {
    for (var i = 0; i < MotionLimits.confirmFixes; i++) {
      controller.add(fix);
    }
  }

  @override
  Future<LocationAccess> checkAccess({bool request = false}) async {
    checks++;
    if (request) requests++;
    return access;
  }

  @override
  Stream<PositionFix> fixes({LocationMode mode = LocationMode.precise}) {
    modes.add(mode);
    return controller.stream;
  }

  @override
  Future<void> openAppSettings() async => appSettingsOpened++;

  @override
  Future<void> openLocationSettings() async => locationSettingsOpened++;

  @override
  bool googleAccuracyDeclined = false;
  int googleAccuracyPrompts = 0;

  @override
  Future<void> allowGoogleAccuracyPrompt() async {
    googleAccuracyPrompts++;
    googleAccuracyDeclined = false;
  }
}

class FakeEngine implements WarningEngine {
  @override
  WarningSettings settings = const WarningSettings();

  WarningUpdate Function(PositionFix fix, List<AlertPoint> c, int? limit)?
  respond;
  final calls = <(PositionFix, List<AlertPoint>, int?)>[];

  /// [update] je Aufruf: die Strecke voraus.
  final aheadCalls = <List<GeoPoint>?>[];
  int resets = 0;

  @override
  WarningUpdate update(
    PositionFix fix,
    List<AlertPoint> candidates, {
    int? roadSpeedLimitKmh,
    List<GeoPoint>? roadAhead,
  }) {
    calls.add((fix, candidates, roadSpeedLimitKmh));
    aheadCalls.add(roadAhead);
    return respond?.call(fix, candidates, roadSpeedLimitKmh) ??
        WarningUpdate(
          active: const [],
          sounds: const [],
          speedLimitKmh: roadSpeedLimitKmh,
        );
  }

  @override
  void reset() => resets++;
}

class FakeAudio implements AlertAudio {
  final played = <WarningSound>[];
  double volume = 1;
  bool _muted = false;

  @override
  Future<void> init() async {}

  @override
  Future<void> play(WarningSound sound) async => played.add(sound);

  final announced = <WarningEvent>[];
  final statuses = <StatusMessage>[];
  bool _voice = true;

  @override
  Future<void> announce(WarningEvent event) async => announced.add(event);

  @override
  Future<void> announceStatus(StatusMessage message) async =>
      statuses.add(message);

  @override
  bool get voiceEnabled => _voice;

  @override
  Future<void> setVoiceEnabled(bool enabled) async => _voice = enabled;

  Set<Announcement> _silenced = const {};
  final previews = <Announcement>[];

  @override
  Set<Announcement> get silenced => _silenced;

  @override
  Future<void> setSilenced(Set<Announcement> silenced) async =>
      _silenced = Set.unmodifiable(silenced);

  @override
  Future<void> preview(Announcement announcement) async =>
      previews.add(announcement);

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  bool get muted => _muted;

  @override
  Future<void> setMuted(bool m) async => _muted = m;

  @override
  Future<void> dispose() async {}
}

class FakeAlerts implements AlertRepository {
  @override
  DataScope dataScope = const DataScope();

  List<AlertPoint> points = const [];
  int? limit;

  /// Ohne Zahl: gilt hier ausdrücklich kein Limit?
  bool noLimit = false;
  final pointCalls = <GeoPoint>[];
  final changesController = StreamController<void>.broadcast();
  List<SourceStatus> statuses = const [];
  @override
  List<DataSourcePlugin> plugins = const [];

  @override
  List<AlertPoint> pointsAround(
    GeoPoint center, {
    double radiusMeters = 3000,
    bool withHistory = false,
  }) {
    pointCalls.add(center);
    historyCalls.add(withHistory);
    // Wie die echte Quelle: vergangene Beobachtungen nur auf Wunsch.
    return [
      for (final p in points)
        if (withHistory || !p.historical) p,
    ];
  }

  /// [pointsAround] je Aufruf: mit vergangenen Beobachtungen?
  final historyCalls = <bool>[];

  final viewCalls = <GeoBounds>[];

  @override
  List<AlertPoint> pointsInView(GeoBounds view) {
    viewCalls.add(view);
    return [
      for (final p in points)
        if (view.contains(p.position)) p,
    ];
  }

  @override
  Stream<void> get changes => changesController.stream;

  /// Ladestand um die Position und im Ausschnitt; Änderungen über [statusController] melden.
  DataCoverage coverage = DataCoverage.ready;
  DataCoverage viewCoverage = DataCoverage.ready;

  @override
  DataCoverage coverageAround(GeoPoint center) => coverage;

  @override
  DataCoverage coverageInView(GeoBounds view) => viewCoverage;

  /// Geladene Gebiete, wie sie [loadedAreasIn] liefert (ungefiltert).
  List<GeoBounds> loadedAreas = const [];

  @override
  List<GeoBounds> loadedAreasIn(GeoBounds view) => loadedAreas;

  final statusController = StreamController<List<SourceStatus>>.broadcast();

  @override
  Stream<List<SourceStatus>> watchStatus() async* {
    yield statuses;
    yield* statusController.stream;
  }

  @override
  Future<int?> speedLimitAt(GeoPoint position, double? headingDeg) async =>
      limit;

  @override
  Future<RoadLimit> roadLimitAt(GeoPoint position, double? headingDeg) async =>
      switch (limit) {
        final kmh? => RoadLimit.kmh(kmh),
        null when noLimit => const RoadLimit.none(),
        null => const RoadLimit.unknown(),
      };

  /// Antwort von [roadAheadAt].
  List<GeoPoint>? ahead;

  @override
  Future<List<GeoPoint>?> roadAheadAt(
    GeoPoint position,
    double headingDeg,
  ) async => ahead;

  @override
  bool isPluginEnabled(String pluginId) => false;

  @override
  Future<void> setPluginEnabled(String pluginId, bool enabled) async {}

  @override
  Future<void> dispose() async {}
}

class FakeOsm implements FixedPointSource {
  int size = 2 * 1024 * 1024;
  int clears = 0;

  @override
  Future<SourceResult> load(GeoBounds area) async =>
      const SourceResult(points: []);

  @override
  Future<SourceResult> loadCameras(GeoBounds area) => load(area);

  @override
  Future<int?> speedLimitAt(GeoPoint position, double? headingDeg) async =>
      null;

  @override
  Future<RoadLimit> roadLimitAt(GeoPoint position, double? headingDeg) async =>
      const RoadLimit.unknown();

  @override
  Future<List<GeoPoint>?> roadAheadAt(
    GeoPoint position,
    double headingDeg,
  ) async => null;

  @override
  List<GeoBounds> loadedCameraTilesIn(GeoBounds view) => const [];

  @override
  Future<void> clearCache() async {
    clears++;
    size = 0;
  }

  @override
  Future<int> cacheSizeBytes() async => size;
}

class FakeHotspots implements HotspotRepository {
  @override
  Future<void> flush() async {}

  @override
  Future<void> dispose() async {}

  final items = <Hotspot>[];
  final _controller = StreamController<List<Hotspot>>.broadcast();
  final added = <(GeoPoint, double?)>[];
  final kinds = <HotspotKind>[];
  int undos = 0;
  Object? importError;
  HotspotImportResult importResult = const HotspotImportResult(
    added: 3,
    skippedDuplicates: 1,
    invalid: 0,
  );
  String? lastImported;

  void _emit() => _controller.add(List.of(items));

  @override
  Stream<List<Hotspot>> watch() async* {
    yield List.of(items);
    yield* _controller.stream;
  }

  @override
  Future<List<Hotspot>> all() async => List.of(items);

  @override
  Future<Hotspot> addAt(
    GeoPoint position, {
    double? headingDeg,
    HotspotKind kind = HotspotKind.mobileCamera,
  }) async {
    added.add((position, headingDeg));
    kinds.add(kind);
    final h = Hotspot(
      id: 'h${added.length}',
      position: position,
      createdAt: DateTime.utc(2026, 10, 29, 12),
      kind: kind,
      headingDeg: headingDeg,
    );
    items.insert(0, h);
    _emit();
    return h;
  }

  @override
  Future<void> update(Hotspot hotspot) async {
    final i = items.indexWhere((h) => h.id == hotspot.id);
    if (i >= 0) items[i] = hotspot;
    _emit();
  }

  @override
  Future<void> remove(String id) async {
    items.removeWhere((h) => h.id == id);
    _emit();
  }

  @override
  Future<void> undoLast() async {
    undos++;
    if (items.isNotEmpty) items.removeAt(0);
    _emit();
  }

  @override
  Future<String> exportJson() async => '{"version":1,"hotspots":[]}';

  @override
  Future<HotspotImportResult> importJson(String json) async {
    lastImported = json;
    final e = importError;
    if (e != null) throw e;
    return importResult;
  }
}

class FakeWake implements ScreenWake {
  final calls = <bool>[];

  @override
  Future<void> setOn(bool on) async => calls.add(on);
}

class FakeCarLink implements CarLink {
  final controller = StreamController<bool>.broadcast();
  bool initial = false;

  @override
  Stream<bool> watch() async* {
    yield initial;
    yield* controller.stream;
  }
}

class FakeCompanion implements DriveCompanion {
  final starts = <DriveState>[];
  final changes = <DriveState>[];
  int stops = 0;
  final stopsByUser = <bool>[];

  /// Hält [stopped] an, bis der Test es freigibt (Dienst braucht Zeit zum Beenden).
  Completer<void>? stopGate;

  @override
  Future<void> started(DriveState state) async => starts.add(state);

  @override
  void changed(DriveState state) => changes.add(state);

  @override
  Future<void> stopped({bool byUser = false}) async {
    stops++;
    stopsByUser.add(byUser);
    await stopGate?.future;
  }
}

/// Alle Fakes zusammen plus passende Overrides.
class TestRig {
  TestRig(this.prefs);

  final SharedPreferences prefs;
  final location = FakeLocation();
  final engine = FakeEngine();
  final audio = FakeAudio();
  final alerts = FakeAlerts();
  final osm = FakeOsm();
  final hotspots = FakeHotspots();
  final wake = FakeWake();
  final companion = FakeCompanion();
  final carLink = FakeCarLink();

  static Future<TestRig> create() async {
    SharedPreferences.setMockInitialValues({});
    return TestRig(await SharedPreferences.getInstance());
  }

  late final services = AppServices(
    osm: osm,
    hotspots: hotspots,
    audio: audio,
    engine: engine,
    alerts: alerts,
    prefs: prefs,
    limitPackages: LimitPackages(
      Directory.systemTemp.createTempSync('rig_limit_packages'),
    ),
    limitDownloader: LimitDownloader(
      catalogUrl: Uri.parse('http://127.0.0.1:9/'),
    ),
  );

  List<Override> get overrides => overridesWithCompanion(
    driveCompanionProvider.overrideWithValue(companion),
  );

  /// Wie [overrides], aber mit eigenem Begleiter (etwa der echten BackgroundCompanion).
  List<Override> overridesWithCompanion(Override companionOverride) => [
    servicesProvider.overrideWithValue(services),
    locationServiceProvider.overrideWithValue(location),
    screenWakeProvider.overrideWithValue(wake),
    companionOverride,
    carLinkProvider.overrideWithValue(carLink),
    cockpitMapProvider.overrideWithValue(
      (_) => const ColoredBox(
        color: Color(0xFF222222),
        child: SizedBox.expand(key: Key('map-placeholder')),
      ),
    ),
  ];

  ProviderContainer container() => ProviderContainer.test(overrides: overrides);
}
