import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/theme.dart';
import 'maps_nav_tile.dart';
import 'settings_layout.dart';
import 'warning_controls.dart';

/// Was vor einer Messstelle passiert, in der Reihenfolge, in der es passiert. Folgt den
/// Einstellungen, damit der Text nie etwas verspricht, das abgeschaltet ist.
List<String> warningFlow(AppSettings s) {
  final tolerance = s.overspeedToleranceKmh;
  final tooFast = tolerance == 0
      ? 'Bist du zu schnell'
      : 'Bist du mehr als $tolerance km/h zu schnell';
  final beeps = s.reminderEnabled
      ? 'zweimal, solange Ausrollen noch reicht, und kurz vor der Stelle '
            'schnell hintereinander'
      : 'kurz vor der Stelle schnell hintereinander';
  return [
    'Vor jeder Messstelle kommt eine Ansage mit Piep, mindestens '
        '${distanceText(s.announceMeters)} vorher, bei schneller Fahrt 30 s vorher.',
    if (s.onlyWhenSpeeding) ...[
      '$tooFast, piept es $beeps.',
      'Ist das Limit unbekannt oder gilt keins (Autobahn), bleibt es bei der '
          'Ansage.',
    ] else
      'Danach piept es bei jedem Tempo $beeps.',
  ];
}

/// Eingeklappte Zeile unter „Mehr“.
String warningMoreSummary(AppSettings s) => s.reminderEnabled
    ? 'Piepe zum Ausrollen frühestens ${distanceText(s.reminderMeters)} vorher'
    : 'Ohne Piepe zum Ausrollen';

/// Abschnitt „Warnung“: oben der Ablauf in Worten, darunter die wenigen Regler, die man
/// braucht. Die Feinheit der Ausroll-Piepe liegt unter „Mehr“.
class WarningSection extends ConsumerWidget {
  const WarningSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final ctrl = ref.read(appSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SonarSpace.l,
            0,
            SonarSpace.l,
            SonarSpace.s,
          ),
          child: Semantics(
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in warningFlow(s))
                  Padding(
                    padding: const EdgeInsets.only(bottom: SonarSpace.xs),
                    child: Text(
                      line,
                      style: SonarText.small.copyWith(
                        color: SonarColors.text,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        ChoiceSliderTile(
          title: 'Ansage ab',
          valueText:
              '${distanceText(s.announceMeters)} vor der Messstelle, '
              'bei schneller Fahrt 30 s',
          choices: AppSettings.announceChoices,
          value: s.announceMeters,
          onChanged: (v) => ctrl.change((x) => x.copyWith(announceMeters: v)),
        ),
        SwitchListTile(
          title: const Text('Piepen nur, wenn ich zu schnell bin'),
          subtitle: Text(
            s.onlyWhenSpeeding
                ? 'Bei passendem Tempo bleibt es bei der Ansage'
                : 'Die Piepe kommen bei jedem Tempo',
          ),
          value: s.onlyWhenSpeeding,
          onChanged: (v) => ctrl.change((x) => x.copyWith(onlyWhenSpeeding: v)),
        ),
        ValueSliderTile(
          title: 'Zu schnell ab',
          valueText: s.overspeedToleranceKmh == 0
              ? 'Sobald das Limit überschritten ist'
              : '${s.overspeedToleranceKmh} km/h über dem Limit',
          value: s.overspeedToleranceKmh.clamp(0, 10).toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          onChanged: (v) =>
              ctrl.change((x) => x.copyWith(overspeedToleranceKmh: v.round())),
        ),
        SwitchListTile(
          title: const Text('Vor eigenen Hotspots warnen'),
          value: s.hotspotsEnabled,
          onChanged: (v) => ctrl.change((x) => x.copyWith(hotspotsEnabled: v)),
        ),
        const MapsNavTile(),
        SettingsGroup(
          id: 'warning-more',
          title: 'Mehr',
          summary: warningMoreSummary(s),
          children: [
            SwitchListTile(
              title: const Text('Piepe zum Ausrollen'),
              subtitle: const Text(
                'Zwei Piepe, solange Gas wegnehmen bis zur Stelle noch reicht',
              ),
              value: s.reminderEnabled,
              onChanged: (v) =>
                  ctrl.change((x) => x.copyWith(reminderEnabled: v)),
            ),
            if (s.reminderEnabled)
              ChoiceSliderTile(
                title: 'Piepe zum Ausrollen frühestens',
                valueText:
                    '${distanceText(s.reminderMeters)} vor der Messstelle, '
                    'bei schneller Fahrt früher',
                choices: AppSettings.reminderChoices,
                value: s.reminderMeters,
                onChanged: (v) =>
                    ctrl.change((x) => x.copyWith(reminderMeters: v)),
              ),
          ],
        ),
      ],
    );
  }
}
