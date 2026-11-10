import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import 'drive_controller.dart';

/// Was das Kartenmenü anbietet.
enum MapMenuAction { northUp, headingUp, flat, tilted }

/// Beendet die App vollständig: Überwachung und Vordergrunddienst stoppen, offene Hotspots
/// speichern, dann schließt sich die App.
Future<void> quitApp(WidgetRef ref) async {
  // Erst schließen, wenn der Vordergrunddienst wirklich beendet ist.
  await ref.read(driveControllerProvider.notifier).stop();
  await ref.read(servicesProvider).hotspots.flush();
  await SystemNavigator.pop();
}

/// Aus-Knopf oben rechts links neben „⋯“: beendet Sonarb mit einem Tipp.
class QuitButton extends ConsumerWidget {
  const QuitButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
    color: SonarColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SonarRadius.s),
      side: const BorderSide(color: SonarColors.outline),
    ),
    child: IconButton(
      tooltip: 'Sonarb beenden',
      onPressed: () => quitApp(ref),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: const Icon(Icons.power_settings_new, color: SonarColors.red),
    ),
  );
}

/// Kleiner „⋯“-Knopf oben rechts auf der Karte: Ausrichtung und Ansicht.
class MapMenuButton extends ConsumerWidget {
  const MapMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final ctrl = ref.read(appSettingsProvider.notifier);
    final tilted = s.headingUp && s.tiltWhileDriving;
    return Material(
      color: SonarColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SonarRadius.s),
        side: const BorderSide(color: SonarColors.outline),
      ),
      child: PopupMenuButton<MapMenuAction>(
        tooltip: 'Kartenoptionen',
        icon: const Icon(Icons.more_horiz, color: SonarColors.text),
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        color: SonarColors.surfaceHigh,
        onSelected: (a) => switch (a) {
          MapMenuAction.northUp => ctrl.change(
            (x) => x.copyWith(headingUp: false),
          ),
          MapMenuAction.headingUp => ctrl.change(
            (x) => x.copyWith(headingUp: true),
          ),
          MapMenuAction.flat => ctrl.change(
            (x) => x.copyWith(tiltWhileDriving: false),
          ),
          // Neigen geht nur mit Fahrtrichtung oben; die Wahl stellt beides ein.
          MapMenuAction.tilted => ctrl.change(
            (x) => x.copyWith(tiltWhileDriving: true, headingUp: true),
          ),
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: MapMenuAction.northUp,
            checked: !s.headingUp,
            child: const Text('Norden oben'),
          ),
          CheckedPopupMenuItem(
            value: MapMenuAction.headingUp,
            checked: s.headingUp,
            child: const Text('Fahrtrichtung oben'),
          ),
          const PopupMenuDivider(),
          CheckedPopupMenuItem(
            value: MapMenuAction.flat,
            checked: !tilted,
            child: const Text('Flach'),
          ),
          CheckedPopupMenuItem(
            value: MapMenuAction.tilted,
            checked: tilted,
            child: const Text('Bei Fahrt geneigt'),
          ),
        ],
      ),
    );
  }
}

/// Zurück zur eigenen Position, mit Fahrtrichtung oben; bei Fahrt auch zurück in die Neigung.
class RecenterButton extends StatelessWidget {
  const RecenterButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
    ),
    icon: const Icon(Icons.my_location),
    label: const Text('Zentrieren'),
  );
}

/// Kompass unter dem Kartenmenü, solange die Karte nicht nach Norden zeigt. Die Nadel zeigt
/// nach Norden (rote Spitze); Tippen dreht die Karte zurück.
class NorthButton extends StatelessWidget {
  const NorthButton({
    super.key,
    required this.rotationDeg,
    required this.onPressed,
  });

  /// Drehung der Karte im Uhrzeigersinn, wie `MapCamera.rotation`: dorthin zeigt Norden.
  final double rotationDeg;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: SonarColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SonarRadius.s),
      side: const BorderSide(color: SonarColors.outline),
    ),
    child: IconButton(
      tooltip: 'Norden oben',
      onPressed: onPressed,
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: Transform.rotate(
        angle: rotationDeg * math.pi / 180,
        child: const SizedBox.square(
          dimension: 26,
          child: CustomPaint(painter: _NeedlePainter()),
        ),
      ),
    ),
  );
}

class _NeedlePainter extends CustomPainter {
  const _NeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final h = size.height / 2;
    final w = size.width * 0.22;
    final north = Path()
      ..moveTo(c.dx, c.dy - h)
      ..lineTo(c.dx + w, c.dy)
      ..lineTo(c.dx - w, c.dy)
      ..close();
    final south = Path()
      ..moveTo(c.dx, c.dy + h)
      ..lineTo(c.dx + w, c.dy)
      ..lineTo(c.dx - w, c.dy)
      ..close();
    canvas.drawPath(north, Paint()..color = SonarColors.red);
    canvas.drawPath(south, Paint()..color = SonarColors.textMuted);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => false;
}
