import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/map_layer_settings.dart';
import '../../app/theme.dart';
import 'settings_layout.dart';

/// Was die Karte zeigt. Jeder Schalter trägt das Symbol, mit dem die Sache auf der Karte
/// erscheint. Wirkt nur auf die Karte, nie auf Warnungen oder Ansagen.
class MapLayersScreen extends ConsumerWidget {
  const MapLayersScreen({super.key, this.symbol});

  /// Kartensymbol je Ebene; ohne bleibt die Zeile ohne Symbol.
  final MapLayerSymbolBuilder? symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(mapLayersProvider);
    final ctrl = ref.read(mapLayersProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Kartenebenen')),
      body: ListView(
        padding: pageListPadding(context),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              SonarSpace.l,
              SonarSpace.l,
              SonarSpace.l,
              SonarSpace.s,
            ),
            child: Text(
              'Nur die Anzeige auf der Karte. Warnungen und Ansagen bleiben, wie sie sind.',
              style: SonarText.small,
            ),
          ),
          for (final layer in MapLayer.values)
            SwitchListTile(
              secondary: symbol == null
                  ? null
                  : SizedBox.square(
                      dimension: 28,
                      child: Center(child: symbol!(layer, on.contains(layer))),
                    ),
              title: Text(layer.label),
              subtitle: _hint(layer) == null ? null : Text(_hint(layer)!),
              value: on.contains(layer),
              onChanged: (_) => ctrl.toggle(layer),
            ),
        ],
      ),
    );
  }
}

String? _hint(MapLayer layer) => switch (layer) {
  MapLayer.mobile => 'Rote Flecken, wo häufig mobil gemessen wird',
  MapLayer.signals => 'Erst nah zu sehen',
  MapLayer.loadedAreas =>
    'Blauer Kreis um die Position: dort liegen alle Daten vor. '
        'Gestrichelt, solange er lädt. Nur in der flachen Karte',
  _ => null,
};

/// Kurzfassung für die Einstellungsliste.
String mapLayersSummary(Set<MapLayer> on) {
  if (on.isEmpty) return 'Keine Ebene an';
  if (on.length == MapLayer.values.length) return 'Alle an';
  return [
    for (final l in MapLayer.values)
      if (on.contains(l)) l.label,
  ].join(', ');
}
