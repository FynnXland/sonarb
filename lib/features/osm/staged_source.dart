import '../../core/contracts/fixed_point_source.dart';
import '../../core/geo/geo.dart';

/// Quelle, die ihre Blitzer in Stufen liefern kann, damit die ersten Daten auch bei schlechtem
/// Netz früh da sind. Wird von `OsmSource` erfüllt; das Repository nutzt sie, wenn die Quelle sie
/// anbietet. Vorschlag: bei Bedarf nach `core/contracts` verschieben.
abstract interface class StagedPointSource {
  /// Stufe 0: Blitzer aller Kacheln im Speicher oder im Cache-Ordner, die [area] berühren. Kein
  /// Netz, keine Prüfung des Alters: was einmal geladen wurde, zählt als verfügbar. Wirft nicht.
  Future<SourceResult> loadCached(GeoBounds area);

  /// Stufe 1: nur die Blitzer-Kachel unter [position], mit der Dringlichkeit der Blitzer und ohne
  /// Ampeln und Tempolimits. Die Punkte der ganzen Kachel kommen zurück. Wirft nicht; Fehler in
  /// [SourceResult.error].
  Future<SourceResult> loadFirstStage(GeoPoint position);
}
