import 'package:flutter/material.dart';

import '../../app/app_settings.dart';
import 'settings_screen.dart' show SectionHeader;
import '../../app/theme.dart';
import 'warning_controls.dart' show SettingsExplainer, settingsSubtitle;

String heatSpotTitle(HeatSpotAlert a) => switch (a) {
  HeatSpotAlert.off => 'Aus',
  HeatSpotAlert.speech => 'Ansage',
  HeatSpotAlert.beep => 'Nur Signalton',
};

String? _subtitle(HeatSpotAlert a, {required bool voiceEnabled}) => switch (a) {
  HeatSpotAlert.off => null,
  HeatSpotAlert.speech =>
    voiceEnabled
        ? '„Blitzer-Hotspot voraus“, dann der Signalton'
        : 'Sprachansagen sind aus: nur der Signalton',
  HeatSpotAlert.beep => 'Drei kurze Töne aufwärts',
};

/// Stufe in Worten: „Jede gemeldete Stelle“, „Ab 3 Meldungen“.
String heatSpotReportsText(int n) =>
    n <= 1 ? 'Jede gemeldete Stelle' : 'Ab $n Meldungen';

String _reportsShort(int n) => n <= 1 ? 'Jede' : 'Ab $n';

/// Auswahl unter „Warnungen“: wie Sonarb vor Stellen warnt, an denen früher geblitzt
/// wurde, und ab wie vielen Meldungen eine Stelle zählt (für Ton und Karte).
class HeatSpotSection extends StatelessWidget {
  const HeatSpotSection({
    super.key,
    required this.value,
    required this.minReports,
    required this.voiceEnabled,
    required this.onChanged,
    required this.onMinReports,
    required this.onPreview,
  });

  final HeatSpotAlert value;
  final bool voiceEnabled;
  final ValueChanged<HeatSpotAlert> onChanged;

  /// Mindestzahl früherer Meldungen im Umkreis ([heatSpotReportChoices]).
  final int minReports;
  final ValueChanged<int> onMinReports;

  /// Probe der gewählten Art; nie für [HeatSpotAlert.off].
  final ValueChanged<HeatSpotAlert> onPreview;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader('Blitzer-Hotspots'),
      const SettingsExplainer(
        'Stellen, an denen früher geblitzt wurde (rote Fläche auf der Karte). '
        'Sonarb meldet sie einmal, wenn sie auf der Straße voraus liegen.',
      ),
      RadioGroup<HeatSpotAlert>(
        groupValue: value,
        onChanged: (v) {
          if (v != null && v != value) onChanged(v);
        },
        child: Column(
          children: [
            for (final a in HeatSpotAlert.values)
              RadioListTile<HeatSpotAlert>(
                value: a,
                title: Text(heatSpotTitle(a)),
                subtitle: switch (_subtitle(a, voiceEnabled: voiceEnabled)) {
                  final text? => Text(text),
                  null => null,
                },
                secondary: a == HeatSpotAlert.off
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.volume_up_outlined),
                        tooltip: '${heatSpotTitle(a)} anhören',
                        onPressed: () => onPreview(a),
                      ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          SonarSpace.l,
          SonarSpace.m,
          SonarSpace.l,
          SonarSpace.s,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welche Stellen',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            Text(heatSpotReportsText(minReports), style: settingsSubtitle),
            const SizedBox(height: SonarSpace.s),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final n in heatSpotReportChoices)
                  ButtonSegment(
                    value: n,
                    label: Text(_reportsShort(n)),
                    tooltip: heatSpotReportsText(n),
                  ),
              ],
              selected: {minReports},
              onSelectionChanged: (v) {
                if (v.single != minReports) onMinReports(v.single);
              },
            ),
            const SizedBox(height: SonarSpace.s),
            const Text(
              'Gezählt werden frühere Meldungen im Umkreis von 300 m, jede gleich, '
              'egal wie alt. Gilt auch für die Karte.',
              style: settingsSubtitle,
            ),
          ],
        ),
      ),
    ],
  );
}
