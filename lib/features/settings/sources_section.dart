import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/contracts/alert_repository.dart';
import '../../core/contracts/data_source_plugin.dart';
import 'data_scope_tiles.dart';
import 'format.dart';
import 'warning_controls.dart';

/// Zeile für den Zwischenspeicher der OSM-Daten.
const osmCacheTitle = 'Gespeicherte Kartendaten';

final sourceStatusProvider = StreamProvider<List<SourceStatus>>(
  (ref) => ref.watch(servicesProvider).alerts.watchStatus(),
);

String pluginStatusLabel(PluginStatus s) => switch (s) {
  PluginStatus.disabled => 'Aus',
  PluginStatus.idle => 'Bereit',
  PluginStatus.loading => 'Lädt',
  PluginStatus.ok => 'Aktuell',
  PluginStatus.error => 'Fehler',
};

/// Schalter, die festlegen, was die App lädt: Umkreis, Blitzer für ganz Deutschland und die
/// eingebundenen Zusatzquellen. Direkt sichtbar, ohne Aufklappen.
class SourceSwitches extends ConsumerStatefulWidget {
  const SourceSwitches({super.key});

  @override
  ConsumerState<SourceSwitches> createState() => _SourceSwitchesState();
}

class _SourceSwitchesState extends ConsumerState<SourceSwitches> {
  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(servicesProvider).alerts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DataScopeTiles(),
        // Die Grund-App kommt ohne Zusatzquellen; die Schalter erscheinen nur, wenn welche
        // eingebunden sind.
        for (final p in alerts.plugins)
          SwitchListTile(
            title: Text(p.displayName),
            subtitle: const Text('Zusatzquelle'),
            value: alerts.isPluginEnabled(p.id),
            onChanged: (v) async {
              await alerts.setPluginEnabled(p.id, v);
              if (mounted) setState(() {});
            },
          ),
      ],
    );
  }
}

/// Kurzer Stand je Quelle: „1234 Punkte · Stand 30.10.2026, 09:12“, nur bei Abweichung mit
/// dem Zustand davor („Lädt“, „Fehler“).
String sourceLine(SourceStatus s) => [
  if (s.status != PluginStatus.ok) pluginStatusLabel(s.status),
  '${s.pointCount} Punkte',
  if (s.updatedAt != null) 'Stand ${formatDateTime(s.updatedAt!)}',
].join(' · ');

/// Übersicht: welche Quellen Daten liefern, mit Punktzahl und Stand, kompakt untereinander.
/// Ausgeschaltete stehen gesammelt in einer Zeile. Darunter der Speicher der Kartendaten.
class SourcesOverview extends ConsumerStatefulWidget {
  const SourcesOverview({super.key});

  @override
  ConsumerState<SourcesOverview> createState() => _SourcesOverviewState();
}

class _SourcesOverviewState extends ConsumerState<SourcesOverview> {
  late Future<int> _cacheSize;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _cacheSize = ref.read(servicesProvider).osm.cacheSizeBytes();
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gespeicherte Kartendaten leeren?'),
        content: const Text(
          'Blitzer und Tempolimits werden bei der nächsten Fahrt neu geladen. '
          'Ohne Netz fehlen sie bis dahin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leeren'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _clearing = true);
    final osm = ref.read(servicesProvider).osm;
    String? error;
    try {
      await osm.clearCache();
    } catch (e) {
      error = 'Cache nicht geleert: $e';
    }
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _cacheSize = osm.cacheSizeBytes();
    });
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(sourceStatusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...switch (status) {
          AsyncData(:final value) when value.isEmpty => [
            const _Note('Noch kein Quellenstatus gemeldet.'),
          ],
          AsyncData(:final value) => [
            for (final s in value)
              if (s.status != PluginStatus.disabled) _StatusRow(s),
            if (value.where((s) => s.status == PluginStatus.disabled)
                case final off when off.isNotEmpty)
              _Note('Aus: ${off.map((s) => s.name).join(', ')}'),
          ],
          AsyncError(:final error) => [_Note('Status nicht abrufbar: $error')],
          _ => [const _Note('Status wird geladen')],
        },
        FutureBuilder<int>(
          future: _cacheSize,
          builder: (context, snap) {
            final text = switch (snap) {
              AsyncSnapshot(hasError: true) => 'Größe nicht ermittelbar',
              AsyncSnapshot(:final data?) => formatBytes(data),
              _ => 'wird berechnet',
            };
            return SettingsActionTile(
              title: osmCacheTitle,
              subtitle:
                  '$text. Blitzer, Ampeln und Tempolimits aus OpenStreetMap',
              action: 'Leeren',
              onPressed: _clearing ? null : _clearCache,
            );
          },
        ),
      ],
    );
  }
}

/// Eine Zeile je Quelle, ohne Tippfläche: Name, darunter Stand, bei Fehler mit Meldung.
class _StatusRow extends StatelessWidget {
  const _StatusRow(this.s);

  final SourceStatus s;

  @override
  Widget build(BuildContext context) {
    final error = s.status == PluginStatus.error;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SonarSpace.l,
        vertical: SonarSpace.xs,
      ),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ein Symbol nur bei Fehler: dann trägt es eine Nachricht.
            if (error) ...[
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.error_outline,
                  size: 18,
                  color: SonarColors.red,
                ),
              ),
              const SizedBox(width: SonarSpace.m),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: Theme.of(context).textTheme.bodyLarge),
                  Text(sourceLine(s), style: settingsSubtitle),
                  if (s.message != null)
                    Text(
                      s.message!,
                      style: settingsSubtitle.copyWith(
                        color: error ? SonarColors.red : SonarColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: SonarSpace.l,
      vertical: SonarSpace.s,
    ),
    child: Text(text, style: settingsSubtitle),
  );
}
