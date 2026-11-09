part of 'alert_repository_impl.dart';

/// Plugin-Abrufe, Verfall der Plugin-Punkte und Statusanzeige des Repositorys.
extension _PluginRefresh on AlertRepositoryImpl {
  // ---- Plugins ----
  bool _pluginDue(PluginSlot s, GeoPoint center) {
    final at = s.lastFetchAt;
    final c = s.lastCenter;
    return at == null ||
        c == null ||
        _clock().difference(at) >= s.plugin.refreshInterval ||
        distanceMeters(c, center) > moveThresholdMeters;
  }

  /// Startet die fälligen Plugins, deren Stufe an der Reihe ist. [onlyLater]: nur die der Stufen
  /// 2 und 3, die auf die Blitzer gewartet haben (Stufe 1 startet beim Einschalten und mit jedem Fix).
  void _startDuePlugins(GeoPoint center, {bool onlyLater = false}) {
    for (final s in _slots) {
      if (onlyLater && pluginLoadStage(s.plugin.id) <= 1) continue;
      if (s.enabled &&
          !s.loading &&
          _pluginDue(s, center) &&
          _stageOpen(s, center)) {
        unawaited(_refreshPlugin(s, center));
      }
    }
  }

  Future<void> _refreshPlugin(PluginSlot s, GeoPoint center) async {
    final gen = s.generation;
    s.loading = true;
    s.lastFetchAt = _clock();
    s.lastCenter = center;
    _emitStatus();
    try {
      await _ensureInitialized(s);
      final raw = await s.plugin
          .fetch(GeoBounds.around(center, osmRadiusMeters))
          .timeout(pluginTimeout);
      if (_disposed || gen != s.generation) return;
      final check = checkPluginPoints(s.plugin.id, raw);
      s.absorb(
        check.accepted,
        GeoBounds.around(center, osmRadiusMeters),
        _clock(),
      );
      _history?.record(check.accepted);
      s.lastSuccessAt = _clock();
      s.successCenter = center;
      s.failed = false;
      s.message = check.rejected == 0
          ? null
          : '${check.rejected} Punkte mit ungültiger ID verworfen';
    } catch (e) {
      if (_disposed || gen != s.generation) return;
      s.failed = true;
      s.message = errorText(e);
      _expireStalePluginPoints(emit: false);
    } finally {
      if (!_disposed && gen == s.generation) {
        s.loading = false;
        _emitStatus();
        _emitChanges();
      }
    }
  }

  Future<void> _ensureInitialized(PluginSlot s) async {
    if (s.initialized) return;
    await s.plugin.initialize().timeout(pluginTimeout);
    s.initialized = true;
  }

  void _expireStalePluginPoints({bool emit = true}) {
    final now = _clock();
    var changed = false;
    for (final s in _slots) {
      changed |= s.expire(
        now,
        AlertRepositoryImpl.pluginValidity(s.plugin.refreshInterval),
      );
    }
    if (!changed) return;
    if (emit) {
      _emitChanges();
      _emitStatus();
    } else {
      _merged = null;
      _known = null;
    }
  }

  Future<void> _safeDispose(DataSourcePlugin p) async {
    try {
      await p.dispose();
    } catch (_) {
      // Ein defektes Plugin darf das Ausschalten nicht verhindern.
    }
  }

  List<SourceStatus> _statusSnapshot() => [
    SourceStatus(
      id: 'osm',
      name: 'OpenStreetMap',
      status: _osmLoading
          ? PluginStatus.loading
          // Fehler heißt: keine brauchbaren Blitzerdaten. Gespeicherte Daten, fehlende Tempolimits
          // oder ein gescheiterter Fernblock sind ok; die Meldung steht trotzdem in `message`.
          : _osmUnusable
          ? PluginStatus.error
          : _osmAt == null
          ? PluginStatus.idle
          : PluginStatus.ok,
      pointCount: _osmPoints.length,
      updatedAt: _osmUpdatedAt,
      message: _osmMessage,
    ),
    if (_country.state != CountryState.off)
      SourceStatus(
        id: 'country',
        name: 'Blitzer Deutschland',
        status: switch (_country.state) {
          CountryState.loading => PluginStatus.loading,
          CountryState.error => PluginStatus.error,
          CountryState.ok => PluginStatus.ok,
          _ => PluginStatus.idle,
        },
        pointCount: _country.pointCount,
        updatedAt: _country.updatedAt,
        message: switch (_country.state) {
          CountryState.loading => 'Lädt alle festen Blitzer, einmalig',
          CountryState.error => _country.message,
          CountryState.ok =>
            _country.message == null
                ? null
                : 'Aktualisierung fehlgeschlagen: ${_country.message}',
          _ => 'Lädt gleich',
        },
      ),
    SourceStatus(
      id: 'hotspot',
      name: 'Eigene Hotspots',
      status: _hotspotMessage != null
          ? PluginStatus.error
          : _hotspotsLoaded
          ? PluginStatus.ok
          : PluginStatus.idle,
      pointCount: _hotspotPoints.length,
      updatedAt: _hotspotUpdatedAt,
      message: _hotspotMessage,
    ),
    for (final s in _slots)
      SourceStatus(
        id: s.plugin.id,
        name: s.plugin.displayName,
        status: s.status,
        pointCount: s.points.length,
        updatedAt: s.lastSuccessAt,
        message: s.message,
      ),
  ];
}
