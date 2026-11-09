import 'dart:async';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/contracts/alert_repository.dart';
import '../../core/contracts/data_source_plugin.dart';
import '../../core/contracts/fixed_point_source.dart';
import '../../core/contracts/hotspot_repository.dart';
import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import '../../core/model/road_limit.dart';
import '../osm/country_cameras.dart';
import '../osm/staged_source.dart';
import 'country_loader.dart';
import 'load_stages.dart';
import 'merge_points.dart';
import 'mobile_history.dart';
import 'overview_loader.dart';
import 'plugin_slot.dart';
import 'point_store.dart';
import 'point_merge.dart';

part 'alert_repository_osm.dart';
part 'alert_repository_plugins.dart';

/// Führt OSM, Hotspots und Plugins zusammen. [pointsAround] antwortet synchron mit dem
/// bekannten Stand und stößt fällige Ladevorgänge im Hintergrund an.
class AlertRepositoryImpl implements AlertRepository {
  AlertRepositoryImpl({
    required this._osm,
    required HotspotRepository hotspots,
    required this.plugins,
    required SharedPreferences prefs,
    DateTime Function()? clock,
    MobileHistoryStore? historyStore,
    this.pluginTimeout = const Duration(seconds: 10),
    this.overviewDebounce = const Duration(milliseconds: 1500),
    this.overviewMaxCells = 6000,
  }) : _prefs = prefs,
       _clock = clock ?? DateTime.now {
    if (historyStore != null) {
      final history = _history = MobileHistory(historyStore, clock: _clock);
      unawaited(
        history.load().then((_) {
          if (!_disposed) _emitChanges();
        }),
      );
    }
    const defaults = DataScope();
    _scope = DataScope(
      detailRadiusMeters:
          (prefs.getDouble(_radiusKey) ?? defaults.detailRadiusMeters).clamp(
            DataScope.minRadiusMeters,
            DataScope.maxRadiusMeters,
          ),
      countryCameras: prefs.getBool(_countryKey) ?? defaults.countryCameras,
    );
    for (final p in plugins) {
      if (_slots.any((s) => s.plugin.id == p.id)) continue;
      _slots.add(
        PluginSlot(p, enabled: prefs.getBool(_prefKey(p.id)) ?? false),
      );
    }
    _hotspotSub = hotspots.watch().listen(
      _onHotspots,
      onError: (Object e) {
        _hotspotMessage = 'Hotspots nicht lesbar';
        _emitStatus();
      },
    );
  }

  /// Weg bis zum Neuladen: ein Viertel des Radius, für Blitzer/Plugins mind. 500 m, für Ampeln/Tempo 300 m.
  double get moveThresholdMeters =>
      math.max(500, _scope.detailRadiusMeters * 0.25);
  double get layersMoveThresholdMeters =>
      math.max(300, _scope.layersRadiusMeters * 0.25);

  /// Umkreis um die Position für Ampeln, Tempolimits und die Nahabfrage der Plugins.
  double get osmRadiusMeters => _scope.detailRadiusMeters;
  static const Duration osmMaxAge = Duration(minutes: 10);
  static const Duration osmRetryAfterError = Duration(minutes: 1);

  /// Liegt für die Position gar nichts vor, fragt das Repository schon nach so langer Zeit erneut:
  /// ein Abruf kostet nichts, solange der Server pausiert, und der Hintergrundlauf kann inzwischen fertig sein.
  static const Duration osmRetryNoData = Duration(seconds: 15);
  static const Duration pluginMaxAge = Duration(minutes: 15);

  /// Bis zu diesem Abstand vom Mittelpunkt der geladenen Daten gilt eine Position als abgedeckt:
  /// der OSM-Umkreis abzüglich des Radius, den die Karte und die Warnlogik abfragen.
  double get coveredMeters => math.max(1000, osmRadiusMeters - 3000);

  static const String _radiusKey = 'scope.detailRadiusMeters';
  static const String _countryKey = 'scope.countryCameras';

  late DataScope _scope;

  /// Lädt ganz Deutschland im Hintergrund, solange `dataScope.countryCameras` an ist.
  late final CountryLoader _country = CountryLoader(
    source: _osm is CountryCameraSource ? _osm as CountryCameraSource : null,
    prefs: _prefs,
    clock: _clock,
    enabled: _scope.countryCameras,
    // Nur wenn die Umgebung fertig ist: die Fahrt geht vor.
    canRun: () => !_osmLoading && !_osmPending && _osmAt != null,
    onChanged: _onCountryChanged,
  );

  void _onCountryChanged() {
    // Neue Kacheln auf der Platte: Übersicht und blaue Gebiete neu lesen.
    _overview.forget();
    _emitChanges();
    _emitStatus();
  }

  @override
  DataScope get dataScope => _scope;

  @override
  set dataScope(DataScope scope) {
    final next = DataScope(
      detailRadiusMeters: scope.detailRadiusMeters.clamp(
        DataScope.minRadiusMeters,
        DataScope.maxRadiusMeters,
      ),
      countryCameras: scope.countryCameras,
    );
    if (_disposed || next == _scope) return;
    final radiusChanged = next.detailRadiusMeters != _scope.detailRadiusMeters;
    _scope = next;
    unawaited(_prefs.setDouble(_radiusKey, next.detailRadiusMeters));
    unawaited(_prefs.setBool(_countryKey, next.countryCameras));
    if (radiusChanged) {
      // Beim nächsten Schritt mit dem neuen Umkreis laden (OSM und Plugins).
      _osmAt = null;
      _osmCenter = null;
      for (final s in _slots) {
        s.lastFetchAt = null;
      }
    }
    _country.enabled = next.countryCameras;
    _emitStatus();
  }

  final FixedPointSource _osm;
  final SharedPreferences _prefs;
  final DateTime Function() _clock;
  final Duration pluginTimeout;
  final Duration overviewDebounce;

  /// Speicherbudget des Übersichtsgedächtnisses in Zellen von 0,1° × 0,1° (ganz Deutschland: rund 4800).
  final int overviewMaxCells;

  @override
  final List<DataSourcePlugin> plugins;

  /// Eigener, dauerhafter Verlauf mobiler Blitzer (null ohne Ablage).
  MobileHistory? _history;

  final List<PluginSlot> _slots = [];
  final _changes = StreamController<void>.broadcast();
  final _statusChanges = StreamController<List<SourceStatus>>.broadcast();
  StreamSubscription<List<Hotspot>>? _hotspotSub;
  bool _disposed = false;

  // OSM
  List<AlertPoint> _osmPoints = const [];
  GeoPoint? _osmCenter;
  final _osmData =
      _NearData(); // Ergebnisse der beiden Abfragen, siehe alert_repository_osm
  DateTime? _osmAt;
  DateTime? _osmUpdatedAt;
  bool _osmLoading = false;
  bool _osmFailed = false;

  /// Mittelpunkt der zuletzt übernommenen OSM-Daten.
  GeoPoint? _osmDataCenter;
  double _osmDataRadius = 0;

  /// Letzter Abruf ohne verwertbare Daten, solange kein späterer Erfolg ihn ablöst.
  GeoPoint? _osmFailedCenter;

  /// Der letzte Fehler betraf die Blitzer (nicht nur Ampeln und Tempolimits).
  bool _osmCamerasFailed = false;

  /// Teile laden noch im Hintergrund: früh erneut fragen, aber kein Fehler.
  bool _osmPending = false;
  String? _osmMessage;

  /// Nummer des laufenden Ladevorgangs: späte Teilergebnisse eines älteren verfallen.
  int _osmRun = 0;

  /// Zeitpunkt des ersten Aufrufs von [pointsAround]: ab hier laufen die Wartezeiten der Stufen.
  DateTime? _startedAt;

  // Hotspots
  List<AlertPoint> _hotspotPoints = const [];
  bool _hotspotsLoaded = false;
  DateTime? _hotspotUpdatedAt;
  String? _hotspotMessage;

  GeoPoint? _lastCenter;
  List<AlertPoint>? _merged;

  /// Messstellen der Kartenübersicht, getrennt von [_osmPoints] (Warnlogik).
  late final _overview = OverviewLoader(
    source: _osm,
    clock: _clock,
    debounce: overviewDebounce,
    store: PointStore(maxCells: overviewMaxCells),
    onChanged: _onOverviewChanged,
    onSettled: _emitStatus,
  );

  /// Alle bekannten Punkte für Kartenausschnitte (Umgebung, Übersichtsgedächtnis und Plugins,
  /// zusammengeführt), bis sich etwas ändert.
  List<AlertPoint>? _known;

  void _onOverviewChanged() {
    _known = null;
    _emitChangesOnly();
  }

  void _emitChangesOnly() {
    if (!_disposed) _changes.add(null);
  }

  static String _prefKey(String id) => 'plugin.$id.enabled';

  PluginSlot? _slot(String id) {
    for (final s in _slots) {
      if (s.plugin.id == id) return s;
    }
    return null;
  }

  // ---- Lesen ----
  @override
  List<AlertPoint> pointsAround(
    GeoPoint center, {
    double radiusMeters = 3000,
    bool withHistory = false,
  }) {
    if (_disposed) return const [];
    _lastCenter = center;
    _startedAt ??= _clock();
    _country.poke();
    _expireStalePluginPoints();
    _maybeLoadOsm(center);
    _startDuePlugins(center);
    return [
      for (final p in _mergedPoints())
        if (distanceMeters(center, p.position) <= radiusMeters) p,
      if (withHistory) ..._historyAround(center, radiusMeters),
    ];
  }

  /// Vergangene Beobachtungen der Plugins und der eigene Verlauf um [center]. Was ein Plugin noch im
  /// Speicher hat und der eigene Verlauf auch kennt, zählt einmal.
  List<AlertPoint> _historyAround(GeoPoint center, double radiusMeters) {
    final plugin = [
      for (final s in _slots)
        for (final p in s.points)
          if (p.historical &&
              distanceMeters(center, p.position) <= radiusMeters)
            p,
    ];
    final own = _history?.around(center, radiusMeters) ?? const [];
    if (own.isEmpty) return plugin;
    final known = ObservationIndex(plugin);
    return [
      ...plugin,
      for (final p in own)
        if (known.isEmpty || !known.covers(p)) p,
    ];
  }

  @override
  List<AlertPoint> pointsInView(GeoBounds view) {
    if (_disposed) return const [];
    _overview.request(view);
    _overview.pointsIn(view); // hält die berührten Zellen im Gedächtnis
    return [
      for (final p in _knownPoints())
        if (view.contains(p.position)) p,
      for (final p in _hotspotPoints)
        if (view.contains(p.position)) p,
    ];
  }

  /// Umgebung (neuester Stand) vor dem Übersichtsgedächtnis, dann mit den Plugins zusammengeführt.
  List<AlertPoint> _knownPoints() => _known ??= () {
    final near = {for (final p in _osmPoints) p.id};
    return mergePoints([
      ..._osmPoints,
      for (final p in _overview.store.all)
        if (!near.contains(p.id)) p,
      for (final s in _slots) ...s.points,
    ], sourceName: _sourceName);
  }();

  /// Alle Punkte: OSM und Plugins zusammengeführt, dazu die eigenen Hotspots (bleiben eigene Punkte).
  List<AlertPoint> _mergedPoints() => _merged ??= [
    ...mergePoints([
      ..._osmPoints,
      // Vergangene Beobachtungen zählen nur für die Karte, nie für die Warnlogik.
      for (final s in _slots)
        for (final p in s.points)
          if (!p.historical) p,
    ], sourceName: _sourceName),
    ..._hotspotPoints,
  ];

  String _sourceName(String id) =>
      id == 'osm' ? 'OpenStreetMap' : _slot(id)?.plugin.displayName ?? id;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  DataCoverage coverageAround(GeoPoint center) => _coverageAround(center);

  /// Der Kreis, für den zuletzt Daten übernommen wurden: Mittelpunkt (er hinkt der Position bis zu
  /// einem Viertel des Radius hinterher), Radius und ob alles geladen ist (Blitzer ohne Fehler,
  /// Ampeln und Tempolimits nicht mehr ausstehend). Null, solange nichts da ist. Vorschlag für die
  /// Karte; noch nicht im Vertrag.
  ({GeoPoint center, double radiusMeters, bool complete})? get loadedCircle {
    final c = _osmDataCenter;
    if (_disposed || c == null) return null;
    return (
      center: c,
      radiusMeters: _osmDataRadius,
      complete: !_osmFailed && !_osmPending && !_osmLoading,
    );
  }

  @override
  List<GeoBounds> loadedAreasIn(GeoBounds view) {
    if (_disposed) return const [];
    try {
      return _osm.loadedCameraTilesIn(view);
    } catch (_) {
      return const [];
    }
  }

  @override
  DataCoverage coverageInView(GeoBounds view) =>
      _disposed ? DataCoverage.ready : _overview.coverageOf(view);

  @override
  Future<int?> speedLimitAt(GeoPoint position, double? headingDeg) =>
      _osm.speedLimitAt(position, headingDeg);

  @override
  Future<RoadLimit> roadLimitAt(GeoPoint position, double? headingDeg) =>
      _osm.roadLimitAt(position, headingDeg);

  @override
  Future<List<GeoPoint>?> roadAheadAt(GeoPoint position, double headingDeg) =>
      _osm.roadAheadAt(position, headingDeg);

  // ---- Status ----
  @override
  Stream<List<SourceStatus>> watchStatus() {
    late final StreamController<List<SourceStatus>> out;
    StreamSubscription<List<SourceStatus>>? sub;
    out = StreamController<List<SourceStatus>>(
      onListen: () {
        out.add(_statusSnapshot());
        sub = _statusChanges.stream.listen(out.add, onDone: out.close);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  void _emitStatus() {
    if (!_disposed) _statusChanges.add(_statusSnapshot());
  }

  void _emitChanges() {
    _merged = null;
    _known = null;
    _emitChangesOnly();
  }

  // ---- Hotspots ----
  void _onHotspots(List<Hotspot> list) {
    if (_disposed) return;
    _hotspotPoints = [for (final h in list) hotspotToAlertPoint(h)];
    _hotspotsLoaded = true;
    _hotspotUpdatedAt = _clock();
    _hotspotMessage = null;
    _emitChanges();
    _emitStatus();
  }

  /// Punkte des letzten Erfolgs gelten mindestens [pluginMaxAge], aber immer zwei
  /// Abrufintervalle lang. Sonst verschwinden sie kurz, wenn Intervall und Höchstalter gleich sind.
  static Duration pluginValidity(Duration refreshInterval) {
    final twice = refreshInterval * 2;
    return twice > pluginMaxAge ? twice : pluginMaxAge;
  }

  @override
  bool isPluginEnabled(String pluginId) => _slot(pluginId)?.enabled ?? false;

  @override
  Future<void> setPluginEnabled(String pluginId, bool enabled) async {
    final s = _slot(pluginId);
    if (_disposed || s == null || s.enabled == enabled) return;
    s.enabled = enabled;
    unawaited(_prefs.setBool(_prefKey(pluginId), enabled));
    if (enabled) {
      _emitStatus();
      final gen = s.generation;
      try {
        await _ensureInitialized(s);
      } catch (e) {
        if (_disposed || gen != s.generation) return;
        s.failed = true;
        s.message = errorText(e);
        _emitStatus();
        return;
      }
      final center = _lastCenter;
      if (!_disposed && gen == s.generation && center != null && !s.loading) {
        unawaited(_refreshPlugin(s, center));
      }
    } else {
      final wasInitialized = s.initialized;
      s.reset();
      if (wasInitialized) await _safeDispose(s.plugin);
      _emitChanges();
      _emitStatus();
    }
  }

  // ---- Aufräumen ----
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _overview.dispose();
    await _history?.dispose();
    await _hotspotSub?.cancel();
    for (final s in _slots) {
      s.generation++;
      if (s.initialized) await _safeDispose(s.plugin);
      s.initialized = false;
    }
    await _changes.close();
    await _statusChanges.close();
  }
}
