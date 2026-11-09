import 'foreground_monitor.dart';
import 'monitor_snapshot.dart';

export 'monitor_snapshot.dart' show MonitorSnapshot, notificationLine;

/// Hält die App während der Überwachung im Vordergrund-Status und zeigt eine kompakte,
/// laufend aktualisierte Benachrichtigung. Verdrahtet in `app/services.dart`.
abstract interface class BackgroundMonitor {
  /// Fragt bei Bedarf nach dem Benachrichtigungsrecht und startet den Dienst.
  /// Nur aufrufen, solange die App sichtbar ist (Android erlaubt den Start sonst nicht).
  Future<void> start(MonitorSnapshot snapshot);

  /// Neuer Inhalt. Gesetzt wird nur bei Änderung und höchstens einmal pro Sekunde.
  void show(MonitorSnapshot snapshot);

  Future<void> stop();

  /// Knopf „Beenden“ in der Benachrichtigung.
  Stream<void> get stopRequests;

  /// Schiebt die App in den Hintergrund.
  Future<void> leaveForeground();
}

BackgroundMonitor createBackgroundMonitor() => ForegroundTaskMonitor();
