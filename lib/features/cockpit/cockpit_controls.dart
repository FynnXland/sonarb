import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/theme.dart';
import 'drive_controller.dart';
import 'instruments.dart';

/// Kopfzeile: GPS-Güte links, Ton und Einstellungen rechts (Einstellungen in der Ecke).
class CockpitStatusBar extends ConsumerWidget {
  const CockpitStatusBar({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drive = ref.watch(driveControllerProvider);
    final muted = ref.watch(appSettingsProvider.select((s) => s.muted));
    final enforcement = ref.watch(
      appSettingsProvider.select((s) => s.enforcementFeatures),
    );
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(child: GpsIndicator(drive: drive)),
                if (!enforcement) ...[
                  const SizedBox(width: SonarSpace.m),
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: EnforcementOffBadge(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Semantics(
            toggled: !muted,
            label: muted ? 'Ton aus' : 'Ton an',
            excludeSemantics: true,
            child: TextButton.icon(
              onPressed: () =>
                  ref.read(appSettingsProvider.notifier).toggleMuted(),
              style: TextButton.styleFrom(
                foregroundColor: muted ? SonarColors.amber : SonarColors.text,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: SonarSpace.m),
              ),
              icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
              label: Text(
                muted ? 'Stumm' : 'Ton an',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Einstellungen',
            onPressed: onOpenSettings,
            iconSize: 28,
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
    );
  }
}

/// Steht in der Kopfzeile, solange die Blitzer-Funktionen aus sind: Wer nichts gemeldet
/// bekommt, soll nicht glauben, es gebe keine Blitzer. Reicht der Platz nicht für den Text
/// (schmales Telefon, große Schrift), bleibt das durchgestrichene Kamera-Symbol; abgeschnitten
/// wird nichts.
class EnforcementOffBadge extends StatelessWidget {
  const EnforcementOffBadge({super.key});

  static const label = 'Blitzer aus';
  static const _icon = 20.0;

  @override
  Widget build(BuildContext context) {
    final style = SonarText.label.copyWith(color: SonarColors.amber);
    return Semantics(
      label: 'Blitzer-Funktionen sind aus',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Blitzer-Funktionen sind aus',
        child: LayoutBuilder(
          builder: (context, box) {
            final text = TextPainter(
              text: TextSpan(text: label, style: style),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            final fits = _icon + SonarSpace.xs + text.width <= box.maxWidth;
            text.dispose();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  size: _icon,
                  color: SonarColors.amber,
                ),
                if (fits) ...[
                  const SizedBox(width: SonarSpace.xs),
                  Text(label, maxLines: 1, softWrap: false, style: style),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
