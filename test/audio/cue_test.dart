import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/alert_audio.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/audio/cue.dart';

AlertPoint point(AlertKind kind, {HotspotKind? report, int? maxSpeed}) =>
    AlertPoint(
      id: 'p',
      kind: kind,
      position: const GeoPoint(48, 9),
      source: 'test',
      reportKind: report,
      maxSpeed: maxSpeed,
    );

WarningEvent event(AlertPoint p, WarningStage stage) =>
    WarningEvent(point: p, stage: stage, distanceMeters: 900);

void main() {
  final now = DateTime.utc(2026, 10, 29, 12);

  test('kurze Ansagetexte je Art', () {
    final cases = {
      point(AlertKind.speedCamera): 'Fester Blitzer voraus',
      point(AlertKind.redLightCamera): 'Rotlichtblitzer voraus',
      point(AlertKind.sectionControl): 'Abschnittskontrolle voraus',
      point(AlertKind.live): 'Mobiler Blitzer voraus',
      point(AlertKind.construction): 'Baustelle voraus',
      point(AlertKind.hotspot, report: HotspotKind.mobileCamera):
          'Mobiler Blitzer voraus',
      point(AlertKind.hotspot, report: HotspotKind.distanceCheck):
          'Abstandsmessung voraus',
      point(AlertKind.hotspot, report: HotspotKind.construction):
          'Baustelle voraus',
      point(AlertKind.hotspot, report: HotspotKind.danger):
          'Gefahrenstelle voraus',
      point(AlertKind.hotspot, report: HotspotKind.other):
          'Gemeldete Stelle voraus',
    };
    cases.forEach((p, text) => expect(speechFor(p), text, reason: '$p'));
    expect(speechFor(point(AlertKind.trafficSignal)), isNull);
  });

  test('bekanntes Limit wird angehängt, bei Baustellen nicht', () {
    expect(
      speechFor(point(AlertKind.speedCamera, maxSpeed: 50)),
      'Fester Blitzer voraus, Tempo 50',
    );
    expect(
      speechFor(point(AlertKind.construction, maxSpeed: 60)),
      'Baustelle voraus',
    );
  });

  test('Statustexte', () {
    expect(statusText(StatusMessage.gpsLost), 'GPS-Signal verloren');
    expect(statusText(StatusMessage.gpsRestored), 'GPS-Signal wieder da');
    expect(
      statusText(StatusMessage.dataUnavailable),
      'Blitzerdaten nicht verfügbar',
    );
    expect(statusText(StatusMessage.dataRestored), 'Blitzerdaten wieder da');
    expect(statusText(StatusMessage.positionFound), 'Position gefunden');
  });

  test('Piepmuster je Stufe, Sprache nur bei announce', () {
    final camera = point(AlertKind.speedCamera);
    final expected = {
      WarningStage.announce: Beep.one,
      WarningStage.reminder: Beep.two,
      WarningStage.imminent: Beep.rapid,
    };
    expected.forEach((stage, beep) {
      final cue = cueForEvent(event(camera, stage), now);
      expect(cue.beep, beep, reason: '$stage');
      expect(
        cue.speech,
        stage == WarningStage.announce ? 'Fester Blitzer voraus' : isNull,
      );
    });
  });

  test('Baustelle und Gefahrenstelle: sanfter Doppelton', () {
    for (final p in [
      point(AlertKind.construction),
      point(AlertKind.hotspot, report: HotspotKind.danger),
      point(AlertKind.hotspot, report: HotspotKind.other),
    ]) {
      expect(
        cueForEvent(event(p, WarningStage.announce), now).beep,
        Beep.chime,
      );
    }
  });

  test('Priorität: nähere Stufe vor Art, Messstelle vor Hinweis', () {
    int prio(AlertPoint p, WarningStage s) => eventPriority(event(p, s));
    final fixed = point(AlertKind.speedCamera);
    final mobile = point(AlertKind.hotspot, report: HotspotKind.mobileCamera);
    final site = point(AlertKind.construction);
    expect(
      prio(mobile, WarningStage.imminent),
      greaterThan(prio(fixed, WarningStage.reminder)),
    );
    expect(
      prio(fixed, WarningStage.announce),
      greaterThan(prio(mobile, WarningStage.announce)),
    );
    expect(
      prio(mobile, WarningStage.announce),
      greaterThan(prio(site, WarningStage.announce)),
    );
    final status = cueForStatus(StatusMessage.gpsLost, now);
    expect(status!.priority, lessThan(prio(site, WarningStage.announce)));
  });

  test('neuere Meldung desselben Punkts behält die noch offene Ansage', () {
    final camera = point(AlertKind.speedCamera);
    final first = cueForEvent(event(camera, WarningStage.announce), now);
    final second = cueForEvent(event(camera, WarningStage.reminder), now);
    final merged = second.replacing(first);
    expect(merged.speech, 'Fester Blitzer voraus');
    expect(merged.beep, Beep.two);
    expect(merged.priority, second.priority);
  });

  test('Einzelsignale', () {
    expect(cueForSound(WarningSound.testTone, now).beep, Beep.one);
    expect(cueForSound(WarningSound.overspeed, now).beep, Beep.overspeed);
  });

  test('jedes Muster hat eine Datei', () {
    expect(beepAssets.keys.toSet(), Beep.values.toSet());
  });

  group('abgeschaltete Sätze', () {
    final camera = point(AlertKind.speedCamera, maxSpeed: 50);
    final site = point(AlertKind.hotspot, report: HotspotKind.construction);

    test('Satz aus: Sprache entfällt, Piep bleibt', () {
      final cue = cueForEvent(
        event(site, WarningStage.announce),
        now,
        silenced: {Announcement.construction},
      );
      expect(cue.speech, isNull);
      expect(cue.beep, Beep.chime);
    });

    test('Tempo-Zusatz einzeln abschaltbar', () {
      expect(
        speechFor(camera, silenced: {Announcement.speedLimit}),
        'Fester Blitzer voraus',
      );
      expect(
        speechFor(camera, silenced: {Announcement.fixedCamera}),
        isNull,
        reason: 'Zusatz allein ergibt keinen Satz',
      );
    });

    test('andere Arten bleiben unberührt', () {
      expect(
        speechFor(camera, silenced: {Announcement.construction}),
        'Fester Blitzer voraus, Tempo 50',
      );
    });

    test('Statusmeldung aus: gar keine Ausgabe', () {
      expect(
        cueForStatus(
          StatusMessage.dataUnavailable,
          now,
          silenced: {Announcement.dataUnavailable},
        ),
        isNull,
      );
      expect(
        cueForStatus(
          StatusMessage.dataRestored,
          now,
          silenced: {Announcement.dataUnavailable},
        )!.speech,
        'Blitzerdaten wieder da',
      );
    });

    test('jeder Satz hat eine Probe, Zusatz mit Beispiel-Tempo', () {
      for (final a in Announcement.values) {
        final cue = previewCue(a, now);
        expect(cue.preview, isTrue, reason: '$a');
        expect(cue.speech, isNotNull, reason: '$a');
      }
      expect(
        previewCue(Announcement.speedLimit, now).speech,
        'Fester Blitzer voraus, Tempo 50',
      );
      expect(previewCue(Announcement.danger, now).beep, Beep.chime);
      expect(previewCue(Announcement.gpsLost, now).beep, isNull);
    });

    test('jede Art mit Warnung hat einen eigenen Satz', () {
      final used = {
        for (final kind in AlertKind.values)
          for (final report in [null, ...HotspotKind.values])
            ?announcementFor(point(kind, report: report)),
      };
      expect(used, {
        Announcement.fixedCamera,
        Announcement.redLightCamera,
        Announcement.sectionControl,
        Announcement.mobileCamera,
        Announcement.distanceCheck,
        Announcement.construction,
        Announcement.danger,
        Announcement.otherReport,
      });
    });
  });
}
