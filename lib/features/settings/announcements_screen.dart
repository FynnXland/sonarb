import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/contracts/alert_audio.dart';
import 'heat_spot_section.dart';
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
  Announcement.speedLimit => '„Fester Blitzer voraus, Tempo 50“',
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

/// Jeder Satz einzeln: abgeschaltet entfällt die Sprache, der Piep bleibt.
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final ctrl = ref.read(appSettingsProvider.notifier);
    final audio = ref.read(servicesProvider).audio;
    return Scaffold(
      appBar: AppBar(title: const Text('Sprachansagen')),
      body: ListView(
        padding: pageListPadding(context),
        children: [
          SwitchListTile(
            title: const Text('Sprachansagen'),
            subtitle: const Text('Aus: nur Signaltöne'),
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
              'kommt trotzdem. Das Lautsprecher-Symbol spielt den Satz zur Probe ab.',
              style: SonarText.small,
            ),
          ),
          for (final (i, (title, items)) in announcementGroups.indexed) ...[
            SectionHeader(title),
            for (final a in items)
              _AnnouncementTile(
                announcement: a,
                on: !s.silenced.contains(a),
                enabled: s.voiceEnabled,
                onChanged: (v) =>
                    ctrl.change((x) => x.withAnnouncement(a, on: v)),
                onPreview: () => audio.preview(a),
              ),
            // Direkt nach den Blitzern.
            if (i == 0)
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
    required this.onChanged,
    required this.onPreview,
  });

  final Announcement announcement;
  final bool on;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final title = announcementTitle(announcement);
    final subtitle = _subtitle(announcement);
    return SwitchListTile(
      value: on,
      onChanged: enabled ? onChanged : null,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      // Anhören geht auch bei ausgeschalteter Sprache: man soll vorher wissen, was kommt.
      secondary: IconButton(
        icon: const Icon(Icons.volume_up_outlined),
        tooltip: '$title anhören',
        onPressed: onPreview,
      ),
    );
  }
}
