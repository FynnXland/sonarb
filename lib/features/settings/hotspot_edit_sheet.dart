import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/contracts/hotspot_repository.dart';
import 'format.dart';

/// Bearbeiten: Art, Notiz, Richtung löschen. Gibt den geänderten Hotspot zurück, null bei Abbruch.
Future<Hotspot?> showHotspotEditSheet(BuildContext context, Hotspot h) =>
    showModalBottomSheet<Hotspot>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SonarColors.surface,
      builder: (_) => _EditSheet(h),
    );

class _EditSheet extends StatefulWidget {
  const _EditSheet(this.original);

  final Hotspot original;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late HotspotKind _kind = widget.original.kind;
  late final _note = TextEditingController(text: widget.original.note ?? '');
  bool _clearHeading = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final o = widget.original;
    final note = _note.text.trim();
    // Neu bauen statt copyWith: copyWith kann eine Notiz nicht auf null setzen.
    Navigator.pop(
      context,
      Hotspot(
        id: o.id,
        position: o.position,
        createdAt: o.createdAt,
        kind: _kind,
        headingDeg: _clearHeading ? null : o.headingDeg,
        note: note.isEmpty ? null : note,
        radiusMeters: o.radiusMeters,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heading = widget.original.headingDeg;
    return Padding(
      padding: EdgeInsets.only(
        left: SonarSpace.l,
        right: SonarSpace.l,
        top: SonarSpace.l,
        bottom: MediaQuery.viewInsetsOf(context).bottom + SonarSpace.l,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Meldung bearbeiten', style: SonarText.warningKind),
            const SizedBox(height: SonarSpace.m),
            const Text('Art', style: SonarText.label),
            const SizedBox(height: SonarSpace.xs),
            Wrap(
              spacing: SonarSpace.s,
              runSpacing: SonarSpace.s,
              children: [
                for (final k in HotspotKind.values)
                  ChoiceChip(
                    label: Text(hotspotKindLabel(k)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: SonarSpace.l),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Notiz',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: SonarSpace.s),
            if (heading == null)
              const Text(
                'Gilt für alle Fahrtrichtungen.',
                style: SonarText.small,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _clearHeading
                          ? 'Gilt nach dem Speichern für alle Fahrtrichtungen.'
                          : 'Gilt nur in Fahrtrichtung ${heading.round()}°.',
                      style: SonarText.small,
                    ),
                  ),
                  if (!_clearHeading)
                    TextButton(
                      onPressed: () => setState(() => _clearHeading = true),
                      child: const Text('Richtung löschen'),
                    ),
                ],
              ),
            const SizedBox(height: SonarSpace.l),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: SonarSpace.s),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Speichern'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
