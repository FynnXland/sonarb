import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/alert_audio.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/core/model/heat_spot.dart';
import 'package:sonarb/features/audio/cue.dart';

import '../../tool/gen_sounds.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1);
  const spot = AlertPoint(
    id: '${heatSpotIdPrefix}1_2',
    kind: AlertKind.live,
    position: GeoPoint(48, 9),
    source: 'verlauf',
    category: AlertCategory.mobileSpeed,
    maxSpeed: 50,
    historical: true,
  );

  WarningEvent event(AlertPoint p) =>
      WarningEvent(point: p, stage: WarningStage.announce, distanceMeters: 600);

  test('Ansage: Satz ohne Tempo, dann das Hotspot-Signal', () {
    final cue = cueForEvent(event(spot), now);
    expect(cue.speech, 'Blitzer-Hotspot voraus');
    expect(cue.beep, Beep.hotspot);
  });

  test('Nur Signalton: Satz abgeschaltet, Signal bleibt', () {
    final cue = cueForEvent(
      event(spot),
      now,
      silenced: {Announcement.heatSpot},
    );
    expect(cue.speech, isNull);
    expect(cue.beep, Beep.hotspot);
  });

  test('andere vergangene Beobachtungen bleiben stumm', () {
    final old = spot.copyWith(id: 'plugin:verlauf:1');
    final cue = cueForEvent(event(old), now);
    expect(cue.speech, isNull);
    expect(cue.beep, isNull);
  });

  test('Hotspot liegt unter allen anderen Warnungen', () {
    const works = AlertPoint(
      id: 'w',
      kind: AlertKind.construction,
      position: GeoPoint(48, 9),
      source: 'test',
    );
    expect(eventPriority(event(spot)), lessThan(eventPriority(event(works))));
  });

  test('Proben: Ansage mit Signal, Signal allein auch bei Stumm', () {
    final speech = previewCue(Announcement.heatSpot, now);
    expect(speech.speech, 'Blitzer-Hotspot voraus');
    expect(speech.beep, Beep.hotspot);
    final beep = cueForSound(WarningSound.heatSpotPreview, now);
    expect(beep.speech, isNull);
    expect(beep.beep, Beep.hotspot);
    expect(beep.preview, isTrue);
  });

  test('Hotspot-Signal: die einzige steigende Tonfolge', () {
    List<double> pitches(String name) => [
      for (final t in soundSpecs.firstWhere((s) => s.name == name).tones)
        t.freq,
    ];
    bool rises(List<double> f) =>
        f.length > 1 &&
        [for (var i = 1; i < f.length; i++) f[i] > f[i - 1]].every((x) => x);
    for (final s in soundSpecs) {
      expect(rises(pitches(s.name)), s.name == 'hotspot', reason: s.name);
    }
  });
}
