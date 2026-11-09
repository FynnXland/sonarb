import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Brems- oder Beschleunigungsvorgang im Verlauf.
enum TraceEventKind { decel, accel }

/// Ein Vorgang mit Spitze über 1,5 m/s². Zeiten in Sekunden ab Fahrtbeginn.
class TraceEvent {
  const TraceEvent({
    required this.kind,
    required this.second,
    required this.seconds,
    required this.peakMps2,
    required this.fromKmh,
    required this.toKmh,
  });

  final TraceEventKind kind;
  final int second;
  final int seconds;

  /// Spitze, m/s² (Betrag).
  final double peakMps2;
  final int fromKmh;
  final int toKmh;

  List<Object> toJson() => [
    kind == TraceEventKind.decel ? 0 : 1,
    second,
    seconds,
    (peakMps2 * 10).round(),
    fromKmh,
    toKmh,
  ];

  static TraceEvent? fromJson(Object? raw) {
    if (raw is! List || raw.length < 6 || raw.any((v) => v is! num)) {
      return null;
    }
    final v = [for (final x in raw) (x as num).round()];
    return TraceEvent(
      kind: v[0] == 0 ? TraceEventKind.decel : TraceEventKind.accel,
      second: v[1],
      seconds: v[2],
      peakMps2: v[3] / 10,
      fromKmh: v[4],
      toKmh: v[5],
    );
  }
}

/// Tempolimit ab einer Sekunde: km/h, [none] für „kein Limit“, null für unbekannt.
class TraceLimit {
  const TraceLimit(this.second, this.kmh);

  /// Kein Tempolimit (OSM `maxspeed=none`).
  static const none = 0;

  final int second;
  final int? kmh;
}

/// Tempoverlauf einer Fahrt: ein Wert je Sekunde ab dem ersten Fix, in ganzen km/h. Keine
/// Positionen. Gespeichert getrennt von der Zusammenfassung (`stats/traces/<id>.json`).
class TripTrace {
  TripTrace({
    required this.speeds,
    this.limits = const [],
    this.events = const [],
  });

  /// Kein Messwert in dieser Sekunde (Lücke, Tunnel).
  static const gap = 255;

  /// Höchstes speicherbares Tempo.
  static const maxKmh = 254;

  /// Tempo je Sekunde in km/h, [gap] ohne Messwert.
  final Uint8List speeds;

  /// Wechsel des Limits, nach Zeit geordnet.
  final List<TraceLimit> limits;
  final List<TraceEvent> events;

  int get length => speeds.length;

  /// Tempo in Sekunde [i], null bei Lücke.
  int? speedAt(int i) {
    final v = speeds[i];
    return v == gap ? null : v;
  }

  /// Limit in Sekunde [i] wie [TraceLimit.kmh].
  int? limitAt(int i) {
    int? kmh;
    for (final l in limits) {
      if (l.second > i) break;
      kmh = l.kmh;
    }
    return kmh;
  }

  /// Höchstes Tempo im Verlauf.
  int get peakKmh {
    var best = 0;
    for (final v in speeds) {
      if (v != gap && v > best) best = v;
    }
    return best;
  }

  int get version => 1;

  Map<String, Object?> toJson() => {
    'v': version,
    'speed': base64Encode(speeds),
    'limits': [
      for (final l in limits) [l.second, l.kmh],
    ],
    'events': [for (final e in events) e.toJson()],
  };

  /// Null bei unbrauchbarem Inhalt.
  static TripTrace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final speed = raw['speed'];
    if (speed is! String) return null;
    final Uint8List bytes;
    try {
      bytes = base64Decode(speed);
    } on FormatException {
      return null;
    }
    final limits = <TraceLimit>[];
    final rawLimits = raw['limits'];
    if (rawLimits is List) {
      for (final l in rawLimits) {
        if (l is List && l.length == 2 && l[0] is num) {
          final kmh = l[1];
          limits.add(
            TraceLimit((l[0] as num).round(), kmh is num ? kmh.round() : null),
          );
        }
      }
    }
    final rawEvents = raw['events'];
    return TripTrace(
      speeds: bytes,
      limits: limits,
      events: [
        if (rawEvents is List)
          for (final e in rawEvents) ?TraceEvent.fromJson(e),
      ],
    );
  }
}

/// Wie die Sekunden zwischen zwei Fixes gefüllt werden.
enum TraceFill {
  /// Linear zwischen den beiden Werten (lückenlose Kette).
  interpolate,

  /// Stand: 0 km/h.
  stand,

  /// Unbekannt.
  gap,
}

/// Baut den Verlauf Fix für Fix auf. Höchstens [maxSeconds] Sekunden.
class TraceBuilder {
  /// 24 h; danach kommt nichts mehr dazu.
  static const maxSeconds = 24 * 3600;

  final _speeds = <int>[];
  final _limits = <TraceLimit>[];
  final _events = <TraceEvent>[];

  int get length => _speeds.length;

  /// Tempo [kmh] zur Sekunde [seconds] ab Fahrtbeginn. Die Sekunden seit dem letzten Wert
  /// füllt [fill].
  void add(
    double seconds,
    double kmh, {
    TraceFill fill = TraceFill.interpolate,
  }) {
    final i = seconds.round();
    if (i < 0 || i >= maxSeconds) return;
    final value = kmh.round().clamp(0, TripTrace.maxKmh);
    if (_speeds.isEmpty) {
      for (var k = 0; k < i; k++) {
        _speeds.add(TripTrace.gap);
      }
      _speeds.add(value);
      return;
    }
    final last = _speeds.length - 1;
    if (i <= last) {
      _speeds[last] = value;
      return;
    }
    final from = _speeds[last];
    for (var k = last + 1; k < i; k++) {
      _speeds.add(switch (fill) {
        TraceFill.stand => 0,
        TraceFill.gap => TripTrace.gap,
        TraceFill.interpolate =>
          from == TripTrace.gap
              ? TripTrace.gap
              : (from + (value - from) * (k - last) / (i - last)).round(),
      });
    }
    _speeds.add(value);
  }

  /// Limit ab Sekunde [seconds], gespeichert nur bei Wechsel.
  /// Vor dem ersten Eintrag gilt „unbekannt“.
  void limit(double seconds, int? kmh) {
    final current = _limits.isEmpty ? null : _limits.last.kmh;
    if (current == kmh) return;
    final s = math.max(0, seconds.round());
    if (_limits.isNotEmpty && _limits.last.second == s) _limits.removeLast();
    _limits.add(TraceLimit(s, kmh));
  }

  void event(TraceEvent e) => _events.add(e);

  /// Verlauf bis einschließlich Sekunde [endSecond].
  TripTrace build(int endSecond) {
    final n = math.min(_speeds.length, math.max(0, endSecond + 1));
    return TripTrace(
      speeds: Uint8List.fromList(_speeds.sublist(0, n)),
      limits: [
        for (final l in _limits)
          if (l.second < n) l,
      ],
      events: [
        for (final e in _events)
          if (e.second < n) e,
      ],
    );
  }
}
