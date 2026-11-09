import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import '../../core/contracts/alert_audio.dart';
import '../../core/contracts/alert_repository.dart';
import '../../core/contracts/data_source_plugin.dart';
import '../../core/contracts/warning_engine.dart';
import '../../core/geo/geo.dart';
import '../../core/model/position_fix.dart';
import '../../core/model/road_limit.dart';
import '../stats/trip_log.dart';
import 'car_link.dart';
import 'drive_state.dart';
import 'location_service.dart';
import 'motion_detector.dart';
import 'standstill_gate.dart';
import 'status_latch.dart';

/// Ab dieser Genauigkeit gilt der erste Fix als „Position gefunden“. Reicht für die Umgebung
/// und die Blitzerdaten; eine grobe Funkzellenortung (oft über 1 km) zählt noch nicht.
const double positionFoundMaxAccuracyMeters = 100;

/// Takt der Zeitregeln. Bei genauer Messung jede Sekunde (Signalverlust nach 5 s,
/// Prüffenster). Im Sparmodus zählen nur Pausen von Minuten; dort weckt ein seltener Takt
/// die App seltener.
Duration tickFor(LocationMode mode) => switch (mode) {
  LocationMode.precise => const Duration(seconds: 1),
  LocationMode.economy => const Duration(seconds: 5),
};

/// Uhr für Empfangszeit und Signalverlust, in Tests ersetzbar.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Läuft neben der Überwachung mit: Hintergrunddienst und Benachrichtigung.
/// Umsetzung und Provider in `app/services.dart`.
abstract interface class DriveCompanion {
  /// Überwachung beginnt, die App ist sichtbar. Darf nach Rechten fragen.
  Future<void> started(DriveState state);

  /// Neuer Zustand. Kommt bis zu mehrmals pro Sekunde; die Umsetzung drosselt selbst.
  void changed(DriveState state);

  /// Überwachung endet. [byUser]: Der Nutzer hat beendet; neu starten darf dann nur das
  /// nächste Öffnen der App, nie der Dienst oder die Benachrichtigung von selbst.
  Future<void> stopped({bool byUser = false});
}

/// Überwachung: GPS-Fix → Fahrterkennung → (nur bei Fahrt) Punkte, Tempolimit,
/// Warnlogik, Ton → Zustand. Gestartet von der Oberfläche, ohne Start-Knopf.
class DriveController extends Notifier<DriveState> {
  StreamSubscription<PositionFix>? _sub;
  StreamSubscription<List<SourceStatus>>? _sourcesSub;
  StreamSubscription<bool>? _carSub;
  Timer? _ticker;
  PositionFix? _pending;
  bool _processing = false;
  DriveCompanion? _companion;

  final _motion = MotionDetector();
  final _standstill = StandstillGate();
  final _fixes = StreamController<PositionFix>.broadcast();

  /// Empfangszeit des letzten Fixes, auch wenn er im Stand nicht in den Zustand ging.
  DateTime? _lastRawFixAt;
  LocationMode? _mode;
  DateTime? _preciseSince;

  /// Letzter eindeutiger Stand der OSM-Quelle (Laden zählt nicht).
  bool _dataProblem = false;

  final _dataSpeech = DataAnnouncer();
  final _gps = StatusLatch(
    raiseAfter: StatusHold.gpsLost,
    clearAfter: StatusHold.gpsBack,
  );
  final _data = StatusLatch(
    raiseAfter: StatusHold.dataLost,
    clearAfter: StatusHold.dataBack,
  );

  /// „Position gefunden“ ist für diesen Start schon angesagt. Gilt bis zum nächsten [start],
  /// also auch über Moduswechsel und GPS-Verlust hinweg (dafür gibt es gpsRestored).
  bool _positionAnnounced = false;

  /// Zählt Überwachungen; verwirft Ergebnisse, die nach [stop] noch eintreffen.
  int _session = 0;

  @override
  DriveState build() {
    ref.onDispose(() {
      unawaited(_teardown());
      unawaited(_fixes.close());
    });
    listenSelf((_, next) => _companion?.changed(next));
    return const DriveState();
  }

  /// Jeder Fix der Überwachung, ungedrosselt: bei Fahrt etwa jede Sekunde, im Sparmodus
  /// alle 20 s, im Stand auch dann, wenn [DriveState.fix] gleich bleibt. Für Abnehmer wie
  /// eine Fahrtstatistik; die Anzeige liest [DriveState.fix].
  Stream<PositionFix> get positionFixes => _fixes.stream;

  AppServices get _services => ref.read(servicesProvider);
  LocationService get _location => ref.read(locationServiceProvider);
  TripLog get _trips => ref.read(tripLogProvider);
  DateTime _now() => ref.read(clockProvider)();

  Future<void> start() async {
    if (state.phase == DrivePhase.running ||
        state.phase == DrivePhase.starting) {
      return;
    }
    final session = ++_session;
    state = const DriveState(phase: DrivePhase.starting);
    LocationAccess access;
    try {
      access = await _location.checkAccess(request: true);
    } catch (e) {
      debugPrint('Standortprüfung fehlgeschlagen: $e');
      access = LocationAccess.denied;
    }
    if (!ref.mounted || session != _session) return;
    if (access != LocationAccess.granted) {
      state = DriveState(phase: DrivePhase.blocked, access: access);
      return;
    }
    _motion.begin(_now());
    _standstill.reset();
    _lastRawFixAt = null;
    _positionAnnounced = false;
    _gps.reset();
    _data.reset();
    _dataProblem = false;
    _dataSpeech.reset();
    state = DriveState(
      phase: DrivePhase.running,
      access: LocationAccess.granted,
      googleAccuracyDeclined: _location.googleAccuracyDeclined,
    );
    _sourcesSub = _services.alerts.watchStatus().listen(
      _onSources,
      onError: (Object e) => debugPrint('Quellenstatus: $e'),
    );
    _followMode();
    _carSub = ref
        .read(carLinkProvider)
        .watch()
        .listen(
          _onCarLink,
          onError: (Object e) => debugPrint('Bluetooth-Audio: $e'),
        );

    final companion = ref.read(driveCompanionProvider);
    _companion = companion;
    try {
      await companion.started(state);
    } catch (e) {
      debugPrint('Hintergrunddienst nicht gestartet: $e');
    }
  }

  /// Nur auf ausdrücklichen Wunsch des Nutzers (Einstellungen): Googles Dialog
  /// „Standortgenauigkeit“ noch einmal zeigen. Läuft die Überwachung, sofort mit neuem Abo.
  Future<void> retryGoogleAccuracy() async {
    await _location.allowGoogleAccuracyPrompt();
    if (!ref.mounted) return;
    state = state.copyWith(googleAccuracyDeclined: false);
    if (!state.running) return;
    _mode = null;
    _followMode();
  }

  /// Beendet die Überwachung: Positions-Abo, Takt, Quellen- und Bluetooth-Beobachtung,
  /// Warnlogik und den Vordergrunddienst samt Benachrichtigung. Das Future endet, wenn der
  /// Dienst beendet ist; vor `SystemNavigator.pop()` darauf warten, sonst kann die Engine
  /// verschwinden, bevor der Dienst gestoppt ist. Neu gestartet wird erst beim nächsten Öffnen.
  Future<void> stop() {
    _session++;
    final saved = _trips.ended();
    final stopped = _teardown(byUser: true);
    _services.engine.reset();
    state = const DriveState();
    return Future.wait([stopped, saved]);
  }

  Future<void> _teardown({bool byUser = false}) {
    _sub?.cancel();
    _sub = null;
    _sourcesSub?.cancel();
    _sourcesSub = null;
    _carSub?.cancel();
    _carSub = null;
    _ticker?.cancel();
    _ticker = null;
    _pending = null;
    _mode = null;
    final companion = _companion;
    _companion = null;
    if (companion == null) return Future.value();
    return _stopCompanion(companion, byUser: byUser);
  }

  Future<void> _stopCompanion(
    DriveCompanion companion, {
    required bool byUser,
  }) async {
    try {
      await companion.stopped(byUser: byUser);
    } catch (e) {
      debugPrint('Hintergrunddienst nicht beendet: $e');
    }
  }

  /// Bestellt Positionen im Takt, den die Fahrterkennung gerade verlangt.
  void _followMode() {
    final mode = _motion.mode;
    if (mode == _mode) return;
    _mode = mode;
    debugPrint('Ortung: ${mode.name}');
    _ticker?.cancel();
    _ticker = Timer.periodic(tickFor(mode), (_) => _tick());
    // Abbestellen wirkt sofort; geolocator erlaubt danach gleich einen neuen Strom.
    _sub?.cancel();
    if (mode == LocationMode.precise) _preciseSince = _now();
    _sub = _location.fixes(mode: mode).listen(_onFix, onError: _onError);
  }

  /// Übernimmt Wechsel der Fahrterkennung in den Zustand.
  void _applyMotion() {
    final motion = _motion.motion;
    final before = state.motion;
    if (motion != before) {
      if (before == MotionState.driving) {
        unawaited(_trips.ended());
        _services.engine.reset();
        _gps.reset();
        state = state.copyWith(
          motion: motion,
          speedLimitKmh: () => null,
          noSpeedLimit: false,
          overspeed: false,
          primary: () => null,
          upcoming: const [],
          gpsLost: false,
        );
      } else {
        state = state.copyWith(motion: motion);
      }
      if (motion == MotionState.driving) _trips.started();
      if (motion == MotionState.driving && _data.active) {
        if (_dataSpeech.lost(_now())) _status(StatusMessage.dataUnavailable);
      }
    }
    _followMode();
  }

  void _onFix(PositionFix fix) {
    if (!state.running) return;
    final now = _now();
    _lastRawFixAt = now;
    _fixes.add(fix);
    if (!_positionAnnounced &&
        fix.accuracyMeters <= positionFoundMaxAccuracyMeters) {
      _positionAnnounced = true;
      // Kommt gleich eine Warnung dazu, ordnet die Tonausgabe nach Priorität: Status zuletzt.
      _status(StatusMessage.positionFound);
    }
    _motion.onFix(fix, now);
    _applyMotion();
    // Die Statistik braucht jeden Fix der Fahrt, auch die, die der Stand-Filter zurückhält.
    if (state.motion == MotionState.driving) _trips.fix(fix);
    // Im Stand ändert ein weiterer Fix nichts Sichtbares: kein neuer Zustand, keine
    // Warnlogik, kein Tempolimit-Abruf. Die Karte muss dann auch nicht neu zeichnen.
    if (!_standstill.admit(fix, now)) {
      if (state.stale) state = state.copyWith(stale: false);
      return;
    }
    if (state.motion == MotionState.driving) {
      _pending = fix;
      if (!_processing) _drain();
      return;
    }
    // Ohne Fahrt nur die Position: keine Warnlogik, kein Tempolimit-Abruf.
    state = state.copyWith(
      fix: fix,
      lastFixAt: _now(),
      stale: false,
      error: () => null,
    );
  }

  /// Verarbeitet Fixes nacheinander; kommt während der Berechnung ein neuer, zählt nur der jüngste.
  Future<void> _drain() async {
    _processing = true;
    final session = _session;
    try {
      while (_pending != null) {
        final fix = _pending!;
        _pending = null;
        await _process(fix, session);
        if (!ref.mounted || session != _session) return;
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _process(PositionFix fix, int session) async {
    final s = _services;
    final points = s.alerts.pointsAround(
      fix.position,
      withHistory: s.engine.settings.heatSpotsEnabled,
    );
    var road = const RoadLimit.unknown();
    try {
      road = await s.alerts.roadLimitAt(fix.position, fix.headingDeg);
    } catch (e) {
      debugPrint('Tempolimit nicht ermittelbar: $e');
    }
    if (!ref.mounted || session != _session) return;
    if (state.motion != MotionState.driving) return;

    final roadLimit = road.kmh;
    // Strecke voraus für Baustellen und andere Hinweise; ohne Daten die gerade Linie.
    List<GeoPoint>? ahead;
    final heading = fix.headingDeg;
    if (heading != null) {
      try {
        ahead = await s.alerts.roadAheadAt(fix.position, heading);
      } catch (e) {
        debugPrint('Strecke voraus nicht ermittelbar: $e');
      }
      if (!ref.mounted || session != _session) return;
    }
    WarningUpdate update;
    try {
      update = s.engine.update(
        fix,
        points,
        roadSpeedLimitKmh: roadLimit,
        roadAhead: ahead,
      );
    } catch (e) {
      debugPrint('Warnlogik fehlgeschlagen: $e');
      update = WarningUpdate(
        active: const [],
        sounds: const [],
        speedLimitKmh: roadLimit,
      );
    }
    _trips.context(fix, road, update);
    for (final sound in update.sounds) {
      unawaited(_play(s.audio, sound));
    }
    for (final event in update.events) {
      unawaited(_announce(s.audio, event));
    }
    state = state.copyWith(
      fix: fix,
      lastFixAt: _now(),
      speedLimitKmh: () => update.speedLimitKmh,
      // Ein Limit der Messstelle voraus geht vor; sonst zeigt das Cockpit „kein Limit“.
      noSpeedLimit: update.speedLimitKmh == null && road.none,
      overspeed: update.overspeed,
      primary: () => update.primary,
      upcoming: update.active,
      stale: false,
      error: () => null,
    );
  }

  Future<void> _play(AlertAudio audio, WarningSound sound) async {
    try {
      await audio.play(sound);
    } catch (e) {
      debugPrint('Signal $sound nicht abspielbar: $e');
    }
  }

  Future<void> _announce(AlertAudio audio, WarningEvent event) async {
    try {
      await audio.announce(event);
    } catch (e) {
      debugPrint('Ansage $event nicht abspielbar: $e');
    }
  }

  void _status(StatusMessage message) {
    final audio = _services.audio;
    unawaited(() async {
      try {
        await audio.announceStatus(message);
      } catch (e) {
        debugPrint('Statusansage $message nicht abspielbar: $e');
      }
    }());
  }

  void _onCarLink(bool connected) {
    if (!state.running) return;
    debugPrint('Bluetooth-Audio: ${connected ? 'verbunden' : 'getrennt'}');
    _motion.onCarLink(connected, _now());
    _applyMotion();
  }

  void _onError(Object error) {
    if (error is LocationAccessError) {
      _session++;
      unawaited(_trips.ended());
      unawaited(_teardown());
      _services.engine.reset();
      state = DriveState(phase: DrivePhase.blocked, access: error.access);
      return;
    }
    debugPrint('Positionsstrom: $error');
    state = state.copyWith(error: () => 'GPS meldet einen Fehler.');
  }

  void _onSources(List<SourceStatus> sources) {
    for (final s in sources) {
      if (s.id != 'osm') continue;
      if (s.status == PluginStatus.error) _dataProblem = true;
      if (s.status == PluginStatus.ok) _dataProblem = false;
    }
  }

  void _tick() {
    if (!state.running) return;
    final now = _now();
    _motion.onTick(now);
    _applyMotion();
    _checkStale(now);
    _checkConnections(now);
    final declined = _location.googleAccuracyDeclined;
    if (declined != state.googleAccuracyDeclined) {
      state = state.copyWith(googleAccuracyDeclined: declined);
    }
  }

  void _checkStale(DateTime now) {
    // Im Stand misst das GPS nur zur Prüfung; ausbleibende Fixes sind dort kein Signalverlust.
    if (_mode != LocationMode.precise ||
        state.motion == MotionState.stationary) {
      if (state.stale) state = state.copyWith(stale: false);
      return;
    }
    if (state.stale) return;
    final last = _lastRawFixAt;
    final since = _preciseSince;
    final reference = last != null && (since == null || last.isAfter(since))
        ? last
        : since;
    if (reference != null &&
        now.difference(reference) > GpsQualityLimits.stale) {
      state = state.copyWith(stale: true);
    }
  }

  /// GPS- und Datenverlust entprellt melden. Angesagt wird nur während der Fahrt.
  void _checkConnections(DateTime now) {
    final driving = state.motion == MotionState.driving;
    final gps = _gps.update(driving && state.stale, now);
    final data = _data.update(_dataProblem, now);
    if (gps == null && data == null) return;
    state = state.copyWith(gpsLost: _gps.active, dataUnavailable: _data.active);
    // Zurück im Stand: nichts ansagen, aber der nächste Ausfall darf wieder angesagt werden.
    if (data == false && !driving) _dataSpeech.restoredSilently();
    if (!driving) return;
    if (gps != null) {
      _status(gps ? StatusMessage.gpsLost : StatusMessage.gpsRestored);
    }
    if (data == true && _dataSpeech.lost(now)) {
      _status(StatusMessage.dataUnavailable);
    } else if (data == false && _dataSpeech.restored()) {
      _status(StatusMessage.dataRestored);
    }
  }
}

final driveControllerProvider = NotifierProvider<DriveController, DriveState>(
  DriveController.new,
);
