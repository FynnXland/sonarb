import '../geo/geo.dart';
import '../model/hotspot_kind.dart';

export '../model/hotspot_kind.dart';

/// Selbst gesetzte Gefahrenstelle. Bleibt lokal auf dem Gerät.
class Hotspot {
  const Hotspot({
    required this.id,
    required this.position,
    required this.createdAt,
    this.kind = HotspotKind.mobileCamera,
    this.headingDeg,
    this.note,
    this.radiusMeters = 300,
  });

  final String id;
  final GeoPoint position;
  final DateTime createdAt;
  final HotspotKind kind;

  /// Fahrtrichtung beim Setzen. Null = gilt für alle Richtungen.
  final double? headingDeg;
  final String? note;

  /// Ab dieser Entfernung kommt das Hotspot-Signal.
  final double radiusMeters;

  Hotspot copyWith({
    GeoPoint? position,
    HotspotKind? kind,
    double? headingDeg,
    bool clearHeading = false,
    String? note,
    bool clearNote = false,
    double? radiusMeters,
  }) => Hotspot(
    id: id,
    position: position ?? this.position,
    createdAt: createdAt,
    kind: kind ?? this.kind,
    headingDeg: clearHeading ? null : (headingDeg ?? this.headingDeg),
    note: clearNote ? null : (note ?? this.note),
    radiusMeters: radiusMeters ?? this.radiusMeters,
  );
}

/// Ergebnis eines JSON-Imports.
class HotspotImportResult {
  const HotspotImportResult({
    required this.added,
    required this.skippedDuplicates,
    required this.invalid,
  });

  final int added;
  final int skippedDuplicates;
  final int invalid;
}

/// Ungültige Importdatei (kein JSON, falsches Format, unbekannte Version).
class HotspotFormatException implements Exception {
  const HotspotFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lokale Hotspot-Verwaltung. Implementierung: `features/hotspots`.
abstract interface class HotspotRepository {
  /// Aktuelle Liste, neueste zuerst. Liefert beim Abonnieren sofort den Stand.
  Stream<List<Hotspot>> watch();

  Future<List<Hotspot>> all();

  /// Ein-Tap-Erfassung: legt einen Hotspot an der Position an und gibt ihn zurück.
  Future<Hotspot> addAt(
    GeoPoint position, {
    double? headingDeg,
    HotspotKind kind = HotspotKind.mobileCamera,
  });

  Future<void> update(Hotspot hotspot);
  Future<void> remove(String id);

  /// Letzten Hotspot zurücknehmen (Rückgängig nach Ein-Tap).
  Future<void> undoLast();

  /// Alle Hotspots als JSON (Format siehe docs/HOTSPOT-FORMAT.md).
  Future<String> exportJson();

  /// Importiert und führt zusammen. Wirft [HotspotFormatException] bei ungültiger Datei.
  Future<HotspotImportResult> importJson(String json);

  /// Wartet, bis alle Änderungen gespeichert sind (z. B. wenn die App in den Hintergrund geht).
  Future<void> flush();

  /// Speichert Ausstehendes und gibt Ressourcen frei.
  Future<void> dispose();
}
