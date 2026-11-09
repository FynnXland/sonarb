import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/contracts/data_source_plugin.dart';
import 'package:sonarb/core/contracts/fixed_point_source.dart';
import 'package:sonarb/core/contracts/hotspot_repository.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/core/model/road_limit.dart';

AlertPoint osmPoint(
  String n,
  double lat,
  double lon, {
  AlertKind kind = AlertKind.speedCamera,
}) => AlertPoint(
  id: 'osm:node/$n',
  kind: kind,
  position: GeoPoint(lat, lon),
  source: 'osm',
);

AlertPoint pluginPoint(
  String pluginId,
  String n,
  double lat,
  double lon, {
  AlertKind kind = AlertKind.live,
}) => AlertPoint(
  id: 'plugin:$pluginId:$n',
  kind: kind,
  position: GeoPoint(lat, lon),
  source: pluginId,
);

class FakeOsm implements FixedPointSource {
  int loads = 0;
  final List<GeoBounds> areas = [];
  SourceResult result = const SourceResult(points: []);
  Object? throwOnLoad;

  /// Solange gesetzt, hängen Ladevorgänge an diesem Completer.
  Completer<SourceResult>? gate;

  @override
  Future<SourceResult> load(GeoBounds area) {
    loads++;
    areas.add(area);
    if (throwOnLoad != null) return Future.error(throwOnLoad!);
    return gate?.future ?? Future.value(result);
  }

  int cameraLoads = 0;
  final List<GeoBounds> cameraAreas = [];
  SourceResult cameraResult = const SourceResult(points: []);

  /// Solange gesetzt, hängen Übersichts-Abfragen an diesem Completer.
  Completer<SourceResult>? cameraGate;

  @override
  Future<SourceResult> loadCameras(GeoBounds area) {
    cameraLoads++;
    cameraAreas.add(area);
    return cameraGate?.future ?? Future.value(cameraResult);
  }

  @override
  Future<int?> speedLimitAt(GeoPoint position, double? headingDeg) async => 50;

  @override
  Future<RoadLimit> roadLimitAt(GeoPoint position, double? headingDeg) async =>
      const RoadLimit.kmh(50);

  @override
  Future<List<GeoPoint>?> roadAheadAt(
    GeoPoint position,
    double headingDeg,
  ) async => null;

  List<GeoBounds> loadedTiles = const [];
  final loadedQueries = <GeoBounds>[];

  @override
  List<GeoBounds> loadedCameraTilesIn(GeoBounds view) {
    loadedQueries.add(view);
    return loadedTiles;
  }

  @override
  Future<void> clearCache() async {}

  @override
  Future<int> cacheSizeBytes() async => 0;
}

class FakeHotspots extends Fake implements HotspotRepository {
  FakeHotspots([List<Hotspot> initial = const []]) : _list = initial;

  List<Hotspot> _list;
  final _ctrl = StreamController<List<Hotspot>>.broadcast();

  void set(List<Hotspot> list) {
    _list = list;
    _ctrl.add(list);
  }

  @override
  Stream<List<Hotspot>> watch() {
    final out = StreamController<List<Hotspot>>();
    StreamSubscription<List<Hotspot>>? sub;
    out.onListen = () {
      out.add(_list);
      sub = _ctrl.stream.listen(out.add);
    };
    out.onCancel = () => sub?.cancel();
    return out.stream;
  }
}

class FakePlugin implements DataSourcePlugin {
  FakePlugin(
    this.id, {
    this.refreshInterval = const Duration(seconds: 30),
    this.onFetch,
  });

  @override
  final String id;
  @override
  String get displayName => 'Plugin $id';
  @override
  final Duration refreshInterval;

  Future<List<AlertPoint>> Function(GeoBounds area)? onFetch;
  Object? initializeError;
  int initializes = 0;
  int fetches = 0;
  int disposes = 0;
  GeoBounds? lastArea;

  @override
  Future<void> initialize() async {
    initializes++;
    if (initializeError != null) throw initializeError!;
  }

  @override
  Future<List<AlertPoint>> fetch(GeoBounds area) {
    fetches++;
    lastArea = area;
    return onFetch?.call(area) ?? Future.value(const []);
  }

  @override
  Future<void> dispose() async => disposes++;
}
