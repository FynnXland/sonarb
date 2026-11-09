import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import 'cockpit_controls.dart';
import 'data_coverage.dart';
import 'drive_controller.dart';
import 'drive_map.dart';
import 'drive_state.dart';
import 'instruments.dart';
import 'point_sheet.dart';
import 'location_service.dart';
import 'report_area.dart';
import 'screen_wake.dart';
import 'standby_panel.dart';
import 'upcoming_panel.dart';

/// Hauptbildschirm. Hochformat: Instrumente oben, Karte unten. Querformat: nebeneinander.
class CockpitScreen extends ConsumerStatefulWidget {
  const CockpitScreen({super.key, required this.onOpenSettings});

  /// Öffnet die Einstellungen; das Future endet, wenn der Nutzer zurückkehrt.
  final Future<void> Function() onOpenSettings;

  @override
  ConsumerState<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends ConsumerState<CockpitScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _resumed = true;
  bool _onTop = true;
  bool? _wakeOn;
  late final ScreenWake _wake;

  @override
  void initState() {
    super.initState();
    _wake = ref.read(screenWakeProvider);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _resumed = true;
        _syncWake();
        _recheckAccess();
      },
      onPause: () {
        _resumed = false;
        _syncWake();
        ref.read(servicesProvider).hotspots.flush();
      },
    );
    _syncWake();
    // Es gibt keinen Start-Knopf: Die Überwachung läuft, sobald das Cockpit offen ist.
    Future.microtask(() {
      if (mounted) ref.read(driveControllerProvider.notifier).start();
    });
  }

  /// Zurück in der App, etwa aus den Systemeinstellungen: nur nachsehen, nicht fragen. Der
  /// Berechtigungsdialog pausiert selbst die App; eine Anfrage hier löste ihn also nach jedem
  /// „Nicht erlauben“ gleich wieder aus. Gefragt wird beim Öffnen und über „Erneut prüfen“.
  Future<void> _recheckAccess() async {
    if (ref.read(driveControllerProvider).phase != DrivePhase.blocked) return;
    final LocationAccess access;
    try {
      access = await ref.read(locationServiceProvider).checkAccess();
    } catch (_) {
      return;
    }
    if (!mounted || access != LocationAccess.granted) return;
    if (ref.read(driveControllerProvider).phase == DrivePhase.blocked) {
      ref.read(driveControllerProvider.notifier).start();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    if (_wakeOn == true) _wake.setOn(false);
    super.dispose();
  }

  void _syncWake() {
    final on = _resumed && _onTop;
    if (_wakeOn == on) return;
    _wakeOn = on;
    _wake.setOn(on);
  }

  Future<void> _openSettings() async {
    _onTop = false;
    _syncWake();
    await widget.onOpenSettings();
    if (!mounted) return;
    _onTop = true;
    _syncWake();
  }

  @override
  Widget build(BuildContext context) {
    final map = ref.watch(cockpitMapProvider)(context);
    final status = CockpitStatusBar(onOpenSettings: _openSettings);
    const gap = SizedBox(height: SonarSpace.s);
    const pad = EdgeInsets.symmetric(horizontal: SonarSpace.m);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth > box.maxHeight) {
              return Row(
                children: [
                  SizedBox(
                    width: box.maxWidth * 0.5,
                    child: Padding(
                      padding: const EdgeInsets.all(SonarSpace.m)
                          .copyWith(top: SonarSpace.xs),
                      child: Column(
                        children: [
                          status,
                          gap,
                          const Expanded(child: _Instruments(bandHeight: 64)),
                          gap,
                          const ReportArea(),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: map),
                ],
              );
            }
            return Column(
              children: [
                Padding(padding: pad, child: status),
                Padding(
                  padding: pad,
                  child: _InstrumentsFrame(
                    speedHeight: speedRowHeight(box.maxHeight),
                    extraRows: upcomingRowsFor(
                      box.maxHeight,
                      MediaQuery.textScalerOf(context).scale(1),
                    ),
                    blockedHeight: (box.maxHeight * 0.38).clamp(224.0, 340.0),
                  ),
                ),
                gap,
                Expanded(child: map),
                const Padding(
                  padding: EdgeInsets.all(SonarSpace.s),
                  child: ReportArea(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Höhe der Tempozeile im Hochformat: so hoch, wie Zahl und Schild groß lesbar brauchen, nicht
/// mehr. Den Rest bekommt die Karte, damit vorn mehr Strecke zu sehen ist.
double speedRowHeight(double screenHeight) =>
    (screenHeight * 0.15).clamp(104.0, 132.0);

/// Kleine Zeilen unter dem nächsten Punkt: auf niedrigen Bildschirmen mit großer Schrift nur
/// eine, damit die Karte Höhe behält.
int upcomingRowsFor(double screenHeight, double textScale) =>
    screenHeight < 720 && textScale > 1.2 ? 1 : upcomingExtraRows;

/// Hochformat: Instrumente so hoch wie ihr Inhalt (Tempozeile oder Bereit-Anzeige, darunter das
/// Hinweisfeld). Nur solange der Standort nicht nutzbar ist, steht eine feste Höhe für die
/// Erklärung zur Verfügung.
class _InstrumentsFrame extends ConsumerWidget {
  const _InstrumentsFrame({
    required this.speedHeight,
    required this.blockedHeight,
    required this.extraRows,
  });

  final double speedHeight;
  final double blockedHeight;
  final int extraRows;

  /// Ring und Text im Bereit-Zustand bei normaler Schrift.
  static const _readyHeight = 100.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drive = ref.watch(driveControllerProvider);
    if (!drive.running) {
      return SizedBox(
        height: blockedHeight,
        child: const Center(child: BlockedPanel()),
      );
    }
    final driving = isDriving(drive);
    // Die Bereit-Anzeige ist Text: sie wächst mit der Systemschrift.
    final readyHeight = MediaQuery.textScalerOf(context)
        .scale(_readyHeight)
        .clamp(_readyHeight, 176.0);
    return AnimatedSize(
      duration: SonarMotion.fade,
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (drive.error != null)
            Text(
              drive.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SonarText.small.copyWith(color: SonarColors.red),
            ),
          SizedBox(
            height: driving ? speedHeight : readyHeight,
            child: AnimatedSwitcher(
              duration: SonarMotion.fade,
              child: driving
                  ? SpeedRow(key: const ValueKey('driving'), drive: drive)
                  // Beim Wechsel zur Fahrt schrumpft die Fläche sofort; die ausblendende
                  // Bereit-Anzeige behält ihre Höhe und wird beschnitten, statt zu quetschen.
                  : ClipRect(
                      key: const ValueKey('ready'),
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: readyHeight,
                        maxHeight: readyHeight,
                        child: const ReadyPanel(),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: SonarSpace.s),
          UpcomingPanel(
            upcoming: drive.upcoming,
            height: 72,
            coverage: ref.watch(coverageAroundProvider),
            still: driving,
            extraRows: extraRows,
            onOpen: (p) => showPointSheet(context, [p]),
          ),
        ],
      ),
    );
  }
}

class _Instruments extends ConsumerWidget {
  const _Instruments({required this.bandHeight});

  final double bandHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drive = ref.watch(driveControllerProvider);
    if (!drive.running) {
      return const Center(child: BlockedPanel());
    }
    final driving = isDriving(drive);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (drive.error != null)
          Text(
            drive.error!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SonarText.small.copyWith(color: SonarColors.red),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: SonarMotion.fade,
            child: driving
                ? SpeedRow(key: const ValueKey('driving'), drive: drive)
                : const ReadyPanel(key: ValueKey('ready')),
          ),
        ),
        const SizedBox(height: SonarSpace.s),
        UpcomingPanel(
          upcoming: drive.upcoming,
          height: bandHeight,
          coverage: ref.watch(coverageAroundProvider),
          still: driving,
          onOpen: (p) => showPointSheet(context, [p]),
        ),
      ],
    );
  }
}
