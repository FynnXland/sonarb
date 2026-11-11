import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/contracts/alert_audio.dart';
import 'heat_spot_section.dart';
import 'settings_layout.dart';
import 'warning_controls.dart';

/// Ein Satz über der Seite: was vor einer Stelle passiert. Folgt den Einstellungen, damit der
/// Text nie etwas verspricht, das abgeschaltet ist.
String warningFlow(AppSettings s) {
  final at = distanceText(s.announceMeters);
  if (!s.enforcementFeatures) {
    return 'Mindestens $at vor Baustellen und Gefahren kommt eine Ansage mit '
        'Signalton. Die Blitzer-Funktionen sind aus.';
  }
  return s.onlyWhenSpeeding
      ? 'Mindestens $at vor jeder Messstelle kommt eine Ansage mit Signalton. '
            'Weitere Signaltöne nur, wenn du zu schnell bist.'
      : 'Mindestens $at vor jeder Messstelle kommt eine Ansage mit Signalton, '
            'danach Signaltöne bei jedem Tempo.';
}

/// „ab +3 km/h“, „ab dem Limit“.
String toleranceShort(int kmh) => kmh == 0 ? 'ab dem Limit' : 'ab +$kmh km/h';

/// Kurzfassung auf der Übersicht, höchstens zwei Angaben.
String warningSummary(AppSettings s) {
  final at = '${distanceText(s.announceMeters)} vorher';
  if (!s.enforcementFeatures) return '$at · ohne Blitzer';
  return s.onlyWhenSpeeding
      ? '$at · ${toleranceShort(s.overspeedToleranceKmh)}'
      : '$at · Signalton immer';
}

/// Unterseite „Warnungen“: wann und wie oft Sonarb sich meldet. Ohne Blitzer-Funktionen fehlt
/// alles, was nur Messstellen betrifft.
class WarningScreen extends ConsumerWidget {
  const WarningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final ctrl = ref.read(appSettingsProvider.notifier);
    final audio = ref.read(servicesProvider).audio;
    final cameras = s.enforcementFeatures;
    return Scaffold(
      appBar: AppBar(title: const Text('Warnungen')),
      body: ListView(
        padding: pageListPadding(context, top: SonarSpace.s),
        children: [
          Semantics(container: true, child: SettingsExplainer(warningFlow(s))),
          ChoiceSliderTile(
            title: 'Ansage ab',
            valueText:
                '${distanceText(s.announceMeters)} vorher, '
                'bei schneller Fahrt 30 s',
            choices: AppSettings.announceChoices,
            value: s.announceMeters,
            onChanged: (v) => ctrl.change((x) => x.copyWith(announceMeters: v)),
          ),
          if (cameras)
            SwitchListTile(
              title: const Text('Signalton nur, wenn ich zu schnell bin'),
              subtitle: Text(
                s.onlyWhenSpeeding
                    ? 'Sonst und ohne bekanntes Limit bleibt es bei der Ansage'
                    : 'Die Signaltöne kommen bei jedem Tempo',
              ),
              value: s.onlyWhenSpeeding,
              onChanged: (v) =>
                  ctrl.change((x) => x.copyWith(onlyWhenSpeeding: v)),
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
            onChanged: (v) => ctrl.change(
              (x) => x.copyWith(overspeedToleranceKmh: v.round()),
            ),
          ),
          if (cameras) ...[
            SwitchListTile(
              title: const Text('Signalton zum Ausrollen'),
              subtitle: const Text(
                'Zwei Signaltöne, solange Gas wegnehmen bis zur Stelle reicht',
              ),
              value: s.reminderEnabled,
              onChanged: (v) =>
                  ctrl.change((x) => x.copyWith(reminderEnabled: v)),
            ),
            if (s.reminderEnabled)
              ChoiceSliderTile(
                title: 'Ausrollen frühestens',
                valueText:
                    '${distanceText(s.reminderMeters)} vorher, '
                    'bei schneller Fahrt früher',
                choices: AppSettings.reminderChoices,
                value: s.reminderMeters,
                onChanged: (v) =>
                    ctrl.change((x) => x.copyWith(reminderMeters: v)),
              ),
          ],
          SwitchListTile(
            title: const Text('Vor eigenen Meldungen warnen'),
            subtitle: const Text('Stellen, die du über „Melden“ gesetzt hast'),
            value: s.hotspotsEnabled,
            onChanged: (v) =>
                ctrl.change((x) => x.copyWith(hotspotsEnabled: v)),
          ),
          if (cameras)
            HeatSpotSection(
              value: s.heatSpotAlert,
              minReports: s.heatSpotMinReports,
              voiceEnabled: s.voiceEnabled,
              onChanged: (v) =>
                  ctrl.change((x) => x.copyWith(heatSpotAlert: v)),
              onMinReports: (v) =>
                  ctrl.change((x) => x.copyWith(heatSpotMinReports: v)),
              onPreview: (v) => v == HeatSpotAlert.speech
                  ? audio.preview(Announcement.heatSpot)
                  : audio.play(WarningSound.heatSpotPreview),
            ),
        ],
      ),
    );
  }
}
