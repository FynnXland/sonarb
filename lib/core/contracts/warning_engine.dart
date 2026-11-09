import '../geo/geo.dart';
import '../model/alert_point.dart';
import '../model/position_fix.dart';
import 'alert_audio.dart';

enum WarningLevel { none, pre, main }

/// Annäherungsstufe an einen Punkt, von weit nach nah. Jede Stufe meldet je Punkt höchstens
/// ein [WarningEvent]. Abstände siehe [WarningSettings].
enum WarningStage {
  /// Erste Ansage: Sprache („Fester Blitzer voraus“) und ein Piep. Kommt immer.
  announce,

  /// Erinnerung: zwei Piepe, rechtzeitig zum Ausrollen. Mit
  /// [WarningSettings.onlyWhenSpeeding] nur, wenn das Tempo über Limit plus Toleranz liegt.
  reminder,

  /// Unmittelbar vor dem Punkt: kurze, schnelle Piepfolge. Bedingung wie [reminder].
  imminent,
}

/// Neu erreichte Stufe eines Punkts. Die Tonausgabe entscheidet über Sprache und Piepmuster.
class WarningEvent {
  const WarningEvent({
    required this.point,
    required this.stage,
    required this.distanceMeters,
  });

  final AlertPoint point;
  final WarningStage stage;
  final double distanceMeters;

  @override
  String toString() => 'WarningEvent(${point.id}, $stage, $distanceMeters)';
}

/// Ein Punkt, der gerade relevant ist (vor einem, in Fahrtrichtung gültig).
class ActiveWarning {
  const ActiveWarning({
    required this.point,
    required this.distanceMeters,
    required this.level,
    this.stage,
  });

  final AlertPoint point;
  final double distanceMeters;
  final WarningLevel level;

  /// Zuletzt erreichte Stufe, null vor der ersten Ansage.
  final WarningStage? stage;
}

/// Abstände und Toleranzen der Warnlogik. Werte in Metern, Sekunden bzw. Grad.
///
/// Eine Stufe gilt als erreicht, wenn der Abstand kleiner ist als ihre Zone. Zonen:
/// - erste Ansage: max([announceMeters], [announceSeconds] × Tempo), der Zeitanteil höchstens
///   [maxTimedAnnounceMeters];
/// - Erinnerung: max([reminderMeters], [reminderSeconds] × Tempo, Ausrollweg bis zum Limit);
///   Ausrollweg = [reactionSeconds] × v + (v² − v_Limit²) / (2 × [coastDecelMps2]);
/// - unmittelbar: max([imminentMeters], [imminentSeconds] × Tempo).
/// Jede Zone ist höchstens so groß wie die vorige.
class WarningSettings {
  const WarningSettings({
    this.headingToleranceDeg = 45,
    this.aheadConeDeg = 60,
    this.hotspotsEnabled = true,
    this.heatSpotsEnabled = true,
    this.heatSpotMinReports = 1,
    this.overspeedToleranceKmh = 3,
    this.announceMeters = 600,
    this.announceSeconds = 30,
    this.reminderEnabled = true,
    this.reminderMeters = 250,
    this.reminderSeconds = 15,
    this.imminentMeters = 60,
    this.imminentSeconds = 4,
    this.onlyWhenSpeeding = true,
    this.coastDecelMps2 = 0.7,
    this.reactionSeconds = 2,
  });

  final double announceMeters;
  final double announceSeconds;

  /// Aus: keine Erinnerung, erste Ansage und „unmittelbar“ bleiben.
  final bool reminderEnabled;
  final double reminderMeters;
  final double reminderSeconds;
  final double imminentMeters;
  final double imminentSeconds;

  /// Erinnerung und „unmittelbar“ nur, wenn das Tempo über Limit plus Toleranz liegt,
  /// ohne bekanntes Limit gar nicht. Ist das Tempo unsicher, kommen sie trotzdem.
  final bool onlyWhenSpeeding;

  /// Verzögerung beim Ausrollen (Gas weg, Motorbremse), m/s².
  final double coastDecelMps2;
  final double reactionSeconds;

  /// Maximale Abweichung zwischen eigenem Kurs und Fahrtrichtung der Messstelle.
  final double headingToleranceDeg;

  /// Punkt gilt als „vor einem“, wenn die Peilung zum Punkt höchstens so weit vom Kurs abweicht.
  final double aheadConeDeg;
  final bool hotspotsEnabled;

  /// Blitzer-Hotspots: Häufungen vergangener mobiler Blitzer ([AlertPoint.historical]) auf der
  /// Fahrtlinie, eine Ansage je Durchfahrt. Dafür braucht die Warnlogik die vergangenen
  /// Beobachtungen unter den Kandidaten (`AlertRepository.pointsAround` mit `withHistory`).
  final bool heatSpotsEnabled;

  /// Ab so vielen vergangenen Meldungen im Umkreis von 300 m gilt eine Stelle als Hotspot.
  /// Dieselbe Stufe nutzt die Karte.
  final int heatSpotMinReports;
  final int overspeedToleranceKmh;

  /// Der Zeitanteil der ersten Ansage wächst nicht unbegrenzt mit dem Tempo.
  static const double maxTimedAnnounceMeters = 2000;

  /// Größte mögliche Ansage-Zone.
  double get maxAnnounceMeters => announceMeters > maxTimedAnnounceMeters
      ? announceMeters
      : maxTimedAnnounceMeters;

  /// So weit voraus braucht die Warnlogik Punkte (`AlertRepository.pointsAround`). Wer weiter
  /// weg ist, gilt als vergessen und wird bei erneuter Annäherung wieder angesagt.
  double get lookAheadMeters => maxAnnounceMeters + 500;

  WarningSettings copyWith({
    double? headingToleranceDeg,
    double? aheadConeDeg,
    bool? hotspotsEnabled,
    bool? heatSpotsEnabled,
    int? heatSpotMinReports,
    int? overspeedToleranceKmh,
    double? announceMeters,
    double? announceSeconds,
    bool? reminderEnabled,
    double? reminderMeters,
    double? reminderSeconds,
    double? imminentMeters,
    double? imminentSeconds,
    bool? onlyWhenSpeeding,
    double? coastDecelMps2,
    double? reactionSeconds,
  }) => WarningSettings(
    headingToleranceDeg: headingToleranceDeg ?? this.headingToleranceDeg,
    aheadConeDeg: aheadConeDeg ?? this.aheadConeDeg,
    hotspotsEnabled: hotspotsEnabled ?? this.hotspotsEnabled,
    heatSpotsEnabled: heatSpotsEnabled ?? this.heatSpotsEnabled,
    heatSpotMinReports: heatSpotMinReports ?? this.heatSpotMinReports,
    overspeedToleranceKmh: overspeedToleranceKmh ?? this.overspeedToleranceKmh,
    announceMeters: announceMeters ?? this.announceMeters,
    announceSeconds: announceSeconds ?? this.announceSeconds,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderMeters: reminderMeters ?? this.reminderMeters,
    reminderSeconds: reminderSeconds ?? this.reminderSeconds,
    imminentMeters: imminentMeters ?? this.imminentMeters,
    imminentSeconds: imminentSeconds ?? this.imminentSeconds,
    onlyWhenSpeeding: onlyWhenSpeeding ?? this.onlyWhenSpeeding,
    coastDecelMps2: coastDecelMps2 ?? this.coastDecelMps2,
    reactionSeconds: reactionSeconds ?? this.reactionSeconds,
  );
}

/// Ergebnis eines Schritts der Warnlogik.
class WarningUpdate {
  const WarningUpdate({
    required this.active,
    this.sounds = const [],
    this.events = const [],
    this.speedLimitKmh,
    this.overspeed = false,
  });

  /// In diesem Schritt neu erreichte Stufen, wichtigster Punkt zuerst.
  final List<WarningEvent> events;

  static const empty = WarningUpdate(active: []);

  /// Relevante Punkte, nächster zuerst. `active.first` ist die Hauptanzeige.
  final List<ActiveWarning> active;

  /// Einzelsignale neben den Stufen. Die Warnlogik meldet hier derzeit nichts: Zu schnell
  /// zeigt sich über [WarningStage.reminder] und [WarningStage.imminent].
  final List<WarningSound> sounds;

  /// Maßgebliches Tempolimit: Messstelle in Hauptwarnung, sonst Straße.
  final int? speedLimitKmh;
  final bool overspeed;

  ActiveWarning? get primary => active.isEmpty ? null : active.first;
}

/// Zustandsbehaftete, reine Warnlogik (kein Flutter, kein I/O). Implementierung: `features/warning`.
abstract interface class WarningEngine {
  WarningSettings get settings;
  set settings(WarningSettings value);

  /// Ein GPS-Schritt. [candidates] = alle Punkte in der Umgebung, [roadSpeedLimitKmh] = Tempolimit der Straße.
  /// [roadAhead] = Strecke, der man wahrscheinlich folgt (`AlertRepository.roadAheadAt`), ab der
  /// Position; null ohne Straßendaten. Baustellen und andere Hinweise warnen damit nur auf dieser
  /// Strecke, ohne sie an der geraden Linie wie bisher.
  WarningUpdate update(
    PositionFix fix,
    List<AlertPoint> candidates, {
    int? roadSpeedLimitKmh,
    List<GeoPoint>? roadAhead,
  });

  /// Vergisst bereits angekündigte Punkte (z. B. bei Fahrtende).
  void reset();
}
