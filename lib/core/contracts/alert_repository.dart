import '../geo/geo.dart';
import '../model/alert_point.dart';
import '../model/road_limit.dart';
import 'data_source_plugin.dart';

/// Stand einer Quelle für Anzeige und Einstellungen.
class SourceStatus {
  const SourceStatus({
    required this.id,
    required this.name,
    required this.status,
    this.pointCount = 0,
    this.updatedAt,
    this.message,
  });

  final String id;
  final String name;
  final PluginStatus status;
  final int pointCount;
  final DateTime? updatedAt;
  final String? message;
}

/// Wie weit die Punkte für eine Gegend geladen sind.
enum CoverageState {
  /// Für diese Gegend liegt noch nichts vor; geladen wird gerade oder gleich.
  loading,

  /// Geladen. Steht dann nichts auf der Karte, gibt es dort nichts.
  ready,

  /// Daten liegen vor, der letzte Abruf ist aber gescheitert (gespeicherter oder lückenhafter Stand).
  stale,

  /// Abruf gescheitert, für diese Gegend liegen keine Blitzer vor. Neuer Versuch folgt von selbst.
  failed,

  /// Kartenausschnitt zu groß für eine Abfrage (siehe [maxOverviewSpanDeg]); es gilt der bekannte Stand.
  tooWide,
}

/// Ladestand einer Gegend: feste Messstellen aus OSM, dazu Plugins, die dort zum ersten Mal laden.
class DataCoverage {
  const DataCoverage(this.state, {this.loadingPlugins = const []});

  static const ready = DataCoverage(CoverageState.ready);
  static const loading = DataCoverage(CoverageState.loading);

  final CoverageState state;

  /// Namen eingeschalteter Plugins, die für diese Gegend noch keine Punkte geliefert haben und laden.
  final List<String> loadingPlugins;

  @override
  bool operator ==(Object other) =>
      other is DataCoverage &&
      other.state == state &&
      other.loadingPlugins.join('\n') == loadingPlugins.join('\n');

  @override
  int get hashCode => Object.hash(state, Object.hashAll(loadingPlugins));

  @override
  String toString() => 'DataCoverage($state, $loadingPlugins)';
}

/// Größerer Kartenausschnitt (in Grad, Nord-Süd oder West-Ost): keine neuen Abfragen,
/// nur der bekannte Stand. 0,5° sind rund 55 × 35 km.
const double maxOverviewSpanDeg = 0.5;

/// Welche Daten die App vorhält: Blitzer, Kontrollen und Plugins im Umkreis
/// [detailRadiusMeters] um die eigene Position. Der Umkreis wandert beim Fahren mit und wird
/// laufend nachgeladen; die Karte zeigt ihn als blauen Kreis.
class DataScope {
  const DataScope({
    this.detailRadiusMeters = 5000,
    this.countryCameras = false,
  });

  /// Umkreis um die eigene Position für alle Daten.
  final double detailRadiusMeters;

  /// Zusätzlich feste Blitzer für ganz Deutschland vorhalten (Übersicht beim Herauszoomen).
  final bool countryCameras;

  static const double minRadiusMeters = 2000;
  static const double maxRadiusMeters = 50000;

  /// Ampeln und Tempolimits lädt die App unabhängig vom eingestellten Umkreis nur so weit um die
  /// Position: Sie werden nur dort gebraucht, wo man gerade fährt, und machen fast die gesamte
  /// Datenmenge aus. Blitzer, Kontrollen und Plugins folgen [detailRadiusMeters].
  static const double detailLayersRadiusMeters = 3000;

  /// Wirksamer Radius für Ampeln und Tempolimits.
  double get layersRadiusMeters => detailRadiusMeters < detailLayersRadiusMeters
      ? detailRadiusMeters
      : detailLayersRadiusMeters;

  @override
  bool operator ==(Object other) =>
      other is DataScope &&
      other.detailRadiusMeters == detailRadiusMeters &&
      other.countryCameras == countryCameras;

  @override
  int get hashCode => Object.hash(detailRadiusMeters, countryCameras);
}

/// Führt OSM, Hotspots und Plugins zu einer Punktliste zusammen.
/// Implementierung: `features/alerts`.
abstract interface class AlertRepository {
  /// Gilt ab sofort; ein größerer Umkreis lädt beim nächsten Schritt nach, Deutschland-Blitzer
  /// laden einmalig im Hintergrund (Fortschritt über [watchStatus]).
  DataScope get dataScope;
  set dataScope(DataScope scope);

  /// Liefert die Punkte um [center]. Lädt bei Bedarf nach (Cache, Overpass, Plugins),
  /// ohne den Aufrufer zu blockieren: gibt sofort den bekannten Stand zurück.
  /// Mit [withHistory] kommen die vergangenen Beobachtungen der Plugins
  /// ([AlertPoint.historical]) dazu, unverändert und nicht zusammengeführt. Die Warnlogik bildet
  /// daraus Blitzer-Hotspots.
  List<AlertPoint> pointsAround(
    GeoPoint center, {
    double radiusMeters = 3000,
    bool withHistory = false,
  });

  /// Punkte im Kartenausschnitt [view] für die Übersicht: alle Quellen, auch fern der eigenen
  /// Position. Gibt sofort den bekannten Stand zurück und lädt feste Messstellen für den Ausschnitt
  /// nach (entprellt, nur bis [maxOverviewSpanDeg] Kantenlänge). Neue Daten melden sich über [changes].
  List<AlertPoint> pointsInView(GeoBounds view);

  /// Meldet, wenn sich die Punktmenge geändert hat (neue Daten geladen, Hotspot gesetzt).
  Stream<void> get changes;

  /// Ladestand der Punkte um [center], passend zu [pointsAround]. Stößt selbst nichts an.
  /// Änderungen melden sich über [changes] oder [watchStatus].
  DataCoverage coverageAround(GeoPoint center);

  /// Gebiete im Ausschnitt [view], für die schon Blitzerdaten vorliegen: Rechtecke der geladenen
  /// OSM-Kacheln. Stößt selbst nichts an; neue Gebiete melden sich über [changes].
  List<GeoBounds> loadedAreasIn(GeoBounds view);

  /// Ladestand der Übersicht für [view], passend zu [pointsInView]. Stößt selbst nichts an.
  /// Änderungen melden sich über [changes] oder [watchStatus].
  DataCoverage coverageInView(GeoBounds view);

  /// Stand aller Quellen (osm, hotspot, Plugins).
  Stream<List<SourceStatus>> watchStatus();

  /// Tempolimit der Straße, durchgereicht an [FixedPointSource.speedLimitAt].
  Future<int?> speedLimitAt(GeoPoint position, double? headingDeg);

  /// Tempolimit mit „kein Limit“, durchgereicht an [FixedPointSource.roadLimitAt].
  Future<RoadLimit> roadLimitAt(GeoPoint position, double? headingDeg);

  /// Strecke voraus, durchgereicht an [FixedPointSource.roadAheadAt].
  Future<List<GeoPoint>?> roadAheadAt(GeoPoint position, double headingDeg);

  /// Registrierte Plugins mit Ein/Aus-Zustand.
  List<DataSourcePlugin> get plugins;
  bool isPluginEnabled(String pluginId);
  Future<void> setPluginEnabled(String pluginId, bool enabled);

  Future<void> dispose();
}
