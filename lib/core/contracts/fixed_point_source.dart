import '../geo/geo.dart';
import '../model/alert_point.dart';
import '../model/road_limit.dart';

/// Ergebnis einer Abfrage fester Punkte.
class SourceResult {
  const SourceResult({
    required this.points,
    this.fetchedAt,
    this.fromCache = false,
    this.error,
    this.notice,
    this.errorInDetailsOnly = false,
  });

  /// True, wenn [error] nur Ampeln und Tempolimits betrifft; die Blitzer sind dann vollständig.
  final bool errorInDetailsOnly;

  final List<AlertPoint> points;

  /// Hinweis ohne Störung, z. B. dass Ampeln und Tempolimits im Hintergrund nachgeladen werden.
  final String? notice;

  /// Zeitpunkt, zu dem die Daten vom Server geholt wurden (auch bei Cache-Treffern).
  final DateTime? fetchedAt;
  final bool fromCache;

  /// Kurzer Fehlertext, wenn der Server nicht erreichbar war. Punkte können trotzdem aus dem Cache kommen.
  final String? error;
}

/// Feste Messstellen, Ampeln und Tempolimits aus OpenStreetMap (Overpass).
/// Implementierung: `features/osm`.
abstract interface class FixedPointSource {
  /// Alle festen Punkte in [area]. Nutzt den lokalen Cache, lädt nur fehlende oder veraltete Kacheln.
  /// Wirft nicht bei Netzfehlern, sondern setzt [SourceResult.error].
  Future<SourceResult> load(GeoBounds area);

  /// Tempolimit (km/h) der Straße, auf der man bei [position] mit Kurs [headingDeg] am
  /// wahrscheinlichsten fährt. Null, wenn unbekannt. Nutzt nur bereits geladene Daten.
  Future<int?> speedLimitAt(GeoPoint position, double? headingDeg);

  /// Wie [speedLimitAt], unterscheidet aber „kein Limit“ (Autobahn ohne Tempolimit) von
  /// „unbekannt“. Ein Aufruf ersetzt [speedLimitAt], nicht beide nacheinander aufrufen.
  Future<RoadLimit> roadLimitAt(GeoPoint position, double? headingDeg);

  /// Strecke, der man bei [position] mit Kurs [headingDeg] wahrscheinlich folgt: die eigene
  /// Straße und ihre Fortsetzung (an Kreuzungen gleicher Name oder gleiche Nummer, sonst gleiche
  /// Art), bis etwa 2,5 km voraus, ab der Position. Null, wenn die Straßendaten fehlen oder keine
  /// Straße passt. Nutzt nur bereits geladene Daten, stößt nichts an.
  Future<List<GeoPoint>?> roadAheadAt(GeoPoint position, double headingDeg);

  /// Nur feste Messstellen in [area], für die Kartenübersicht beim Herauszoomen. Nutzt den Cache
  /// von [load] mit, lädt keine Ampeln und Tempolimits. Wirft nicht, Fehler in [SourceResult.error].
  Future<SourceResult> loadCameras(GeoBounds area);

  /// Rechtecke der Blitzer-Kacheln mit Daten (Speicher oder Cache-Ordner), die [view] berühren.
  /// Synchron, stößt nichts an. Der Cache-Ordner wird beim ersten Aufruf im Hintergrund gelesen;
  /// bis dahin zählen nur Kacheln im Speicher.
  List<GeoBounds> loadedCameraTilesIn(GeoBounds view);

  /// Cache leeren (Einstellungen).
  Future<void> clearCache();

  /// Belegter Speicher des Caches in Bytes.
  Future<int> cacheSizeBytes();
}
