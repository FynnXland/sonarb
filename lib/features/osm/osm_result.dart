import '../../core/contracts/fixed_point_source.dart';
import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import 'osm_layer.dart';
import 'osm_tile.dart';
import 'overpass_client.dart';

/// Ergebnis für eine Kachel einer Schicht: Daten (evtl. veraltet) und ob der Abruf gescheitert ist.
class TileOutcome {
  const TileOutcome(this.data, {this.fetched = false, this.failureReason});

  final TileData? data;
  final bool fetched;
  final String? failureReason;
}

/// Eine Kachel einer Schicht im Lauf von `load`; [outcome] bleibt null, solange sie aussteht.
class TileSlot {
  TileSlot(this.layer, this.id);

  final OsmLayer layer;
  final TileId id;
  TileOutcome? outcome;
}

/// Fasst die Kacheln eines `load` zu einem `SourceResult` zusammen. Fehlt der Ausgang einer Kachel
/// (noch unterwegs), zählen die Daten aus [memory]. Meldungen: Blitzer-Lücken sind ein Fehler,
/// fehlende Ampeln und Tempolimits nur dann, wenn der Abruf scheiterte, sonst ein Hinweis.
SourceResult assembleResult(
  GeoBounds area,
  List<TileSlot> slots,
  TileData? Function(OsmLayer, TileId) memory,
) {
  final seen = <String>{};
  final points = <AlertPoint>[];
  DateTime? oldest;
  var anyFetched = false;
  final reason = <OsmLayer, String>{};
  final missing = <OsmLayer>{};
  final pending = <OsmLayer>{};
  for (final s in slots) {
    final o = s.outcome;
    final data = o?.data ?? memory(s.layer, s.id);
    if (o == null) {
      pending.add(s.layer);
    } else {
      anyFetched |= o.fetched;
      final r = o.failureReason;
      if (r != null) reason.putIfAbsent(s.layer, () => r);
    }
    if (data == null) {
      if (o != null && o.failureReason != null) missing.add(s.layer);
      continue;
    }
    if (s.layer.hasWays) continue; // Wege laufen über speedLimitAt
    // Der Stand der Daten ist der der Blitzer; Ampeln werden seltener aufgefrischt.
    if (s.layer == OsmLayer.cameras &&
        (oldest == null || data.fetchedAt.isBefore(oldest))) {
      oldest = data.fetchedAt;
    }
    for (final p in data.points) {
      if (area.contains(p.position) && seen.add(p.id)) points.add(p);
    }
  }

  String? error;
  String? notice;
  var detailsOnly = false;
  final cam =
      reason[OsmLayer.cameras] ??
      (pending.contains(OsmLayer.cameras) ? OverpassReason.silent : null);
  if (cam != null) {
    final gap =
        missing.contains(OsmLayer.cameras) ||
        pending.contains(OsmLayer.cameras);
    error = '$cam, ${gap ? 'Daten unvollständig' : 'Daten aus dem Cache'}';
  } else {
    final detail = reason[OsmLayer.signals] ?? reason[OsmLayer.limits];
    final gap =
        missing.contains(OsmLayer.signals) || missing.contains(OsmLayer.limits);
    if (detail != null) {
      detailsOnly = true;
      error =
          '$detail, '
          '${gap ? 'Ampeln und Tempolimits unvollständig' : 'Daten aus dem Cache'}';
    } else if (pending.isNotEmpty) {
      notice = 'Ampeln und Tempolimits werden nachgeladen';
    }
  }

  return SourceResult(
    points: points,
    fetchedAt: oldest,
    fromCache: !anyFetched,
    error: error,
    notice: notice,
    errorInDetailsOnly: detailsOnly,
  );
}
