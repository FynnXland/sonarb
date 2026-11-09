import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../core/contracts/fixed_point_source.dart';
import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import '../../core/model/road_limit.dart';
import 'country_cameras.dart';
import 'limit_packages.dart';
import 'osm_country.dart';
import 'osm_details.dart';
import 'osm_gate.dart';
import 'osm_layer.dart';
import 'osm_result.dart';
import 'osm_road_ahead.dart';
import 'osm_speed.dart';
import 'osm_tile.dart';
import 'osm_tile_store.dart';
import 'overpass_client.dart';
import 'staged_source.dart';

part 'osm_source_cameras.dart';
part 'osm_source_country.dart';
part 'osm_source_backoff.dart';
part 'osm_source_road.dart';
part 'osm_source_memory.dart';

String _key(OsmLayer layer, TileId id) => '${layer.name}/${id.key}';

const _unreachable = TileOutcome(
  null,
  failureReason: OverpassReason.unreachable,
);

/// `FixedPointSource` auf Basis von Overpass mit Kachel-Cache.
///
/// Drei Schichten werden getrennt geladen (siehe [OsmLayer]). `load` wartet nur auf die Blitzer;
/// Ampeln und Tempolimits bekommen danach noch [detailGrace], der Rest läuft im Hintergrund weiter
/// und steht beim nächsten Aufruf bzw. in `speedLimitAt` bereit.
class OsmSource
    implements FixedPointSource, CountryCameraSource, StagedPointSource {
  OsmSource({
    required Directory cacheDir,
    http.Client? client,
    List<String> endpoints = defaultOverpassEndpoints,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
    this.maxAge = const Duration(days: 7),
    this.detailMaxAge = const Duration(days: 30),
    this.retryAfterFailure = const Duration(seconds: 60),
    this.maxMemoryTiles = 200,
    this.maxCachedTiles = maxCachedTilesPerView,
    List<TileId> Function()? countryTiles,
    this.detailGrace = const Duration(seconds: 8),
    this.cameraDeadline = const Duration(seconds: 150),
    this.maxInlineWait = const Duration(seconds: 60),
    int maxParallelRequests = 2,
    LimitPackages? limitPackages,
  }) : _store = OsmTileStore(cacheDir),
       packages =
           limitPackages ??
           LimitPackages(
             Directory(
               '${cacheDir.path}${Platform.pathSeparator}limit_packages',
             ),
           ),
       _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       _gate = PriorityGate(maxParallelRequests),
       _countryTiles = countryTiles ?? germanyTiles,
       _detailGate = PriorityGate(1) {
    _client = OverpassClient(
      client: client ?? http.Client(),
      endpoints: endpoints,
      now: _now,
    );
  }

  final OsmTileStore _store;

  /// Tempolimit-Pakete auf dem Gerät: wo ein Paket die Zelle ganz kennt, fragt die Quelle Overpass
  /// nicht nach Tempolimits.
  final LimitPackages packages;
  late final OverpassClient _client;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  final PriorityGate _gate;

  /// Ampeln und Tempolimits laufen einzeln, damit für Blitzer immer ein Platz frei bleibt.
  final PriorityGate _detailGate;

  /// Kacheln, die ein Länderlauf schreibt, auch wenn sie leer sind (Voreinstellung: Deutschland).
  final List<TileId> Function() _countryTiles;

  /// Ab diesem Alter wird eine Blitzer-Kachel neu geladen, Ampeln und Tempolimits (selten, schwer) später.
  final Duration maxAge, detailMaxAge;

  /// Nach einem Fehlschlag wird dieselbe Kachel mindestens so lange nicht erneut abgefragt.
  final Duration retryAfterFailure;
  final int maxMemoryTiles;

  /// Höchstens so viele Kacheln liest ein Übersichts-Ausschnitt aus dem Cache.
  final int maxCachedTiles;

  /// So lange wartet `load` nach den Blitzern noch auf Ampeln und Tempolimits.
  final Duration detailGrace;

  /// Längste Wartezeit von `load` auf die Blitzer; danach kommt das Vorhandene mit Fehlertext.
  final Duration cameraDeadline;

  /// Ist ein Endpunkt höchstens so lange pausiert, wartet eine Blitzer-Kachel darauf, statt aufzugeben.
  final Duration maxInlineWait;

  /// In-Memory-Index der geladenen Kacheln (Schicht + Kachel), zuletzt benutzte hinten.
  final LinkedHashMap<String, TileData> _memory = LinkedHashMap();
  final Set<String> _notOnDisk = {};
  final Map<String, Future<TileOutcome>> _inFlight = {};

  /// Abrufe der Kartenübersicht laufen getrennt: die Fahrt reiht sich nie hinter ihnen ein.
  final Map<String, Future<TileOutcome>> _overviewFlight = {};

  /// Nachladen im Hintergrund (Zellen unter und vor dem Fahrzeug), das niemand abwartet.
  final Set<Future<void>> _background = {};
  final Map<String, ({DateTime until, String reason})> _failures = {};

  int _netFailures =
      0; // Fehlschläge ohne Netz in Folge (Funkloch): wachsende Pausen
  DateTime? _netFailedAt;
  final _motion = _Motion(); // Tempo und Kurs aus den Aufrufen von speedLimitAt
  final _hold = _LimitHold(); // letztes Limit über kurze Lücken halten

  /// Blitzer-Kacheln mit Daten, im Speicher oder auf der Platte. Für die Kartenansicht der
  /// geladenen Gebiete; der Plattenteil kommt aus einem einmaligen Lesen des Ordners.
  final Set<TileId> _cameraTiles = {};
  Future<void>? _cameraIndex;

  /// Wird beim Leeren erhöht; ein noch laufendes Lesen des Ordners verwirft dann sein Ergebnis.
  int _cacheGeneration = 0;

  @override
  Future<SourceResult> load(GeoBounds area) async {
    try {
      final center = area.center;
      await packages.ready;
      final slots = _forMotion([
        for (final layer in OsmLayer.values)
          for (final id in tilesCovering(
            area,
            perDegree: layer.perDegree,
            maxTiles: layer.maxTilesPerLoad,
          ))
            TileSlot(layer, id),
      ], center).where((s) => !_packaged(s)).toList();

      // Erst alle Cache-Dateien lesen, damit die Abrufe danach ohne Pause in die Warteschlange
      // gehen und diese nach Dringlichkeit ordnen kann.
      await Future.wait(slots.map(_warm));
      Future<void> start(TileSlot s) =>
          _obtain(s.layer, s.id, s.id.distanceTo(center)).then((o) {
            s.outcome = o;
          });

      // Fehlende Blitzer-Kacheln gehen gemeinsam in einer Anfrage: wenige Anfragen, wenig Last.
      final cameraSlots = [
        for (final s in slots)
          if (s.layer == OsmLayer.cameras) s,
      ];
      final missing = [
        for (final s in cameraSlots)
          if (!_inFlight.containsKey(_key(s.layer, s.id)) &&
              _readyOutcome(s.layer, s.id) == null)
            s.id,
      ];
      if (missing.length > 1) _startFetch(OsmLayer.cameras, missing, 0);
      final cameras = Future.wait(cameraSlots.map(start));

      // Ampeln und Tempolimits erst, wenn die Blitzer da sind (oder die Frist abläuft): der Server
      // bekommt sie nacheinander, und die Blitzer-Anfrage steht nicht im Wettbewerb mit den schweren.
      await _within(cameras, cameraDeadline);
      final details = Future.wait(_detailOrder(slots, center).map(start));
      await _within(details, detailGrace);

      return assembleResult(area, slots, (l, i) => _memory[_key(l, i)]);
    } catch (_) {
      return const SourceResult(
        points: [],
        error: 'OSM-Daten konnten nicht gelesen werden',
      );
    }
  }

  @override
  Future<SourceResult> loadCameras(GeoBounds area) => _loadCameras(area);

  @override
  Future<SourceResult> loadCached(GeoBounds area) => _cachedCameras(area);

  @override
  Future<SourceResult> loadFirstStage(GeoPoint position) =>
      _loadFirstStage(position);

  /// Wartet höchstens [limit]; false, wenn die Zeit ablief. Der Rest läuft weiter und landet im Speicher.
  static Future<bool> _within(Future<void> f, Duration limit) async {
    try {
      await f.timeout(limit);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<int?> speedLimitAt(GeoPoint position, double? headingDeg) async =>
      (await roadLimitAt(position, headingDeg)).kmh;

  @override
  Future<RoadLimit> roadLimitAt(GeoPoint position, double? headingDeg) async {
    try {
      final ways = await _waysAround(position);
      // Die Zelle unter der Position und die in Fahrtrichtung sind als Nächstes dran (billig: nur
      // Fehlendes, ohne Netz nichts).
      _motion.update(position, headingDeg, _now());
      _inBackground(_ensureRoadCells(position));
      final picked = pickSpeedLimit(ways, position, headingDeg);
      return roadLimitOf(_hold.resolve(picked, position, headingDeg, _now()));
    } catch (_) {
      return const RoadLimit.unknown();
    }
  }

  @override
  Future<List<GeoPoint>?> roadAheadAt(GeoPoint position, double headingDeg) =>
      _roadAhead(position, headingDeg);

  @override
  List<GeoBounds> loadedCameraTilesIn(GeoBounds view) {
    _cameraIndex ??= _indexCameraTiles();
    return [
      for (final id in _cameraTiles)
        if (_touches(id.bounds, view)) id.bounds,
    ];
  }

  Future<void> _indexCameraTiles() async {
    final gen = _cacheGeneration;
    final ids = await _store.list(OsmLayer.cameras);
    if (gen == _cacheGeneration) _cameraTiles.addAll(ids);
  }

  void _noteCameraTile(OsmLayer layer, TileId id) {
    if (layer == OsmLayer.cameras) _cameraTiles.add(id);
  }

  @override
  Future<CountryLoadResult> loadCountryCameras() => _loadCountry();

  @override
  Future<void> clearCache() async {
    _cacheGeneration++;
    _cameraTiles.clear();
    _memory.clear();
    _notOnDisk.clear();
    _failures.clear();
    await _store.clear();
  }

  @override
  Future<int> cacheSizeBytes() => _store.sizeBytes();

  /// Kacheln ohne die aktuellen Details (alter Cache) gelten als veraltet: Blitzer-Kacheln nach
  /// [pointDetailVersion], Tempolimit-Kacheln nach [wayDetailVersion], Ampeln gar nicht.
  bool _isFresh(OsmLayer layer, TileData t) =>
      _now().difference(t.fetchedAt) <
          (layer == OsmLayer.cameras ? maxAge : detailMaxAge) &&
      !t.partial &&
      t.detailVersion >=
          (layer == OsmLayer.cameras
              ? pointDetailVersion
              : layer.hasWays
              ? wayDetailVersion
              : 0);

  /// Liest die Platten-Datei einer Kachel in den Speicher (einmal je Kachel).
  Future<void> _warm(TileSlot s) async {
    final key = _key(s.layer, s.id);
    if (_memory.containsKey(key) || _notOnDisk.contains(key)) return;
    if (_inFlight.containsKey(key)) return;
    try {
      final data = await _store.read(s.layer, s.id);
      if (data != null && !_memory.containsKey(key)) {
        _remember(key, data);
        _noteCameraTile(s.layer, s.id);
      } else if (data == null) {
        _notOnDisk.add(key);
      }
    } catch (_) {}
  }

  /// Ergebnis ohne Abruf: frische Daten oder eine Kachel, die nach einem Fehlschlag noch ruht.
  TileOutcome? _readyOutcome(OsmLayer layer, TileId id) {
    final key = _key(layer, id);
    final data = _memory[key];
    if (data != null) _remember(key, data); // als zuletzt benutzt markieren
    if (data != null && _isFresh(layer, data)) return TileOutcome(data);
    final failure = _failures[key];
    if (failure != null && _now().isBefore(failure.until)) {
      return TileOutcome(data, failureReason: failure.reason);
    }
    return null;
  }

  void _inBackground(Future<void> work) {
    _background.add(work);
    unawaited(work.whenComplete(() => _background.remove(work)));
  }

  /// Wartet, bis keine Abfrage und kein Nachladen im Hintergrund mehr läuft. Für Tests: Statt
  /// eine feste Zeit zu warten, kommt das Ende genau dann, wenn alles erledigt ist, auch unter Last.
  /// Mit [fetches] `false` nur, bis das Nachladen seine Abfragen eingeplant hat (für Tests, die
  /// eine Antwort absichtlich zurückhalten).
  Future<void> whenIdle({bool fetches = true}) async {
    while (true) {
      await Future<void>.delayed(Duration.zero);
      final pending = [
        ..._background,
        if (fetches) ..._inFlight.values,
        if (fetches) ..._overviewFlight.values,
      ];
      if (pending.isEmpty) return;
      await Future.wait([
        for (final f in pending) f.then<void>((_) {}, onError: (Object _) {}),
      ]);
    }
  }

  /// Parallele Aufrufe für dieselbe Kachel teilen sich einen Lauf.
  Future<TileOutcome> _obtain(OsmLayer layer, TileId id, double distance) {
    final key = _key(layer, id);
    final running = _inFlight[key];
    if (running != null) return running;
    final ready = _readyOutcome(layer, id);
    if (ready != null) return Future.value(ready);
    _startFetch(layer, [id], distance);
    return _inFlight[key]!;
  }

  /// Holt [tiles] mit einer Anfrage und trägt jede Kachel als laufend ein.
  void _startFetch(
    OsmLayer layer,
    List<TileId> tiles,
    double distance, {
    bool overview = false,
  }) {
    final group = _fetchGroup(layer, tiles, distance, overview: overview);
    final flights = overview ? _overviewFlight : _inFlight;
    for (final id in tiles) {
      final key = _key(layer, id);
      flights[key] = group.then((m) => m[id]!).whenComplete(() {
        flights.remove(key);
      });
    }
  }

  Future<Map<TileId, TileOutcome>> _fetchGroup(
    OsmLayer layer,
    List<TileId> tiles,
    double distance, {
    bool overview = false,
  }) async {
    try {
      // Blitzer-Kacheln der Fahrt warten eine kurze Pause der Server ab, andere geben auf und
      // versuchen es beim nächsten Aufruf wieder.
      final attempts = layer == OsmLayer.cameras && !overview ? 3 : 1;
      final priority = overview ? overviewPriority : layer.priority;
      for (var attempt = 1; ; attempt++) {
        try {
          Future<Map<TileId, TileData>> request() => _gate.run(
            () => _client.fetch(layer, tiles),
            priority: priority,
            order: distance,
          );
          // Nur die Blitzer der Fahrt gehen am Einzelplatz vorbei: für sie bleibt immer ein Platz frei.
          final fresh = layer == OsmLayer.cameras && !overview
              ? await request()
              : await _detailGate.run(
                  request,
                  priority: priority,
                  order: distance,
                );
          for (final id in tiles) {
            final key = _key(layer, id);
            _failures.remove(key);
            _notOnDisk.remove(key);
            _netFailures = 0;
            // Übersichts-Kacheln liegen nur auf der Platte: viele davon dürfen die Tempolimit-Wege
            // im Speicher nicht verdrängen.
            if (!overview || _memory.containsKey(key)) {
              _remember(key, fresh[id]!);
            }
            _noteCameraTile(layer, id);
          }
          await Future.wait([
            for (final id in tiles) _store.write(layer, id, fresh[id]!),
          ]);
          return {
            for (final id in tiles) id: TileOutcome(fresh[id], fetched: true),
          };
        } on OverpassException catch (e) {
          final wait = e.retryAfter;
          if (attempt < attempts && wait != null && wait <= maxInlineWait) {
            await _sleep(wait + const Duration(seconds: 1));
            continue;
          }
          // Kein Netz: die Pausen wachsen mit jedem Fehlschlag in Folge, jeder Erfolg setzt zurück.
          if (e.reason == OverpassReason.unreachable) _noteNetFailure();
          var pause = wait != null && wait > retryAfterFailure
              ? wait
              : retryAfterFailure;
          final backoff = _netBackoff();
          if (backoff > pause) pause = backoff;
          final until = _now().add(pause);
          return {
            for (final id in tiles)
              id: () {
                final key = _key(layer, id);
                _failures[key] = (until: until, reason: e.reason);
                return TileOutcome(_memory[key], failureReason: e.reason);
              }(),
          };
        }
      }
    } catch (_) {
      return {for (final id in tiles) id: _unreachable};
    }
  }
}
