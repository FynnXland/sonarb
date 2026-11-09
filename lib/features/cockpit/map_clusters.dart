import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../app/map_layer_settings.dart';
import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import 'map_layers.dart';

/// Punkte einer Raster-Zelle und Ebene: [lead] steht für alle, [members] enthält auch ihn.
/// Bündeln heißt nie Weglassen: Wer nicht einzeln steht, zählt im Bündel mit.
class MarkerGroup {
  MarkerGroup(this.lead, this.members, this.cellX, this.cellY);

  final AlertPoint lead;
  final List<AlertPoint> members;
  final int cellX;
  final int cellY;

  /// Platz unter den Bündeln derselben Zelle (verschiedene Ebenen am selben Ort).
  int slot = 0;
  int slots = 1;

  int get count => members.length;

  /// Seitlicher Versatz in Symbolbreiten, damit Bündel derselben Zelle nebeneinander stehen.
  double get spread => slot - (slots - 1) / 2;
}

/// Bündel ändern sich nur an ganzen Zoomstufen. Dazwischen (beim Ziehen, Zoomen und Fahren)
/// bleibt jede Zuordnung gleich: nichts springt, nichts flackert.
int clusterZoom(double zoom) => zoom.floor().clamp(0, 22);

/// Kantenlänge einer Zelle in Weltbildpunkten bei [clusterZoom]. Etwas mehr als ein Symbol
/// breit: Punkte darin würden sich überdecken.
double clusterCellPx(int zoom) => markerSizeForZoom(zoom.toDouble()) * 1.4;

/// Web-Mercator in Bildpunkten der Zoomstufe [zoom] (256er-Kacheln), unabhängig vom Ausschnitt.
/// Dadurch hängt das Raster nicht am Verschieben der Karte.
Offset worldPixel(GeoPoint g, int zoom) {
  final scale = 256.0 * math.pow(2, zoom);
  final x = (g.lon + 180) / 360 * scale;
  final s = math.sin(g.lat * math.pi / 180).clamp(-0.9999, 0.9999);
  final y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * scale;
  return Offset(x, y);
}

/// Wer ein Bündel anführt: die wichtigere Art (Reihenfolge von [AlertCategory]), dann die ID.
/// Unabhängig von der Reihenfolge, in der die Quellen ihre Punkte liefern.
int _leadOrder(AlertPoint a, AlertPoint b) {
  final c = a.effectiveCategory.index.compareTo(b.effectiveCategory.index);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// Bündelt die sichtbaren Punkte ([markerPoints]) je Ebene in einem festen Raster der ganzen
/// Zoomstufe. Bündel verschiedener Ebenen in derselben Zelle bekommen nebeneinander Platz.
/// Reihenfolge: von Norden nach Süden, damit südlichere Symbole die nördlichen überdecken.
List<MarkerGroup> clusterPoints(
  List<AlertPoint> points,
  Set<MapLayer> layers,
  double zoom,
) {
  final z = clusterZoom(zoom);
  final cell = clusterCellPx(z);
  final byCell = <(MapLayer, int, int), List<AlertPoint>>{};
  for (final p in markerPoints(points, layers, zoom)) {
    final o = worldPixel(p.position, z);
    final key = (layerOf(p), (o.dx / cell).floor(), (o.dy / cell).floor());
    (byCell[key] ??= []).add(p);
  }
  // Zellgrenzen trennen sonst zwei Punkte, die fast aufeinander liegen. Bündel derselben Ebene,
  // deren Anführer näher als eine Dreiviertelzelle stehen, werden eins. Feste Reihenfolge,
  // damit das Ergebnis nicht von der Liefer-Reihenfolge abhängt.
  for (final members in byCell.values) {
    members.sort(_leadOrder);
  }
  final cells = byCell.entries.toList()
    ..sort((a, b) => _leadOrder(a.value.first, b.value.first));
  final merged = <(MapLayer, int, int, Offset, List<AlertPoint>)>[];
  // Nur Nachbarzellen kommen in Frage: Index je Zelle statt Suche über alle Bündel.
  final index = <(MapLayer, int, int), List<int>>{};
  for (final e in cells) {
    final (layer, cx, cy) = e.key;
    final at = worldPixel(e.value.first.position, z);
    var near = -1;
    search:
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final i in index[(layer, cx + dx, cy + dy)] ?? const <int>[]) {
          if ((merged[i].$4 - at).distance < cell * 0.75) {
            near = i;
            break search;
          }
        }
      }
    }
    if (near < 0) {
      (index[e.key] ??= []).add(merged.length);
      merged.add((layer, cx, cy, at, [...e.value]));
    } else {
      merged[near].$5
        ..addAll(e.value)
        ..sort(_leadOrder);
    }
  }
  final groups = <MarkerGroup>[];
  final sameCell = <(int, int), List<(MapLayer, MarkerGroup)>>{};
  for (final m in merged) {
    final g = MarkerGroup(m.$5.first, m.$5, m.$2, m.$3);
    groups.add(g);
    (sameCell[(m.$2, m.$3)] ??= []).add((m.$1, g));
  }
  for (final list in sameCell.values) {
    if (list.length < 2) continue;
    list.sort((a, b) => a.$1.index.compareTo(b.$1.index));
    for (var i = 0; i < list.length; i++) {
      list[i].$2
        ..slot = i
        ..slots = list.length;
    }
  }
  groups.sort((a, b) {
    final lat = b.lead.position.lat.compareTo(a.lead.position.lat);
    return lat != 0 ? lat : a.lead.id.compareTo(b.lead.id);
  });
  return groups;
}
