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
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(child: GpsIndicator(drive: drive)),
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
