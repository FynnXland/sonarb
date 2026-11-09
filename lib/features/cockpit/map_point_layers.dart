import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/map_layer_settings.dart';
import '../../app/theme.dart';
import '../../core/model/alert_point.dart';
import 'map_clusters.dart';
import 'map_heat.dart';
import 'map_layers.dart';
import 'symbols/category_symbol.dart';

/// Rot, das auf den dunklen Kacheln leuchtet. Wie kräftig, sagt die Häufigkeit
/// ([heatIntensity]), nicht das Übereinanderlegen.
const heatColor = Color(0xFFFF3B30);

/// So klein wird ein Fleck beim Herauszoomen höchstens, damit er sichtbar bleibt.
const heatMinRadiusPx = 28.0;

/// Weiche rote Flecken unter den Symbolen. Zeigt, wo häufig mobil geblitzt wird, ohne eine
/// genaue Stelle zu behaupten: eine einzelne Meldung ist ein Hauch, viele glühen kräftig
/// ([heatIntensity]). Straßen und Namen bleiben darunter lesbar.
class HeatLayer extends StatelessWidget {
  const HeatLayer({super.key, required this.cells});

  /// Zählraster aus [heatCells] bzw. [HeatCache].
  final List<HeatCell> cells;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: HeatPainter(
            heatSpots(cells, camera),
            heatStrengthForZoom(camera.zoom),
          ),
        ),
      ),
    );
  }
}

/// Flecken im Ausschnitt. Weit draußen fallen viele Zellen auf wenige Bildpunkte: Dann steht je
/// Bildschirmzelle nur der stärkste Fleck, damit sich zarte Einzelmeldungen nicht zu einem
/// kräftigen Rot aufaddieren und die Zahl der Kreise begrenzt bleibt.
List<HeatSpot> heatSpots(List<HeatCell> cells, MapCamera camera) {
  final view = Offset.zero & camera.size;
  final z = clusterZoom(camera.zoom);
  final strongest = <(int, int), (HeatCell, double)>{};
  for (final c in cells) {
    final radius = (heatSpotMeters / metersPerPixel(c.center.lat, camera.zoom))
        .clamp(heatMinRadiusPx, heatMaxRadiusPx);
    final o = worldPixel(c.center, z);
    final key = (
      (o.dx / heatMinRadiusPx).floor(),
      (o.dy / heatMinRadiusPx).floor(),
    );
    final best = strongest[key];
    if (best == null || c.intensity > best.$1.intensity) {
      strongest[key] = (c, radius);
    }
  }
  return [
    for (final (c, radius) in strongest.values)
      if (camera.latLngToScreenOffset(LatLng(c.center.lat, c.center.lon))
          case final at when view.inflate(radius).contains(at))
        HeatSpot(at, radius, c.intensity),
  ];
}

class HeatSpot {
  const HeatSpot(this.center, this.radius, [this.intensity = 1]);

  final Offset center;
  final double radius;

  /// Stärke 0 bis 1 aus der Häufigkeit ([heatIntensity]).
  final double intensity;
}

class HeatPainter extends CustomPainter {
  HeatPainter(this.spots, [this.strength = 1]);

  final List<HeatSpot> spots;

  /// Faktor auf die Deckkraft, siehe [heatStrengthForZoom].
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in spots) {
      final a = heatMaxAlpha * s.intensity * strength;
      if (a <= 0) continue;
      canvas.drawCircle(
        s.center,
        s.radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              heatColor.withValues(alpha: a),
              heatColor.withValues(alpha: a * 0.4),
              heatColor.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ).createShader(Rect.fromCircle(center: s.center, radius: s.radius)),
      );
    }
  }

  @override
  bool shouldRepaint(HeatPainter old) =>
      old.spots != spots || old.strength != strength;
}

/// Symbole der Punkte in jeder Zoomstufe, nie kleiner als [markerMinSize]. Wo sie sich
/// überdecken würden, steht ein Bündel mit Zahl; ausgelassen wird nichts.
class MapPointLayer extends StatelessWidget {
  const MapPointLayer({super.key, required this.points, required this.layers});

  final List<AlertPoint> points;
  final Set<MapLayer> layers;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final size = markerSizeForZoom(camera.zoom);
    return MarkerLayer(
      // Bleibt aufrecht zum Bildschirm und dreht um den Bodenpunkt.
      rotate: true,
      markers: [
        for (final g in clusterPoints(points, layers, camera.zoom))
          if (categorySymbolLayout(g.lead.effectiveCategory, size: size)
              case final l)
            Marker(
              // Je Punkt derselbe Schlüssel: neue Abfragen bauen nichts neu auf.
              key: ValueKey(g.lead.id),
              point: LatLng(g.lead.position.lat, g.lead.position.lon),
              width: l.box.width,
              height: l.box.height,
              alignment: l.markerAlignment,
              child: Transform.translate(
                offset: Offset(g.spread * l.box.width * 1.05, 0),
                child: GroupSymbol(group: g, size: size),
              ),
            ),
      ],
    );
  }
}

/// Symbol eines Bündels: der führende Punkt, bei mehreren mit ihrer Zahl am Kopf.
class GroupSymbol extends StatelessWidget {
  const GroupSymbol({
    super.key,
    required this.group,
    required this.size,
    this.upright = false,
  });

  final MarkerGroup group;
  final double size;
  final bool upright;

  @override
  Widget build(BuildContext context) {
    final lead = group.lead;
    final symbol = CategorySymbol(
      lead.effectiveCategory,
      speed: lead.maxSpeed,
      size: size,
      upright: upright,
    );
    if (group.count < 2) return symbol;
    final badge = clusterBadgeSize(size);
    return Semantics(
      label: '${group.count} Punkte, ${lead.effectiveCategory.label}',
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          symbol,
          Positioned(
            top: -badge * 0.35,
            right: -badge * 0.35,
            child: ClusterBadge(count: group.count, size: badge),
          ),
        ],
      ),
    );
  }
}

/// Durchmesser der Zahl am Bündel: mit dem Symbol, aber nie unter 14.
double clusterBadgeSize(double symbolSize) => math.max(14, symbolSize * 0.62);

/// Zahl der Punkte im Bündel: weiß auf dunkel mit hellem Rand, auf jeder Karte lesbar.
class ClusterBadge extends StatelessWidget {
  const ClusterBadge({super.key, required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minWidth: size, minHeight: size),
    padding: EdgeInsets.symmetric(horizontal: size * 0.18),
    decoration: BoxDecoration(
      color: SonarColors.bg,
      borderRadius: BorderRadius.circular(size / 2),
      border: Border.all(color: SonarColors.text, width: 1.5),
    ),
    alignment: Alignment.center,
    child: Text(
      count > 99 ? '99+' : '$count',
      maxLines: 1,
      // Die Karte skaliert ihre Symbole selbst; die Zahl wächst mit dem Symbol.
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: size * 0.6,
        height: 1,
        fontWeight: FontWeight.w800,
        color: SonarColors.text,
      ),
    ),
  );
}
