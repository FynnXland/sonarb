part of 'osm_source.dart';

extension _TileMemory on OsmSource {
  void _remember(String key, TileData data) {
    _memory.remove(key);
    _memory[key] = data;
    // Zuerst gehen Blitzer- und Ampelkacheln, die Wege fürs Tempolimit zuletzt: sie werden bei
    // jeder Positionsmeldung gebraucht, und ohne sie ist das Limit sofort unbekannt.
    while (_memory.length > maxMemoryTiles) {
      _memory.remove(
        _memory.keys.firstWhere(
          (k) => !k.startsWith('limits/') && !k.startsWith('minorLimits/'),
          orElse: () => _memory.keys.first,
        ),
      );
    }
  }
}
