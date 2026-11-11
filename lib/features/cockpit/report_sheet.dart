import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/model/alert_point.dart';
import '../../core/model/enforcement.dart';
import 'format.dart';

/// So lange bleibt das Auswahlblatt offen, wenn niemand etwas wählt.
const reportSheetTimeout = Duration(seconds: 8);

/// Die Arten, die der Nutzer melden kann.
const reportKinds = [
  HotspotKind.mobileCamera,
  HotspotKind.distanceCheck,
  HotspotKind.construction,
  HotspotKind.danger,
];

/// Die Arten im Blatt; ohne Blitzer-Funktionen fehlen mobiler Blitzer und Abstandsmessung.
List<HotspotKind> reportKindsFor({required bool enforcement}) => [
  for (final k in reportKinds)
    if (enforcement || !reportKindIsEnforcement(k)) k,
];

IconData reportKindIcon(HotspotKind kind) => switch (kind) {
  HotspotKind.mobileCamera => Icons.photo_camera,
  HotspotKind.distanceCheck => Icons.straighten,
  HotspotKind.construction => Icons.construction,
  HotspotKind.danger || HotspotKind.other => Icons.warning_amber,
};

/// Öffnet das Auswahlblatt. Ergebnis null bei Abbrechen oder Zeitablauf.
Future<HotspotKind?> showReportSheet(
  BuildContext context, {
  List<HotspotKind> kinds = reportKinds,
}) => showModalBottomSheet<HotspotKind>(
  context: context,
  isScrollControlled: true,
  backgroundColor: SonarColors.surface,
  builder: (_) => ReportSheet(kinds: kinds),
);

/// Große Kacheln, damit man sie im Auto trifft, und ein großes Abbrechen.
class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, this.kinds = reportKinds});

  /// Kacheln zu zweit nebeneinander; bei ungerader Zahl steht die letzte allein.
  final List<HotspotKind> kinds;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(reportSheetTimeout, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(SonarSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Was melden?', style: SonarText.warningKind),
          const SizedBox(height: SonarSpace.m),
          for (var i = 0; i < widget.kinds.length; i += 2) ...[
            Row(
              children: [
                Expanded(child: _KindTile(kind: widget.kinds[i])),
                if (i + 1 < widget.kinds.length) ...[
                  const SizedBox(width: SonarSpace.m),
                  Expanded(child: _KindTile(kind: widget.kinds[i + 1])),
                ],
              ],
            ),
            const SizedBox(height: SonarSpace.m),
          ],
          SizedBox(
            height: SonarSpace.driveTarget,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(textStyle: SonarText.button),
              child: const Text('Abbrechen'),
            ),
          ),
          const SizedBox(height: SonarSpace.s),
          const _Countdown(),
        ],
      ),
    ),
  );
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind});

  final HotspotKind kind;

  @override
  Widget build(BuildContext context) => Material(
    color: SonarColors.surfaceHigh,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SonarRadius.m),
      side: const BorderSide(color: SonarColors.outline),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(SonarRadius.m),
      onTap: () => Navigator.of(context).pop(kind),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 96),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SonarSpace.s,
            vertical: SonarSpace.m,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(reportKindIcon(kind), size: 32, color: SonarColors.hotspot),
              const SizedBox(height: SonarSpace.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  hotspotKindLabel(kind),
                  maxLines: 1,
                  softWrap: false,
                  style: SonarText.label.copyWith(fontSize: 17),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Dünner Balken, der in [reportSheetTimeout] ausläuft: zeigt, dass sich das Blatt von
/// selbst schließt.
class _Countdown extends StatelessWidget {
  const _Countdown();

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox(height: 4);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: reportSheetTimeout,
      builder: (_, value, _) => LinearProgressIndicator(
        value: value,
        minHeight: 4,
        color: SonarColors.textMuted,
        backgroundColor: SonarColors.surfaceHigh,
      ),
    );
  }
}
