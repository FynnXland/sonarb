import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/contracts/warning_engine.dart';
import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import 'drive_controller.dart';
import 'format.dart';
import 'point_details.dart';
import 'standby_panel.dart';
import 'symbols/category_symbol.dart';

/// Das Blatt reicht höchstens bis hier (Anteil der Bildschirmhöhe). Bei der Fahrt niedriger:
/// Hochkant bleiben darüber Tempo, Limit und das ganze Hinweisfeld frei (bei 360 × 640 endet
/// das Hinweisfeld knapp über der Hälfte).
const pointSheetMaxHeight = 0.55;
const pointSheetMaxHeightDriving = 0.45;

/// So viele Punkte zeigt die Liste eines Bündels; der Rest braucht einen näheren Blick.
const clusterListMax = 12;

/// Öffnet das Blatt zu [points]: ein Punkt zeigt seine Angaben, mehrere (ein Bündel) erst eine
/// kurze Liste. Eine Liste statt Hineinzoomen, weil Punkte an derselben Stelle sich durch Zoomen
/// nie trennen und die Karte dabei nicht springt.
Future<void> showPointSheet(BuildContext context, List<AlertPoint> points) {
  if (points.isEmpty) return Future.value();
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
    // Bei der Fahrt nicht abdunkeln: Tempo und Warnung darüber bleiben voll lesbar.
    barrierColor: driving
        ? Colors.transparent
        : SonarColors.bg.withValues(alpha: 0.45),
    constraints: BoxConstraints(
      maxHeight:
          height * (driving ? pointSheetMaxHeightDriving : pointSheetMaxHeight),
    ),
    builder: (_) => PointSheet(points: points),
  );
}

/// Inhalt des Blatts. Schließt sich selbst, sobald eine Hauptwarnung beginnt: dann gehört der
/// Blick auf die Straße, und die Warnung steht ohnehin groß im Hinweisfeld.
class PointSheet extends ConsumerStatefulWidget {
  const PointSheet({super.key, required this.points});

  final List<AlertPoint> points;

  @override
  ConsumerState<PointSheet> createState() => _PointSheetState();
}

class _PointSheetState extends ConsumerState<PointSheet> {
  late AlertPoint? _open = widget.points.length == 1
      ? widget.points.single
      : null;

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    ref.listen(
      driveControllerProvider.select(
        (d) => d.primary?.level == WarningLevel.main,
      ),
      (was, now) {
        if (now && was != true) _close();
      },
    );
    final open = _open;
    if (open != null) {
      return PointDetails(
        point: open,
        onClose: _close,
        onBack: widget.points.length > 1
            ? () => setState(() => _open = null)
            : null,
      );
    }
    return _ClusterList(
      points: widget.points,
      onPick: (p) => setState(() => _open = p),
      onClose: _close,
    );
  }
}

/// Kopfzeile des Blatts: optional Zurück, Titel, Schließen. Beide Knöpfe 48 × 48.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.leading,
    this.onBack,
  });

  final String title;
  final Widget? leading;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: SonarSpace.s, right: SonarSpace.xs),
    child: Row(
      children: [
        if (onBack != null)
          IconButton(
            tooltip: 'Zurück zur Liste',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          )
        else
          const SizedBox(width: SonarSpace.s),
        if (leading != null) ...[
          // Symbole sind nicht quadratisch (Nadel höher, Tafel breiter).
          SizedBox(
            width: 44,
            height: 48,
            child: FittedBox(fit: BoxFit.scaleDown, child: leading),
          ),
          const SizedBox(width: SonarSpace.m),
        ],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: SonarText.warningKind),
          ),
        ),
        IconButton(
          tooltip: 'Schließen',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class _ClusterList extends ConsumerWidget {
  const _ClusterList({
    required this.points,
    required this.onPick,
    required this.onClose,
  });

  final List<AlertPoint> points;
  final ValueChanged<AlertPoint> onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fix = ref.watch(driveControllerProvider.select((d) => d.fix));
    final shown = points.take(clusterListMax).toList();
    final rest = points.length - shown.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: '${points.length} Punkte an dieser Stelle',
          onClose: onClose,
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.only(
              bottom: SonarSpace.l + MediaQuery.viewPaddingOf(context).bottom,
            ),
            children: [
              for (final p in shown)
                ListTile(
                  minTileHeight: 56,
                  leading: SizedBox(
                    width: 36,
                    height: 40,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: CategorySymbol(p.effectiveCategory, size: 24),
                    ),
                  ),
                  title: Text(
                    p.maxSpeed == null
                        ? p.effectiveCategory.label
                        : '${p.effectiveCategory.label}, ${p.maxSpeed} km/h',
                    style: SonarText.label,
                  ),
                  subtitle: fix == null
                      ? null
                      : Text(
                          '${formatDistance(distanceMeters(fix.position, p.position))} entfernt',
                          style: SonarText.small,
                        ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onPick(p),
                ),
              if (rest > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SonarSpace.l,
                    SonarSpace.s,
                    SonarSpace.l,
                    0,
                  ),
                  child: Text(
                    'Und $rest weitere. Näher heranzoomen, um sie einzeln zu sehen.',
                    style: SonarText.small,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
