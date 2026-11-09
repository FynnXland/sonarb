import '../../core/contracts/warning_engine.dart';
import '../../core/model/position_fix.dart';
import 'location_service.dart';

enum DrivePhase {
  /// Keine Fahrt.
  idle,

  /// Berechtigung wird geprüft.
  starting,

  /// GPS läuft.
  running,

  /// Standort nicht nutzbar, Grund in [DriveState.access].
  blocked,
}

/// Selbst erkannte Bewegung, solange die Überwachung läuft ([DrivePhase.running]).
/// Es gibt keinen Start-Knopf: Die App misst sparsam, bis sie eine Fahrt erkennt.
enum MotionState {
  /// Noch zu wenig Messungen.
  unknown,

  /// Steht oder geht zu Fuß: GPS selten und mit wenig Genauigkeit, keine Warnungen.
  stationary,

  /// Fährt: GPS jede Sekunde, Warnlogik aktiv.
  driving,
}

enum GpsQuality {
  /// Noch kein Fix oder letzter Fix zu alt.
  none,

  /// Ungenauer als [GpsQualityLimits.poorMeters].
  poor,
  good,
}

abstract final class GpsQualityLimits {
  static const poorMeters = 30.0;

  /// Nach dieser Zeit ohne neuen Fix gilt das Signal als verloren.
  static const stale = Duration(seconds: 5);
}

class DriveState {
  const DriveState({
    this.phase = DrivePhase.idle,
    this.access,
    this.fix,
    this.lastFixAt,
    this.speedLimitKmh,
    this.noSpeedLimit = false,
    this.overspeed = false,
    this.primary,
    this.upcoming = const [],
    this.motion = MotionState.unknown,
    this.stale = false,
    this.gpsLost = false,
    this.dataUnavailable = false,
    this.googleAccuracyDeclined = false,
    this.error,
  });

  final DrivePhase phase;
  final LocationAccess? access;
  final PositionFix? fix;

  /// Empfangszeit (Gerätezeit) des letzten Fixes.
  final DateTime? lastFixAt;
  final int? speedLimitKmh;

  /// Ohne Zahl bekannt, dass auf dieser Straße kein Limit gilt (Autobahn). Nur zusammen mit
  /// `speedLimitKmh == null`; die Warnlogik vergleicht dann nicht mit dem Tempo.
  final bool noSpeedLimit;
  final bool overspeed;
  final ActiveWarning? primary;

  /// Alle relevanten Punkte voraus, nächster zuerst (Blitzer, Meldungen, Baustellen).
  final List<ActiveWarning> upcoming;
  final MotionState motion;

  /// Seit [GpsQualityLimits.stale] kein neuer Fix. Nur bei genauer Messung (Fahrt oder
  /// Fahrtprüfung); im Sparmodus sind lange Pausen zwischen den Fixes normal.
  final bool stale;

  /// Entprellt: GPS während der Fahrt verloren, angesagt über `AlertAudio.announceStatus`.
  final bool gpsLost;

  /// Entprellt: Blitzerdaten (OpenStreetMap) nicht ladbar.
  final bool dataUnavailable;

  /// Googles Dialog „Standortgenauigkeit“ wurde abgelehnt; geortet wird ohne Google.
  /// Für einen Hinweis in den Einstellungen, siehe `DriveController.retryGoogleAccuracy`.
  final bool googleAccuracyDeclined;

  /// Unerwarteter Fehler im Positionsstrom.
  final String? error;

  bool get running => phase == DrivePhase.running;

  bool get driving => running && motion == MotionState.driving;

  /// Fix, der für Hotspot und Karte taugt.
  PositionFix? get usableFix => running && !stale ? fix : null;

  GpsQuality get gpsQuality {
    final f = fix;
    if (!running || f == null || stale) return GpsQuality.none;
    return f.accuracyMeters > GpsQualityLimits.poorMeters
        ? GpsQuality.poor
        : GpsQuality.good;
  }

  DriveState copyWith({
    DrivePhase? phase,
    LocationAccess? access,
    PositionFix? fix,
    DateTime? lastFixAt,
    int? Function()? speedLimitKmh,
    bool? noSpeedLimit,
    bool? overspeed,
    ActiveWarning? Function()? primary,
    List<ActiveWarning>? upcoming,
    MotionState? motion,
    bool? stale,
    bool? gpsLost,
    bool? dataUnavailable,
    bool? googleAccuracyDeclined,
    String? Function()? error,
  }) => DriveState(
    phase: phase ?? this.phase,
    access: access ?? this.access,
    fix: fix ?? this.fix,
    lastFixAt: lastFixAt ?? this.lastFixAt,
    speedLimitKmh: speedLimitKmh != null ? speedLimitKmh() : this.speedLimitKmh,
    noSpeedLimit: noSpeedLimit ?? this.noSpeedLimit,
    overspeed: overspeed ?? this.overspeed,
    primary: primary != null ? primary() : this.primary,
    upcoming: upcoming ?? this.upcoming,
    motion: motion ?? this.motion,
    stale: stale ?? this.stale,
    gpsLost: gpsLost ?? this.gpsLost,
    dataUnavailable: dataUnavailable ?? this.dataUnavailable,
    googleAccuracyDeclined:
        googleAccuracyDeclined ?? this.googleAccuracyDeclined,
    error: error != null ? error() : this.error,
  );
}
