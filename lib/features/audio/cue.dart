import '../../core/contracts/alert_audio.dart';
import '../../core/contracts/warning_engine.dart';
import '../../core/model/alert_point.dart';
import '../../core/model/heat_spot.dart';

/// Piepmuster. Dateien erzeugt `tool/gen_sounds.dart`.
enum Beep {
  /// Ein Piep: erste Ansage.
  one,

  /// Zwei Piepe: Erinnerung.
  two,

  /// Schnelle Folge unmittelbar vor dem Punkt.
  rapid,

  /// Sanfter Doppelton für Baustelle, Gefahrenstelle, Sonstiges.
  chime,

  /// Tiefer Doppelton bei Überschreitung.
  overspeed,

  /// Aufsteigender Dreiklang für Blitzer-Hotspots: die einzige steigende Tonfolge.
  hotspot,
}

/// Stille für den Vorlauf vor einer Ausgabe, länger als jeder Vorlauf.
const silenceAsset = 'assets/sounds/silence.wav';

/// Piepe gegenüber der Sprache, gemessen an der lautesten Stelle (siehe docs/AUDIO.md).
const double beepTrim = 0.56;

const beepAssets = {
  Beep.one: 'assets/sounds/beep_1.wav',
  Beep.two: 'assets/sounds/beep_2.wav',
  Beep.rapid: 'assets/sounds/beep_rapid.wav',
  Beep.chime: 'assets/sounds/chime.wav',
  Beep.overspeed: 'assets/sounds/overspeed.wav',
  Beep.hotspot: 'assets/sounds/hotspot.wav',
};

/// Eine Ausgabe: erst [speech] (falls Sprache an und verfügbar), dann [beep].
class Cue {
  const Cue({
    this.speech,
    this.beep,
    required this.priority,
    required this.createdAt,
    this.key,
    this.preview = false,
  });

  final String? speech;
  final Beep? beep;

  /// Höher = wichtiger. Bestimmt die Reihenfolge in der Warteschlange.
  final int priority;
  final DateTime createdAt;

  /// Gleicher Schlüssel ersetzt eine noch wartende Ausgabe (z. B. derselbe Punkt).
  final String? key;

  /// Vom Nutzer angetippte Probe: kommt auch bei Stumm und ausgeschalteter Sprache.
  final bool preview;

  /// Neuere Ausgabe für denselben Schlüssel; eine noch nicht gesprochene Ansage bleibt erhalten.
  Cue replacing(Cue older) => Cue(
    speech: speech ?? older.speech,
    beep: beep ?? older.beep,
    priority: priority > older.priority ? priority : older.priority,
    createdAt: createdAt,
    key: key,
    preview: preview,
  );

  @override
  String toString() => 'Cue($speech, $beep, $priority)';
}

/// Statusansagen liegen unter den Warnungen, der Probeton ganz unten.
const int _statusPriority = 5;
const int _testPriority = 1;
const int _overspeedPriority = 35;

/// Über allem: der Nutzer hat gerade getippt und wartet auf den Ton.
const int _previewPriority = 100;

/// Stufe × 10 + Gewicht der Art: imminent geht vor allem anderen.
int eventPriority(WarningEvent e) =>
    10 + e.stage.index * 10 + _importance(e.point);

int _importance(AlertPoint p) => switch (toneOf(p)) {
  PointTone.stages => p.effectiveCategory.isMobile ? 2 : 3,
  PointTone.chime => 1,
  PointTone.heat || PointTone.silent => 0,
};

/// Welche Töne ein Punkt bekommt.
enum PointTone {
  /// Blitzer: ein Piep, zwei Piepe, schnelle Folge.
  stages,

  /// Gefahrenstellen und weitere Kontrollen: sanfter Doppelton zur einzigen Ansage.
  chime,

  /// Ende der Abschnittskontrolle: nur Sprache.
  silent,

  /// Blitzer-Hotspot: eigenes Signal zur einzigen Ansage.
  heat,
}

PointTone toneOf(AlertPoint p) {
  // Vergangene Beobachtung: nie ein Ton, auch wenn ein Ereignis durchrutscht. Nur der daraus
  // gebildete Hotspot hat sein eigenes Signal.
  if (p.historical) return isHeatSpot(p) ? PointTone.heat : PointTone.silent;
  final c = p.effectiveCategory;
  if (c == AlertCategory.sectionEnd) return PointTone.silent;
  if (c.group == CategoryGroup.camera) return PointTone.stages;
  return PointTone.chime;
}

/// Nur eine Ansage, keine Stufen.
bool announceOnly(AlertPoint p) => toneOf(p) != PointTone.stages;

Beep? beepFor(WarningEvent e) => switch (toneOf(e.point)) {
  PointTone.silent => null,
  PointTone.chime => Beep.chime,
  PointTone.heat => Beep.hotspot,
  PointTone.stages => switch (e.stage) {
    WarningStage.announce => Beep.one,
    WarningStage.reminder => Beep.two,
    WarningStage.imminent => Beep.rapid,
  },
};

/// Schalter und gesprochener Satz für [p], null bei Ampeln. Ohne feine Art (eigene Meldung,
/// ältere Plugins) gilt der Satz der groben Art, etwa „Baustelle voraus“ statt
/// „Tagesbaustelle voraus“.
(Announcement, String)? phraseOf(AlertPoint p) {
  if (isHeatSpot(p)) return _say(Announcement.heatSpot);
  if (p.historical) return null;
  final c = p.category;
  if (c == null) {
    final a = _coarse(p);
    return a == null ? null : (a, a.text);
  }
  return switch (c) {
    AlertCategory.fixedSpeed => _say(Announcement.fixedCamera),
    AlertCategory.tunnelSpeed => (
      Announcement.fixedCamera,
      'Blitzer im Tunnel voraus',
    ),
    AlertCategory.fixedRedLightSpeed => (
      Announcement.redLightCamera,
      'Rotlicht- und Tempoblitzer voraus',
    ),
    AlertCategory.fixedRedLight ||
    AlertCategory.mobileRedLight => _say(Announcement.redLightCamera),
    AlertCategory.sectionStart => _say(Announcement.sectionControl),
    AlertCategory.sectionEnd => _say(Announcement.sectionEnd),
    AlertCategory.semiStationary => (
      Announcement.mobileCamera,
      'Blitzeranhänger voraus',
    ),
    AlertCategory.mobileSpeed => _say(Announcement.mobileCamera),
    AlertCategory.mobileDistance => _say(Announcement.distanceCheck),
    AlertCategory.longTermRoadworks => _say(Announcement.construction),
    AlertCategory.dayRoadworks => (
      Announcement.construction,
      'Tagesbaustelle voraus',
    ),
    AlertCategory.trafficJamEnd => _say(Announcement.trafficJamEnd),
    AlertCategory.accident => _say(Announcement.accident),
    AlertCategory.obstacle => (Announcement.danger, 'Hindernis voraus'),
    AlertCategory.slipperyRoad => (Announcement.danger, 'Glätte voraus'),
    AlertCategory.poorVisibility => (
      Announcement.danger,
      'Sichtbehinderung voraus',
    ),
    AlertCategory.breakdown => (Announcement.danger, 'Pannenfahrzeug voraus'),
    AlertCategory.officialNotice => (
      Announcement.danger,
      'Verkehrsmeldung voraus',
    ),
    AlertCategory.accessControl => (
      Announcement.otherControls,
      'Einfahrtskontrolle voraus',
    ),
    AlertCategory.heightControl => _say(Announcement.otherControls),
    AlertCategory.weightControl => (
      Announcement.otherControls,
      'Gewichtskontrolle voraus',
    ),
    AlertCategory.busLane => _say(Announcement.busLane),
    AlertCategory.noOvertaking => _say(Announcement.noOvertaking),
    AlertCategory.closure => _say(Announcement.closure),
    AlertCategory.trafficSignal => null,
    AlertCategory.otherReport => _say(Announcement.otherReport),
  };
}

(Announcement, String) _say(Announcement a) => (a, a.text);

Announcement? _coarse(AlertPoint p) => switch (p.kind) {
  AlertKind.speedCamera => Announcement.fixedCamera,
  AlertKind.redLightCamera => Announcement.redLightCamera,
  AlertKind.sectionControl => Announcement.sectionControl,
  AlertKind.live => Announcement.mobileCamera,
  AlertKind.construction => Announcement.construction,
  AlertKind.trafficSignal => null,
  AlertKind.hotspot => switch (p.reportKind) {
    HotspotKind.mobileCamera || null => Announcement.mobileCamera,
    HotspotKind.distanceCheck => Announcement.distanceCheck,
    HotspotKind.construction => Announcement.construction,
    HotspotKind.danger => Announcement.danger,
    HotspotKind.other => Announcement.otherReport,
  },
};

/// Schalter für [p], null bei Ampeln.
Announcement? announcementFor(AlertPoint p) => phraseOf(p)?.$1;

/// Satz [a] mit Tempo-Zusatz [limit], ohne abgeschaltete Teile. Null, wenn nichts zu sagen ist.
String? sentence(
  Announcement a, {
  int? limit,
  Set<Announcement> silenced = const {},
}) {
  if (a == Announcement.speedLimit || silenced.contains(a)) return null;
  if (limit == null || silenced.contains(Announcement.speedLimit)) {
    return a.text;
  }
  return '${a.text}, ${Announcement.speedLimit.text} $limit';
}

/// Kurzer Satz für die erste Ansage, bei Blitzern mit Tempolimit, falls bekannt.
String? speechFor(AlertPoint p, {Set<Announcement> silenced = const {}}) {
  final phrase = phraseOf(p);
  if (phrase == null) return null;
  final (a, text) = phrase;
  if (silenced.contains(a)) return null;
  final limit = announceOnly(p) ? null : p.maxSpeed;
  if (limit == null || silenced.contains(Announcement.speedLimit)) return text;
  return '$text, ${Announcement.speedLimit.text} $limit';
}

Announcement announcementOfStatus(StatusMessage m) => switch (m) {
  StatusMessage.gpsLost => Announcement.gpsLost,
  StatusMessage.gpsRestored => Announcement.gpsRestored,
  StatusMessage.dataUnavailable => Announcement.dataUnavailable,
  StatusMessage.dataRestored => Announcement.dataRestored,
  StatusMessage.positionFound => Announcement.positionFound,
};

String statusText(StatusMessage m) => announcementOfStatus(m).text;

/// Sprache nur bei der ersten Ansage; die späteren Stufen sind reine Piepe.
Cue cueForEvent(
  WarningEvent e,
  DateTime now, {
  Set<Announcement> silenced = const {},
}) => Cue(
  speech: e.stage == WarningStage.announce
      ? speechFor(e.point, silenced: silenced)
      : null,
  beep: beepFor(e),
  priority: eventPriority(e),
  createdAt: now,
  key: 'point:${e.point.id}',
);

Cue? cueForStatus(
  StatusMessage m,
  DateTime now, {
  Set<Announcement> silenced = const {},
}) {
  final a = announcementOfStatus(m);
  if (silenced.contains(a)) return null;
  return Cue(
    speech: a.text,
    priority: _statusPriority,
    createdAt: now,
    key: 'status',
  );
}

/// Probe für den Bildschirm „Sprachansagen“: Satz und der Piep der ersten Ansage.
Cue previewCue(Announcement a, DateTime now) {
  final (text, beep) = switch (a) {
    Announcement.speedLimit => (
      sentence(Announcement.fixedCamera, limit: 50),
      Beep.one,
    ),
    Announcement.construction ||
    Announcement.danger ||
    Announcement.otherReport ||
    Announcement.trafficJamEnd ||
    Announcement.accident ||
    Announcement.otherControls ||
    Announcement.noOvertaking ||
    Announcement.closure ||
    Announcement.busLane => (a.text, Beep.chime),
    Announcement.heatSpot => (a.text, Beep.hotspot),
    Announcement.sectionEnd ||
    Announcement.gpsLost ||
    Announcement.gpsRestored ||
    Announcement.dataUnavailable ||
    Announcement.dataRestored ||
    Announcement.positionFound => (a.text, null),
    _ => (a.text, Beep.one),
  };
  return Cue(
    speech: text,
    beep: beep,
    priority: _previewPriority,
    createdAt: now,
    key: 'preview',
    preview: true,
  );
}

Cue cueForSound(WarningSound s, DateTime now) => switch (s) {
  WarningSound.testTone => Cue(
    beep: Beep.one,
    priority: _testPriority,
    createdAt: now,
    key: 'test',
  ),
  WarningSound.overspeed => Cue(
    beep: Beep.overspeed,
    priority: _overspeedPriority,
    createdAt: now,
    key: 'overspeed',
  ),
  WarningSound.heatSpotPreview => Cue(
    beep: Beep.hotspot,
    priority: _previewPriority,
    createdAt: now,
    key: 'preview',
    preview: true,
  ),
};
