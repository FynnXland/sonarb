import '../model/announcement.dart';
import 'warning_engine.dart';

export '../model/announcement.dart';

/// Einzelsignale für [AlertAudio.play]. Warnungen vor Punkten laufen über [AlertAudio.announce].
enum WarningSound {
  /// Probeton, z. B. zum Einstellen der Lautstärke.
  testTone,

  /// Über dem Tempolimit an einer Messstelle.
  overspeed,

  /// Probe des Hotspot-Signals ohne Satz (Einstellung „Nur Signalton“). Kommt auch bei Stumm,
  /// weil der Nutzer ausdrücklich tippt.
  heatSpotPreview,
}

/// Zustandsmeldungen, die die App von sich aus ansagt.
enum StatusMessage {
  /// GPS-Signal seit einigen Sekunden weg.
  gpsLost,
  gpsRestored,

  /// Blitzerdaten nicht ladbar (kein Netz, Server nicht erreichbar).
  dataUnavailable,
  dataRestored,

  /// Erster brauchbarer Fix nach dem Start der Überwachung (Standort war noch unbekannt).
  positionFound,
}

/// Tonausgabe mit Audio-Ducking: andere Apps (Musik, Navigation) werden leiser, nicht gestoppt.
/// Implementierung: `features/audio`.
abstract interface class AlertAudio {
  Future<void> init();

  /// Spielt [sound]. Ein laufendes Signal wird durch ein wichtigeres ersetzt, nie gestapelt.
  Future<void> play(WarningSound sound);

  /// Sprachansage und Piepmuster für eine neu erreichte Stufe.
  /// Bei [WarningStage.announce] zuerst die Sprache („Fester Blitzer voraus“), dann der Piep.
  Future<void> announce(WarningEvent event);

  /// Kurze Ansage zum Zustand der App, z. B. „GPS-Signal verloren“.
  Future<void> announceStatus(StatusMessage message);

  /// 0.0–1.0, relativ zur Medienlautstärke.
  Future<void> setVolume(double volume);

  bool get muted;
  Future<void> setMuted(bool muted);

  /// Sprachansagen an oder aus. Aus: nur Piepe.
  bool get voiceEnabled;
  Future<void> setVoiceEnabled(bool enabled);

  /// Einzeln abgeschaltete Sätze. Sie entfallen, der Piep bleibt.
  Set<Announcement> get silenced;
  Future<void> setSilenced(Set<Announcement> silenced);

  /// Spielt [announcement] zur Probe mit dem Piep, der danach käme. Gilt auch bei Stumm,
  /// ausgeschalteter Sprache oder abgeschaltetem Satz, weil der Nutzer ausdrücklich tippt.
  Future<void> preview(Announcement announcement);

  Future<void> dispose();
}
