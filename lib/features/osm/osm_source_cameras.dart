part of 'osm_source.dart';

/// Ab dieser Kantenlänge (Grad) ist ein Ausschnitt eine Übersicht aus dem Cache: es wird nichts
/// geladen, nur gelesen, was schon da ist. Entspricht `maxOverviewSpanDeg` der Karte.
const double cacheOnlySpanDeg = 0.5;

/// Höchstens so viele Kacheln liest ein Ausschnitt aus dem Cache, die mittennächsten zuerst.
const int maxCachedTilesPerView = 6000;

bool _touches(GeoBounds a, GeoBounds b) =>
    a.south <= b.north &&
    a.north >= b.south &&
    a.west <= b.east &&
    a.east >= b.west;

extension _CameraLoading on OsmSource {
  bool _isWide(GeoBounds a) =>
      (a.north - a.south) > cacheOnlySpanDeg ||
      (a.east - a.west) > cacheOnlySpanDeg;

  /// Blitzer aller Kacheln im Ausschnitt, die im Speicher oder im Cache-Ordner liegen. Kein Netz,
  /// keine Frische-Prüfung: Was einmal geladen wurde, bleibt auf der Karte. Die Kacheln werden nicht
  /// in den Speicher übernommen, damit viele Kacheln die Tempolimit-Wege nicht verdrängen.
  Future<SourceResult> _cachedCameras(GeoBounds area) async {
    try {
      await (_cameraIndex ??= _indexCameraTiles());
      final c = area.center;
      final ids = [
        for (final id in _cameraTiles)
          if (_touches(id.bounds, area)) id,
      ]..sort((a, b) => a.distanceTo(c).compareTo(b.distanceTo(c)));
      final points = <AlertPoint>[];
      final seen = <String>{};
      DateTime? oldest;
      final take = ids.take(maxCachedTiles).toList();
      for (var i = 0; i < take.length; i += 16) {
        final chunk = take.sublist(i, math.min(i + 16, take.length));
        final tiles = await Future.wait(
          chunk.map((id) async {
            try {
              return _memory[_key(OsmLayer.cameras, id)] ??
                  await _store.read(OsmLayer.cameras, id);
            } catch (_) {
              return null;
            }
          }),
        );
        for (final t in tiles) {
          if (t == null) continue;
          if (oldest == null || t.fetchedAt.isBefore(oldest)) {
            oldest = t.fetchedAt;
          }
          for (final p in t.points) {
            if (area.contains(p.position) && seen.add(p.id)) points.add(p);
          }
        }
      }
      return SourceResult(points: points, fetchedAt: oldest, fromCache: true);
    } catch (_) {
      return const SourceResult(
        points: [],
        error: 'OSM-Daten konnten nicht gelesen werden',
      );
    }
  }

  /// Stufe 1 der Fahrt: die Blitzer-Kachel unter [position] allein, ohne Warten auf Ampeln und
  /// Tempolimits und ohne die Nachbarn. Eine Kachel statt einer Hülle über bis zu vier ist die
  /// kleinste Abfrage, die der Cache kennt. Frist wie bei `load`.
  Future<SourceResult> _loadFirstStage(GeoPoint position) async {
    try {
      final id = TileId.of(
        position.lat,
        position.lon,
        OsmLayer.cameras.perDegree,
      );
      final slot = TileSlot(OsmLayer.cameras, id);
      await _warm(slot);
      await OsmSource._within(
        _obtain(
          OsmLayer.cameras,
          id,
          0,
        ).then((o) => slot.outcome = o).then((_) {}),
        cameraDeadline,
      );
      return assembleResult(id.bounds, [slot], (l, i) => _memory[_key(l, i)]);
    } catch (_) {
      return const SourceResult(
        points: [],
        error: 'OSM-Daten konnten nicht gelesen werden',
      );
    }
  }

  Future<SourceResult> _loadCameras(GeoBounds area) async {
    if (_isWide(area)) return _cachedCameras(area);
    try {
      final slots = [
        for (final id in tilesCovering(
          area,
          perDegree: OsmLayer.cameras.perDegree,
        ))
          TileSlot(OsmLayer.cameras, id),
      ];
      await Future.wait(slots.map(_warm));
      // Eine Anfrage über die Hülle aller fehlenden Kacheln, hinten in der Schlange.
      final missing = [
        for (final s in slots)
          if (_runningFor(s.layer, s.id) == null &&
              _readyOutcome(s.layer, s.id) == null)
            s.id,
      ];
      if (missing.isNotEmpty) {
        _startFetch(OsmLayer.cameras, missing, 0, overview: true);
      }
      final settled = [
        for (final s in slots)
          _settled(s.layer, s.id).then((o) => s.outcome = o),
      ];
      await OsmSource._within(Future.wait(settled), cameraDeadline);
      return assembleResult(area, slots, (l, i) => _memory[_key(l, i)]);
    } catch (_) {
      return const SourceResult(
        points: [],
        error: 'OSM-Daten konnten nicht gelesen werden',
      );
    }
  }

  Future<TileOutcome> _settled(OsmLayer layer, TileId id) =>
      _runningFor(layer, id) ??
      Future.value(_readyOutcome(layer, id) ?? _unreachable);

  Future<TileOutcome>? _runningFor(OsmLayer layer, TileId id) {
    final key = _key(layer, id);
    return _inFlight[key] ?? _overviewFlight[key];
  }
}
