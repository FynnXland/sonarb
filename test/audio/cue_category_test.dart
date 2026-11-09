import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/alert_audio.dart';
import 'package:sonarb/core/contracts/warning_engine.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/audio/cue.dart';
import 'package:sonarb/features/settings/announcements_screen.dart';

/// Punkt mit grober Art passend zur Kategorie, so wie OSM und Plugins sie liefern.
AlertPoint point(AlertCategory c, {int? maxSpeed}) => AlertPoint(
  id: 'p',
  kind: switch (c.group) {
    CategoryGroup.camera =>
      c == AlertCategory.sectionStart || c == AlertCategory.sectionEnd
          ? AlertKind.sectionControl
          : AlertKind.speedCamera,
    _ => AlertKind.construction,
  },
  position: const GeoPoint(48, 9),
  source: 'test',
  category: c,
  maxSpeed: maxSpeed,
);

WarningEvent event(
  AlertPoint p, [
  WarningStage stage = WarningStage.announce,
]) => WarningEvent(point: p, stage: stage, distanceMeters: 500);

void main() {
  final now = DateTime.utc(2026, 10, 29, 12);

  test('Satz je feiner Art', () {
    const expected = {
      AlertCategory.fixedSpeed: 'Fester Blitzer voraus',
      AlertCategory.tunnelSpeed: 'Blitzer im Tunnel voraus',
      AlertCategory.fixedRedLightSpeed: 'Rotlicht- und Tempoblitzer voraus',
      AlertCategory.fixedRedLight: 'Rotlichtblitzer voraus',
      AlertCategory.mobileRedLight: 'Rotlichtblitzer voraus',
      AlertCategory.sectionStart: 'Abschnittskontrolle voraus',
      AlertCategory.sectionEnd: 'Ende der Abschnittskontrolle',
      AlertCategory.semiStationary: 'Blitzeranhänger voraus',
      AlertCategory.mobileSpeed: 'Mobiler Blitzer voraus',
      AlertCategory.mobileDistance: 'Abstandsmessung voraus',
      AlertCategory.longTermRoadworks: 'Baustelle voraus',
      AlertCategory.dayRoadworks: 'Tagesbaustelle voraus',
      AlertCategory.trafficJamEnd: 'Stauende voraus',
      AlertCategory.obstacle: 'Hindernis voraus',
      AlertCategory.accident: 'Unfall voraus',
      AlertCategory.slipperyRoad: 'Glätte voraus',
      AlertCategory.poorVisibility: 'Sichtbehinderung voraus',
      AlertCategory.breakdown: 'Pannenfahrzeug voraus',
      AlertCategory.officialNotice: 'Verkehrsmeldung voraus',
      AlertCategory.accessControl: 'Einfahrtskontrolle voraus',
      AlertCategory.heightControl: 'Höhenkontrolle voraus',
      AlertCategory.weightControl: 'Gewichtskontrolle voraus',
      AlertCategory.busLane: 'Busspur voraus',
      AlertCategory.noOvertaking: 'Überholverbot voraus',
      AlertCategory.closure: 'Sperrung voraus',
      AlertCategory.otherReport: 'Gemeldete Stelle voraus',
    };
    expect(
      expected.keys.toSet(),
      AlertCategory.values.toSet()..remove(AlertCategory.trafficSignal),
      reason: 'jede Kategorie mit Warnung hat einen Satz',
    );
    expected.forEach((c, text) {
      expect(speechFor(point(c)), text, reason: '$c');
    });
    expect(speechFor(point(AlertCategory.trafficSignal)), isNull);
  });

  test('Kontrollen mit grober Art construction heißen nie „Baustelle“', () {
    for (final c in [
      AlertCategory.heightControl,
      AlertCategory.weightControl,
      AlertCategory.accessControl,
      AlertCategory.noOvertaking,
    ]) {
      final p = point(c);
      expect(p.kind, AlertKind.construction);
      expect(speechFor(p), isNot(contains('Baustelle')), reason: '$c');
    }
  });

  test('ohne feine Art gelten die Sätze der groben Art', () {
    AlertPoint hotspot(HotspotKind k) => AlertPoint(
      id: 'h',
      kind: AlertKind.hotspot,
      position: const GeoPoint(48, 9),
      source: 'hotspot',
      reportKind: k,
    );
    expect(speechFor(hotspot(HotspotKind.construction)), 'Baustelle voraus');
    expect(speechFor(hotspot(HotspotKind.danger)), 'Gefahrenstelle voraus');
  });

  test('Ende der Abschnittskontrolle: nur Sprache, kein Piep, kein Tempo', () {
    final end = point(AlertCategory.sectionEnd, maxSpeed: 100);
    final cue = cueForEvent(event(end), now);
    expect(cue.speech, 'Ende der Abschnittskontrolle');
    expect(cue.beep, isNull);
    expect(
      cueForEvent(event(end), now, silenced: {Announcement.sectionEnd}).speech,
      isNull,
    );
  });

  test('Tempo-Zusatz nur bei Blitzern', () {
    expect(
      speechFor(point(AlertCategory.tunnelSpeed, maxSpeed: 80)),
      'Blitzer im Tunnel voraus, Tempo 80',
    );
    expect(
      speechFor(point(AlertCategory.heightControl, maxSpeed: 30)),
      'Höhenkontrolle voraus',
    );
  });

  test('Töne: Blitzer gestuft, Hinweise Doppelton', () {
    expect(
      cueForEvent(event(point(AlertCategory.semiStationary)), now).beep,
      Beep.one,
    );
    for (final c in [
      AlertCategory.trafficJamEnd,
      AlertCategory.heightControl,
      AlertCategory.closure,
    ]) {
      expect(cueForEvent(event(point(c)), now).beep, Beep.chime, reason: '$c');
    }
  });

  test('ein Schalter deckt mehrere Arten ab', () {
    const off = {Announcement.otherControls};
    for (final c in [
      AlertCategory.heightControl,
      AlertCategory.weightControl,
      AlertCategory.accessControl,
    ]) {
      expect(speechFor(point(c), silenced: off), isNull, reason: '$c');
    }
    expect(speechFor(point(AlertCategory.closure), silenced: off), isNotNull);
  });

  test('jeder Schalter einer Kategorie steht im Bildschirm', () {
    final listed = {for (final (_, items) in announcementGroups) ...items};
    for (final c in AlertCategory.values) {
      final a = announcementFor(point(c));
      if (a != null) expect(listed, contains(a), reason: '$c');
    }
  });

  test('Probe für die neuen Schalter', () {
    expect(previewCue(Announcement.sectionEnd, now).beep, isNull);
    expect(previewCue(Announcement.trafficJamEnd, now).beep, Beep.chime);
    expect(
      previewCue(Announcement.otherControls, now).speech,
      'Höhenkontrolle voraus',
    );
  });

  test('vergangene Beobachtung: kein Satz, kein Piep, die Warteschlange verwirft sie', () {
    for (final stage in WarningStage.values) {
      final old = point(
        AlertCategory.mobileSpeed,
        maxSpeed: 50,
      ).copyWith(historical: true);
      final cue = cueForEvent(event(old, stage), now);
      expect(cue.speech, isNull, reason: '$stage');
      expect(cue.beep, isNull, reason: '$stage');
    }
  });
}
