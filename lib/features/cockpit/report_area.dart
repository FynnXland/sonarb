import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/model/position_fix.dart';
import 'drive_controller.dart';
import 'format.dart';
import 'hotspot_tap.dart';
import 'report_sheet.dart';

/// „Melden“ öffnet ein Auswahlblatt; erst die Wahl speichert. Danach 5 s „Rückgängig“.
class ReportArea extends ConsumerWidget {
  const ReportArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tap = ref.watch(hotspotTapProvider);
    final fix = ref.watch(driveControllerProvider.select((d) => d.usableFix));
    final controller = ref.read(hotspotTapProvider.notifier);

    if (tap.phase == HotspotTapPhase.confirm) {
      return SizedBox(
        height: SonarSpace.driveTarget,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Gemeldet: ${hotspotKindLabel(tap.kind)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SonarText.warningKind.copyWith(fontSize: 19),
                ),
              ),
            ),
            const SizedBox(width: SonarSpace.s),
            Flexible(
              child: SizedBox(
                height: SonarSpace.driveTarget,
                child: OutlinedButton(
                  onPressed: controller.undo,
                  style: OutlinedButton.styleFrom(
                    textStyle: SonarText.button,
                    padding: const EdgeInsets.symmetric(
                      horizontal: SonarSpace.l,
                    ),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Rückgängig'),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final saving = tap.phase == HotspotTapPhase.saving;
    final reason = tap.message ?? (fix == null ? 'Kein GPS-Fix' : null);
    return SizedBox(
      height: SonarSpace.driveTarget,
      width: double.infinity,
      child: FilledButton(
        onPressed: fix == null || saving
            ? null
            : () => _report(context, controller, fix),
        style: FilledButton.styleFrom(
          backgroundColor: SonarColors.hotspot,
          foregroundColor: SonarColors.onSignal,
          disabledBackgroundColor: SonarColors.surfaceHigh,
          disabledForegroundColor: SonarColors.textMuted,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Melden'),
              if (reason != null)
                Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Die Position gilt ab dem Tippen auf „Melden“, auch wenn die Wahl etwas dauert.
  Future<void> _report(
    BuildContext context,
    HotspotTapController controller,
    PositionFix fix,
  ) async {
    final kind = await showReportSheet(context);
    if (kind != null) await controller.report(fix, kind);
  }
}
