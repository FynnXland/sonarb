import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/map_layer_settings.dart';
import '../../app/theme.dart';
import 'legend_screen.dart';
import 'settings_layout.dart';
import 'settings_screen.dart' show SectionHeader;
import 'warning_controls.dart';

/// Ebenen, die nur Blitzer zeigen; ohne Blitzer-Funktionen fehlen sie.
const enforcementLayers = {MapLayer.fixedCameras, MapLayer.mobile};

/// Die Ebenen, die auf der Seite stehen.
List<MapLayer> shownLayers({required bool enforcement}) => [
  for (final l in MapLayer.values)
    if (enforcement || !enforcementLayers.contains(l)) l,
];

/// Seite „Karte“: oben die Neigung, darunter was die Karte zeigt, unten die Legende. Jeder
/// Ebenen-Schalter trägt das Symbol, mit dem die Sache auf der Karte erscheint. Die Ebenen
/// wirken nur auf die Karte, nie auf Warnungen oder Ansagen.
class MapLayersScreen extends ConsumerWidget {
  const MapLayersScreen({
    super.key,
    this.symbol,
    this.categorySymbol,
    this.limitSign,
  });

  /// Kartensymbol je Ebene; ohne bleibt die Zeile ohne Symbol.
  final MapLayerSymbolBuilder? symbol;

  /// Für die Legende; ohne gibt es keinen Eintrag.
  final CategorySymbolBuilder? categorySymbol;
  final LimitSignBuilder? limitSign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(mapLayersProvider);
    final ctrl = ref.read(mapLayersProvider.notifier);
    final s = ref.watch(appSettingsProvider);
    final settings = ref.read(appSettingsProvider.notifier);
    final legend = categorySymbol;
    return Scaffold(
      appBar: AppBar(title: const Text('Karte')),
      body: ListView(
        padding: pageListPadding(context),
        children: [
          SwitchListTile(
            title: const Text('Karte bei Fahrt neigen'),
            subtitle: const Text(
              'Mit Fahrtrichtung oben: Blick schräg nach vorn',
            ),
            value: s.tiltWhileDriving,
            onChanged: (v) =>
                settings.change((x) => x.copyWith(tiltWhileDriving: v)),
          ),
          const SectionHeader('Kartenebenen'),
          const SettingsExplainer(
            'Nur die Anzeige auf der Karte. Warnungen und Ansagen bleiben, wie sie sind.',
          ),
          for (final layer in shownLayers(enforcement: s.enforcementFeatures))
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
          if (legend != null) ...[
            const SizedBox(height: SonarSpace.s),
            SettingsLinkTile(
              title: 'Legende',
              subtitle: 'Was die Symbole auf der Karte bedeuten',
              page: (_) => LegendScreen(symbol: legend, limitSign: limitSign),
            ),
          ],
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

/// Kurzfassung der Ebenen: alle, keine oder die eingeschalteten.
String mapLayersSummary(Set<MapLayer> on, {bool enforcement = true}) {
  final shown = shownLayers(enforcement: enforcement);
  final visible = [
    for (final l in shown)
      if (on.contains(l)) l,
  ];
  if (visible.isEmpty) return 'Keine Ebene an';
  if (visible.length == shown.length) return 'Alle an';
  return [for (final l in visible) l.label].join(', ');
}

/// Zeile „Karte“ auf der Übersicht: kurz, höchstens zwei Angaben.
String mapSummary(Set<MapLayer> on, AppSettings s) {
  final shown = shownLayers(enforcement: s.enforcementFeatures);
  final count = shown.where(on.contains).length;
  final layers = count == shown.length
      ? 'Alle Ebenen'
      : '$count von ${shown.length} Ebenen';
  return '$layers · ${s.tiltWhileDriving ? 'neigt bei Fahrt' : 'flach'}';
}
