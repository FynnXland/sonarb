import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/contracts/data_source_plugin.dart';
import '../../core/geo/geo.dart';
import '../../core/model/alert_point.dart';

/// Vorlage: holt Punkte aus einem JSON-Feed per HTTP GET.
///
/// Anfrage: `GET <baseUrl>?south=…&west=…&north=…&east=…` (optional `Authorization: Bearer <token>`).
/// Antwort:
/// ```json
/// {"points":[{"id":"a1","lat":52.5,"lon":13.4,"kind":"live","bearings":[90],"maxSpeed":50}]}
/// ```
/// `kind` ist `live` (Standard) oder `speedCamera`; `bearings` und `maxSpeed` sind optional.
/// URL und Token kommen vom Aufrufer (lokale `plugin.dart`), nie aus dem Repository.
class JsonFeedPlugin implements DataSourcePlugin {
  JsonFeedPlugin({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    this.bearerToken,
    this.refreshInterval = const Duration(seconds: 60),
    http.Client? client,
  }) : assert(RegExp(r'^[a-z0-9_-]+$').hasMatch(id), 'ID nur aus [a-z0-9_-]'),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  @override
  final String id;
  @override
  final String displayName;
  @override
  final Duration refreshInterval;

  final Uri baseUrl;
  final String? bearerToken;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<AlertPoint>> fetch(GeoBounds area) async {
    final uri = baseUrl.replace(
      queryParameters: {
        ...baseUrl.queryParameters,
        'south': '${area.south}',
        'west': '${area.west}',
        'north': '${area.north}',
        'east': '${area.east}',
      },
    );
    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (bearerToken != null && bearerToken!.isNotEmpty)
          'Authorization': 'Bearer $bearerToken',
      },
    );
    if (response.statusCode != 200) {
      throw JsonFeedException('HTTP ${response.statusCode}');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const JsonFeedException('Antwort ist kein JSON');
    }
    final list = decoded is Map ? decoded['points'] : null;
    if (list is! List) throw const JsonFeedException('Feld "points" fehlt');
    return [for (final raw in list) ?_parse(raw)];
  }

  /// Ungültige Einträge werden übersprungen, damit ein einzelner Fehler nicht den ganzen Feed kostet.
  AlertPoint? _parse(Object? raw) {
    if (raw is! Map) return null;
    final pointId = raw['id'];
    final lat = raw['lat'];
    final lon = raw['lon'];
    if (pointId == null || lat is! num || lon is! num) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    final kind = switch (raw['kind']) {
      null || 'live' => AlertKind.live,
      'speedCamera' => AlertKind.speedCamera,
      _ => null,
    };
    if (kind == null) return null;
    final bearings = raw['bearings'];
    final maxSpeed = raw['maxSpeed'];
    return AlertPoint(
      id: 'plugin:$id:$pointId',
      kind: kind,
      position: GeoPoint(lat.toDouble(), lon.toDouble()),
      source: id,
      travelBearings: bearings is List
          ? [
              for (final b in bearings)
                if (b is num) b.toDouble(),
            ]
          : const [],
      maxSpeed: maxSpeed is num ? maxSpeed.round() : null,
    );
  }

  @override
  Future<void> dispose() async {
    if (_ownsClient) _client.close();
  }
}

/// Fehler des Feeds mit kurzer, anzeigbarer Meldung.
class JsonFeedException implements Exception {
  const JsonFeedException(this.message);
  final String message;

  @override
  String toString() => message;
}
