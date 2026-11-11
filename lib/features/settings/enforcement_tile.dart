import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/legal.dart';
import '../../app/theme.dart';

/// Titel des Schalters, überall gleich (Einstellungen, Startbildschirm).
const enforcementTitle = 'Blitzer-Funktionen';

/// Zeile unter dem Schalter: was er gerade bewirkt.
String enforcementSubtitle({required bool on}) => on
    ? 'Zeigt Blitzer und Kontrollen. Beim Fahren in Deutschland nicht erlaubt '
          '(§ 23 Abs. 1c StVO)'
    : 'Tempo, Tempolimit, Baustellen und Gefahren laufen weiter';

/// Ein Schalter für alles, was Verkehrsüberwachung anzeigt oder meldet
/// ([AppSettings.enforcementFeatures]). Mit [notice] steht der ausführliche Rechtshinweis
/// darunter; sonst trägt ihn die Seite „Über“.
class EnforcementTile extends ConsumerWidget {
  const EnforcementTile({
    super.key,
    this.notice = false,
    this.subtitle,
    this.contentPadding,
  });

  final bool notice;

  /// Innenabstand des Schalters; null ist der Standard der Liste.
  final EdgeInsetsGeometry? contentPadding;

  /// Eigene Unterzeile statt [enforcementSubtitle], etwa im Startbildschirm.
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(
      appSettingsProvider.select((s) => s.enforcementFeatures),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: contentPadding,
          secondary: Icon(
            on ? Icons.photo_camera_outlined : Icons.no_photography_outlined,
            color: on ? null : SonarColors.amber,
          ),
          title: const Text(enforcementTitle),
          subtitle: Text(subtitle ?? enforcementSubtitle(on: on)),
          value: on,
          onChanged: (v) => ref
              .read(appSettingsProvider.notifier)
              .change((s) => s.copyWith(enforcementFeatures: v)),
        ),
        if (notice)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              SonarSpace.l,
              0,
              SonarSpace.l,
              SonarSpace.s,
            ),
            child: Text(enforcementNotice, style: SonarText.small),
          ),
      ],
    );
  }
}
