part of 'osm_source.dart';

/// Dringlichkeit des Länderlaufs: hinter allem anderen.
const int countryPriority = 9;

extension _CountryLoading on OsmSource {
  Future<CountryLoadResult> _loadCountry() async {
    final gen = _cacheGeneration;
    final CountryData data;
    try {
      data = await _detailGate.run(
        () => _gate.run(
          _client.fetchCountry,
          priority: countryPriority,
          order: 0,
        ),
        priority: countryPriority,
      );
    } on OverpassException catch (e) {
      return CountryLoadResult(error: e.reason);
    } catch (_) {
      return const CountryLoadResult(error: OverpassReason.unreachable);
    }
    if (gen != _cacheGeneration) {
      return const CountryLoadResult(error: 'Cache wurde geleert');
    }

    // Alle Kacheln des Landes, auch leere: „hier ist nichts“ ist eine Auskunft.
    final tiles = {..._countryTiles(), ...data.byTile.keys}.toList();
    var written = 0;
    for (var i = 0; i < tiles.length; i += 40) {
      final chunk = tiles.sublist(i, math.min(i + 40, tiles.length));
      final done = await Future.wait(
        chunk.map((t) => _writeCountryTile(t, data)),
      );
      written += done.where((w) => w).length;
      if (gen != _cacheGeneration) break;
    }
    return CountryLoadResult(
      fetchedAt: data.fetchedAt,
      points: data.pointCount,
      tiles: written,
    );
  }

  /// Schreibt eine Kachel. Randkacheln sind unvollständig (jenseits der Grenze fehlt etwas) und
  /// ersetzen keine vollständige, frische Kachel, die schon im Cache liegt.
  Future<bool> _writeCountryTile(TileId t, CountryData data) async {
    try {
      final partial = !isInteriorTile(t);
      if (partial) {
        final existing =
            _memory[_key(OsmLayer.cameras, t)] ??
            await _store.read(OsmLayer.cameras, t);
        if (existing != null &&
            !existing.partial &&
            _isFresh(OsmLayer.cameras, existing)) {
          return false;
        }
      }
      final tile = TileData(
        fetchedAt: data.fetchedAt,
        points: data.byTile[t] ?? const [],
        ways: const [],
        detailVersion: pointDetailVersion,
        partial: partial,
      );
      final key = _key(OsmLayer.cameras, t);
      await _store.write(OsmLayer.cameras, t, tile);
      _memory.remove(key); // beim nächsten Zugriff frisch von der Platte
      _notOnDisk.remove(key);
      _failures.remove(key);
      _cameraTiles.add(t);
      return true;
    } catch (_) {
      return false;
    }
  }
}
