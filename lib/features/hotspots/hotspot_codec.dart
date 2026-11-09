import 'dart:convert';

import '../../core/contracts/hotspot_repository.dart';
import '../../core/geo/geo.dart';

/// Kennung und Version des Austauschformats (siehe docs/HOTSPOT-FORMAT.md).
const String hotspotFormatName = 'sonarb-hotspots';
const int hotspotFormatVersion = 1;

const double _defaultRadiusMeters = 300;

Map<String, dynamic> hotspotToJson(Hotspot h) => {
  'id': h.id,
  'lat': h.position.lat,
  'lon': h.position.lon,
  'kind': h.kind.name,
  'headingDeg': h.headingDeg,
  'note': h.note,
  'radiusMeters': h.radiusMeters,
  'createdAt': h.createdAt.toUtc().toIso8601String(),
};

/// Komplettes Dokument (Export und Speicherdatei haben dasselbe Format).
String encodeHotspotDocument(
  List<Hotspot> items,
  DateTime exportedAt, {
  bool pretty = false,
}) {
  final doc = {
    'format': hotspotFormatName,
    'version': hotspotFormatVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'hotspots': [for (final h in items) hotspotToJson(h)],
  };
  return (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
      .convert(doc);
}

/// Liefert die rohen Einträge eines Dokuments (Objekt mit Kopf oder reines Array).
/// Wirft [HotspotFormatException] mit kurzem deutschem Text.
List<Object?> parseHotspotDocument(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const HotspotFormatException('Die Datei enthält kein gültiges JSON.');
  }
  if (decoded is List) return decoded;
  if (decoded is! Map) {
    throw const HotspotFormatException(
      'Unbekanntes Dateiformat: erwartet wird ein Hotspot-Export.',
    );
  }
  if (decoded['format'] != hotspotFormatName) {
    throw const HotspotFormatException(
      'Falsches Dateiformat: Das ist kein Sonarb-Hotspot-Export.',
    );
  }
  final version = decoded['version'];
  if (version is! int || version < 1) {
    throw const HotspotFormatException(
      'Die Versionsangabe der Datei fehlt oder ist ungültig.',
    );
  }
  if (version > hotspotFormatVersion) {
    throw HotspotFormatException(
      'Die Datei hat Version $version, diese App versteht höchstens '
      'Version $hotspotFormatVersion. Bitte die App aktualisieren.',
    );
  }
  final list = decoded['hotspots'];
  if (list is! List) {
    throw const HotspotFormatException('Die Hotspot-Liste in der Datei fehlt.');
  }
  return list;
}

/// Einen Eintrag lesen. Null = ungültig (Koordinaten fehlen/außerhalb, unbekannte Art, falsche Typen).
/// Fehlende optionale Felder werden ersetzt, damit auch `{lat, lon}` genügt.
Hotspot? hotspotFromJson(
  Object? raw, {
  required String Function() newId,
  required DateTime now,
}) {
  if (raw is! Map) return null;

  final lat = raw['lat'];
  final lon = raw['lon'];
  if (lat is! num || lon is! num) return null;
  if (!lat.isFinite || !lon.isFinite) return null;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;

  final rawId = raw['id'];
  if (rawId != null && (rawId is! String || rawId.trim().isEmpty)) return null;

  var kind = HotspotKind.mobileCamera;
  final rawKind = raw['kind'];
  if (rawKind != null) {
    final match = HotspotKind.values.where((k) => k.name == rawKind);
    if (match.isEmpty) return null;
    kind = match.first;
  }

  double? heading;
  final rawHeading = raw['headingDeg'];
  if (rawHeading != null) {
    if (rawHeading is! num || !rawHeading.isFinite) return null;
    heading = normalizeDegrees(rawHeading.toDouble());
  }

  final rawNote = raw['note'];
  if (rawNote != null && rawNote is! String) return null;

  var radius = _defaultRadiusMeters;
  final rawRadius = raw['radiusMeters'];
  if (rawRadius != null) {
    if (rawRadius is! num || !rawRadius.isFinite || rawRadius <= 0) return null;
    radius = rawRadius.toDouble();
  }

  var createdAt = now;
  final rawCreated = raw['createdAt'];
  if (rawCreated != null) {
    final parsed = rawCreated is String ? DateTime.tryParse(rawCreated) : null;
    if (parsed == null) return null;
    createdAt = parsed;
  }

  return Hotspot(
    id: (rawId as String?) ?? newId(),
    position: GeoPoint(lat.toDouble(), lon.toDouble()),
    createdAt: createdAt,
    kind: kind,
    headingDeg: heading,
    note: rawNote as String?,
    radiusMeters: radius,
  );
}

/// Neueste zuerst; bei gleichem Zeitstempel bleibt die bisherige Reihenfolge.
List<Hotspot> sortNewestFirst(List<Hotspot> items) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final c = b.$2.createdAt.compareTo(a.$2.createdAt);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}
