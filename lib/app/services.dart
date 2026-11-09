import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/contracts/alert_audio.dart';
import '../core/contracts/alert_repository.dart';
import '../core/contracts/fixed_point_source.dart';
import '../core/contracts/hotspot_repository.dart';
import '../core/contracts/warning_engine.dart';
import '../core/model/alert_point.dart';
import '../features/alerts/alerts.dart';
import '../features/audio/audio.dart';
import '../features/background/background.dart';
import '../features/cockpit/drive_controller.dart';
import '../features/cockpit/drive_state.dart';
import '../features/cockpit/map_heat_spots.dart';
import '../features/hotspots/hotspots.dart';
import '../features/osm/limit_download.dart';
import '../features/osm/limit_packages.dart';
import '../features/osm/osm.dart';
import '../features/warning/heat_spots.dart';
import '../features/warning/warning.dart';
import '../plugins/installed_plugins.dart';
import 'app_settings.dart';

/// Alle Module nach dem Start. Tests bauen das mit Fakes und überschreiben [servicesProvider].
class AppServices {
  AppServices({
    required this.osm,
    required this.hotspots,
    required this.audio,
    required this.engine,
    required this.alerts,
    required this.prefs,
    required this.limitPackages,
    required this.limitDownloader,
    this.heatSpots = noHeatSpots,
  });

  final FixedPointSource osm;
  final HotspotRepository hotspots;
  final AlertAudio audio;
  final WarningEngine engine;
  final AlertRepository alerts;
  final SharedPreferences prefs;

  /// Tempolimit-Pakete auf dem Gerät und ihr Download; `osm` liest dieselben Pakete.
  final LimitPackages limitPackages;
  final LimitDownloader limitDownloader;

  /// Blitzer-Hotspots für die Karte, wie sie die Warnlogik bildet ([createHeatSpotFinder]).
  final HeatSpotFinder heatSpots;

  Future<void> dispose() async {
    await alerts.dispose();
    await hotspots.dispose();
    await audio.dispose();
  }
}

/// Ohne Warnlogik (Tests): keine Hotspots auf der Karte.
List<AlertPoint> noHeatSpots(List<AlertPoint> points, DateTime now) => const [];

/// Hotspots für die Karte mit derselben Erkennung und derselben Stufe wie die Ansage, damit
/// Karte und Ton dieselben Stellen zeigen. [minReports] liest die gewählte Stufe, in der App
/// aus den Einstellungen der Warnlogik. Eigener Zwischenspeicher, gleiche Ergebnisse.
HeatSpotFinder createHeatSpotFinder({int Function()? minReports}) {
  final cache = HeatSpotCache();
  return (points, now) => cache.spotsIn(
    points,
    now,
    minReports: minReports?.call() ?? defaultHeatSpotReports,
  );
}

/// Startet alle Module in der Reihenfolge, die die Verträge verlangen.
Future<AppServices> startServices() async {
  final support = await getApplicationSupportDirectory();
  final cacheDir = Directory('${support.path}${Platform.pathSeparator}osm');
  final dataDir = Directory('${support.path}${Platform.pathSeparator}hotspots');
  await cacheDir.create(recursive: true);
  await dataDir.create(recursive: true);

  final prefs = await SharedPreferences.getInstance();
  final limitPackages = LimitPackages(
    Directory('${cacheDir.path}${Platform.pathSeparator}limit_packages'),
  );
  final osm = createOsmSource(cacheDir: cacheDir, limitPackages: limitPackages);
  final hotspots = await createHotspotRepository(dataDir: dataDir);
  final audio = createAlertAudio();
  await audio.init();
  final engine = createWarningEngine();
  final alerts = createAlertRepository(
    osm: osm,
    hotspots: hotspots,
    plugins: installedPlugins(),
    prefs: prefs,
    dataDir: dataDir,
  );
  final services = AppServices(
    osm: osm,
    hotspots: hotspots,
    audio: audio,
    engine: engine,
    alerts: alerts,
    prefs: prefs,
    limitPackages: limitPackages,
    limitDownloader: LimitDownloader(catalogUrl: Uri.parse(limitCatalogUrl)),
    heatSpots: createHeatSpotFinder(
      minReports: () => engine.settings.heatSpotMinReports,
    ),
  );
  await AppSettings.load(prefs).applyTo(services);
  return services;
}

/// Startvorgang. Kein automatisches Wiederholen: Fehler werden angezeigt, der Nutzer startet neu.
final bootstrapProvider = FutureProvider<AppServices>((ref) async {
  final services = await startServices();
  ref.onDispose(services.dispose);
  return services;
}, retry: (_, _) => null);

/// Nur lesen, wenn [bootstrapProvider] fertig ist (die Oberfläche baut erst danach).
final servicesProvider = Provider<AppServices>(
  (ref) => ref.watch(bootstrapProvider).requireValue,
);

/// Hintergrunddienst und Benachrichtigung zur Überwachung. Tests ersetzen das durch einen Fake.
final driveCompanionProvider = Provider<DriveCompanion>((ref) {
  final companion = BackgroundCompanion(ref, createBackgroundMonitor());
  ref.onDispose(companion.dispose);
  return companion;
});

/// Inhalt der Benachrichtigung aus dem Fahrtzustand.
MonitorSnapshot monitorSnapshotOf(DriveState s) {
  final next = s.upcoming.isNotEmpty ? s.upcoming.first : s.primary;
  return MonitorSnapshot(
    driving: s.driving,
    speedKmh: s.fix?.speedKmh,
    limitKmh: s.speedLimitKmh,
    next: next?.point,
    nextMeters: next?.distanceMeters,
    gpsLost: s.gpsLost,
    dataUnavailable: s.dataUnavailable,
  );
}

/// Verbindet die Überwachung mit dem Hintergrunddienst. Beenden (Knopf im Cockpit oder in der
/// Benachrichtigung) stoppt beides; erst das nächste Öffnen der App startet wieder.
class BackgroundCompanion implements DriveCompanion {
  BackgroundCompanion(this._ref, this._monitor);

  final Ref _ref;
  final BackgroundMonitor _monitor;
  StreamSubscription<void>? _stopRequests;
  AppLifecycleListener? _lifecycle;

  /// Nach „Beenden“: neu starten, sobald die App wieder geöffnet wird.
  bool _restartOnOpen = false;
  bool _hiddenSinceStop = false;

  @override
  Future<void> started(DriveState state) async {
    _restartOnOpen = false;
    _stopRequests ??= _monitor.stopRequests.listen(
      (_) => unawaited(_onStopRequest()),
    );
    _lifecycle ??= AppLifecycleListener(
      onHide: () => _hiddenSinceStop = true,
      onShow: _onShow,
    );
    await _monitor.start(monitorSnapshotOf(state));
  }

  @override
  void changed(DriveState state) => _monitor.show(monitorSnapshotOf(state));

  @override
  Future<void> stopped({bool byUser = false}) {
    if (byUser) {
      _restartOnOpen = true;
      _hiddenSinceStop = !_visible;
    }
    return _monitor.stop();
  }

  bool get _visible => switch (WidgetsBinding.instance.lifecycleState) {
    AppLifecycleState.resumed || AppLifecycleState.inactive => true,
    _ => false,
  };

  /// „Beenden“ in der Benachrichtigung.
  Future<void> _onStopRequest() async {
    final visible = _visible;
    await _ref.read(driveControllerProvider.notifier).stop();
    // Sichtbar und gestoppt sähe aus wie eine hängende App: in den Hintergrund damit.
    if (visible) await _monitor.leaveForeground();
  }

  /// Erst nach echtem Verlassen neu starten. Schließen der Benachrichtigungsleiste allein
  /// meldet ebenfalls „sichtbar“ und darf „Beenden“ nicht aufheben.
  void _onShow() {
    if (!_restartOnOpen || !_hiddenSinceStop) return;
    _restartOnOpen = false;
    final controller = _ref.read(driveControllerProvider.notifier);
    if (_ref.read(driveControllerProvider).phase == DrivePhase.idle) {
      unawaited(controller.start());
    }
  }

  void dispose() {
    _stopRequests?.cancel();
    _lifecycle?.dispose();
  }
}
