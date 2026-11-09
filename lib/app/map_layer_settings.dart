import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services.dart';

/// Was die Karte zeigt. Die Schalter wirken nur auf die Kartenanzeige, nie auf Warnungen
/// oder Ansagen.
enum MapLayer {
  /// Feste Blitzer, Rotlicht- und Abschnittskontrollen.
  fixedCameras,

  /// Mobile Blitzer, Abstandsmessungen und Live-Punkte als rötliche Flecken.
  mobile,

  /// Baustellen, gemeldet oder aus Quellen.
  construction,

  /// Gefahrenstellen und sonstige Meldungen.
  danger,

  /// Ampeln, erst nah gezeigt.
  signals,

  /// Blauer Kreis um die Position: der Umkreis, in dem alle Daten vorliegen ([DataScope]).
  loadedAreas,
}

extension MapLayerLabel on MapLayer {
  /// Name in den Einstellungen.
  String get label => switch (this) {
    MapLayer.fixedCameras => 'Blitzer',
    MapLayer.mobile => 'Mobile Blitzer',
    MapLayer.construction => 'Baustellen',
    MapLayer.danger => 'Gefahrenstellen',
    MapLayer.signals => 'Ampeln',
    MapLayer.loadedAreas => 'Umkreis',
  };
}

/// Zeichnet das Kartensymbol einer Ebene. Die Einstellungen bekommen es von `app/`, weil das
/// Symbol im Cockpit wohnt.
typedef MapLayerSymbolBuilder = Widget Function(MapLayer layer, bool on);

/// Ampeln sind Beiwerk: standardmäßig aus, damit die Karte ruhig bleibt.
const defaultMapLayers = {
  MapLayer.fixedCameras,
  MapLayer.mobile,
  MapLayer.construction,
  MapLayer.danger,
  MapLayer.loadedAreas,
};

/// Eingeschaltete Ebenen, gespeichert in SharedPreferences (ein Schlüssel je Ebene).
class MapLayersController extends Notifier<Set<MapLayer>> {
  static String _key(MapLayer layer) => 'map.layer.${layer.name}';

  @override
  Set<MapLayer> build() {
    final prefs = ref.watch(servicesProvider).prefs;
    return {
      for (final l in MapLayer.values)
        if (prefs.getBool(_key(l)) ?? defaultMapLayers.contains(l)) l,
    };
  }

  Future<void> toggle(MapLayer layer) async {
    final on = !state.contains(layer);
    state = on ? {...state, layer} : ({...state}..remove(layer));
    await ref.read(servicesProvider).prefs.setBool(_key(layer), on);
  }
}

final mapLayersProvider = NotifierProvider<MapLayersController, Set<MapLayer>>(
  MapLayersController.new,
);
