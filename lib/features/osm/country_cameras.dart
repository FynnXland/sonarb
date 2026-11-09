/// Ergebnis eines Laufs, der alle festen Messstellen Deutschlands in den Kachel-Cache holt.
class CountryLoadResult {
  const CountryLoadResult({
    this.error,
    this.fetchedAt,
    this.points = 0,
    this.tiles = 0,
  });

  /// Kurzer Fehlertext; null bei Erfolg.
  final String? error;

  /// Zeitpunkt der Overpass-Daten.
  final DateTime? fetchedAt;

  /// Anzahl der Messstellen (Knoten und Relationen).
  final int points;

  /// Anzahl der in den Cache geschriebenen Kacheln (0,1°), auch leere.
  final int tiles;

  bool get ok => error == null;
}

/// Quelle, die ganz Deutschland auf einmal in den Cache holen kann. Wird von [OsmSource] erfüllt;
/// das Repository nutzt sie, wenn die Quelle sie anbietet. Vorschlag: bei Bedarf nach
/// `core/contracts` verschieben.
abstract interface class CountryCameraSource {
  /// Lädt alle festen Messstellen Deutschlands mit einer Anfrage und legt sie kachelweise in den
  /// Cache. Wirft nicht; Fehler stehen in [CountryLoadResult.error]. Läuft hinter allen Abfragen der
  /// Fahrt in der Warteschlange.
  Future<CountryLoadResult> loadCountryCameras();
}
