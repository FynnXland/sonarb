import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/app_settings.dart';
import '../../app/legal.dart';
import '../../app/map_layer_settings.dart';
import '../../app/privacy_screen.dart';
import '../../app/theme.dart';
import '../osm/limit_download.dart' show limitPackagesPublished;
import '../stats/stats_entry.dart';
import 'announcements_screen.dart';
import 'hotspots_screen.dart';
import 'limit_packages_tile.dart';
import 'legend_screen.dart';
import 'map_layers_screen.dart';
import 'settings_layout.dart';
import 'warning_section.dart';
import 'sources_section.dart';
import 'warning_controls.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({
    super.key,
    this.mapLayerSymbol,
    this.categorySymbol,
    this.limitSign,
    this.googleAccuracyDeclined = false,
    this.onRetryGoogleAccuracy,
  });

  /// Kartensymbol je Ebene für die Seite „Kartenebenen“, von `app/` hereingereicht.
  final MapLayerSymbolBuilder? mapLayerSymbol;

  /// Kartensymbol je Art für die Legende, ebenfalls von `app/`. Ohne gibt es keinen Eintrag.
  final CategorySymbolBuilder? categorySymbol;

  /// Tempolimit-Schilder des Cockpits für die Legende, ebenfalls von `app/`.
  final LimitSignBuilder? limitSign;

  /// Googles Standortgenauigkeit wurde abgelehnt; von `app/` aus der Überwachung hereingereicht.
  final bool googleAccuracyDeclined;

  /// Fragt Googles Standortgenauigkeit noch einmal an (der Dialog kommt dann genau einmal).
  final VoidCallback? onRetryGoogleAccuracy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final ctrl = ref.read(appSettingsProvider.notifier);
    final layers = ref.watch(mapLayersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: pageListPadding(context),
        children: [
          const SectionHeader('Warnung'),
          const WarningSection(),
          const SectionHeader('Ton und Sprache'),
          ValueSliderTile(
            title: 'Lautstärke',
            valueText: '${(s.volume * 100).round()} % der Medienlautstärke',
            value: s.volume.clamp(0, 1).toDouble(),
            min: 0,
            max: 1,
            divisions: 10,
            onChanged: (v) => ctrl.change((x) => x.copyWith(volume: v)),
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Sprachansagen'),
            subtitle: Text(voiceSummary(s)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
            ),
          ),
          SwitchListTile(
            title: const Text('Stumm'),
            subtitle: const Text('Keine Signaltöne, Anzeige bleibt'),
            value: s.muted,
            onChanged: (v) => ctrl.change((x) => x.copyWith(muted: v)),
          ),
          const SectionHeader('Karte'),
          ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: const Text('Kartenebenen'),
            subtitle: Text(mapLayersSummary(layers)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => MapLayersScreen(symbol: mapLayerSymbol),
              ),
            ),
          ),
          if (categorySymbol != null)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Legende'),
              subtitle: const Text('Was die Symbole auf der Karte bedeuten'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => LegendScreen(
                    symbol: categorySymbol!,
                    limitSign: limitSign,
                  ),
                ),
              ),
            ),
          SwitchListTile(
            title: const Text('Karte bei Fahrt neigen'),
            subtitle: const Text(
              'Mit Fahrtrichtung oben: Blick schräg nach vorn',
            ),
            value: s.tiltWhileDriving,
            onChanged: (v) =>
                ctrl.change((x) => x.copyWith(tiltWhileDriving: v)),
          ),
          if (googleAccuracyDeclined && onRetryGoogleAccuracy != null) ...[
            const SectionHeader('Ortung'),
            ListTile(
              leading: const Icon(Icons.gps_not_fixed),
              title: const Text('Ortung ohne Google-Standortgenauigkeit'),
              subtitle: const Text(
                'Mit Google findet die App den Standort schneller und braucht im Stand weniger Akku.',
              ),
              trailing: TextButton(
                onPressed: onRetryGoogleAccuracy,
                child: const Text('Erneut anfragen'),
              ),
            ),
          ],
          const SectionHeader('Fahrten'),
          const StatsEntryTile(),
          const SectionHeader('Hotspots'),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('Hotspots verwalten'),
            subtitle: const Text('Liste, bearbeiten, Import und Export'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const HotspotsScreen()),
            ),
          ),
          const SectionHeader('Daten'),
          const SourceSwitches(),
          if (limitPackagesPublished) const LimitPackagesTile(),
          const SectionHeader('Stand der Quellen'),
          const SourcesOverview(),
          const SectionHeader('Über'),
          const _About(),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      SonarSpace.xl,
      SonarSpace.l,
      SonarSpace.s,
    ),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: SonarText.label.copyWith(color: SonarColors.amber),
      ),
    ),
  );
}

class _About extends ConsumerWidget {
  const _About();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version =
        ref.watch(appVersionProvider).value ?? appVersionFallbackLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sonarb · $version', style: SonarText.label),
              const SizedBox(height: SonarSpace.s),
              const Text(
                'Blitzer, Ampeln und Tempolimits stammen aus OpenStreetMap. '
                'Daten © OpenStreetMap-Mitwirkende, Lizenz Open Database License (ODbL) 1.0, '
                'openstreetmap.org/copyright. Kartenbilder: OpenStreetMap-Tile-Server.',
                style: SonarText.small,
              ),
              const SizedBox(height: SonarSpace.m),
              const Text(stvoNotice, style: SonarText.small),
            ],
          ),
        ),
        const SizedBox(height: SonarSpace.s),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Datenschutz'),
          subtitle: const Text(
            'Was die App speichert und wohin sie Daten schickt',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const PrivacyScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
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
    );
  }
}
