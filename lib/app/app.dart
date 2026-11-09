import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/cockpit/cockpit_screen.dart';
import '../features/cockpit/drive_controller.dart';
import '../features/cockpit/instruments.dart';
import '../features/cockpit/layer_symbol.dart';
import '../features/cockpit/symbols/category_symbol.dart';
import '../features/settings/settings_screen.dart';
import '../core/model/alert_point.dart';
import 'intro.dart';
import 'map_layer_settings.dart';
import 'services.dart';
import 'theme.dart';
import 'welcome.dart';

class SonarbApp extends StatelessWidget {
  const SonarbApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sonarb',
    debugShowCheckedModeBanner: false,
    theme: buildSonarTheme(),
    themeMode: ThemeMode.dark,
    home: const StartGate(),
  );
}

/// Zeigt beim Start das Logo mit Peilkeil, solange die Module laden, danach das Cockpit.
class StartGate extends ConsumerWidget {
  const StartGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootstrapProvider);
    if (boot case AsyncError(:final error)) {
      return _StartMessage(
        text: 'Start fehlgeschlagen: $error',
        action: () => ref.invalidate(bootstrapProvider),
      );
    }
    return IntroGate(ready: boot is AsyncData, child: const _Home());
  }
}

/// Beim ersten Start der Erklärbildschirm, danach das Cockpit. Erst das Cockpit fragt
/// nach dem Standort; [IntroGate] baut dieses Widget, wenn die Module geladen sind.
class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(welcomeSeenProvider)) return const WelcomeScreen();
    return CockpitScreen(
      onOpenSettings: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Consumer(
            builder: (context, ref, _) => SettingsScreen(
              mapLayerSymbol: _layerSymbol,
              categorySymbol: _categorySymbol,
              limitSign: _limitSign,
              googleAccuracyDeclined: ref.watch(
                driveControllerProvider.select((s) => s.googleAccuracyDeclined),
              ),
              onRetryGoogleAccuracy: () => ref
                  .read(driveControllerProvider.notifier)
                  .retryGoogleAccuracy(),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _layerSymbol(MapLayer layer, bool on) =>
    LayerSymbol(layer: layer, on: on);

Widget _categorySymbol(AlertCategory c, {int? speed, required double size}) =>
    CategorySymbol(c, speed: speed, size: size);

Widget _limitSign({int? kmh, bool none = false, required double size}) =>
    kmh != null
    ? SpeedLimitSign(limitKmh: kmh, size: size)
    : none
    ? NoSpeedLimitSign(size: size)
    : const SizedBox.shrink();

class _StartMessage extends StatelessWidget {
  const _StartMessage({required this.text, this.action});

  final String text;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(SonarSpace.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Sonarb', style: SonarText.warningKind),
            const SizedBox(height: SonarSpace.l),
            if (action == null)
              const LinearProgressIndicator()
            else
              const SizedBox.shrink(),
            const SizedBox(height: SonarSpace.m),
            Text(text, style: SonarText.label),
            if (action != null) ...[
              const SizedBox(height: SonarSpace.l),
              FilledButton(
                onPressed: action,
                child: const Text('Erneut starten'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
