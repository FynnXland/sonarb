import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/contracts/hotspot_repository.dart';
import 'format.dart';
import 'hotspot_edit_sheet.dart';
import 'hotspot_files.dart';
import 'settings_layout.dart';

final hotspotListProvider = StreamProvider<List<Hotspot>>(
  (ref) => ref.watch(servicesProvider).hotspots.watch(),
);

class HotspotsScreen extends ConsumerStatefulWidget {
  const HotspotsScreen({super.key});

  @override
  ConsumerState<HotspotsScreen> createState() => _HotspotsScreenState();
}

class _HotspotsScreenState extends ConsumerState<HotspotsScreen> {
  String? _message;
  bool _messageIsError = false;
  bool _busy = false;

  HotspotRepository get _repo => ref.read(servicesProvider).hotspots;

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() => _run(() async {
    final String? text;
    try {
      text = await ref.read(hotspotFilesProvider).pickText();
    } catch (e) {
      _say(
        'Datei nicht lesbar. Eine JSON-Datei aus dem Sonarb-Export wählen.',
        error: true,
      );
      return;
    }
    if (text == null) return;
    try {
      final result = await _repo.importJson(text);
      _say(formatImportResult(result));
    } on HotspotFormatException catch (e) {
      _say('Datei nicht importiert: ${e.message}', error: true);
    } catch (e) {
      _say('Import fehlgeschlagen: $e', error: true);
    }
  });

  Future<void> _export() => _run(() async {
    try {
      final json = await _repo.exportJson();
      await ref
          .read(hotspotFilesProvider)
          .shareJson(json, exportFileName(DateTime.now()));
    } catch (e) {
      _say('Export fehlgeschlagen: $e', error: true);
    }
  });

  Future<void> _delete(Hotspot h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Meldung löschen?'),
        content: Text(
          '${hotspotKindLabel(h.kind)} vom ${formatDate(h.createdAt)}. '
          'Lässt sich nicht rückgängig machen.',
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
    if (ok != true) return;
    try {
      await _repo.remove(h.id);
    } catch (e) {
      _say('Löschen fehlgeschlagen: $e', error: true);
    }
  }

  Future<void> _edit(Hotspot h) async {
    final edited = await showHotspotEditSheet(context, h);
    if (edited == null) return;
    try {
      await _repo.update(edited);
    } catch (e) {
      _say('Änderung nicht gespeichert: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(hotspotListProvider);
    final hasItems = list.asData?.value.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Eigene Meldungen')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SonarSpace.l,
              SonarSpace.s,
              SonarSpace.l,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Importieren'),
                  ),
                ),
                const SizedBox(width: SonarSpace.s),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || !hasItems ? null : _export,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Exportieren'),
                  ),
                ),
              ],
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SonarSpace.l,
                SonarSpace.m,
                SonarSpace.l,
                0,
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _message!,
                  style: SonarText.label.copyWith(
                    color: _messageIsError ? SonarColors.red : SonarColors.text,
                  ),
                ),
              ),
            ),
          const SizedBox(height: SonarSpace.s),
          Expanded(
            child: switch (list) {
              AsyncData(:final value) when value.isEmpty => const _Empty(),
              AsyncData(:final value) => ListView.separated(
                padding: pageListPadding(context),
                itemCount: value.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) => _HotspotTile(
                  hotspot: value[i],
                  onEdit: () => _edit(value[i]),
                  onDelete: () => _delete(value[i]),
                ),
              ),
              AsyncError(:final error) => Padding(
                padding: const EdgeInsets.all(SonarSpace.l),
                child: Text(
                  'Meldungen nicht lesbar: $error',
                  style: SonarText.label.copyWith(color: SonarColors.red),
                ),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(SonarSpace.l),
    child: Text(
      'Noch keine eigenen Meldungen. Im Cockpit „Melden“ tippen '
      'oder eine Exportdatei importieren.',
      style: SonarText.small,
    ),
  );
}

class _HotspotTile extends StatelessWidget {
  const _HotspotTile({
    required this.hotspot,
    required this.onEdit,
    required this.onDelete,
  });

  final Hotspot hotspot;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final h = hotspot;
    final lines = [
      formatCoord(h.position),
      if (h.note != null && h.note!.isNotEmpty) h.note!,
    ];
    return ListTile(
      onTap: onEdit,
      title: Text(
        '${hotspotKindLabel(h.kind)} · ${formatDateTime(h.createdAt)}',
      ),
      subtitle: Text(
        lines.join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Löschen',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}
