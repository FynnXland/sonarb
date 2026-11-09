import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import '../../core/contracts/alert_repository.dart';
import 'drive_controller.dart';

/// Ladestand der Punkte rund um die eigene Position; null, solange es keinen Fix gibt.
/// Folgt Position, neuen Punkten und dem Quellenstatus.
final coverageAroundProvider = NotifierProvider<CoverageAround, DataCoverage?>(
  CoverageAround.new,
);

class CoverageAround extends Notifier<DataCoverage?> {
  @override
  DataCoverage? build() {
    final alerts = ref.watch(servicesProvider).alerts;
    final subs = <StreamSubscription<Object?>>[
      alerts.changes.listen((_) => _update()),
      alerts.watchStatus().listen((_) => _update(), onError: (_) {}),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    ref.listen(
      driveControllerProvider.select((d) => d.running ? d.fix?.position : null),
      (_, _) => _update(),
    );
    return _compute();
  }

  DataCoverage? _compute() {
    final drive = ref.read(driveControllerProvider);
    final fix = drive.fix;
    if (!drive.running || fix == null) return null;
    return ref.read(servicesProvider).alerts.coverageAround(fix.position);
  }

  void _update() {
    if (!ref.mounted) return;
    state = _compute();
  }
}
