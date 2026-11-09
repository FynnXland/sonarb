import 'dart:math' as math;

import '../../app/map_layer_settings.dart';
import '../../core/model/alert_point.dart';

/// Ab diesem Zoom erscheinen Ampeln.
const signalMinZoom = 15.0;

/// Zu welcher Ebene ein Punkt gehört, nach seiner feinen Art. Plugins liefern Gefahrenmeldungen
/// (Stauende, Unfall …) mit der groben Art `live` wie mobile Blitzer; die Ebene darf deshalb
/// nicht an der groben Art hängen.
MapLayer layerOf(AlertPoint p) {
  final c = p.effectiveCategory;
  if (c == AlertCategory.trafficSignal) return MapLayer.signals;
  if (isMobileCamera(c)) return MapLayer.mobile;
  return switch (c) {
    AlertCategory.longTermRoadworks ||
    AlertCategory.dayRoadworks ||
    AlertCategory.closure => MapLayer.construction,
    _ when c.group == CategoryGroup.hazard => MapLayer.danger,
    // Feste Messstellen und weitere Kontrollen (Höhe, Gewicht, Einfahrt, Busspur, Überholverbot).
    _ => MapLayer.fixedCameras,
  };
}

/// Mobile bzw. vorübergehende Messung: Symbol in der Ebene „Mobile“ und Teil der roten Wärme.
bool isMobileCamera(AlertCategory c) =>
    c.isMobile || c == AlertCategory.semiStationary;

/// Punkte der Wärme-Ebene: aktuelle und vergangene mobile Beobachtungen. Wo sie sich häufen,
/// leuchtet der Hintergrund (`map_heat.dart`).
List<AlertPoint> heatPoints(List<AlertPoint> points, Set<MapLayer> layers) {
  if (!layers.contains(MapLayer.mobile)) return const [];
  return [
    for (final p in points)
      if (layerOf(p) == MapLayer.mobile) p,
  ];
}

/// Meter je Bildpunkt (Web-Mercator, 256-Pixel-Kacheln).
double metersPerPixel(double latitude, double zoom) =>
    156543.03392 * math.cos(latitude * math.pi / 180) / math.pow(2, zoom);

/// Größter Fleck in Bildpunkten: ganz nah soll er die Karte nicht flach einfärben.
const heatMaxRadiusPx = 300.0;

/// Stärke des Flecks nach Zoom: bis Zoom 16 voll, danach blasser, ab Zoom 19 nur noch ein Hauch.
/// Dort sieht man die gemeldeten Stellen selbst.
double heatStrengthForZoom(double zoom) =>
    zoom <= 16 ? 1.0 : (1 - (zoom - 16) * 0.25).clamp(0.25, 1.0);

/// Kleinste Symbolgröße (Durchmesser des Nadelkopfs): darunter wird nichts kleiner, und nichts
/// blendet aus. Zu dichte Stellen werden gebündelt (`map_clusters.dart`).
const markerMinSize = 16.0;
const markerMaxSize = 26.0;

/// Symbolgröße: beim Herauszoomen klein, aber nie unter [markerMinSize], nah größer.
double markerSizeForZoom(double zoom) =>
    (12 + (zoom - 8) * 1.7).clamp(markerMinSize, markerMaxSize);

/// Punkte, die als Symbol erscheinen: alle eingeschalteten Ebenen in jeder Zoomstufe, nur
/// Ampeln erst nah. Mobile Blitzer stehen als Symbol auch über ihrem Wärmefleck.
List<AlertPoint> markerPoints(
  List<AlertPoint> points,
  Set<MapLayer> layers,
  double zoom,
) => [
  for (final p in points)
    // Vergangene Beobachtungen zählen nur für die Wärme.
    if (!p.historical && _showsMarker(layerOf(p), layers, zoom)) p,
];

bool _showsMarker(MapLayer layer, Set<MapLayer> layers, double zoom) {
  if (!layers.contains(layer)) return false;
  return switch (layer) {
    MapLayer.signals => zoom >= signalMinZoom,
    _ => true,
  };
}
