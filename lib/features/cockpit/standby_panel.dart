import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/sonar_mark.dart';
import '../../app/theme.dart';
import 'drive_controller.dart';
import 'drive_state.dart';
import 'location_service.dart';

/// Ab diesem Tempo gilt eine Position als Fahrt, solange die Erkennung noch nichts meldet.
const _drivingSpeedMps = 2.0;

/// Fährt gerade: erkannt als Fahrt, oder noch unklar und mit gültigem Fix schnell genug.
bool isDriving(DriveState drive) {
  if (!drive.running) return false;
  return switch (drive.motion) {
    MotionState.driving => true,
    MotionState.stationary => false,
    MotionState.unknown =>
      drive.fix != null &&
          !drive.stale &&
          drive.fix!.speedMps >= _drivingSpeedMps,
  };
}

/// Im Stand: Sonar lauscht, die App erkennt die Fahrt selbst.
class ReadyPanel extends StatelessWidget {
  const ReadyPanel({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Bereit. Erkennt Fahrt automatisch.',
    excludeSemantics: true,
    child: LayoutBuilder(
      builder: (context, box) {
        final ring = (box.maxHeight * 0.8).clamp(56.0, 120.0);
        return Row(
          children: [
            SonarPulse(size: ring),
            const SizedBox(width: SonarSpace.l),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Schmaler Bildschirm, große Schrift: die Zeile darunter bricht um, „Bereit“
                  // wird dann kleiner statt unten aus dem Feld zu ragen.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Bereit',
                        style: SonarText.speed.copyWith(fontSize: 56),
                      ),
                    ),
                  ),
                  const SizedBox(height: SonarSpace.xs),
                  const Text(
                    'erkennt Fahrt automatisch',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SonarText.label,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Anzeige, solange der Standort geprüft wird oder nicht nutzbar ist.
class BlockedPanel extends ConsumerWidget {
  const BlockedPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drive = ref.watch(driveControllerProvider);
    final controller = ref.read(driveControllerProvider.notifier);
    final location = ref.read(locationServiceProvider);

    if (drive.phase != DrivePhase.blocked) {
      return const Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(width: SonarSpace.m),
          Expanded(
            child: Text('Standort wird geprüft', style: SonarText.label),
          ),
        ],
      );
    }

    final (message, actionLabel, action) = switch (drive.access) {
      LocationAccess.serviceOff => (
        'GPS aus. In den Systemeinstellungen einschalten.',
        'Standort-Einstellungen',
        location.openLocationSettings,
      ),
      LocationAccess.deniedForever => (
        'Standortzugriff dauerhaft abgelehnt. In den App-Einstellungen erlauben.',
        'Einstellungen öffnen',
        location.openAppSettings,
      ),
      _ => (
        'Standortzugriff abgelehnt. Ohne Standort gibt es keine Warnungen.',
        null,
        null,
      ),
    };

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: SonarText.label),
          const SizedBox(height: SonarSpace.m),
          SizedBox(
            height: SonarSpace.driveTarget,
            child: FilledButton(
              onPressed: controller.start,
              child: const Text('Erneut prüfen'),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: SonarSpace.s),
            OutlinedButton(onPressed: action, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  }
}
