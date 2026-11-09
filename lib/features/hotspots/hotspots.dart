import 'dart:io';

import '../../core/contracts/hotspot_repository.dart';
import 'file_hotspot_repository.dart';

/// Einstieg Modul Hotspots. Signatur ist Vertrag mit `app/`.
Future<HotspotRepository> createHotspotRepository({
  required Directory dataDir,
}) => FileHotspotRepository.open(dataDir);
