import '../geo/geo.dart';
import 'alert_category.dart';
import 'hotspot_kind.dart';

export 'alert_category.dart';
export 'hotspot_kind.dart';

/// Art eines Warnpunkts. Die Warnlogik entscheidet anhand der Art über Ton und Distanzen.
enum AlertKind {
  /// Fester Blitzer (Geschwindigkeit), OSM `highway=speed_camera`.
  speedCamera,

  /// Rotlichtblitzer, OSM `enforcement=traffic_signals`.
  redLightCamera,

  /// Abschnittskontrolle, OSM `enforcement=average_speed` / `section_control`.
  sectionControl,

  /// Ampel, OSM `highway=traffic_signals`. Nur Kartenanzeige, keine Warnung.
  trafficSignal,

  /// Eigener Hotspot (gemeldete Stelle). Genaue Art in [AlertPoint.reportKind].
  hotspot,

  /// Punkt aus einem Plugin (Live-Feed).
  live,

  /// Baustelle, z. B. aus einem Plugin. Gemeldete Baustellen sind [hotspot] mit
  /// [HotspotKind.construction].
  construction,
}

extension AlertKindX on AlertKind {
  /// Feste Messstellen mit Vor- und Hauptwarnung.
  bool get isFixedCamera =>
      this == AlertKind.speedCamera ||
      this == AlertKind.redLightCamera ||
      this == AlertKind.sectionControl;
}

/// Eine Angabe zu einem Punkt für die Detailansicht, z. B. „Erlaubt“ → „50 km/h“ oder
/// „Seit“ → „März 2021“. [label] ist kurz und deutsch; gleiche Labels aus mehreren Quellen
/// werden beim Zusammenführen zusammengelegt, unterschiedliche Werte bleiben erhalten.
class PointDetail {
  const PointDetail(this.label, this.value);

  final String label;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is PointDetail && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => '$label: $value';
}

/// Herkunft eines Punkts: Quelle mit Namen, Lizenzhinweis und Stand der Daten.
class PointSource {
  const PointSource({
    required this.id,
    required this.name,
    this.attribution,
    this.updatedAt,
    this.url,
  });

  /// `osm`, `hotspot` oder die Plugin-ID.
  final String id;

  /// Anzeigename, z. B. „OpenStreetMap“.
  final String name;

  /// Pflichthinweis der Lizenz, z. B. „© OpenStreetMap-Mitwirkende, ODbL“.
  final String? attribution;

  /// Stand der Daten dieser Quelle für diesen Punkt (letzte Änderung oder Abruf).
  final DateTime? updatedAt;

  /// Link auf den Eintrag bei der Quelle, falls es einen gibt (z. B. OSM-Knoten).
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is PointSource && other.id == id && other.url == url;

  @override
  int get hashCode => Object.hash(id, url);
}

/// Ein Punkt, vor dem gewarnt oder der auf der Karte gezeigt wird.
/// Quellen: OSM (Core), Hotspots (Core), Plugins (optional).
class AlertPoint {
  const AlertPoint({
    required this.id,
    required this.kind,
    required this.position,
    required this.source,
    this.travelBearings = const [],
    this.maxSpeed,
    this.label,
    this.radiusMeters,
    this.reportKind,
    this.details = const [],
    this.sources = const [],
    this.category,
    this.observedAt,
    this.historical = false,
  });

  /// Eindeutig über alle Quellen: `osm:node/123`, `hotspot:<uuid>`, `plugin:<pluginId>:<id>`.
  final String id;
  final AlertKind kind;
  final GeoPoint position;

  /// Fahrtrichtungen (Grad, 0 = Nord), für die der Punkt gilt.
  /// Leer = Richtung unbekannt oder beide Richtungen: gilt immer.
  final List<double> travelBearings;

  /// Erlaubte Geschwindigkeit an der Messstelle in km/h, falls bekannt.
  final int? maxSpeed;

  /// `osm`, `hotspot` oder die Plugin-ID.
  final String source;

  /// Kurze Bezeichnung für die Anzeige, optional.
  final String? label;

  /// Warnradius für Hotspots und Live-Punkte. Null = Standard der Warnlogik.
  final double? radiusMeters;

  /// Art der Meldung bei [AlertKind.hotspot], sonst null.
  final HotspotKind? reportKind;

  /// Alles, was die Quellen über den Punkt wissen, für die Detailansicht (Antippen).
  final List<PointDetail> details;

  /// Alle Quellen dieses Punkts. Leer heißt: nur [source], ohne weitere Angaben.
  /// Nach dem Zusammenführen doppelter Punkte stehen hier alle beteiligten Quellen.
  final List<PointSource> sources;

  /// Feine Art für Symbol und Legende. Null: abgeleitet aus [kind] und [reportKind].
  final AlertCategory? category;

  /// Wann der Punkt beobachtet oder gemeldet wurde (bei mobilen Blitzern, Meldungen), falls bekannt.
  final DateTime? observedAt;

  /// Vergangene Beobachtung, z. B. ein mobiler Blitzer von vor Monaten. Solche Punkte zählen nur für
  /// die Häufigkeit (rote Wärme-Ebene), erscheinen nicht als Symbol und lösen keine Warnung aus.
  final bool historical;

  /// Die gesetzte oder abgeleitete feine Art.
  AlertCategory get effectiveCategory =>
      category ?? defaultCategory(kind, reportKind);

  AlertPoint copyWith({
    String? id,
    AlertKind? kind,
    GeoPoint? position,
    String? source,
    List<double>? travelBearings,
    int? maxSpeed,
    String? label,
    double? radiusMeters,
    HotspotKind? reportKind,
    List<PointDetail>? details,
    List<PointSource>? sources,
    AlertCategory? category,
    DateTime? observedAt,
    bool? historical,
  }) => AlertPoint(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    position: position ?? this.position,
    source: source ?? this.source,
    travelBearings: travelBearings ?? this.travelBearings,
    maxSpeed: maxSpeed ?? this.maxSpeed,
    label: label ?? this.label,
    radiusMeters: radiusMeters ?? this.radiusMeters,
    reportKind: reportKind ?? this.reportKind,
    details: details ?? this.details,
    sources: sources ?? this.sources,
    category: category ?? this.category,
    observedAt: observedAt ?? this.observedAt,
    historical: historical ?? this.historical,
  );

  @override
  String toString() => 'AlertPoint($id, $kind, $position, $travelBearings)';
}
