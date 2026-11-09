import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'drive_controller.dart';
import 'map_heat.dart';
import 'point_details.dart' show formatDate;
import 'point_sheet.dart';
import 'standby_panel.dart';

/// „Hier 7 mobile Blitzer gemeldet“ bzw. „Hier 1 mobiler Blitzer gemeldet“.
String heatCountText(int count) => count == 1
    ? 'Hier 1 mobiler Blitzer gemeldet'
    : 'Hier $count mobile Blitzer gemeldet';

/// Wann im Umkreis gemeldet wurde: „vom 03.02.2025 bis 12.08.2026“, an einem Tag „am …“.
String? heatPeriodText(DateTime? earliest, DateTime? latest) {
  if (latest == null) return null;
  final from = earliest ?? latest;
  if (DateUtils.isSameDay(from.toLocal(), latest.toLocal())) {
    return 'am ${formatDate(latest)}';
  }
  return 'vom ${formatDate(from)} bis ${formatDate(latest)}';
}

/// Kurzes Blatt zu einem Wärmefleck oder roten Punkt: wie oft im Umkreis gemeldet und wann.
/// Gleiche Regeln wie das Punktblatt: bei Fahrt niedriger und ohne Abdunkeln.
Future<void> showHeatSheet(BuildContext context, HeatCell cell) {
  final driving = isDriving(
    ProviderScope.containerOf(context).read(driveControllerProvider),
  );
  final height = MediaQuery.sizeOf(context).height;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: SonarColors.surface,
    barrierColor: driving
        ? Colors.transparent
        : SonarColors.bg.withValues(alpha: 0.45),
    constraints: BoxConstraints(
      maxHeight:
          height * (driving ? pointSheetMaxHeightDriving : pointSheetMaxHeight),
    ),
    builder: (context) => HeatSheet(cell: cell),
  );
}

class HeatSheet extends StatelessWidget {
  const HeatSheet({super.key, required this.cell});

  final HeatCell cell;

  @override
  Widget build(BuildContext context) {
    final period = heatPeriodText(cell.earliest, cell.latest);
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.only(
        bottom: SonarSpace.xl + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        SheetHeader(
          title: 'Mobile Blitzer',
          onClose: () => Navigator.of(context).maybePop(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SonarSpace.l,
            SonarSpace.s,
            SonarSpace.l,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(heatCountText(cell.count), style: SonarText.label),
              if (period != null) Text(period, style: SonarText.label),
              const SizedBox(height: SonarSpace.s),
              Text(
                'Gezählt im Umkreis von ${heatNeighbourMeters.round()} m. '
                'Je öfter dort gemessen wurde, desto kräftiger das Rot; '
                'ältere Meldungen zählen weniger.',
                style: SonarText.small,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
