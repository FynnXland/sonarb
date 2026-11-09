import 'dart:async';

import '../../core/contracts/alert_repository.dart';
import '../../core/contracts/fixed_point_source.dart';
import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';
import 'point_store.dart';

/// Lädt feste Messstellen für den sichtbaren Kartenausschnitt nach und hält sie getrennt von den
/// Punkten um die eigene Position, damit die Warnlogik davon unberührt bleibt.
///
/// [request] wird bei jeder Kartenbewegung gerufen und ist billig: erst [debounce] nach dem letzten
/// Aufruf geht eine Abfrage raus, die nicht schon von einem frischen Ausschnitt abgedeckt ist. Bis
/// [maxOverviewSpanDeg] Kantenlänge lädt die Quelle nach; darüber liest sie nur, was im Cache liegt.
///
/// Die Punkte liegen im [store] (Zellen, Speicherbudget), nicht je Ausschnitt: Was einmal geladen
/// wurde, kommt in jeder Zoomstufe zurück und verschwindet nicht, während nachgeladen wird. Die
/// gemerkten Ausschnitte dienen nur dem Ladestand.
class OverviewLoader {
  OverviewLoader({
    required this.source,
    required this.onChanged,
    required this.clock,
    this.onSettled,
    this.debounce = const Duration(milliseconds: 1500),
    this.maxViews = 16,
    this.maxAge = const Duration(minutes: 10),
    this.retryAfterError = const Duration(minutes: 1),
    PointStore? store,
  }) : store = store ?? PointStore();

  final FixedPointSource source;
  final void Function() onChanged;

  /// Nach jeder Abfrage, auch ohne neue Punkte: der Ladestand ([coverageOf]) hat sich geändert.
  final void Function()? onSettled;
  final DateTime Function() clock;
  final Duration debounce;
  final int maxViews;
  final Duration maxAge;
  final Duration retryAfterError;

  /// Alle bekannten Messstellen außerhalb der Warnlogik.
  final PointStore store;

  /// Geladene Ausschnitte, der älteste vorn.
  final List<_View> _views = [];
  Timer? _timer;
  GeoBounds? _wanted;
  bool _loading = false;
  bool _disposed = false;

  /// Bekannte Messstellen im Ausschnitt [view].
  List<AlertPoint> pointsIn(GeoBounds view) => store.pointsIn(view);

  /// Nimmt Punkte aus einer anderen Abfrage (Umgebung der Position) ins Gedächtnis auf. Ampeln
  /// gehören nicht dazu: die Übersicht zeigt feste Messstellen. Gibt zurück, ob sich etwas änderte.
  bool remember(
    GeoBounds area,
    Iterable<AlertPoint> points, {
    required bool complete,
  }) => store.ingest(
    area,
    points.where((p) => p.kind != AlertKind.trafficSignal),
    authoritative: complete,
  );

  /// Ladestand für [view]: geladen, sobald ein gemerkter Ausschnitt ihn ganz enthält und erfolgreich
  /// war; sonst lädt er, solange eine Abfrage läuft oder wartet, danach gilt der Fehlschlag.
  DataCoverage coverageOf(GeoBounds view) {
    if (!isOverviewSized(view)) {
      return const DataCoverage(CoverageState.tooWide);
    }
    _View? best;
    for (final v in _views.reversed) {
      if (v.view.containsBounds(view)) {
        best = v;
        break;
      }
    }
    if (best != null && best.ok) return DataCoverage.ready;
    if (_loading || (_timer?.isActive ?? false) || best == null) {
      return DataCoverage.loading;
    }
    return DataCoverage(
      store.pointsIn(view).isEmpty ? CoverageState.failed : CoverageState.stale,
    );
  }

  /// Vergisst die gemerkten Ausschnitte (nicht die Punkte): neue Kacheln auf der Platte werden beim
  /// nächsten [request] gelesen.
  void forget() => _views.clear();

  /// Merkt [view] vor und stößt nach [debounce] die Abfrage an, falls nötig.
  void request(GeoBounds view) {
    if (_disposed) return;
    if (_covered(view)) return;
    _wanted = view;
    _timer?.cancel();
    _timer = Timer(debounce, _run);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  bool _covered(GeoBounds view) {
    final now = clock();
    for (final v in _views) {
      final limit = v.ok ? maxAge : retryAfterError;
      if (now.difference(v.at) < limit && v.view.containsBounds(view)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _run() async {
    final view = _wanted;
    if (_disposed || view == null) return;
    // Läuft schon eine Abfrage, wird danach der zuletzt gewünschte Ausschnitt geprüft.
    if (_loading) return;
    _loading = true;
    try {
      SourceResult r;
      try {
        r = await source.loadCameras(view);
      } catch (_) {
        r = const SourceResult(points: [], error: 'Abfrage gescheitert');
      }
      if (_disposed) return;
      final ok = r.error == null;
      // Nur eine vollständige Antwort für einen Ausschnitt, der geladen werden durfte, ersetzt Zellen.
      final changed = store.ingest(
        view,
        r.points,
        authoritative: ok && isOverviewSized(view),
      );
      _views.removeWhere((v) => v.view.sameAs(view));
      _views.add(_View(view, clock(), ok));
      while (_views.length > maxViews) {
        _views.removeAt(0);
      }
      if (changed) onChanged();
    } finally {
      _loading = false;
      if (!_disposed) onSettled?.call();
    }
    final next = _wanted;
    if (!_disposed && next != null && !_covered(next)) {
      _timer?.cancel();
      _timer = Timer(debounce, _run);
    }
  }
}

/// True, wenn der Ausschnitt klein genug für eine Abfrage ist.
bool isOverviewSized(GeoBounds view) =>
    (view.north - view.south) <= maxOverviewSpanDeg &&
    (view.east - view.west) <= maxOverviewSpanDeg;

class _View {
  _View(this.view, this.at, this.ok);

  final GeoBounds view;
  final DateTime at;
  final bool ok;
}

extension on GeoBounds {
  bool containsBounds(GeoBounds o) =>
      o.south >= south && o.north <= north && o.west >= west && o.east <= east;

  bool sameAs(GeoBounds o) =>
      o.south == south && o.north == north && o.west == west && o.east == east;
}
