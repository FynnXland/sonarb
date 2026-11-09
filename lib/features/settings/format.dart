import '../../core/contracts/hotspot_repository.dart';
import '../../core/geo/geo.dart';

String _two(int v) => v.toString().padLeft(2, '0');

/// 29.10.2026
String formatDate(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.day)}.${_two(l.month)}.${l.year}';
}

/// 29.10.2026, 14:03
String formatDateTime(DateTime t) {
  final l = t.toLocal();
  return '${formatDate(l)}, ${_two(l.hour)}:${_two(l.minute)}';
}

/// 52,5200 / 13,4050 (vier Stellen reichen auf etwa 10 m)
String formatCoord(GeoPoint p) =>
    '${p.lat.toStringAsFixed(4)} / ${p.lon.toStringAsFixed(4)}'.replaceAll(
      '.',
      ',',
    );

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

String hotspotKindLabel(HotspotKind k) => switch (k) {
  HotspotKind.mobileCamera => 'Mobiler Blitzer',
  HotspotKind.distanceCheck => 'Abstandsmessung',
  HotspotKind.construction => 'Baustelle',
  HotspotKind.danger => 'Gefahrenstelle',
  HotspotKind.other => 'Sonstiges',
};

/// „3 übernommen, 1 doppelt, 0 ungültig“
String formatImportResult(HotspotImportResult r) =>
    '${r.added} übernommen, ${r.skippedDuplicates} doppelt, ${r.invalid} ungültig';
