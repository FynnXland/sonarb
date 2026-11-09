part of 'alert_repository_impl.dart';

/// Ergebnisse der Nahabfrage: [near] aus `load` um die Position (Blitzer, Ampeln im kleinen Radius),
/// [far] aus `loadCameras` für den größeren eingestellten Umkreis.
class _NearData {
  List<AlertPoint> near = const [];
  List<AlertPoint> far = const [];
  GeoPoint? farCenter;
  double farRadius = 0;
  DateTime? farAt;
  bool farFailed = false;

  /// Der große Umkreis lädt noch (nur ein Lauf zugleich).
  bool farLoading = false;

  /// Ausgang der letzten Nahabfrage, für die gemeinsame Meldung von Nah- und Fernteil.
  String? nearError;
  bool nearDetailsOnly = false;
  String? nearNotice;
}

/// Zerlegt [area] in Blöcke bis 0,49° Kantenlänge: größer lädt `loadCameras` nicht aus dem Netz.
List<GeoBounds> _blocks(GeoBounds area) {
  const step = 0.49;
  final rows = ((area.north - area.south) / step).ceil().clamp(1, 1000);
  final cols = ((area.east - area.west) / step).ceil().clamp(1, 1000);
  final h = (area.north - area.south) / rows,
      w = (area.east - area.west) / cols;
  return [
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++)
        GeoBounds(
          south: area.south + r * h,
          west: area.west + c * w,
          north: area.south + (r + 1) * h,
          east: area.west + (c + 1) * w,
        ),
  ];
}

/// Nahabfrage von OSM und Ladestand einer Gegend.
extension _OsmLoading on AlertRepositoryImpl {
  void _maybeLoadOsm(GeoPoint center) {
    if (_osmLoading) return;
    final last = _osmCenter;
    final at = _osmAt;
    final due =
        last == null ||
        at == null ||
        distanceMeters(last, center) > layersMoveThresholdMeters ||
        _clock().difference(at) >=
            (_osmUnusable
                ? AlertRepositoryImpl.osmRetryNoData
                : _osmFailed || _osmPending
                ? AlertRepositoryImpl.osmRetryAfterError
                : AlertRepositoryImpl.osmMaxAge);
    if (due) unawaited(_loadOsm(center));
  }

  /// Darf ein Plugin dieser Stufe jetzt laden? Stufe 1 immer. Später folgende Stufen warten auf die
  /// Blitzer der Position, höchstens [stageWait] je Stufe; wo das Plugin schon Daten für die Gegend hat,
  /// gilt die Reihenfolge nicht.
  bool _stageOpen(PluginSlot s, GeoPoint center) {
    final stage = pluginLoadStage(s.plugin.id);
    if (stage <= 1 || _pluginCovers(s, center)) return true;
    final since = _startedAt ?? _clock();
    final waited = _clock().difference(since);
    final blitzerHere = _blitzerAvailable(center);
    if (stage == 2) return blitzerHere || waited >= stageWait;
    // Stufe 3: nach den Baustellen und nachdem die Umgebung fertig geladen ist.
    final earlier = [
      for (final o in _slots)
        if (o.enabled && pluginLoadStage(o.plugin.id) == 2) o,
    ];
    final settled = !_osmLoading && !earlier.any((o) => o.loading);
    return (blitzerHere && settled) || waited >= stageWait * 2;
  }

  /// Blitzerdaten für die Position sind da: ein früherer Stand in der Nähe oder eine Kachel darunter.
  bool _blitzerAvailable(GeoPoint center) {
    final d = _osmDataCenter;
    if (d != null && distanceMeters(d, center) <= coveredMeters) return true;
    return _cameraTileAt(center);
  }

  /// Der große Umkreis ist an der Reihe: andere Größe, ein Viertel Weg, Fehlschlag oder zu alt.
  bool _farDue(GeoPoint center) {
    if (osmRadiusMeters <= _scope.layersRadiusMeters) return false;
    final c = _osmData.farCenter, at = _osmData.farAt;
    if (c == null || at == null || _osmData.farRadius != osmRadiusMeters) {
      return true;
    }
    return distanceMeters(c, center) > moveThresholdMeters ||
        _clock().difference(at) >=
            (_osmData.farFailed
                ? AlertRepositoryImpl.osmRetryAfterError
                : AlertRepositoryImpl.osmMaxAge);
  }

  /// Blitzer im großen Umkreis, Block für Block (jeder nur, was fehlt). Gibt Punkte und Fehler.
  Future<(List<AlertPoint>, String?)> _loadFar(GeoPoint center) async {
    final area = GeoBounds.around(center, osmRadiusMeters);
    final results = await Future.wait([
      for (final b in _blocks(area)) _osm.loadCameras(b).then((r) => (b, r)),
    ]);
    final seen = <String>{};
    final points = <AlertPoint>[];
    String? error;
    for (final (b, r) in results) {
      _overview.remember(b, r.points, complete: r.error == null);
      error ??= r.error;
      for (final p in r.points) {
        if (seen.add(p.id)) points.add(p);
      }
    }
    return (points, error);
  }

  /// Setzt die Sammelzustände aus dem Ausgang der Nahabfrage und des Fernblocks zusammen.
  void _applyOsmFlags() {
    final error = _osmData.nearError, farFailed = _osmData.farFailed;
    _osmFailed = error != null || farFailed;
    _osmCamerasFailed =
        (error != null && !_osmData.nearDetailsOnly) || farFailed;
    _osmPending = _osmData.nearNotice != null;
    _osmMessage =
        error ??
        (farFailed ? 'Blitzer nicht vollständig' : _osmData.nearNotice);
  }

  /// Nah- und Fernpunkte zusammen: Ampeln und Blitzer der Position vor dem Rest, ohne Doppelte.
  void _mergeOsmPoints() {
    final ids = <String>{};
    _osmPoints = [
      for (final p in [..._osmData.near, ..._osmData.far])
        if (ids.add(p.id)) p,
    ];
  }

  /// Lädt die Umgebung (3 km) in Stufen und danach den großen Umkreis daneben. Wo noch nichts für die
  /// Position vorliegt, kommen zuerst der Cache und die Kachel unter dem Fahrzeug ([_startEarlyStages]),
  /// dann das ganze Fenster. Jede Stufe wird übernommen, sobald sie da ist; ein Fernblock, der in der
  /// Warteschlange hängt, hält sie nicht zurück und blockiert auch das nächste Nachladen nicht.
  Future<void> _loadOsm(GeoPoint center) async {
    _osmLoading = true;
    _osmCenter = center;
    final run = ++_osmRun;
    _emitStatus();
    try {
      final small = GeoBounds.around(center, _scope.layersRadiusMeters);
      _startEarlyStages(center, small, run);
      final r = await _osm.load(small);
      if (_disposed) return;
      // Fehlschlag ohne Daten: den bisherigen Stand behalten.
      // Die Umgebung kommt auch ins Übersichtsgedächtnis; nur vollständige Blitzerdaten ersetzen.
      _overview.remember(
        small,
        r.points,
        complete: r.error == null || r.errorInDetailsOnly,
      );
      if (osmRadiusMeters <= _scope.layersRadiusMeters) {
        _osmData.far = const []; // der kleine Radius deckt alles ab
        _osmData.farCenter = null;
      }
      // Brauchbar: Blitzer da (auch aus dem Cache) oder gar nichts schiefgegangen. Fehlende Ampeln
      // und Tempolimits oder ein gescheiterter Fernblock machen die Daten nicht unbrauchbar. Auch eine
      // Strecke ohne Blitzer, deren Kachel unter dem Fahrzeug geladen ist, hat alles Nötige.
      final nearOk =
          r.points.isNotEmpty ||
          r.error == null ||
          r.errorInDetailsOnly ||
          _cameraTileAt(center);
      if (nearOk) _osmData.near = r.points;
      _mergeOsmPoints();
      if (nearOk) {
        _osmUpdatedAt = r.fetchedAt ?? _clock();
        _osmDataCenter = center;
        _osmDataRadius = osmRadiusMeters;
        _osmFailedCenter = null;
      } else {
        _osmFailedCenter = center;
      }
      _osmData
        ..nearError = r.error
        ..nearDetailsOnly = r.errorInDetailsOnly
        ..nearNotice = r.notice;
      _applyOsmFlags();
    } catch (e) {
      if (_disposed) return;
      _osmFailedCenter = center;
      _osmData
        ..nearError = shortenError(e)
        ..nearDetailsOnly = false
        ..nearNotice = null;
      _applyOsmFlags();
    } finally {
      _osmLoading = false;
      _osmAt = _clock();
      if (!_disposed) {
        // Erst jetzt der große Umkreis: er kommt nach allem, was die Fahrt braucht.
        if (_farDue(center) && !_osmData.farLoading) {
          unawaited(_refreshFar(center));
        }
        _startDuePlugins(
          center,
          onlyLater: true,
        ); // ohne auf den nächsten Fix zu warten
        _emitStatus();
        _emitChanges();
      }
    }
  }

  /// Stufe 0 und 1, wenn für die Position noch nichts vorliegt (Start der Fahrt, neue Gegend): die
  /// Blitzer aus dem Cache ohne Netz, und die Kachel unter dem Fahrzeug allein. Beides läuft neben
  /// dem Fenster und wird übernommen, sobald es da ist. Quellen ohne Stufen laden das Fenster wie bisher.
  void _startEarlyStages(GeoPoint center, GeoBounds small, int run) {
    if (_osm is! StagedPointSource) return;
    final source = _osm as StagedPointSource;
    final held = _osmDataCenter;
    if (held != null && distanceMeters(held, center) <= coveredMeters) return;
    unawaited(_early(source.loadCached(small), center, run));
    unawaited(_early(source.loadFirstStage(center), center, run));
  }

  Future<void> _early(
    Future<SourceResult> stage,
    GeoPoint center,
    int run,
  ) async {
    try {
      _applyEarly(await stage, center, run);
    } catch (_) {
      // Eine frühe Stufe darf das Fenster nicht stören; es lädt ohnehin weiter.
    }
  }

  /// Übernimmt das Ergebnis einer frühen Stufe, solange das Fenster noch lädt. Nur wenn es etwas
  /// bringt: Punkte, oder eine Blitzer-Kachel unter dem Fahrzeug (dann ist die Stelle abgedeckt,
  /// auch ohne Blitzer darin). Der Rest bleibt, bis das Fenster ihn ersetzt.
  void _applyEarly(SourceResult r, GeoPoint center, int run) {
    if (_disposed || !_osmLoading || run != _osmRun) return;
    if (r.points.isEmpty && !_cameraTileAt(center)) return;
    final ids = {for (final p in _osmData.near) p.id};
    _osmData.near = [
      ..._osmData.near,
      for (final p in r.points)
        if (ids.add(p.id)) p,
    ];
    _mergeOsmPoints();
    _osmDataCenter = center;
    _osmDataRadius = osmRadiusMeters;
    _osmFailedCenter = null;
    _osmUpdatedAt ??= r.fetchedAt;
    _startDuePlugins(center, onlyLater: true);
    _emitStatus();
    _emitChanges();
  }

  /// Der große Umkreis, unabhängig von der Nahabfrage: kommt er später, ergänzt er die Punkte.
  Future<void> _refreshFar(GeoPoint center) async {
    _osmData.farLoading = true;
    try {
      final (points, error) = await _loadFar(center);
      if (_disposed || osmRadiusMeters <= _scope.layersRadiusMeters) return;
      if (points.isNotEmpty || error == null) _osmData.far = points;
      _osmData
        ..farCenter = center
        ..farRadius = osmRadiusMeters
        ..farAt = _clock()
        ..farFailed = error != null;
      _mergeOsmPoints();
      _applyOsmFlags();
      _emitStatus();
      _emitChanges();
    } catch (_) {
      _osmData.farFailed = true;
    } finally {
      _osmData.farLoading = false;
    }
  }

  /// Für die Position des letzten Abrufs liegen gar keine brauchbaren Blitzerdaten vor: Abruf
  /// gescheitert und kein früherer Stand in der Nähe. Nur dann gilt die Quelle als ausgefallen.
  bool get _osmUnusable {
    final failed = _osmFailedCenter, data = _osmDataCenter;
    if (failed == null) return false;
    if (data != null && distanceMeters(data, failed) <= coveredMeters) {
      return false;
    }
    // Ein Blitzer-Plugin (Stufe 1) mit Daten für die Stelle: es liegt etwas vor.
    final here = _lastCenter ?? failed;
    for (final s in _slots) {
      if (s.enabled &&
          !s.failed &&
          pluginLoadStage(s.plugin.id) == 1 &&
          _pluginCovers(s, here)) {
        return false;
      }
    }
    // Auch ohne Treffer im letzten Abruf (eine Strecke ohne Blitzer, eine Kachel fehlt) fehlt nichts,
    // wenn die Blitzer-Kachel unter dem Fahrzeug geladen ist, auch aus dem Cache und alt.
    return !_cameraTileAt(_lastCenter ?? failed);
  }

  bool _cameraTileAt(GeoPoint p) {
    try {
      return _osm
          .loadedCameraTilesIn(
            GeoBounds(
              south: p.lat - 0.00001,
              west: p.lon - 0.00001,
              north: p.lat + 0.00001,
              east: p.lon + 0.00001,
            ),
          )
          .isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  DataCoverage _coverageAround(GeoPoint center) {
    if (_disposed) return DataCoverage.ready;
    bool near(GeoPoint? c) =>
        c != null && distanceMeters(c, center) <= coveredMeters;
    final CoverageState state;
    if (near(_osmDataCenter)) {
      state = _osmFailed && _osmCamerasFailed
          ? CoverageState.stale
          : CoverageState.ready;
    } else if (!_osmLoading && near(_osmFailedCenter)) {
      state = CoverageState.failed;
    } else {
      state = CoverageState.loading;
    }
    final plugins = [
      for (final s in _slots)
        if (s.enabled &&
            !s.failed &&
            (s.lastSuccessAt == null ||
                (s.loading && !_pluginCovers(s, center))))
          s.plugin.displayName,
    ];
    return DataCoverage(state, loadingPlugins: plugins);
  }

  bool _pluginCovers(PluginSlot s, GeoPoint center) {
    final c = s.successCenter;
    return c != null && distanceMeters(c, center) <= coveredMeters;
  }
}
