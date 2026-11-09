import 'dart:math' as math;

import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import 'map_clusters.dart';
import '../../app/map_layer_settings.dart';
import 'map_layers.dart';

/// Umkreis, in dem mobile Beobachtungen zusammen zählen: etwa ein Straßenabschnitt, auf dem
/// eine Messstelle typischerweise wechselt (Parkbucht, Einfahrt, Brücke).
const heatNeighbourMeters = 300.0;

/// Gemalter Radius eines Flecks: etwas größer als der Zählkreis, damit benachbarte Zellen
/// ineinander übergehen statt als Punkte nebeneinander zu stehen.
const heatSpotMeters = 360.0;

/// Nach dieser Zeit zählt eine Beobachtung nur noch halb. Ein Jahr: Messstellen wechseln mit
/// Baustellen und Schwerpunktaktionen, zwei Jahre alte Daten sagen noch etwas, aber weniger.
const heatHalfLife = Duration(days: 365);

/// Bei so vielen (gewichteten) Beobachtungen hat der Fleck halbe Stärke.
const heatHalfCount = 4.0;

/// Steilheit der Kurve. Mit 2 bleibt eine einzelne Meldung ein Hauch (6 %), drei sind deutlich
/// (36 %), acht bis zehn kräftig (80–86 %), danach sättigt sie gegen 100 %.
const heatHillExponent = 2.0;

/// Deckkraft in der Mitte eines Flecks bei voller Stärke.
const heatMaxAlpha = 0.5;

/// Gewicht einer Beobachtung nach Alter: halbiert sich je [heatHalfLife]. Ohne Datum oder mit
/// Datum in der Zukunft zählt sie voll.
double observationWeight(AlertPoint p, DateTime now) {
  final at = p.observedAt;
  if (at == null) return 1;
  final days = now.difference(at).inHours / 24;
  if (days <= 0) return 1;
  return math.pow(0.5, days / (heatHalfLife.inHours / 24)).toDouble();
}

/// Stärke 0 bis 1 aus der gewichteten Zahl der Beobachtungen (Hill-Kurve).
double heatIntensity(double weightedCount) {
  if (weightedCount <= 0) return 0;
  final n = math.pow(weightedCount, heatHillExponent);
  final k = math.pow(heatHalfCount, heatHillExponent);
  return (n / (n + k)).toDouble();
}

/// Eine Zelle des Zählrasters mit dem, was in ihrem Umkreis beobachtet wurde.
class HeatCell {
  HeatCell(this.center, this.ownCount);

  /// Mittelpunkt der Beobachtungen in der Zelle.
  GeoPoint center;
  final int ownCount;

  /// Im Umkreis [heatNeighbourMeters]: Zahl, Gewicht, älteste und jüngste Beobachtung.
  int count = 0;
  double weight = 0;
  DateTime? earliest;
  DateTime? latest;

  double get intensity => heatIntensity(weight);

  /// Eine Beobachtung im Umkreis mitzählen.
  void add(AlertPoint p, DateTime now) {
    count += 1;
    weight += observationWeight(p, now);
    final at = p.observedAt;
    if (at == null) return;
    if (latest == null || at.isAfter(latest!)) latest = at;
    if (earliest == null || at.isBefore(earliest!)) earliest = at;
  }
}

/// Was im Umkreis [heatNeighbourMeters] um [center] beobachtet wurde, etwa um einen angetippten
/// Punkt. Einmal durch die Liste: nur beim Antippen, nicht je Bild.
HeatCell heatCellAround(GeoPoint center, List<AlertPoint> heat, DateTime now) {
  final cell = HeatCell(center, 0);
  for (final p in heat) {
    if (distanceMeters(center, p.position) <= heatNeighbourMeters) {
      cell.add(p, now);
    }
  }
  return cell;
}

/// Zählraster: fest in Metern (Zellen etwa [heatNeighbourMeters] groß), unabhängig von Zoom
/// und Ausschnitt. Ein Durchlauf über die Punkte, dann je Zelle die 3 × 3 Nachbarn. So bleiben
/// auch Tausende alter Beobachtungen schnell.
List<HeatCell> heatCells(List<AlertPoint> heat, DateTime now) {
  if (heat.isEmpty) return const [];
  const z = 16;
  final cellPx = heatNeighbourMeters / metersPerPixel(51, z.toDouble());
  final raw = <(int, int), List<AlertPoint>>{};
  for (final p in heat) {
    final o = worldPixel(p.position, z);
    (raw[((o.dx / cellPx).floor(), (o.dy / cellPx).floor())] ??= []).add(p);
  }
  final cells = <(int, int), (HeatCell, List<AlertPoint>)>{};
  raw.forEach((key, members) {
    var lat = 0.0;
    var lon = 0.0;
    for (final p in members) {
      lat += p.position.lat;
      lon += p.position.lon;
    }
    final center = GeoPoint(lat / members.length, lon / members.length);
    cells[key] = (HeatCell(center, members.length), members);
  });
  cells.forEach((key, entry) {
    final cell = entry.$1;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final n = cells[(key.$1 + dx, key.$2 + dy)];
        if (n == null) continue;
        for (final p in n.$2) {
          if (distanceMeters(cell.center, p.position) > heatNeighbourMeters) {
            continue;
          }
          cell.add(p, now);
        }
      }
    }
  });
  return [for (final e in cells.values) e.$1];
}

/// Merkt sich das Raster der letzten Punktliste: Die Karte baut bei jeder Bewegung neu, die
/// Punkte ändern sich nur mit einer neuen Abfrage oder beim Umschalten der Ebene.
class HeatCache {
  List<AlertPoint>? _source;
  bool? _on;
  DateTime? _day;
  List<AlertPoint> _heat = const [];
  List<HeatCell> _cells = const [];

  List<HeatCell> cellsFor(
    List<AlertPoint> points,
    Set<MapLayer> layers,
    DateTime now,
  ) {
    _update(points, layers, now);
    return _cells;
  }

  /// Die Punkte der Wärme-Ebene ([heatPoints]) zur selben Liste.
  List<AlertPoint> pointsFor(
    List<AlertPoint> points,
    Set<MapLayer> layers,
    DateTime now,
  ) {
    _update(points, layers, now);
    return _heat;
  }

  void _update(List<AlertPoint> points, Set<MapLayer> layers, DateTime now) {
    final on = layers.contains(MapLayer.mobile);
    final day = DateTime(now.year, now.month, now.day);
    if (!identical(points, _source) || on != _on || day != _day) {
      _source = points;
      _on = on;
      _day = day;
      _heat = heatPoints(points, layers);
      _cells = heatCells(_heat, now);
    }
  }
}
