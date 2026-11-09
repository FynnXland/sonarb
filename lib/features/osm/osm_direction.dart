import '../../core/geo/geo.dart';

/// Ergebnis des Lesens eines `direction`-Werts.
class ParsedDirection {
  const ParsedDirection({
    this.degrees = const [],
    this.forward = false,
    this.backward = false,
    this.all = false,
  });

  /// Absolute Kurse in Grad.
  final List<double> degrees;

  /// Relativ zur Wegrichtung am Knoten.
  final bool forward;
  final bool backward;

  /// `both`/`all`: gilt in jeder Richtung.
  final bool all;
}

const _cardinals = <String, double>{
  'n': 0,
  'nne': 22.5,
  'ne': 45,
  'ene': 67.5,
  'e': 90,
  'ese': 112.5,
  'se': 135,
  'sse': 157.5,
  's': 180,
  'ssw': 202.5,
  'sw': 225,
  'wsw': 247.5,
  'w': 270,
  'wnw': 292.5,
  'nw': 315,
  'nnw': 337.5,
  'north': 0,
  'east': 90,
  'south': 180,
  'west': 270,
};

/// Liest einen `direction`-Wert (Grad, Himmelsrichtung, forward/backward, both/all, Listen mit `;`).
/// Null, wenn er nicht verständlich ist.
ParsedDirection? parseDirection(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final degrees = <double>[];
  var forward = false, backward = false, all = false;
  for (final token in raw.split(';')) {
    final t = token.trim().toLowerCase();
    if (t.isEmpty) continue;
    if (t == 'forward') {
      forward = true;
    } else if (t == 'backward') {
      backward = true;
    } else if (t == 'both' || t == 'all') {
      all = true;
    } else if (_cardinals.containsKey(t)) {
      degrees.add(_cardinals[t]!);
    } else {
      final range = RegExp(r'^(\d+(?:[.,]\d+)?)\s*-\s*(\d+(?:[.,]\d+)?)$')
          .firstMatch(t);
      if (range != null) {
        // Sichtfeld „67-292“: Mitte des Bogens im Uhrzeigersinn.
        final a = _num(range.group(1)!), b = _num(range.group(2)!);
        degrees.add(normalizeDegrees(a + normalizeDegrees(b - a) / 2));
        continue;
      }
      final n = double.tryParse(t.replaceAll(',', '.'));
      if (n == null || n < 0 || n > 360) return null;
      degrees.add(normalizeDegrees(n));
    }
  }
  if (degrees.isEmpty && !forward && !backward && !all) return null;
  return ParsedDirection(
    degrees: degrees,
    forward: forward,
    backward: backward,
    all: all,
  );
}

double _num(String s) => double.parse(s.replaceAll(',', '.'));

/// Weg, auf dem ein Knoten liegt: Kurs in Wegrichtung am Knoten und Einbahn-Flag.
class WayContext {
  const WayContext({required this.bearing, this.oneway = 0});

  /// Peilung in Wegrichtung am Knoten.
  final double bearing;

  /// 1 = Einbahn in Wegrichtung, -1 = Einbahn dagegen, 0 = beidseitig.
  final int oneway;
}

/// Fahrtrichtungen (Grad), für die ein Blitzer gilt. Leer = alle Richtungen oder unbekannt.
///
/// Auslegung: `direction` nennt die Fahrtrichtung der kontrollierten Fahrzeuge (Richtung der
/// Messung), nicht die Blickrichtung des Geräts. [direction] hat Vorrang vor [cameraDirection].
/// Fehlt beides oder ist es unverständlich, entscheidet nur eine Einbahnstraße.
List<double> resolveNodeBearings({
  String? direction,
  String? cameraDirection,
  WayContext? way,
}) {
  ParsedDirection? parsed;
  for (final raw in [direction, cameraDirection]) {
    parsed = parseDirection(raw);
    if (parsed != null) break;
  }
  if (parsed == null) {
    if (way != null && way.oneway != 0) {
      return [normalizeDegrees(way.bearing + (way.oneway > 0 ? 0 : 180))];
    }
    return const [];
  }
  if (parsed.all || (parsed.forward && parsed.backward)) return const [];

  final result = <double>[...parsed.degrees];
  if (parsed.forward || parsed.backward) {
    if (way == null) return const []; // relativ, aber ohne Weg: nicht auflösbar
    result.add(normalizeDegrees(way.bearing + (parsed.forward ? 0 : 180)));
  }
  return _dedupe(result);
}

/// Fahrtrichtung einer Enforcement-Relation: Peilung von [from] nach [target].
/// Leer, wenn eine Position fehlt oder beide praktisch zusammenfallen.
List<double> bearingFromTo(GeoPoint? from, GeoPoint? target) {
  if (from == null || target == null) return const [];
  if (distanceMeters(from, target) < 3) return const [];
  return [bearingDegrees(from, target)];
}

List<double> _dedupe(List<double> values) {
  final out = <double>[];
  for (final v in values) {
    final n = normalizeDegrees(v);
    if (!out.any((o) => angleDifference(o, n) < 0.5)) out.add(n);
  }
  return out;
}
