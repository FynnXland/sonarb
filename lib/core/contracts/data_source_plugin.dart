import '../geo/geo.dart';
import '../model/alert_point.dart';

/// Zustand eines Plugins für die Einstellungsseite.
enum PluginStatus { disabled, idle, loading, ok, error }

/// Optionale Zusatzdatenquelle (z. B. privater Live-Feed). Der Core funktioniert ohne Plugins.
///
/// Regeln:
/// - IDs der gelieferten Punkte beginnen mit `plugin:<id>:`; [AlertPoint.source] = [id].
/// - [fetch] wirft bei Fehlern; der Aufrufer fängt ab, ein Plugin bringt die App nie zum Absturz.
/// - Zugangsdaten bleiben im Plugin bzw. im lokalen Speicher, nie im Repository.
abstract interface class DataSourcePlugin {
  /// Stabile, kurze ID aus `[a-z0-9_-]`.
  String get id;

  /// Name in den Einstellungen.
  String get displayName;

  /// Wie oft [fetch] für denselben Bereich höchstens aufgerufen wird.
  Duration get refreshInterval;

  Future<void> initialize();

  /// Punkte im Bereich [area].
  Future<List<AlertPoint>> fetch(GeoBounds area);

  Future<void> dispose();
}
