import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/contracts/hotspot_repository.dart';
import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import 'drive_controller.dart';
import 'format.dart';
import 'instruments.dart';
import 'point_sheet.dart';
import 'standby_panel.dart';
import 'symbols/category_symbol.dart';

/// Alles zu einem Punkt: Art und Symbol, groß Tempolimit und Abstand, dann die Angaben der
/// Quellen, ganz unten die Quellen selbst mit Stand und Lizenzhinweis.
class PointDetails extends ConsumerWidget {
  const PointDetails({
    super.key,
    required this.point,
    required this.onClose,
    this.onBack,
  });

  final AlertPoint point;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fix = ref.watch(driveControllerProvider.select((d) => d.fix));
    final driving = ref.watch(driveControllerProvider.select(isDriving));
    final services = ref.read(servicesProvider);
    final hotspotId =
        point.kind == AlertKind.hotspot && point.id.startsWith('hotspot:')
        ? point.id.substring('hotspot:'.length)
        : null;
    final distance = fix == null
        ? null
        : distanceMeters(fix.position, point.position);

    Widget body(Hotspot? hotspot) {
      final rows = [
        ...point.details,
        if (hotspot != null) ...hotspotDetails(hotspot),
        if (point.details.isEmpty && hotspot == null) ...fallbackDetails(point),
      ];
      final sources = point.sources.isNotEmpty
          ? point.sources
          : [fallbackSource(point, services)];
      return ListView(
        shrinkWrap: true,
        // Unter der Gestenleiste bleibt der letzte Knopf frei.
        padding: EdgeInsets.only(
          bottom: SonarSpace.xl + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          SheetHeader(
            title: point.effectiveCategory.label,
            // Ohne Zahl: das Tempo steht darunter groß auf dem Schild.
            leading: CategorySymbol(point.effectiveCategory, size: 32),
            onBack: onBack,
            onClose: onClose,
          ),
          if (point.maxSpeed != null || distance != null)
            _Lead(maxSpeed: point.maxSpeed, distanceMeters: distance),
          const _SectionTitle('Angaben'),
          if (rows.isEmpty)
            const _Hint(
              'Die Quelle nennt zu diesem Punkt keine weiteren Angaben.',
            )
          else
            for (final d in rows) _DetailRow(d),
          if (hotspot != null) ...[
            if (!driving)
              _DeleteHotspot(
                onDelete: () async {
                  await services.hotspots.remove(hotspot.id);
                  onClose();
                },
              ),
            const _Hint('Bearbeiten unter Einstellungen, Eigene Meldungen.'),
          ],
          _SectionTitle(sources.length == 1 ? 'Quelle' : 'Quellen'),
          for (final s in sources) _SourceTile(s),
        ],
      );
    }

    if (hotspotId == null) return body(null);
    return StreamBuilder<List<Hotspot>>(
      stream: services.hotspots.watch(),
      builder: (context, snap) {
        Hotspot? found;
        for (final h in snap.data ?? const <Hotspot>[]) {
          if (h.id == hotspotId) found = h;
        }
        return body(found);
      },
    );
  }
}

/// Angaben einer eigenen Meldung.
List<PointDetail> hotspotDetails(Hotspot h) => [
  PointDetail('Gemeldet', formatDateTime(h.createdAt)),
  PointDetail(
    'Gilt für',
    h.headingDeg == null
        ? 'beide Richtungen'
        : 'Fahrt nach ${compassName(h.headingDeg!)}',
  ),
  PointDetail('Warnung ab', formatDistance(h.radiusMeters)),
  if (h.note != null && h.note!.trim().isNotEmpty)
    PointDetail('Notiz', h.note!.trim()),
];

/// Was der Punkt selbst weiß, solange die Quelle keine Angaben liefert.
List<PointDetail> fallbackDetails(AlertPoint p) => [
  if (p.label != null && p.label!.trim().isNotEmpty)
    PointDetail('Bezeichnung', p.label!.trim()),
  if (p.travelBearings.isNotEmpty)
    PointDetail(
      'Gilt für',
      p.travelBearings.map((b) => 'Fahrt nach ${compassName(b)}').join(', '),
    ),
];

/// Quelle aus dem Kürzel des Punkts, solange er keine eigene Quellenliste trägt.
PointSource fallbackSource(AlertPoint p, AppServices services) =>
    switch (p.source) {
      'osm' => const PointSource(
        id: 'osm',
        name: 'OpenStreetMap',
        attribution: '© OpenStreetMap-Mitwirkende, ODbL 1.0',
      ),
      'hotspot' => const PointSource(
        id: 'hotspot',
        name: 'Eigene Meldung',
        attribution: 'Nur auf diesem Gerät gespeichert',
      ),
      final id => PointSource(
        id: id,
        name:
            [
              for (final plugin in services.alerts.plugins)
                if (plugin.id == id) plugin.displayName,
            ].firstOrNull ??
            id,
      ),
    };

/// „nach Osten“ für 90°, acht Himmelsrichtungen.
String compassName(double deg) {
  const names = [
    'Norden',
    'Nordosten',
    'Osten',
    'Südosten',
    'Süden',
    'Südwesten',
    'Westen',
    'Nordwesten',
  ];
  return names[(((deg % 360) + 22.5) ~/ 45) % 8];
}

String _two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.day)}.${_two(l.month)}.${l.year}';
}

String formatDateTime(DateTime t) {
  final l = t.toLocal();
  return '${formatDate(l)}, ${_two(l.hour)}:${_two(l.minute)} Uhr';
}

/// Tempolimit als Schild (der Blickfang des Blatts) und der Abstand von hier.
class _Lead extends StatelessWidget {
  const _Lead({required this.maxSpeed, required this.distanceMeters});

  final int? maxSpeed;
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      SonarSpace.m,
      SonarSpace.l,
      0,
    ),
    child: Row(
      children: [
        if (maxSpeed != null) ...[
          SpeedLimitSign(limitKmh: maxSpeed!, size: 72),
          const SizedBox(width: SonarSpace.l),
        ],
        if (distanceMeters != null)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDistance(distanceMeters!),
                  style: SonarText.distance.copyWith(color: SonarColors.text),
                ),
                const Text('Luftlinie von hier', style: SonarText.small),
              ],
            ),
          ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      SonarSpace.xl,
      SonarSpace.l,
      SonarSpace.xs,
    ),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: SonarText.label.copyWith(color: SonarColors.amber),
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      SonarSpace.s,
      SonarSpace.l,
      0,
    ),
    child: Text(text, style: SonarText.small),
  );
}

/// Label links in fester Spalte, Wert rechts daneben; bei großer Schrift untereinander.
class _DetailRow extends StatelessWidget {
  const _DetailRow(this.detail);

  final PointDetail detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: SonarSpace.l,
      vertical: SonarSpace.s,
    ),
    child: MergeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final label = Text(detail.label, style: SonarText.small);
          final value = Text(detail.value, style: SonarText.label);
          final scale = MediaQuery.textScalerOf(context).scale(1);
          if (scale > 1.3 || box.maxWidth < 280) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, value],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(width: 112, child: label),
              const SizedBox(width: SonarSpace.m),
              Expanded(child: value),
            ],
          );
        },
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile(this.source);

  final PointSource source;

  @override
  Widget build(BuildContext context) {
    final updated = source.updatedAt;
    final url = source.url;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SonarSpace.l,
        SonarSpace.s,
        SonarSpace.xs,
        SonarSpace.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source.name, style: SonarText.label),
          if (updated != null)
            Text('Stand ${formatDate(updated)}', style: SonarText.small),
          if (source.attribution != null)
            Text(source.attribution!, style: SonarText.small),
          if (url != null) _CopyableUrl(url),
        ],
      ),
    );
  }
}

/// Die Adresse zum Eintrag bei der Quelle: markierbar und mit einem Knopf zum Kopieren.
/// Ein Öffnen im Browser bräuchte ein weiteres Paket (url_launcher).
class _CopyableUrl extends StatefulWidget {
  const _CopyableUrl(this.url);

  final String url;

  @override
  State<_CopyableUrl> createState() => _CopyableUrlState();
}

class _CopyableUrlState extends State<_CopyableUrl> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SelectableText(
          widget.url,
          style: SonarText.small.copyWith(color: SonarColors.text),
        ),
      ),
      Semantics(
        liveRegion: true,
        child: _copied
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: SonarSpace.m),
                child: Text('Kopiert', style: SonarText.small),
              )
            : IconButton(
                tooltip: 'Adresse kopieren',
                onPressed: _copy,
                icon: const Icon(Icons.copy, size: 20),
              ),
      ),
    ],
  );
}

class _DeleteHotspot extends StatelessWidget {
  const _DeleteHotspot({required this.onDelete});

  final Future<void> Function() onDelete;

  Future<void> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Meldung löschen?'),
        content: const Text(
          'Die Stelle verschwindet von der Karte, es kommt dort keine Warnung mehr.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) await onDelete();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      SonarSpace.m,
      SonarSpace.l,
      0,
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => _confirm(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: SonarColors.red,
          side: const BorderSide(color: SonarColors.red),
          minimumSize: const Size(48, 48),
        ),
        icon: const Icon(Icons.delete_outline),
        label: const Text('Meldung löschen'),
      ),
    ),
  );
}
