import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'background.dart';
import 'notification_pacer.dart';

const _serviceId = 4107;

/// Höchstens so oft wird die Benachrichtigung neu gesetzt. Jedes Setzen kostet eine
/// Runde durch Systemdienst und Statusleiste; bei Fahrt änderte sich das Tempo sonst jede
/// Sekunde. Das genaue Tempo zeigt das Cockpit, die Leiste nur den groben Stand.
const notificationMinGap = Duration(seconds: 2);
const _stopButtonId = 'stop';
const _stopMessage = 'sonarb:stop';

/// Monochromes Symbol für die Statusleiste, im Manifest als meta-data hinterlegt.
const _iconMetaData = 'de.fynn.handy.sonarb.NOTIFICATION_ICON';

/// Einstieg des Dienst-Isolats. Es tut nichts außer den Knopf „Beenden“ weiterzugeben.
@pragma('vm:entry-point')
void sonarbMonitorTask() {
  FlutterForegroundTask.setTaskHandler(_MonitorTaskHandler());
}

class _MonitorTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id != _stopButtonId) return;
    FlutterForegroundTask.sendDataToMain(_stopMessage);
    // Läuft die App selbst nicht mehr, beendet sich der Dienst hier.
    FlutterForegroundTask.stopService();
  }
}

/// Vordergrunddienst vom Typ location über flutter_foreground_task. Der Standort wird
/// weiter in der App gemessen; der Dienst hält sie nur im Vordergrund-Status, damit
/// Android die Messungen im Hintergrund nicht drosselt.
class ForegroundTaskMonitor implements BackgroundMonitor {
  ForegroundTaskMonitor() {
    _pacer = NotificationPacer(_update, minGap: notificationMinGap);
  }

  late final NotificationPacer _pacer;
  final _stops = StreamController<void>.broadcast();
  bool _initialized = false;
  bool _running = false;
  String? _latest;

  /// Start und Stopp nacheinander, auch wenn sie schnell aufeinander folgen.
  Future<void> _queue = Future.value();

  @override
  Stream<void> get stopRequests => _stops.stream;

  @override
  Future<void> start(MonitorSnapshot snapshot) {
    _latest = notificationLine(snapshot);
    return _serial(_start);
  }

  @override
  Future<void> stop() {
    _latest = null;
    return _serial(_stop);
  }

  @override
  void show(MonitorSnapshot snapshot) {
    final text = notificationLine(snapshot);
    _latest = text;
    if (_running) _pacer.submit(text);
  }

  @override
  Future<void> leaveForeground() async {
    try {
      FlutterForegroundTask.minimizeApp();
    } catch (e) {
      debugPrint('App nicht in den Hintergrund gelegt: $e');
    }
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _queue.then((_) => action()).catchError((Object e) {
      debugPrint('Hintergrunddienst: $e');
    });
    _queue = next;
    return next;
  }

  void _setUp() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'monitor',
        channelName: 'Überwachung',
        channelDescription:
            'Tempo und nächste Warnung, solange Sonarb im Hintergrund läuft.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // Kein Dauer-Wakelock: Im Stand soll die CPU schlafen dürfen. Während der Fahrt
        // weckt das GPS das Gerät ohnehin jede Sekunde.
        allowWakeLock: false,
        allowAutoRestart: false,
      ),
    );
  }

  Future<void> _start() async {
    final text = _latest;
    if (text == null) return;
    _setUp();
    await _askForNotifications();
    if (_latest == null) return;
    final ServiceRequestResult result;
    if (await FlutterForegroundTask.isRunningService) {
      result = await FlutterForegroundTask.updateService(
        notificationTitle: text,
        notificationText: '',
      );
    } else {
      result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: const [ForegroundServiceTypes.location],
        notificationTitle: text,
        notificationText: '',
        notificationIcon: const NotificationIcon(metaDataName: _iconMetaData),
        notificationButtons: const [
          NotificationButton(id: _stopButtonId, text: 'Beenden'),
        ],
        callback: sonarbMonitorTask,
      );
    }
    if (result case ServiceRequestFailure(:final error)) {
      debugPrint('Vordergrunddienst nicht gestartet: $error');
      return;
    }
    _running = true;
    _pacer.reset(sent: text);
    final latest = _latest;
    if (latest != null) _pacer.submit(latest);
  }

  Future<void> _stop() async {
    _running = false;
    _pacer.reset();
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }

  /// Android 13+: ohne dieses Recht läuft der Dienst trotzdem, nur unsichtbar.
  Future<void> _askForNotifications() async {
    final now = await FlutterForegroundTask.checkNotificationPermission();
    if (now == NotificationPermission.granted) return;
    await FlutterForegroundTask.requestNotificationPermission();
  }

  void _update(String text) {
    unawaited(
      FlutterForegroundTask.updateService(notificationTitle: text).then<void>(
        (_) {},
        onError: (Object e) {
          debugPrint('Benachrichtigung nicht aktualisiert: $e');
        },
      ),
    );
  }

  void _onTaskData(Object data) {
    if (data == _stopMessage) _stops.add(null);
  }
}
