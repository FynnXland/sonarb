import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/app_settings.dart';
import '../../app/map_layer_settings.dart';
import '../../app/theme.dart';
import '../../core/contracts/data_source_plugin.dart';
import '../stats/stats_entry.dart';
import 'data_scope_tiles.dart';
import 'enforcement_tile.dart';
import 'hotspots_screen.dart';
import 'legend_screen.dart';
import 'map_layers_screen.dart';
import 'settings_layout.dart';
import 'settings_pages.dart';
import 'sources_section.dart';
import 'warning_controls.dart';
import 'warning_section.dart';

/// Übersicht: oben der Blitzer-Schalter, darunter wenige Zeilen, jede mit dem aktuellen Stand
/// in einer Zeile. Details liegen eine Ebene tiefer; Häufiges oben, Seltenes unten.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({
    super.key,
    this.mapLayerSymbol,
    this.categorySymbol,
    this.limitSign,
    this.googleAccuracyDeclined = false,
    this.onRetryGoogleAccuracy,
  });

  /// Kartensymbol je Ebene für die Seite „Karte“, von `app/` hereingereicht.
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
    final layers = ref.watch(mapLayersProvider);
    final version =
        ref.watch(appVersionProvider).value ?? appVersionFallbackLabel;
    final retry = onRetryGoogleAccuracy;
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: pageListPadding(context, top: SonarSpace.s),
        children: [
          // Hier muss man etwas tun: deshalb ganz oben.
          if (googleAccuracyDeclined && retry != null)
            SettingsActionTile(
              icon: Icons.gps_not_fixed,
              title: 'Ortung ohne Google-Standortgenauigkeit',
              subtitle:
                  'Mit Google findet die App den Standort schneller und braucht '
                  'im Stand weniger Akku.',
              action: 'Erneut anfragen',
              onPressed: retry,
            ),
          const EnforcementTile(),
          const SectionHeader('Unterwegs'),
          SettingsLinkTile(
            icon: Icons.notifications_active_outlined,
            title: 'Warnungen',
            subtitle: warningSummary(s),
            page: (_) => const WarningScreen(),
          ),
          SettingsLinkTile(
            icon: s.muted
                ? Icons.volume_off_outlined
                : Icons.volume_up_outlined,
            title: 'Ton und Sprache',
            subtitle: soundSummary(s),
            page: (_) => const SoundScreen(),
          ),
          SettingsLinkTile(
            icon: Icons.layers_outlined,
            title: 'Karte',
            subtitle: mapSummary(layers, s),
            page: (_) => MapLayersScreen(
              symbol: mapLayerSymbol,
              categorySymbol: categorySymbol,
              limitSign: limitSign,
            ),
          ),
          const SectionHeader('Daten und App'),
          const StatsEntryTile(),
          SettingsLinkTile(
            icon: Icons.place_outlined,
            title: 'Eigene Meldungen',
            subtitle: 'Liste, bearbeiten, Import und Export',
            page: (_) => const HotspotsScreen(),
          ),
          const _DataLink(),
          SettingsLinkTile(
            icon: Icons.navigation_outlined,
            title: 'Google Maps (Probe)',
            subtitle: s.mapsNavigation
                ? 'An: liest Navigationshinweise'
                : 'Aus',
            page: (_) => const MapsNavScreen(),
          ),
          SettingsLinkTile(
            icon: Icons.info_outline,
            title: 'Über Sonarb',
            subtitle: '$version · Datenschutz, Lizenzen',
            page: (_) => const AboutScreen(),
          ),
        ],
      ),
    );
  }
}

/// Zeile „Daten und Quellen“: der Umkreis, bei einem Fehler stattdessen die Quelle in Rot.
class _DataLink extends ConsumerWidget {
  const _DataLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = ref.watch(
      appSettingsProvider.select((s) => s.detailRadiusMeters),
    );
    final failed = ref
        .watch(sourceStatusProvider)
        .value
        ?.where((s) => s.status == PluginStatus.error)
        .map((s) => s.name)
        .toList();
    final hasError = failed != null && failed.isNotEmpty;
    return SettingsLinkTile(
      icon: hasError ? Icons.error_outline : Icons.storage_outlined,
      title: 'Daten und Quellen',
      subtitle: hasError
          ? '${failed.join(', ')}: Fehler'
          : detailRadiusText(radius),
      subtitleColor: hasError ? SonarColors.red : null,
      page: (_) => const DataScreen(),
    );
  }
}

/// Kopf einer Gruppe. Grau statt Amber: Amber heißt im Cockpit „Vorwarnung“ und bleibt hier
/// den Bedienelementen.
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
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: SonarColors.textMuted,
        ),
      ),
    ),
  );
}
