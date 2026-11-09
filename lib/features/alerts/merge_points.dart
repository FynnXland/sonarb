import 'dart:math' as math;

import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';

/// Feste Messstellen (Blitzer, Rotlicht, Abschnittskontrolle) gelten bis zu diesem Abstand als derselbe Punkt.
const double fixedMergeMeters = 40;

/// Feste Messstellen bis zu diesem Abstand gelten ebenfalls als derselbe Punkt, wenn der Partner
/// eindeutig ist: Keine weitere Messstelle der beiden Quellen liegt in diesem Umkreis, die ebenfalls zur
/// Richtung passt. Gemessen an Hamburg und Berlin: Dieselbe Kamera liegt in zwei Quellen im Mittel 7 m,
/// in neun von zehn Fällen unter 31 m und im Einzelfall bis 97 m auseinander.
const double fixedWideMergeMeters = 100;

/// Ein Plugin-Punkt gilt bis zu diesem Abstand als derselbe feste Blitzer wie ein OSM-Punkt, wenn es
/// Hinweise darauf gibt: Die Richtungen stimmen bestätigt überein oder beide kennen dasselbe Tempolimit.
/// OSM bleibt dabei die Position (die Kamera steht dort als Symbol auf der Karte), das Plugin liefert
/// nur zusätzliche Angaben. Voraussetzung ist ein eindeutiger Partner wie bei [fixedWideMergeMeters].
const double fixedPluginMergeMeters = 200;

/// Ein Plugin-Punkt, der höchstens so weit von einer OSM-Kamera liegt und von jeder anderen OSM-Kamera
/// deutlich weiter weg (mindestens das Dreifache, mindestens 60 m), gehört zu ihr, auch wenn seine
/// Richtung bis zu [fixedNearMaxBearingDeg] abweicht. Quellen geben Richtungen unterschiedlich an
/// (Fahrtrichtung, Blickrichtung der Kamera, Straßenachse).
const double fixedNearMergeMeters = 30;

/// Größte Richtungsabweichung, die [fixedNearMergeMeters] noch übergeht. Darüber ist es die
/// Gegenrichtung und damit eine eigene Kamera.
const double fixedNearMaxBearingDeg = 150;

/// Mobile Blitzer und Live-Meldungen: Standorte schwanken stärker.
const double mobileMergeMeters = 150;

/// Mobile Blitzer bis zu diesem Abstand gelten ebenfalls als derselbe Punkt, wenn beide Quellen eine
/// Fahrtrichtung angeben, die Richtungen höchstens [mergeConfirmedBearingDeg] auseinanderliegen und der
/// Partner eindeutig ist (wie bei den festen bis [fixedWideMergeMeters]).
const double mobileWideMergeMeters = 250;

/// Richtungen gelten als bestätigt gleich, wenn sie höchstens so weit auseinanderliegen.
const double mergeConfirmedBearingDeg = 30;

/// Baustellen sind lang gestreckt, die Quellen setzen den Punkt unterschiedlich (Anfang, Mitte,
/// Ende der Strecke). Mindestabstand; er wächst mit den Radien beider Punkte bis [areaMergeMaxMeters].
const double constructionMergeMeters = 150;

/// Längster Abstand, bis zu dem zwei Baustellen wegen ihrer Radien als dieselbe Stelle gelten: Liegen
/// die Kreise beider Punkte ineinander (Abstand höchstens Summe der Radien), ist es dieselbe Strecke.
const double areaMergeMaxMeters = 1500;

/// Gefahrenmeldungen (Unfall, Stauende, Glätte): die Radien sind Warnradien, keine Ausdehnung.
/// Darum nur ein wenig mehr als der Mindestabstand.
const double hazardMergeMaxMeters = 300;

/// Haben beide Punkte Fahrtrichtungen und keine liegt innerhalb dieser Abweichung, sind es zwei Punkte.
/// Quellen geben Richtungen unterschiedlich genau an (OSM oft die Blickrichtung der Kamera, das Plugin
/// die Straßenachse): bei eindeutig derselben Kamera weichen sie in jedem vierten Fall um mehr als 45°
/// ab. Unter 90° bleibt eine Gegenrichtungs-Kamera (180°) sicher getrennt, und ein Punkt mit
/// beiden Richtungen passt nie zugleich zu beiden Gegenrichtungs-Punkten.
const double mergeBearingToleranceDeg = 75;

enum _Group { fixed, mobile, construction, hazard }

/// Ende einer Abschnittskontrolle und Höhen-, Gewichts-, Einfahrts- und Überholkontrollen
/// sind eigene Stellen und nie Dubletten einer Messstelle oder Baustelle.
const _neverMerged = {
  AlertCategory.sectionEnd,
  AlertCategory.heightControl,
  AlertCategory.weightControl,
  AlertCategory.accessControl,
  AlertCategory.noOvertaking,
};

_Group? _groupOf(AlertPoint p) {
  // Vergangene Beobachtungen sind Zählpunkte für die Häufigkeit, keine Dubletten.
  if (p.historical || p.kind == AlertKind.hotspot) return null;
  // Nach der feinen Art: Plugins liefern Stauende, Unfall usw. mit der groben Art `live` wie
  // mobile Blitzer, die dürfen nicht miteinander verschmelzen.
  final c = p.effectiveCategory;
  if (_neverMerged.contains(c) || c == AlertCategory.trafficSignal) return null;
  if (c.isMobile || c == AlertCategory.semiStationary) return _Group.mobile;
  if (c.group == CategoryGroup.camera) return _Group.fixed;
  return switch (c) {
    AlertCategory.longTermRoadworks ||
    AlertCategory.dayRoadworks ||
    AlertCategory.closure => _Group.construction,
    _ when c.group == CategoryGroup.hazard => _Group.hazard,
    _ => null,
  };
}

/// Gefahrenmeldungen verschmelzen nur mit derselben Art (Unfall mit Unfall).
bool _sameKindIfHazard(_Group g, AlertPoint a, AlertPoint b) =>
    g != _Group.hazard || a.effectiveCategory == b.effectiveCategory;

/// Abstand, bis zu dem zwei Punkte der Gruppe immer als derselbe gelten (Richtungen vorausgesetzt).
/// Baustellen und Gefahren wachsen mit den Radien der beiden Punkte; ein Punkt ohne Radius zählt 0.
double _limitOf(_Group g, AlertPoint a, AlertPoint b) {
  double reach(double cap) => math.min(
    cap,
    math.max(
      constructionMergeMeters,
      (a.radiusMeters ?? 0) + (b.radiusMeters ?? 0),
    ),
  );
  return switch (g) {
    _Group.fixed => fixedMergeMeters,
    _Group.mobile => mobileMergeMeters,
    _Group.construction => reach(areaMergeMaxMeters),
    _Group.hazard => reach(hazardMergeMaxMeters),
  };
}

/// Weiterer Abstand, bis zu dem ein eindeutiger Partner zählt; 0 = gibt es nicht.
double _wideOf(_Group g, AlertPoint a, AlertPoint b) => switch (g) {
  _Group.fixed =>
    (a.source == 'osm') != (b.source == 'osm') && _sameCamera(a, b)
        ? fixedPluginMergeMeters
        : fixedWideMergeMeters,
  _Group.mobile =>
    _directionsAgree(_bearingsOf(a), _bearingsOf(b))
        ? mobileWideMergeMeters
        : 0,
  _ => 0,
};

/// Zellen der Rasterung (Grad), groß genug für den größten Abstand der Gruppe, auch in Längenrichtung
/// bei 55° Breite: 0,006° ≈ 380 m, 0,03° ≈ 1,9 km (Baustellen bis 1,5 km).
double _cellSize(_Group g) => switch (g) {
  _Group.construction => 0.03,
  _ => 0.006,
};

/// Von wem ein Punkt stammt. Bündelt ein Plugin mehrere Anbieter, stehen sie in
/// [AlertPoint.sources]; jeder zählt dann für sich. Sonst ist es die Quelle des Punkts.
Set<String> _originsOf(AlertPoint p) =>
    p.sources.isEmpty ? {p.source} : {for (final s in p.sources) s.id};

/// Beide Punkte haben Richtungen, und mindestens zwei davon liegen höchstens [mergeConfirmedBearingDeg]
/// auseinander.
bool _directionsAgree(List<double> a, List<double> b) {
  for (final x in a) {
    for (final y in b) {
      final d = (x - y).abs() % 360;
      if (math.min(d, 360 - d) <= mergeConfirmedBearingDeg) return true;
    }
  }
  return false;
}

/// Hinweis, dass zwei feste Messstellen dieselbe Kamera meinen: bestätigt gleiche Richtung oder
/// dasselbe bekannte Tempolimit (Richtungen sind vorher schon als verträglich geprüft).
bool _sameCamera(AlertPoint a, AlertPoint b) =>
    _directionsAgree(_bearingsOf(a), _bearingsOf(b)) ||
    (a.maxSpeed != null && a.maxSpeed == b.maxSpeed);

/// Fahrtrichtungen des Punkts für den Vergleich. Eine drehbare Anlage (Detail „Ausrichtung: Drehbar“)
/// misst in jede Richtung: Ihre Richtung zählt nicht.
List<double> _bearingsOf(AlertPoint p) =>
    p.details.any((d) => d.label == 'Ausrichtung' && d.value == 'Drehbar')
    ? const []
    : p.travelBearings;

/// Kleinste Abweichung zwischen zwei Richtungslisten in Grad; 0, wenn eine leer ist.
double _bearingGap(List<double> a, List<double> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var best = 180.0;
  for (final x in a) {
    for (final y in b) {
      final d = (x - y).abs() % 360;
      best = math.min(best, math.min(d, 360 - d));
    }
  }
  return best;
}

bool _directionsCompatible(List<double> a, List<double> b) {
  if (a.isEmpty || b.isEmpty) return true;
  for (final x in a) {
    for (final y in b) {
      final d = (x - y).abs() % 360;
      if (math.min(d, 360 - d) <= mergeBearingToleranceDeg) return true;
    }
  }
  return false;
}

/// Führt Punkte verschiedener Quellen zusammen, die dieselbe Stelle meinen.
///
/// - Nur Punkte aus **verschiedenen** Quellen und derselben Gruppe (fest, mobil, Baustelle, Gefahr)
///   innerhalb des Abstands der Gruppe (bei Baustellen und Gefahren mit den Radien wachsend), deren
///   Fahrtrichtungen sich nicht widersprechen; weiter weg bei eindeutigem Partner. Je Quelle wird
///   nur der nächste Punkt aufgenommen; liegt dort ein weiterer Punkt derselben Quelle, bleibt er
///   ein eigener Punkt. Nichts wird verworfen: was nicht zusammenpasst, bleibt stehen.
/// - Den Kern liefert die verlässlichste Quelle: bei festen Messstellen, Baustellen und Gefahren `osm` vor
///   den Plugins (die Kamera steht als Symbol auf der Karte), bei mobilen Blitzern die Plugins vor `osm`
///   (sie kennen die aktuelle Stelle); sonst Reihenfolge der Eingabe. Der Kern gibt ID, Art, Kategorie
///   und Position. Richtung, [AlertPoint.maxSpeed], Bezeichnung und Radius: die erste vorhandene Angabe
///   in dieser Reihenfolge (fehlt sie beim Kern, gilt die der anderen Quelle).
/// - Details und Quellen werden vereinigt. Hat dasselbe Label verschiedene Werte, bleiben alle als
///   eigene Einträge, jeweils mit dem Namen der Quelle.
/// - Die Reihenfolge der Ausgabe folgt der Eingabe (Platz des Kerns); nicht zusammengeführte
///   Punkte bleiben unverändert.
///
/// [sourceName] liefert den Anzeigenamen einer Quelle (Plugin-Name); ohne Angabe gilt ihre ID.
List<AlertPoint> mergePoints(
  List<AlertPoint> points, {
  String Function(String sourceId)? sourceName,
}) {
  if (points.length < 2) return points;
  final multiSource = points.map((p) => p.source).toSet().length > 1;
  if (!multiSource) return points;

  final origins = [for (final p in points) _originsOf(p)];
  bool sharesOrigin(int a, int b) => origins[a].any(origins[b].contains);

  // Raster über die mergbaren Punkte, je Gruppe mit eigener Zellgröße.
  final grid = <(_Group, int, int), List<int>>{};
  (_Group, int, int) cellOf(_Group g, GeoPoint p) {
    final size = _cellSize(g);
    return (g, (p.lat / size).floor(), (p.lon / size).floor());
  }

  for (var i = 0; i < points.length; i++) {
    final g = _groupOf(points[i]);
    if (g == null) continue;
    grid.putIfAbsent(cellOf(g, points[i].position), () => []).add(i);
  }

  // Verlässlichkeit: bei festen Messstellen, Baustellen und Gefahren osm zuerst, bei mobilen Blitzern
  // zuletzt (Position und Art kommen von den Plugins); dann Eingabereihenfolge. Rang = Platz in dieser
  // Liste.
  int trust(int i) {
    final osm = points[i].source == 'osm';
    return osm == (_groupOf(points[i]) != _Group.mobile) ? 0 : 1;
  }

  final order = [for (var i = 0; i < points.length; i++) i]
    ..sort((a, b) {
      final ra = trust(a);
      final rb = trust(b);
      return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
    });
  final rank = {for (var r = 0; r < order.length; r++) order[r]: r};

  final consumed = <int>{};
  final children = <int, List<int>>{};

  // Feste Blitzer, OSM gegen Plugin: Die Paare werden nach Abstand gebildet, nächstes zuerst. So
  // bekommt jede OSM-Kamera (oft eine je Fahrtrichtung, 100 bis 150 m auseinander) die nächsten
  // Punkte jedes Anbieters, auch wenn ein Plugin mehrere Anbieter bündelt und je Kamera mehrere Punkte
  // liefert. OSM bleibt die Position, jeder Anbieter zählt je Kamera einmal.
  final pairs = <(double, int, int)>[];
  for (final j in order) {
    if (_groupOf(points[j]) != _Group.fixed || points[j].source == 'osm') {
      continue;
    }
    final (_, cy, cx) = cellOf(_Group.fixed, points[j].position);
    final near = <(int, double)>[];
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        for (final i
            in grid[(_Group.fixed, cy + dy, cx + dx)] ?? const <int>[]) {
          if (points[i].source != 'osm' || sharesOrigin(i, j)) continue;
          near.add((i, distanceMeters(points[i].position, points[j].position)));
        }
      }
    }
    for (final (i, d) in near) {
      if (d > _wideOf(_Group.fixed, points[i], points[j])) continue;
      final a = _bearingsOf(points[i]);
      final b = _bearingsOf(points[j]);
      var fits = _directionsCompatible(a, b);
      if (!fits &&
          d <= fixedNearMergeMeters &&
          _bearingGap(a, b) <= fixedNearMaxBearingDeg) {
        // Eindeutig die nächste Kamera: der Richtungsunterschied gilt als Angabeunterschied.
        fits = near.every((o) => o.$1 == i || o.$2 >= math.max(60, 3 * d));
      }
      if (fits) pairs.add((d, i, j));
    }
  }
  pairs.sort((a, b) {
    final d = a.$1.compareTo(b.$1);
    if (d != 0) return d;
    return a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3);
  });
  for (final (_, i, j) in pairs) {
    if (consumed.contains(j) ||
        (children[i] ?? const []).any((k) => sharesOrigin(k, j))) {
      continue;
    }
    (children[i] ??= []).add(j);
    consumed.add(j);
  }

  // Der Reihe nach, verlässlichste zuerst: jeder Punkt sucht unter den verlässlicheren, noch nicht
  // angehängten Punkten den nächsten Kern (andere Quelle, gleiche Gruppe, im Schwellenwert, Richtungen
  // ohne Widerspruch). Ein Kern nimmt je anderer Quelle höchstens einen Punkt auf. Wer keinen Kern
  // findet, bleibt ein eigener Punkt (und kann selbst Kern werden): nichts wird verworfen.
  for (final j in order) {
    final group = _groupOf(points[j]);
    if (group == null || consumed.contains(j)) continue;
    final o = points[j];
    final (_, cy, cx) = cellOf(group, o.position);
    (int, double)? best;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        for (final i in grid[(group, cy + dy, cx + dx)] ?? const <int>[]) {
          if (rank[i]! >= rank[j]! || consumed.contains(i)) continue;
          final core = points[i];
          if (core.source == o.source || _groupOf(core) != group) continue;
          // Feste Blitzer OSM gegen Plugin sind schon gepaart.
          if (group == _Group.fixed &&
              core.source == 'osm' &&
              o.source != 'osm') {
            continue;
          }
          if (!_sameKindIfHazard(group, core, o)) continue;
          if (!_directionsCompatible(_bearingsOf(core), _bearingsOf(o))) {
            continue;
          }
          // Je Anbieter nimmt ein Kern nur einen Punkt auf.
          if (sharesOrigin(i, j) ||
              (children[i] ?? const []).any((k) => sharesOrigin(k, j))) {
            continue;
          }
          final d = distanceMeters(core.position, o.position);
          if (d > _limitOf(group, core, o)) {
            // Weiter weg nur, wenn beide einander eindeutig zugehören.
            final wide = _wideOf(group, core, o);
            if (d > wide ||
                !_uniquePartners(
                  points,
                  sharesOrigin,
                  grid,
                  cellOf,
                  group,
                  wide,
                  i,
                  j,
                )) {
              continue;
            }
          }
          if (best == null ||
              d < best.$2 ||
              (d == best.$2 && rank[i]! < rank[best.$1]!)) {
            best = (i, d);
          }
        }
      }
    }
    if (best == null) continue;
    (children[best.$1] ??= []).add(j);
    consumed.add(j);
  }

  final name = sourceName ?? (id) => id;
  final merged = <int, AlertPoint>{
    for (final e in children.entries)
      if (e.value.isNotEmpty)
        e.key: _combine(points[e.key], [
          for (final k
              in (e.value..sort((a, b) => rank[a]!.compareTo(rank[b]!))))
            points[k],
        ], name),
  };
  return [
    for (var i = 0; i < points.length; i++)
      if (!consumed.contains(i)) merged[i] ?? points[i],
  ];
}

/// Hat keiner der beiden Punkte [i] und [j] (verschiedene Quellen, Gruppe [group]) im Umkreis von
/// [wide] Metern einen weiteren Punkt der Gruppe aus der Quelle des anderen ([sharesOrigin]), der
/// ebenfalls zu seiner Richtung passt? Dann sind sie einander eindeutig zugeordnet, auch wenn sie weiter auseinanderliegen
/// als der gewöhnliche Abstand.
bool _uniquePartners(
  List<AlertPoint> points,
  bool Function(int, int) sharesOrigin,
  Map<(_Group, int, int), List<int>> grid,
  (_Group, int, int) Function(_Group, GeoPoint) cellOf,
  _Group group,
  double wide,
  int i,
  int j,
) {
  bool competitor(int self, int partner) {
    final me = points[self];
    final (_, cy, cx) = cellOf(group, me.position);
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        for (final k in grid[(group, cy + dy, cx + dx)] ?? const <int>[]) {
          if (k == self || k == partner) continue;
          final other = points[k];
          if (!sharesOrigin(k, partner) ||
              !_directionsCompatible(_bearingsOf(me), _bearingsOf(other))) {
            continue;
          }
          if (distanceMeters(me.position, other.position) <= wide) return true;
        }
      }
    }
    return false;
  }

  return !competitor(i, j) && !competitor(j, i);
}

AlertPoint _combine(
  AlertPoint base,
  List<AlertPoint> others,
  String Function(String) sourceName,
) {
  final all = [base, ...others];
  return base.copyWith(
    category: all.map((p) => p.category).whereType<AlertCategory>().firstOrNull,
    travelBearings: all
        .map((p) => p.travelBearings)
        .firstWhere((b) => b.isNotEmpty, orElse: () => const []),
    maxSpeed: all.map((p) => p.maxSpeed).whereType<int>().firstOrNull,
    label: all.map((p) => p.label).whereType<String>().firstOrNull,
    radiusMeters: all
        .map((p) => p.radiusMeters)
        .whereType<double>()
        .firstOrNull,
    details: _mergeDetails(all, sourceName),
    sources: _mergeSources(all, sourceName),
  );
}

String _nameOf(AlertPoint p, String Function(String) sourceName) =>
    p.sources.isNotEmpty ? p.sources.first.name : sourceName(p.source);

List<PointSource> _mergeSources(
  List<AlertPoint> all,
  String Function(String) sourceName,
) {
  final out = <PointSource>[];
  for (final p in all) {
    final list = p.sources.isNotEmpty
        ? p.sources
        : [PointSource(id: p.source, name: sourceName(p.source))];
    for (final s in list) {
      if (!out.contains(s)) out.add(s);
    }
  }
  return out;
}

/// Gleiche Angaben zählen einmal; verschiedene Werte zum selben Label bleiben, jeweils mit Quelle.
List<PointDetail> _mergeDetails(
  List<AlertPoint> all,
  String Function(String) sourceName,
) {
  // Label → Wert → Quellen, in Reihenfolge des ersten Auftretens.
  final byLabel = <String, Map<String, List<String>>>{};
  for (final p in all) {
    final name = _nameOf(p, sourceName);
    for (final d in p.details) {
      final names = (byLabel[d.label] ??= {}).putIfAbsent(d.value, () => []);
      if (!names.contains(name)) names.add(name);
    }
  }
  return [
    for (final e in byLabel.entries)
      for (final v in e.value.entries)
        PointDetail(
          e.key,
          e.value.length == 1 ? v.key : '${v.key} (${v.value.join(', ')})',
        ),
  ];
}
