import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/contracts/alert_audio.dart';
import 'warning_controls.dart' show settingsSubtitle;
import 'settings_screen.dart' show SectionHeader;
import 'settings_layout.dart';

/// Gruppen wie in der Legende (Blitzer, Gefahrenstellen, Weitere), dann Zusatz und Zustand.
/// [Announcement.heatSpot] fehlt hier: Ihn regelt die Auswahl „Blitzer-Hotspots“.
const announcementGroups = <(String, List<Announcement>)>[
  (
    'Blitzer',
    [
      Announcement.fixedCamera,
      Announcement.redLightCamera,
      Announcement.sectionControl,
      Announcement.sectionEnd,
      Announcement.mobileCamera,
      Announcement.distanceCheck,
    ],
  ),
  (
    'Gefahrenstellen',
    [
      Announcement.construction,
      Announcement.trafficJamEnd,
      Announcement.accident,
      Announcement.danger,
      Announcement.otherReport,
    ],
  ),
  (
    'Weitere',
    [
      Announcement.otherControls,
      Announcement.noOvertaking,
      Announcement.closure,
      Announcement.busLane,
    ],
  ),
  ('Zusatz', [Announcement.speedLimit]),
  (
    'Zustand der App',
    [
      Announcement.positionFound,
      Announcement.gpsLost,
      Announcement.gpsRestored,
      Announcement.dataUnavailable,
      Announcement.dataRestored,
    ],
  ),
];

/// Die Gruppen ohne die Sätze zu Blitzern und Kontrollen, wenn die Blitzer-Funktionen aus sind
/// ([AppSettings.enforcementAnnouncements]). Leere Gruppen fallen weg.
List<(String, List<Announcement>)> announcementGroupsFor({
  required bool enforcement,
}) {
  if (enforcement) return announcementGroups;
  return [
    for (final (title, items) in announcementGroups)
      if (items.where((a) => !AppSettings.enforcementAnnouncements.contains(a))
          case final left when left.isNotEmpty)
        (title, left.toList()),
  ];
}

/// Zeile in den Einstellungen unter „Sprachansagen“.
String voiceSummary(AppSettings s) {
  if (!s.voiceEnabled) return 'Aus: nur Signaltöne';
  final off = s.silenced.length;
  if (off == 0) return 'An, alle Sätze';
  return off == 1 ? 'An, 1 Satz abgeschaltet' : 'An, $off Sätze abgeschaltet';
}

/// Zeilentitel: meist der Satz selbst.
String announcementTitle(Announcement a) => switch (a) {
  Announcement.speedLimit => 'Tempo-Zusatz',
  Announcement.otherControls => 'Höhen-, Gewichts- und Einfahrtskontrolle',
  _ => a.text,
};

String? _subtitle(Announcement a) => switch (a) {
  Announcement.speedLimit => 'Hängt das Limit an, etwa „…, Tempo 50“',
  Announcement.fixedCamera => 'Auch „Blitzer im Tunnel voraus“',
  Announcement.redLightCamera => 'Auch „Rotlicht- und Tempoblitzer voraus“',
  Announcement.sectionEnd => 'Unmittelbar am Ende, ohne Signalton',
  Announcement.mobileCamera => 'Auch Blitzeranhänger und eigene Meldungen',
  Announcement.construction => 'Auch „Tagesbaustelle voraus“',
  Announcement.danger =>
    'Hindernis, Pannenfahrzeug, Glätte, Sichtbehinderung, Verkehrsmeldung',
  Announcement.otherReport => 'Meldung der Art „Sonstiges“',
  _ => null,
};

/// Ab diesem Textfaktor steht „Anhören“ unter der Zeile statt als Symbol davor: Sonst bleiben
/// dem Satz neben Lautsprecher und Schalter nur wenige Wörter je Zeile.
const announcementWideTextScale = 1.5;

/// Jeder Satz einzeln: abgeschaltet entfällt die Sprache, der Signalton bleibt.
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final ctrl = ref.read(appSettingsProvider.notifier);
    final audio = ref.read(servicesProvider).audio;
    final wide =
        MediaQuery.textScalerOf(context).scale(1) >= announcementWideTextScale;
    return Scaffold(
      appBar: AppBar(title: const Text('Sprachansagen')),
      body: ListView(
        padding: pageListPadding(context),
        children: [
          SwitchListTile(
            title: const Text('Sprachansagen'),
            subtitle: Text(
              s.voiceEnabled
                  ? 'An: Sätze wie „Baustelle voraus“, dazu der Signalton'
                  : 'Aus: nur Signaltöne',
            ),
            value: s.voiceEnabled,
            onChanged: (v) => ctrl.change((x) => x.copyWith(voiceEnabled: v)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              SonarSpace.l,
              SonarSpace.s,
              SonarSpace.l,
              0,
            ),
            child: Text(
              'Ein abgeschalteter Satz wird nicht gesprochen, der Signalton '
              'kommt trotzdem. Der Lautsprecher spielt den Satz zur Probe ab.',
              style: settingsSubtitle,
            ),
          ),
          for (final (title, items) in announcementGroupsFor(
            enforcement: s.enforcementFeatures,
          )) ...[
            SectionHeader(title),
            for (final a in items)
              _AnnouncementTile(
                announcement: a,
                on: !s.silenced.contains(a),
                enabled: s.voiceEnabled,
                wide: wide,
                onChanged: (v) =>
                    ctrl.change((x) => x.withAnnouncement(a, on: v)),
                onPreview: () => audio.preview(a),
              ),
          ],
        ],
      ),
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({
    required this.announcement,
    required this.on,
    required this.enabled,
    required this.wide,
    required this.onChanged,
    required this.onPreview,
  });

  final Announcement announcement;
  final bool on;
  final bool enabled;
  final bool wide;
  final ValueChanged<bool> onChanged;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final title = announcementTitle(announcement);
    final subtitle = _subtitle(announcement);
    // Anhören geht auch bei ausgeschalteter Sprache: man soll vorher wissen, was kommt.
    final preview = Tooltip(
      message: '$title anhören',
      child: wide
          ? TextButton.icon(
              onPressed: onPreview,
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('Anhören'),
            )
          : IconButton(
              icon: const Icon(Icons.volume_up_outlined),
              onPressed: onPreview,
            ),
    );
    final tile = SwitchListTile(
      value: on,
      onChanged: enabled ? onChanged : null,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      secondary: wide ? null : preview,
    );
    if (!wide) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.only(left: SonarSpace.s),
          child: preview,
        ),
      ],
    );
  }
}
