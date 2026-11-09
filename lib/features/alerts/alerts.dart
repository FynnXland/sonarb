import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/contracts/alert_repository.dart';
import '../../core/contracts/data_source_plugin.dart';
import '../../core/contracts/fixed_point_source.dart';
import '../../core/contracts/hotspot_repository.dart';
import 'alert_repository_impl.dart';
import 'mobile_history.dart';

/// Einstieg Modul Alerts + Plugins. Signatur ist Vertrag mit `app/`.
///
/// [plugins] kommt aus `lib/plugins/installed_plugins.dart` (siehe docs/PLUGINS.md).
/// [dataDir]: Ordner für den eigenen Verlauf mobiler Blitzer (`mobile_history.json`); ohne Angabe
/// führt das Repository keinen (siehe docs/VERLAUF.md).
AlertRepository createAlertRepository({
  required FixedPointSource osm,
  required HotspotRepository hotspots,
  required List<DataSourcePlugin> plugins,
  required SharedPreferences prefs,
  Directory? dataDir,
}) => AlertRepositoryImpl(
  osm: osm,
  hotspots: hotspots,
  plugins: plugins,
  prefs: prefs,
  historyStore: dataDir == null ? null : FileMobileHistoryStore(dataDir),
);
