import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/app_settings.dart';
import '../../app/legal.dart';
import '../../app/privacy_screen.dart';
import '../../app/theme.dart';
import '../osm/limit_download.dart' show limitPackagesPublished;
import 'announcements_screen.dart';
import 'limit_packages_tile.dart';
import 'maps_nav_tile.dart';
import 'settings_layout.dart';
import 'settings_screen.dart' show SectionHeader;
import 'sources_section.dart';
import 'warning_controls.dart';

/// Zeile „Ton und Sprache“ auf der Übersicht.
String soundSummary(AppSettings s) {
  if (s.muted) return 'Stumm';
  final voice = s.voiceEnabled ? 'Sprachansagen an' : 'nur Signaltöne';
  return '${(s.volume * 100).round()} % · $voice';
}

/// Lautstärke, Stumm und der Weg zu den einzelnen Sätzen.
class SoundScreen extends ConsumerWidget {
  const SoundScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final ctrl = ref.read(appSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Ton und Sprache')),
      body: ListView(
        padding: pageListPadding(context, top: SonarSpace.s),
        children: [
          ValueSliderTile(
            title: 'Lautstärke',
            valueText: '${(s.volume * 100).round()} % der Medienlautstärke',
            value: s.volume.clamp(0, 1).toDouble(),
            min: 0,
            max: 1,
            divisions: 10,
            onChanged: (v) => ctrl.change((x) => x.copyWith(volume: v)),
          ),
          SwitchListTile(
            title: const Text('Stumm'),
            subtitle: const Text('Keine Signaltöne, Anzeige bleibt'),
            value: s.muted,
            onChanged: (v) => ctrl.change((x) => x.copyWith(muted: v)),
          ),
          SettingsLinkTile(
            title: 'Sprachansagen',
            subtitle: voiceSummary(s),
            page: (_) => const AnnouncementsScreen(),
          ),
        ],
      ),
    );
  }
}

/// Was die App lädt und wie aktuell es ist.
class DataScreen extends StatelessWidget {
  const DataScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Daten und Quellen')),
    body: ListView(
      padding: pageListPadding(context, top: SonarSpace.s),
      children: const [
        SourceSwitches(),
        if (limitPackagesPublished) LimitPackagesTile(),
        SectionHeader('Stand der Quellen'),
        SourcesOverview(),
      ],
    ),
  );
}

/// Die Probe mit Google Maps, abseits der Warnungen: Die Warnungen nutzen sie noch nicht.
class MapsNavScreen extends StatelessWidget {
  const MapsNavScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Google Maps (Probe)')),
    body: ListView(
      padding: pageListPadding(context, top: SonarSpace.s),
      children: const [MapsNavTile()],
    ),
  );
}

/// Version, Herkunft der Daten, Rechtliches.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version =
        ref.watch(appVersionProvider).value ?? appVersionFallbackLabel;
    const gap = SizedBox(height: SonarSpace.m);
    return Scaffold(
      appBar: AppBar(title: const Text('Über Sonarb')),
      body: ListView(
        padding: pageListPadding(context, top: SonarSpace.l),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sonarb · $version',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                gap,
                const Text(
                  'Blitzer, Ampeln und Tempolimits stammen aus OpenStreetMap. '
                  'Daten © OpenStreetMap-Mitwirkende, Lizenz Open Database License (ODbL) 1.0, '
                  'openstreetmap.org/copyright. Kartenbilder: OpenStreetMap-Tile-Server.',
                  style: settingsSubtitle,
                ),
                gap,
                const Text(stvoNotice, style: settingsSubtitle),
                gap,
                const Text(enforcementNotice, style: settingsSubtitle),
              ],
            ),
          ),
          const SizedBox(height: SonarSpace.s),
          SettingsLinkTile(
            title: 'Datenschutz',
            subtitle: 'Was die App speichert und wohin sie Daten schickt',
            page: (_) => const PrivacyScreen(),
          ),
          ListTile(
            title: const Text('Lizenzen'),
            subtitle: const Text('Kartendaten und verwendete Pakete'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Sonarb',
              applicationVersion: version,
            ),
          ),
        ],
      ),
    );
  }
}
