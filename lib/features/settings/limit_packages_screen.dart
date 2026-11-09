import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../osm/land_at.dart';
import '../osm/limit_download.dart';
import '../osm/limit_packages.dart';
import 'format.dart';
import 'limit_packages_controller.dart';
import 'settings_layout.dart';
import 'settings_screen.dart' show SectionHeader;
import 'warning_controls.dart';

/// Hinweise an den Stadtstaaten und ihren Nachbarn: Die Zellen rund um Berlin, Bremen und Hamburg
/// liegen im Paket des Flächenlands, nicht im Paket der Stadt.
const Map<String, String> cityStateHints = {
  'berlin': 'Das Umland steht im Paket Brandenburg.',
  'bremen': 'Das Umland steht im Paket Niedersachsen.',
  'hamburg': 'Das Umland steht in Schleswig-Holstein und Niedersachsen.',
  'brandenburg': 'Ohne Berlin, das hat sein eigenes Paket.',
  'niedersachsen': 'Ohne Bremen und Hamburg, die haben ein eigenes Paket.',
  'schleswig-holstein': 'Ohne Hamburg, das hat sein eigenes Paket.',
};

const limitPackagesExplainer =
    'Mit dem Paket deines Bundeslands liest Sonarb Tempolimits direkt vom Gerät: sofort und ohne Netz. '
    'Ohne Paket holt die App sie unterwegs aus dem Netz. Geladen wird nur, wenn du es hier antippst; '
    'dabei wird keine Position gesendet.';

const limitPackagesLicense =
    'Daten: © OpenStreetMap-Mitwirkende, Open Database License (ODbL).';

/// „29.10.2026“ aus 20261029.
String limitPackageDate(int date) =>
    '${(date % 100).toString().padLeft(2, '0')}.'
    '${(date ~/ 100 % 100).toString().padLeft(2, '0')}.${date ~/ 10000}';

/// Tempolimit-Pakete wählen, laden, aktualisieren und löschen.
class LimitPackagesScreen extends ConsumerStatefulWidget {
  const LimitPackagesScreen({super.key});

  @override
  ConsumerState<LimitPackagesScreen> createState() =>
      _LimitPackagesScreenState();
}

class _LimitPackagesScreenState extends ConsumerState<LimitPackagesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(limitPackagesProvider.notifier).checkCatalog();
    });
  }

  Future<void> _confirmInstall(LimitCatalogEntry entry, bool update) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          update ? '${entry.name} aktualisieren?' : '${entry.name} laden?',
        ),
        content: Text(
          '${formatBytes(entry.bytes)} werden geladen, am besten im WLAN. '
          'Stand der Daten: ${limitPackageDate(entry.date)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(update ? 'Aktualisieren' : 'Laden'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(limitPackagesProvider.notifier).install(entry);
    }
  }

  Future<void> _confirmRemove(InstalledLimitPackage p, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name löschen?'),
        content: const Text(
          'Die Tempolimits dort kommen danach wieder aus dem Netz, ohne Netz fehlen sie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(limitPackagesProvider.notifier).remove(p.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(limitPackagesProvider);
    final suggestion = ref.watch(limitSuggestionProvider);
    final ctrl = ref.read(limitPackagesProvider.notifier);
    final names = {
      for (final e in state.catalog ?? <LimitCatalogEntry>[]) e.id: e.name,
    };
    String nameOf(String id) => names[id] ?? landNames[id] ?? id;
    int byName(String a, String b) => nameOf(a).compareTo(nameOf(b));
    // Geladenes oben, darunter das übrige Angebot; ohne Netz nur das Geladene.
    final loaded = [for (final p in state.installed) p.id]..sort(byName);
    final offered = [
      for (final id in names.keys)
        if (state.installedFor(id) == null) id,
    ]..sort(byName);
    Widget tile(String id) => _PackageTile(
      id: id,
      name: nameOf(id),
      entry: state.catalog?.where((e) => e.id == id).firstOrNull,
      installed: state.installedFor(id),
      progress: state.loading[id],
      onInstall: _confirmInstall,
      onRemove: _confirmRemove,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Tempolimits ohne Netz')),
      body: ListView(
        padding: pageListPadding(context),
        children: [
          if (state.unreachable)
            _Notice(
              icon: Icons.cloud_off_outlined,
              title: 'Pakete gerade nicht erreichbar',
              text: state.installed.isEmpty
                  ? 'Ohne Paket kommen die Tempolimits weiter aus dem Netz.'
                  : 'Schon geladene Pakete funktionieren weiter.',
              action: _RowButton(
                label: 'Erneut versuchen',
                onPressed: state.checking ? null : ctrl.checkCatalog,
              ),
            )
          else if (state.checking && state.catalog == null)
            const ListTile(
              leading: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Angebot wird abgerufen'),
            ),
          if (state.error != null)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(state.error!),
            ),
          if (suggestion != null)
            _SuggestionCard(
              entry: suggestion,
              progress: state.loading[suggestion.id],
              onInstall: () => _confirmInstall(suggestion, false),
            ),
          const SettingsExplainer(limitPackagesExplainer),
          if (loaded.isNotEmpty) ...[
            const SectionHeader('Geladen'),
            for (final id in loaded) tile(id),
          ],
          if (offered.isNotEmpty) ...[
            SectionHeader(
              loaded.isEmpty ? 'Bundesländer' : 'Weitere Bundesländer',
            ),
            for (final id in offered) tile(id),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(
              SonarSpace.l,
              SonarSpace.l,
              SonarSpace.l,
              SonarSpace.s,
            ),
            child: Text(limitPackagesLicense, style: SonarText.small),
          ),
        ],
      ),
    );
  }
}

/// Textknopf unter einer Zeile, bündig mit deren Text.
class _RowButton extends StatelessWidget {
  const _RowButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
      ),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}

/// Fortschritt eines Downloads: Signalfarbe auf ruhiger Fläche.
class _Progress extends StatelessWidget {
  const _Progress(this.value);

  final double value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      0,
      SonarSpace.l,
      SonarSpace.s,
    ),
    child: LinearProgressIndicator(
      value: value,
      backgroundColor: SonarColors.surfaceHigh,
    ),
  );
}

/// Hinweis mit Knopf darunter, damit der Text auch bei großer Schrift die volle Breite hat.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SonarSpace.s),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(text)),
        // Bündig mit dem Text neben dem Symbol.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 40),
          child: action,
        ),
      ],
    ),
  );
}

/// Vorschlag für das Land, in dem man gerade ist. Bleibt beim Laden stehen und zeigt dort den
/// Fortschritt, damit nichts unter dem Finger wegspringt.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.entry,
    required this.progress,
    required this.onInstall,
  });

  final LimitCatalogEntry entry;
  final double? progress;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final lines = [
      p != null
          ? 'Wird geladen, ${(p * 100).round()} %'
          : '${formatBytes(entry.bytes)}, Stand ${limitPackageDate(entry.date)}',
      ?cityStateHints[entry.id],
    ];
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: SonarSpace.l,
        vertical: SonarSpace.s,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: SonarSpace.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Du bist in ${entry.name}'),
              subtitle: Text(lines.join('\n')),
            ),
            if (p != null)
              _Progress(p)
            else
              _RowButton(label: 'Paket laden', onPressed: onInstall),
          ],
        ),
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.id,
    required this.name,
    required this.entry,
    required this.installed,
    required this.progress,
    required this.onInstall,
    required this.onRemove,
  });

  final String id;
  final String name;
  final LimitCatalogEntry? entry;
  final InstalledLimitPackage? installed;
  final double? progress;
  final Future<void> Function(LimitCatalogEntry, bool update) onInstall;
  final Future<void> Function(InstalledLimitPackage, String name) onRemove;

  @override
  Widget build(BuildContext context) {
    final inst = installed;
    final offer = entry;
    final p = progress;
    final newer = offer != null && inst != null && offer.isNewerThan(inst);
    final lines = [
      if (p != null)
        'Wird geladen, ${(p * 100).round()} %'
      else if (inst != null) ...[
        '${formatBytes(inst.bytes)} · Stand ${limitPackageDate(inst.date)}',
        if (newer) 'Neuer Stand ${limitPackageDate(offer.date)}',
      ] else if (offer != null)
        formatBytes(offer.bytes),
      ?cityStateHints[id],
    ];
    // Rechts höchstens ein Knopf; „Aktualisieren“ steht unter dem Text, sonst bleibt für den
    // Namen bei großer Schrift kaum Platz.
    final Widget? trailing = p != null
        ? null
        : inst != null
        ? IconButton(
            tooltip: '$name löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => onRemove(inst, name),
          )
        : offer != null
        ? TextButton(
            onPressed: () => onInstall(offer, false),
            child: const Text('Laden'),
          )
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(name),
          subtitle: Text(lines.join('\n')),
          isThreeLine: lines.length > 1,
          trailing: trailing,
        ),
        if (p != null)
          _Progress(p)
        else if (newer)
          Padding(
            padding: const EdgeInsets.only(bottom: SonarSpace.s),
            child: _RowButton(
              label: 'Aktualisieren',
              onPressed: () => onInstall(offer, true),
            ),
          ),
      ],
    );
  }
}
