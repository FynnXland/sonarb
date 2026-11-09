import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/warning/warning.dart';

import 'drive_sim.dart';

void main() {
  late DriveSim sim;
  late WarningEngine engine;

  setUp(() {
    sim = DriveSim();
    // Hier geht es um den Punkt selbst. Hotspots daraus prüft heat_spot_test.dart.
    engine = createWarningEngine()
      ..settings = const WarningSettings(heatSpotsEnabled: false);
  });

  test(
    'mit Hotspots: warnt nur der Hotspot, nie der vergangene Punkt selbst',
    () {
      final p = cam(
        sim.at(1200),
        id: 'alt',
        kind: AlertKind.live,
        maxSpeed: 30,
      ).copyWith(category: AlertCategory.mobileSpeed, historical: true);
      engine.settings = const WarningSettings();
      final r = run(engine, sim.drive(0, 1500), [p]);
      expect(r.stages('alt'), isEmpty);
      expect(r.events, hasLength(1));
      expect(r.events.single.point.id, isNot('alt'));
      expect(r.updates.every((u) => u.active.isEmpty), isTrue);
      expect(r.updates.every((u) => u.speedLimitKmh == null), isTrue);
    },
  );

  test('vergangene Beobachtung: keine Ansage, kein Piep, keine Anzeige, kein Limit', () {
    final old = cam(
      sim.at(1200),
      kind: AlertKind.live,
      maxSpeed: 30,
    ).copyWith(category: AlertCategory.mobileSpeed, historical: true);
    final r = run(engine, sim.drive(0, 1500), [old]); // 72 km/h bei 30
    expect(r.events, isEmpty);
    expect(r.sounds, isEmpty);
    expect(r.updates.every((u) => u.active.isEmpty), isTrue);
    expect(r.updates.every((u) => u.speedLimitKmh == null), isTrue);
  });

  test('alle Arten bleiben still, wenn historisch', () {
    for (final c in AlertCategory.values) {
      engine.reset();
      final p = cam(
        sim.at(1200),
        maxSpeed: 30,
      ).copyWith(category: c, historical: true);
      expect(
        run(engine, sim.drive(0, 1500), [p]).events,
        isEmpty,
        reason: '$c',
      );
    }
  });

  test('gleiche Stelle aktuell und historisch: nur die aktuelle warnt', () {
    final now = cam(
      sim.at(1200),
      id: 'now',
      kind: AlertKind.live,
      maxSpeed: 30,
    );
    final old = now.copyWith(id: 'old', historical: true);
    final r = run(engine, sim.drive(0, 1500), [old, now]);
    expect(r.stages('now'), [
      WarningStage.announce,
      WarningStage.reminder,
      WarningStage.imminent,
    ]);
    expect(r.stages('old'), isEmpty);
    expect(
      r.updates.every((u) => u.active.every((w) => w.point.id == 'now')),
      isTrue,
    );
  });

  test('wird ein Punkt unterwegs historisch, verstummt er sofort, auch beim Halten', () {
    final live = cam(sim.at(1200), maxSpeed: 30);
    final first = run(engine, sim.drive(0, 700), [live]);
    expect(first.stages(), [WarningStage.announce]);

    final old = live.copyWith(historical: true);
    final standing = run(engine, sim.stand(700, 5), [old]);
    expect(standing.updates.every((u) => u.active.isEmpty), isTrue);

    final rest = run(engine, sim.drive(700, 1500), [old]);
    expect(rest.events, isEmpty);
    expect(rest.updates.every((u) => u.active.isEmpty), isTrue);
  });
}
