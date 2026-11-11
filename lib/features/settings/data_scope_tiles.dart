import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../core/contracts/alert_repository.dart';
import 'format.dart';
import 'sources_section.dart';
import 'warning_controls.dart';

/// „5 km um die Position“.
String detailRadiusText(double meters) =>
    '${(meters / 1000).round()} km um die Position';

/// Datenmenge, gemessen und gerechnet in `lib/features/osm/README.md` (Abschnitt „Umkreis und
/// Datenmenge“): Ampeln und Tempolimits laden fest bis 3 km und machen fast alles aus, Blitzer
/// und Baustellen im Umkreis sind klein. Deshalb ein Hinweis für alle Umkreise.
const detailRadiusDataHint =
    'Neue Strecken kosten 0,4 MB pro Stunde auf der Autobahn und bis 4 MB in '
    'Großstädten, bekannte fast nichts.';

/// Was der Schalter tut, steht immer da; bei an kommt der Stand der OSM-Quelle dazu.
const countryCamerasHint = 'Zeigt beim Herauszoomen alle festen Blitzer';

/// Zeile unter „Blitzer für ganz Deutschland“: die Erklärung, bei an mit dem Stand der OSM-Quelle.
String countryCamerasText({
  required bool on,
  required List<SourceStatus>? sources,
}) {
  if (!on) return countryCamerasHint;
  final osm = sources?.where((s) => s.id == 'osm').firstOrNull;
  if (osm == null) {
    return '$countryCamerasHint\nLädt im Hintergrund, Stand folgt';
  }
  return [
    countryCamerasHint,
    [
      pluginStatusLabel(osm.status),
      '${osm.pointCount} Punkte',
      if (osm.updatedAt != null) 'Stand ${formatDateTime(osm.updatedAt!)}',
    ].join(' · '),
    if (osm.message != null) osm.message!,
  ].join('\n');
}

/// Umkreis für alle Daten (wandert mit, auf der Karte der blaue Kreis) und der Schalter für die
/// festen Blitzer in ganz Deutschland (Übersicht beim Herauszoomen).
/// Gespeichert in [AppSettings], weitergereicht an [AlertRepository.dataScope].
class DataScopeTiles extends ConsumerWidget {
  const DataScopeTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final ctrl = ref.read(appSettingsProvider.notifier);
    final sources = ref.watch(sourceStatusProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceSliderTile(
          title: 'Umkreis für Daten',
          valueText: detailRadiusText(s.detailRadiusMeters),
          choices: AppSettings.detailRadiusChoices,
          value: s.detailRadiusMeters,
          onChanged: (v) =>
              ctrl.change((x) => x.copyWith(detailRadiusMeters: v)),
        ),
        const SettingsExplainer(detailRadiusDataHint),
        // Ohne Blitzer-Funktionen lädt die App keine Deutschland-Blitzer (AppSettings.dataScope).
        if (s.enforcementFeatures)
          SwitchListTile(
            title: const Text('Blitzer für ganz Deutschland'),
            subtitle: Text(
              countryCamerasText(on: s.countryCameras, sources: sources),
            ),
            value: s.countryCameras,
            onChanged: (v) => ctrl.change((x) => x.copyWith(countryCameras: v)),
          ),
      ],
    );
  }
}
