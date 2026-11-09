import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import '../../core/contracts/hotspot_repository.dart';
import '../../core/model/position_fix.dart';

enum HotspotTapPhase { ready, saving, confirm, failed }

class HotspotTapState {
  const HotspotTapState(this.phase, {this.message, this.kind});

  static const ready = HotspotTapState(HotspotTapPhase.ready);

  final HotspotTapPhase phase;
  final String? message;

  /// Art der zuletzt gespeicherten Meldung, solange [phase] `confirm` ist.
  final HotspotKind? kind;
}

/// So lange bleibt „Rückgängig“ bzw. eine Fehlermeldung sichtbar.
const hotspotUndoWindow = Duration(seconds: 5);

/// Meldung speichern, danach Rückgängig. Die Position hält der Aufrufer beim Tippen auf
/// „Melden“ fest, nicht erst bei der Wahl der Art.
class HotspotTapController extends Notifier<HotspotTapState> {
  Timer? _timer;

  @override
  HotspotTapState build() {
    ref.onDispose(() => _timer?.cancel());
    return HotspotTapState.ready;
  }

  Future<void> report(PositionFix fix, HotspotKind kind) async {
    if (state.phase == HotspotTapPhase.saving) return;
    _timer?.cancel();
    state = const HotspotTapState(HotspotTapPhase.saving);
    try {
      await ref
          .read(servicesProvider)
          .hotspots
          .addAt(fix.position, headingDeg: fix.headingDeg, kind: kind);
      _show(HotspotTapState(HotspotTapPhase.confirm, kind: kind));
    } catch (e) {
      debugPrint('Meldung nicht gespeichert: $e');
      _show(
        const HotspotTapState(
          HotspotTapPhase.failed,
          message: 'Meldung nicht gespeichert. Erneut melden.',
        ),
      );
    }
  }

  Future<void> undo() async {
    if (state.phase != HotspotTapPhase.confirm) return;
    _timer?.cancel();
    try {
      await ref.read(servicesProvider).hotspots.undoLast();
      if (ref.mounted) state = HotspotTapState.ready;
    } catch (e) {
      debugPrint('Rückgängig fehlgeschlagen: $e');
      _show(
        const HotspotTapState(
          HotspotTapPhase.failed,
          message: 'Rückgängig fehlgeschlagen. Meldung in den Einstellungen löschen.',
        ),
      );
    }
  }

  void _show(HotspotTapState s) {
    if (!ref.mounted) return;
    state = s;
    _timer = Timer(hotspotUndoWindow, () {
      if (ref.mounted) state = HotspotTapState.ready;
    });
  }
}

final hotspotTapProvider =
    NotifierProvider<HotspotTapController, HotspotTapState>(
      HotspotTapController.new,
    );
