import 'dart:math' as math;

/// Straßenart, geschätzt aus dem Tempolimit (siehe [roadClassOf]).
enum RoadClass { urban, rural, motorway, unknown }

/// Stufen über dem Limit, in km/h über dem erlaubten Tempo (gerundet).
enum OverLimit {
  /// Bis +3 km/h, also im Rahmen der Messtoleranz.
  within,

  /// +4 bis +10 km/h.
  upTo10,

  /// +11 bis +20 km/h.
  upTo20,

  /// Ab +21 km/h.
  above20,
}

/// Grenzen und Gewichte der Statistik. Herleitung in `docs/STATISTIK.md`.
abstract final class StatsLimits {
  /// Breite einer Stufe der Tempoverteilung.
  static const binKmh = 10;

  /// Stufen 0–9, 10–19, … ; die letzte nimmt alles ab 250 km/h.
  static const bins = 26;

  /// Toleranz für „im Limit“ und „zu schnell“ an Blitzern.
  static const toleranceKmh = 3;

  /// Unter 1 km Strecke gibt es keinen Wert „Vorausschauend“.
  static const scoreMinMeters = 1000.0;

  /// Je-100-km-Werte rechnen mit mindestens so viel Strecke.
  static const rateFloorMeters = 10000.0;

  /// Ab so vielen harten Bremsungen je 100 km gibt es für diesen Teil keine Punkte mehr.
  static const hardBrakesFullPer100Km = 5.0;

  /// Ebenso für zügige Kurven.
  static const sharpCurvesFullPer100Km = 10.0;

  /// Ab diesem Anteil der Fahrzeit mit +11 km/h oder mehr gibt es keine Punkte mehr.
  static const overLimitFullShare = 0.2;

  /// Mindestens so viel Fahrzeit mit bekanntem Limit, damit der Teil zählt.
  static const overLimitMinSeconds = 60.0;

  /// Stufen der Brems- und Beschleunigungsspitzen: 0,5 m/s² breit ab 0,5 m/s²; die letzte
  /// nimmt alles ab 5 m/s².
  static const peakBinMps2 = 0.5;
  static const peakBins = 10;

  /// Spitze unter dieser Grenze: sanft; ab [hardPeakMps2]: hart. Wie in der Aufzeichnung.
  static const gentlePeakMps2 = 1.5;
  static const hardPeakMps2 = 3.0;

  /// Ruhig gefahren: Das Tempo ändert sich um weniger als so viel.
  static const calmMps2 = 0.5;

  /// Gleichmäßige Abschnitte: ab diesem Tempo und mindestens so lang.
  static const cruiseMinKmh = 30.0;
  static const cruiseMinSeconds = 20.0;

  /// Ruhe-Anteil und Schwankung erst ab so viel Zeit.
  static const smoothMinSeconds = 60.0;

  static const weightGentle = 35.0;
  static const weightHard = 25.0;
  static const weightCurves = 20.0;
  static const weightOverLimit = 20.0;
}

/// Stufe für [excessKmh] = Tempo − Limit, beide in km/h.
OverLimit overLimitOf(double excessKmh) {
  final e = excessKmh.round();
  if (e <= StatsLimits.toleranceKmh) return OverLimit.within;
  if (e <= 10) return OverLimit.upTo10;
  if (e <= 20) return OverLimit.upTo20;
  return OverLimit.above20;
}

/// Stufe einer Brems- oder Beschleunigungsspitze in m/s² (siehe [StatsLimits.peakBinMps2]).
int peakBinOf(double peakMps2) =>
    ((peakMps2 / StatsLimits.peakBinMps2).floor() - 1).clamp(
      0,
      StatsLimits.peakBins - 1,
    );

/// Untere Grenze der Stufe [bin] in m/s².
double peakBinFrom(int bin) => (bin + 1) * StatsLimits.peakBinMps2;

/// Anteile sanft (Spitze unter 1,5 m/s²), mittel und hart (ab 3 m/s²) an allen Vorgängen.
typedef PeakShares = ({double gentle, double medium, double hard, int count});

PeakShares? peakSharesOf(List<double> bins) {
  final n = bins.fold(0.0, (a, b) => a + b);
  if (n <= 0) return null;
  var gentle = 0.0;
  var hard = 0.0;
  for (var i = 0; i < bins.length; i++) {
    final from = peakBinFrom(i);
    if (from < StatsLimits.gentlePeakMps2) gentle += bins[i];
    if (from >= StatsLimits.hardPeakMps2) hard += bins[i];
  }
  return (
    gentle: gentle / n,
    medium: (n - gentle - hard) / n,
    hard: hard / n,
    count: n.round(),
  );
}

List<double> _zeros(int n) => List<double>.filled(n, 0);

List<double> _add(List<double> a, List<double> b) => [
  for (var i = 0; i < a.length; i++) a[i] + (i < b.length ? b[i] : 0),
];

List<double> _list(Object? raw, int n) {
  final out = _zeros(n);
  if (raw is List) {
    for (var i = 0; i < n && i < raw.length; i++) {
      final v = raw[i];
      if (v is num) out[i] = v.toDouble();
    }
  }
  return out;
}

double _num(Map<String, Object?> j, String key) {
  final v = j[key];
  return v is num ? v.toDouble() : 0;
}

int _int(Map<String, Object?> j, String key) {
  final v = j[key];
  return v is num ? v.round() : 0;
}

double _round(double v, [int digits = 1]) {
  final f = math.pow(10, digits);
  return (v * f).round() / f;
}

/// Fahrzeit und Höchsttempo bei einem bestimmten Tempolimit.
class LimitFigures {
  LimitFigures({List<double>? seconds, this.maxKmh = 0})
    : seconds = _list(seconds, OverLimit.values.length);

  /// Fahrzeit je [OverLimit]-Stufe.
  final List<double> seconds;

  /// Höchstes über 3 Fixes gehaltenes Tempo bei diesem Limit.
  final double maxKmh;

  double get totalSeconds => seconds.fold(0.0, (a, b) => a + b);

  /// Anteil der Fahrzeit über der Toleranz (ab +4 km/h).
  double? get overShare {
    final t = totalSeconds;
    return t < 1 ? null : 1 - seconds[OverLimit.within.index] / t;
  }

  /// Anteil ab +11 km/h.
  double? get over10Share {
    final t = totalSeconds;
    if (t < 1) return null;
    return (seconds[OverLimit.upTo20.index] +
            seconds[OverLimit.above20.index]) /
        t;
  }

  LimitFigures operator +(LimitFigures o) => LimitFigures(
    seconds: _add(seconds, o.seconds),
    maxKmh: math.max(maxKmh, o.maxKmh),
  );

  Map<String, Object?> toJson() => {
    's': [for (final v in seconds) _round(v)],
    'vmax': _round(maxKmh),
  };

  factory LimitFigures.fromJson(Object? raw) {
    if (raw is! Map) return LimitFigures();
    final j = raw.cast<String, Object?>();
    return LimitFigures(
      seconds: _list(j['s'], OverLimit.values.length),
      maxKmh: _num(j, 'vmax'),
    );
  }
}

Map<int, LimitFigures> _limitsFromJson(Object? raw) {
  final out = <int, LimitFigures>{};
  if (raw is! Map) return out;
  for (final e in raw.entries) {
    final kmh = int.tryParse('${e.key}');
    if (kmh == null || kmh <= 0) continue;
    out[kmh] = LimitFigures.fromJson(e.value);
  }
  return out;
}

Map<int, LimitFigures> _addLimits(
  Map<int, LimitFigures> a,
  Map<int, LimitFigures> b,
) => {
  for (final k in {...a.keys, ...b.keys})
    k: (a[k] ?? LimitFigures()) + (b[k] ?? LimitFigures()),
};

/// Messwerte einer Fahrt oder die Summe mehrerer Fahrten. Alles außer den Höchstwerten ist
/// eine Summe; Mittel und Anteile rechnen die Getter.
class DriveFigures {
  DriveFigures({
    this.distanceMeters = 0,
    this.movingSeconds = 0,
    this.standSeconds = 0,
    this.stops = 0,
    this.maxKmh = 0,
    List<double>? speedSeconds,
    List<double>? roadSeconds,
    Map<RoadClass, List<double>>? overLimitSeconds,
    this.nightSeconds = 0,
    this.decelerations = 0,
    this.brakes = 0,
    this.hardBrakes = 0,
    this.speedLostMps = 0,
    this.gentleSpeedLostMps = 0,
    this.accelerations = 0,
    this.starts = 0,
    this.strongAccelerations = 0,
    this.sharpCurves = 0,
    this.maxLateralMps2 = 0,
    this.warnings = 0,
    this.camerasPassed = 0,
    this.camerasTooFast = 0,
    this.detailSeconds = 0,
    this.stopSeconds = 0,
    this.longestStopSeconds = 0,
    List<double>? decelPeaks,
    List<double>? accelPeaks,
    this.maxDecelMps2 = 0,
    this.maxAccelMps2 = 0,
    this.calmSeconds = 0,
    this.kinematicSeconds = 0,
    this.cruiseSeconds = 0,
    this.cruiseVariance = 0,
    Map<int, LimitFigures>? limits,
  }) : limits = Map.unmodifiable(limits ?? const <int, LimitFigures>{}),
       decelPeaks = _list(decelPeaks, StatsLimits.peakBins),
       accelPeaks = _list(accelPeaks, StatsLimits.peakBins),
       speedSeconds = _list(speedSeconds, StatsLimits.bins),
       roadSeconds = _list(roadSeconds, RoadClass.values.length),
       overLimitSeconds = {
         for (final c in RoadClass.values)
           c: _list(overLimitSeconds?[c], OverLimit.values.length),
       };

  /// Strecke in Metern.
  final double distanceMeters;

  /// Zeit in Bewegung (Tempo ab 3,6 km/h).
  final double movingSeconds;

  /// Standzeit innerhalb der Fahrt (Ampel, Stau), ohne den Stand am Ende.
  final double standSeconds;

  /// Standphasen ab 5 s.
  final int stops;

  /// Höchstes über 3 Fixes gehaltenes Tempo.
  final double maxKmh;

  /// Fahrzeit je Tempostufe ([StatsLimits.binKmh]).
  final List<double> speedSeconds;

  /// Fahrzeit je [RoadClass], Index = `RoadClass.index`.
  final List<double> roadSeconds;

  /// Fahrzeit mit bekanntem Limit je Straßenart und [OverLimit]-Stufe.
  final Map<RoadClass, List<double>> overLimitSeconds;

  /// Fahrzeit bei Dunkelheit.
  final double nightSeconds;

  /// Alle Verzögerungen mit mindestens 7 km/h Tempoverlust.
  final int decelerations;

  /// Davon mit Spitze über 1,5 m/s².
  final int brakes;

  /// Davon mit Spitze ab 3,0 m/s².
  final int hardBrakes;

  /// Tempoverlust aller Verzögerungen, m/s.
  final double speedLostMps;

  /// Tempoverlust aus sanften Verzögerungen (geschätzt Motorbremse oder Ausrollen), m/s.
  final double gentleSpeedLostMps;

  /// Beschleunigungen mit mindestens 7 km/h Gewinn.
  final int accelerations;

  /// Davon aus dem Stand oder Schritttempo.
  final int starts;

  /// Davon mit Spitze ab 3,0 m/s².
  final int strongAccelerations;

  /// Kurven mit Querbeschleunigung ab 3,5 m/s².
  final int sharpCurves;
  final double maxLateralMps2;

  /// Erste Ansagen der Warnlogik.
  final int warnings;
  final int camerasPassed;
  final int camerasTooFast;

  /// Fahrzeit aus Fahrten mit den ausführlichen Werten unten (ab Version 1.0.0+21). Ältere
  /// Fahrten haben sie nicht; 0 heißt: keine davon.
  final double detailSeconds;

  /// Summe der Halte ab 5 s und der längste davon.
  final double stopSeconds;
  final double longestStopSeconds;

  /// Verzögerungen bzw. Beschleunigungen je Stufe ihrer Spitze ([peakBinOf]).
  final List<double> decelPeaks;
  final List<double> accelPeaks;

  /// Stärkste Spitze einer Verzögerung bzw. Beschleunigung, m/s² (Betrag).
  final double maxDecelMps2;
  final double maxAccelMps2;

  /// Fahrzeit mit Tempoänderung unter [StatsLimits.calmMps2] und die Fahrzeit, in der die
  /// Tempoänderung überhaupt bekannt war.
  final double calmSeconds;
  final double kinematicSeconds;

  /// Zeit auf gleichmäßigen Abschnitten und Σ (Varianz des Tempos · Dauer) darüber, (m/s)²·s.
  final double cruiseSeconds;
  final double cruiseVariance;

  /// Fahrzeit und Höchsttempo je Tempolimit in km/h.
  final Map<int, LimitFigures> limits;

  bool get hasDetail => detailSeconds >= 1;

  double get distanceKm => distanceMeters / 1000;

  /// Mittel in Fahrt (ohne Standzeit), km/h.
  double? get averageKmh =>
      movingSeconds < 1 ? null : distanceMeters / movingSeconds * 3.6;

  /// Mittel über Fahr- und Standzeit (ohne den Stand am Ende), km/h.
  double? get tripAverageKmh {
    final t = movingSeconds + standSeconds;
    return t < 1 ? null : distanceMeters / t * 3.6;
  }

  /// Mittlere Dauer eines Halts.
  double? get meanStopSeconds =>
      !hasDetail || stops == 0 ? null : stopSeconds / stops;

  /// Anteil der Fahrzeit mit Tempoänderung unter [StatsLimits.calmMps2].
  double? get calmShare => kinematicSeconds < StatsLimits.smoothMinSeconds
      ? null
      : calmSeconds / kinematicSeconds;

  /// Mittlere Abweichung (Standardabweichung) des Tempos auf gleichmäßigen Abschnitten, km/h.
  double? get cruiseSwingKmh => cruiseSeconds < StatsLimits.smoothMinSeconds
      ? null
      : math.sqrt(math.max(0, cruiseVariance / cruiseSeconds)) * 3.6;

  PeakShares? get decelShares => peakSharesOf(decelPeaks);
  PeakShares? get accelShares => peakSharesOf(accelPeaks);

  /// Untere Grenze der Stufe mit der meisten Fahrzeit, km/h.
  int? get mostFrequentKmh {
    var best = -1;
    var bestSeconds = 0.0;
    for (var i = 0; i < speedSeconds.length; i++) {
      if (speedSeconds[i] > bestSeconds) {
        best = i;
        bestSeconds = speedSeconds[i];
      }
    }
    return best < 0 ? null : best * StatsLimits.binKmh;
  }

  /// Fahrzeit mit bekanntem Limit, über alle Straßenarten.
  double get limitKnownSeconds =>
      [for (final l in overLimitSeconds.values) ...l]
          .fold(0.0, (a, b) => a + b);

  /// Fahrzeit je Stufe über alle Straßenarten.
  List<double> get overLimitTotal =>
      overLimitSeconds.values.fold(_zeros(OverLimit.values.length), _add);

  /// Anteil der Fahrzeit mit bekanntem Limit ab +11 km/h.
  double? get over10Share {
    final known = limitKnownSeconds;
    if (known < StatsLimits.overLimitMinSeconds) return null;
    final t = overLimitTotal;
    return (t[OverLimit.upTo20.index] + t[OverLimit.above20.index]) / known;
  }

  /// Anteil innerorts an der Fahrzeit mit bekannter Straßenart.
  double? get urbanShare {
    final known = movingSeconds - roadSeconds[RoadClass.unknown.index];
    if (known < 1) return null;
    return roadSeconds[RoadClass.urban.index] / known;
  }

  double? get nightShare =>
      movingSeconds < 1 ? null : nightSeconds / movingSeconds;

  /// Anteil des Tempoverlusts aus sanften Verzögerungen. Geschätzt: Motorbremse, Ausrollen und
  /// leichtes Bremsen sind ohne Fahrzeugdaten nicht zu trennen.
  double? get gentleShare =>
      speedLostMps <= 0 ? null : gentleSpeedLostMps / speedLostMps;

  double _per100Km(int count) =>
      count / math.max(distanceMeters, StatsLimits.rateFloorMeters) * 100000;

  double get hardBrakesPer100Km => _per100Km(hardBrakes);
  double get sharpCurvesPer100Km => _per100Km(sharpCurves);

  /// Vorausschauend, 0–100. Formel in `docs/STATISTIK.md`.
  int? get anticipationScore {
    if (distanceMeters < StatsLimits.scoreMinMeters) return null;
    double part(double v) => v.clamp(0.0, 1.0).toDouble();
    final parts = <(double, double)>[
      if (gentleShare case final g?) (StatsLimits.weightGentle, part(g)),
      (
        StatsLimits.weightHard,
        part(1 - hardBrakesPer100Km / StatsLimits.hardBrakesFullPer100Km),
      ),
      (
        StatsLimits.weightCurves,
        part(1 - sharpCurvesPer100Km / StatsLimits.sharpCurvesFullPer100Km),
      ),
      if (over10Share case final u?)
        (
          StatsLimits.weightOverLimit,
          part(1 - u / StatsLimits.overLimitFullShare),
        ),
    ];
    final weights = parts.fold(0.0, (a, p) => a + p.$1);
    final sum = parts.fold(0.0, (a, p) => a + p.$1 * p.$2);
    return (sum / weights * 100).round();
  }

  DriveFigures operator +(DriveFigures o) => DriveFigures(
    distanceMeters: distanceMeters + o.distanceMeters,
    movingSeconds: movingSeconds + o.movingSeconds,
    standSeconds: standSeconds + o.standSeconds,
    stops: stops + o.stops,
    maxKmh: math.max(maxKmh, o.maxKmh),
    speedSeconds: _add(speedSeconds, o.speedSeconds),
    roadSeconds: _add(roadSeconds, o.roadSeconds),
    overLimitSeconds: {
      for (final c in RoadClass.values)
        c: _add(overLimitSeconds[c]!, o.overLimitSeconds[c]!),
    },
    nightSeconds: nightSeconds + o.nightSeconds,
    decelerations: decelerations + o.decelerations,
    brakes: brakes + o.brakes,
    hardBrakes: hardBrakes + o.hardBrakes,
    speedLostMps: speedLostMps + o.speedLostMps,
    gentleSpeedLostMps: gentleSpeedLostMps + o.gentleSpeedLostMps,
    accelerations: accelerations + o.accelerations,
    starts: starts + o.starts,
    strongAccelerations: strongAccelerations + o.strongAccelerations,
    sharpCurves: sharpCurves + o.sharpCurves,
    maxLateralMps2: math.max(maxLateralMps2, o.maxLateralMps2),
    warnings: warnings + o.warnings,
    camerasPassed: camerasPassed + o.camerasPassed,
    camerasTooFast: camerasTooFast + o.camerasTooFast,
    detailSeconds: detailSeconds + o.detailSeconds,
    stopSeconds: stopSeconds + o.stopSeconds,
    longestStopSeconds: math.max(longestStopSeconds, o.longestStopSeconds),
    decelPeaks: _add(decelPeaks, o.decelPeaks),
    accelPeaks: _add(accelPeaks, o.accelPeaks),
    maxDecelMps2: math.max(maxDecelMps2, o.maxDecelMps2),
    maxAccelMps2: math.max(maxAccelMps2, o.maxAccelMps2),
    calmSeconds: calmSeconds + o.calmSeconds,
    kinematicSeconds: kinematicSeconds + o.kinematicSeconds,
    cruiseSeconds: cruiseSeconds + o.cruiseSeconds,
    cruiseVariance: cruiseVariance + o.cruiseVariance,
    limits: _addLimits(limits, o.limits),
  );

  Map<String, Object?> toJson() => {
    'dist': _round(distanceMeters),
    'moving': _round(movingSeconds),
    'stand': _round(standSeconds),
    'stops': stops,
    'vmax': _round(maxKmh),
    'speed': [for (final s in speedSeconds) _round(s)],
    'road': [for (final s in roadSeconds) _round(s)],
    'over': {
      for (final c in RoadClass.values)
        c.name: [for (final s in overLimitSeconds[c]!) _round(s)],
    },
    'night': _round(nightSeconds),
    'decel': decelerations,
    'brakes': brakes,
    'hard': hardBrakes,
    'lost': _round(speedLostMps, 2),
    'gentle': _round(gentleSpeedLostMps, 2),
    'accel': accelerations,
    'starts': starts,
    'strong': strongAccelerations,
    'curves': sharpCurves,
    'latmax': _round(maxLateralMps2, 2),
    'warn': warnings,
    'cams': camerasPassed,
    'camsFast': camerasTooFast,
    if (hasDetail) ...{
      'detail': _round(detailSeconds),
      'stopSum': _round(stopSeconds),
      'stopMax': _round(longestStopSeconds),
      'decelPk': [for (final v in decelPeaks) v.round()],
      'accelPk': [for (final v in accelPeaks) v.round()],
      'decelMax': _round(maxDecelMps2, 2),
      'accelMax': _round(maxAccelMps2, 2),
      'calm': _round(calmSeconds),
      'kin': _round(kinematicSeconds),
      'cruise': _round(cruiseSeconds),
      'cruiseVar': _round(cruiseVariance, 3),
      'limits': {for (final e in limits.entries) '${e.key}': e.value.toJson()},
    },
  };

  factory DriveFigures.fromJson(Map<String, Object?> j) {
    final over = j['over'];
    return DriveFigures(
      distanceMeters: _num(j, 'dist'),
      movingSeconds: _num(j, 'moving'),
      standSeconds: _num(j, 'stand'),
      stops: _int(j, 'stops'),
      maxKmh: _num(j, 'vmax'),
      speedSeconds: _list(j['speed'], StatsLimits.bins),
      roadSeconds: _list(j['road'], RoadClass.values.length),
      overLimitSeconds: {
        for (final c in RoadClass.values)
          c: _list(over is Map ? over[c.name] : null, OverLimit.values.length),
      },
      nightSeconds: _num(j, 'night'),
      decelerations: _int(j, 'decel'),
      brakes: _int(j, 'brakes'),
      hardBrakes: _int(j, 'hard'),
      speedLostMps: _num(j, 'lost'),
      gentleSpeedLostMps: _num(j, 'gentle'),
      accelerations: _int(j, 'accel'),
      starts: _int(j, 'starts'),
      strongAccelerations: _int(j, 'strong'),
      sharpCurves: _int(j, 'curves'),
      maxLateralMps2: _num(j, 'latmax'),
      warnings: _int(j, 'warn'),
      camerasPassed: _int(j, 'cams'),
      camerasTooFast: _int(j, 'camsFast'),
      detailSeconds: _num(j, 'detail'),
      stopSeconds: _num(j, 'stopSum'),
      longestStopSeconds: _num(j, 'stopMax'),
      decelPeaks: _list(j['decelPk'], StatsLimits.peakBins),
      accelPeaks: _list(j['accelPk'], StatsLimits.peakBins),
      maxDecelMps2: _num(j, 'decelMax'),
      maxAccelMps2: _num(j, 'accelMax'),
      calmSeconds: _num(j, 'calm'),
      kinematicSeconds: _num(j, 'kin'),
      cruiseSeconds: _num(j, 'cruise'),
      cruiseVariance: _num(j, 'cruiseVar'),
      limits: _limitsFromJson(j['limits']),
    );
  }
}

/// Eine gespeicherte Fahrt: Zeitraum und Messwerte, keine Positionen.
class TripSummary {
  const TripSummary({
    required this.id,
    required this.start,
    required this.end,
    required this.figures,
    this.open = false,
  });

  final String id;
  final DateTime start;

  /// Zwischenstand einer laufenden Fahrt. Steht nach einem Neustart noch eine offene Fahrt in
  /// der Ablage, wurde die App hart beendet; sie gilt dann mit ihrem letzten Stand als beendet.
  final bool open;

  /// Letzter Fix in Bewegung; der Stand nach dem Parken zählt nicht.
  final DateTime end;
  final DriveFigures figures;

  Duration get duration => end.difference(start);

  Map<String, Object?> toJson() => {
    'id': id,
    'start': start.toUtc().millisecondsSinceEpoch,
    'end': end.toUtc().millisecondsSinceEpoch,
    if (open) 'open': true,
    ...figures.toJson(),
  };

  /// Null bei unbrauchbarem Eintrag.
  static TripSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, Object?>();
    final id = j['id'];
    final start = j['start'];
    final end = j['end'];
    if (id is! String || start is! int || end is! int) return null;
    return TripSummary(
      id: id,
      start: DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
      end: DateTime.fromMillisecondsSinceEpoch(end, isUtc: true),
      open: j['open'] == true,
      figures: DriveFigures.fromJson(j),
    );
  }

  /// Dieselbe Fahrt als abgeschlossen.
  TripSummary closed() => open
      ? TripSummary(id: id, start: start, end: end, figures: figures)
      : this;
}

/// Summe über [trips].
DriveFigures totalOf(Iterable<TripSummary> trips) =>
    trips.fold(DriveFigures(), (a, t) => a + t.figures);
