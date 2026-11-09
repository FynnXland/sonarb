part of 'osm_source.dart';

/// Pausen im Funkloch: nicht in schneller Folge neu versuchen, jede Minute kostet Akku und Daten.
extension _NetBackoff on OsmSource {
  /// Zählt einen Fehlschlag ohne Netz. Mehrere gleichzeitige Abfragen einer Runde zählen einmal.
  void _noteNetFailure() {
    final now = _now();
    final last = _netFailedAt;
    if (last == null || now.difference(last) >= retryAfterFailure) {
      _netFailures++;
      _netFailedAt = now;
    }
  }

  /// Pause nach _netFailures Fehlschlägen in Folge: nach dem 2. 2 min, dann 5, 15, 30 min.
  Duration _netBackoff() {
    const steps = [60, 120, 300, 900, 1800];
    return _netFailures < 2
        ? Duration.zero
        : Duration(
            seconds: steps[math.min(_netFailures - 1, steps.length - 1)],
          );
  }
}
