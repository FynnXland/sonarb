import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/contracts/alert_audio.dart';
import '../core/contracts/alert_repository.dart';
import '../core/contracts/warning_engine.dart';
import '../core/model/heat_spot.dart';
export '../core/model/heat_spot.dart'
    show HeatSpotAlert, heatSpotReportChoices, defaultHeatSpotReports;
import 'services.dart';

/// Vom Nutzer einstellbare Werte. Gespeichert in SharedPreferences.
class AppSettings {
  const AppSettings({
    this.announceMeters = 600,
    this.reminderEnabled = true,
    this.reminderMeters = 250,
    this.onlyWhenSpeeding = true,
    this.hotspotsEnabled = true,
    this.overspeedToleranceKmh = 3,
    this.volume = 1.0,
    this.muted = false,
    this.headingUp = true,
    this.tiltWhileDriving = true,
    this.voiceEnabled = true,
    this.silenced = const {},
    this.heatSpotAlert = HeatSpotAlert.beep,
    this.heatSpotMinReports = defaultHeatSpotReports,
    this.detailRadiusMeters = 5000,
    this.countryCameras = false,
    this.mapsNavigation = false,
    this.enforcementFeatures = true,
  });

  /// Erste Ansage mindestens so weit vorher ([WarningSettings.announceMeters]).
  final double announceMeters;

  /// Erinnerung (zwei Piepe) an oder aus, mit Mindestabstand.
  final bool reminderEnabled;
  final double reminderMeters;

  /// Erinnerung und „unmittelbar“ nur bei Überschreitung.
  final bool onlyWhenSpeeding;
  final bool hotspotsEnabled;
  final int overspeedToleranceKmh;
  final double volume;
  final bool muted;

  /// Karte in Fahrtrichtung drehen statt Norden oben.
  final bool headingUp;

  /// Bei Fahrt mit „Fahrtrichtung oben“ die Karte schräg nach vorn neigen.
  final bool tiltWhileDriving;

  /// Sprachansagen („Blitzer voraus“). Aus: nur Piepe.
  final bool voiceEnabled;

  /// Einzeln abgeschaltete Sätze; der Piep bleibt. [Announcement.heatSpot] steht nie darin,
  /// den Satz regelt [heatSpotAlert].
  final Set<Announcement> silenced;

  /// Warnung vor Blitzer-Hotspots: aus, Satz mit Signal oder nur das Signal.
  final HeatSpotAlert heatSpotAlert;

  /// Ab so vielen früheren Meldungen im Umkreis gilt eine Stelle als Hotspot, für Ton und
  /// Karte ([heatSpotReportChoices]).
  final int heatSpotMinReports;

  /// Umkreis um die Position für alle Daten ([DataScope.detailRadiusMeters]).
  final double detailRadiusMeters;

  /// Zusätzlich feste Blitzer für ganz Deutschland ([DataScope.countryCameras]).
  final bool countryCameras;

  /// Navigationsmitteilung von Google Maps mitlesen. Standard aus; braucht die Freigabe in Android.
  final bool mapsNavigation;

  /// Blitzer-Funktionen: alles, was Verkehrsüberwachung anzeigt oder meldet (Blitzer,
  /// Abstandsmessungen, Kontrollen, Blitzer-Hotspots und -Verlauf; siehe
  /// `core/model/enforcement.dart`). Aus: weder auf der Karte noch in Warnung, Ansage, Ton oder
  /// im Melden-Blatt. Tempo, Tempolimit, Baustellen und Gefahren bleiben.
  final bool enforcementFeatures;

  /// Wählbare Umkreise in Metern.
  static const detailRadiusChoices = <double>[5000, 10000, 25000, 50000];

  // Neue Schlüssel: die früheren Sekundenwerte (settings.announceSeconds) gelten nicht mehr.
  static const _kAnnounce = 'settings.announceMeters';
  static const _kReminder = 'settings.reminderEnabled';
  static const _kReminderMeters = 'settings.reminderMeters';
  static const _kOnlySpeeding = 'settings.onlyWhenSpeeding';
  static const _kHotspots = 'settings.hotspotsEnabled';
  static const _kTolerance = 'settings.overspeedToleranceKmh';
  static const _kVolume = 'settings.volume';
  static const _kMuted = 'settings.muted';
  static const _kHeadingUp = 'settings.headingUp';
  static const _kTilt = 'settings.tiltWhileDriving';
  static const _kVoice = 'settings.voiceEnabled';
  static const _kSilenced = 'settings.silencedAnnouncements';
  static const _kHeatSpot = 'settings.heatSpotAlert';
  static const _kHeatSpotReports = 'settings.heatSpotMinReports';
  static const _kDetailRadius = 'settings.detailRadiusMeters';
  static const _kCountryCameras = 'settings.countryCameras';
  static const _kMapsNavigation = 'settings.mapsNavigation';
  static const _kEnforcement = 'settings.enforcementFeatures';

  static AppSettings load(SharedPreferences p) {
    const d = AppSettings();
    return AppSettings(
      announceMeters: _clamp(
        p.getDouble(_kAnnounce) ?? d.announceMeters,
        announceChoices,
      ),
      reminderEnabled: p.getBool(_kReminder) ?? d.reminderEnabled,
      reminderMeters: _clamp(
        p.getDouble(_kReminderMeters) ?? d.reminderMeters,
        reminderChoices,
      ),
      onlyWhenSpeeding: p.getBool(_kOnlySpeeding) ?? d.onlyWhenSpeeding,
      hotspotsEnabled: p.getBool(_kHotspots) ?? d.hotspotsEnabled,
      overspeedToleranceKmh: p.getInt(_kTolerance) ?? d.overspeedToleranceKmh,
      volume: p.getDouble(_kVolume) ?? d.volume,
      muted: p.getBool(_kMuted) ?? d.muted,
      headingUp: p.getBool(_kHeadingUp) ?? d.headingUp,
      tiltWhileDriving: p.getBool(_kTilt) ?? d.tiltWhileDriving,
      voiceEnabled: p.getBool(_kVoice) ?? d.voiceEnabled,
      silenced: _decodeSilenced(p.getStringList(_kSilenced)),
      heatSpotAlert:
          HeatSpotAlert.values.asNameMap()[p.getString(_kHeatSpot)] ??
          d.heatSpotAlert,
      heatSpotMinReports: _nearestReports(p.getInt(_kHeatSpotReports)),
      detailRadiusMeters: _clamp(
        p.getDouble(_kDetailRadius) ?? d.detailRadiusMeters,
        detailRadiusChoices,
      ),
      countryCameras: p.getBool(_kCountryCameras) ?? d.countryCameras,
      mapsNavigation: p.getBool(_kMapsNavigation) ?? d.mapsNavigation,
      enforcementFeatures: p.getBool(_kEnforcement) ?? d.enforcementFeatures,
    );
  }

  Future<void> save(SharedPreferences p) async {
    await p.setDouble(_kAnnounce, announceMeters);
    await p.setBool(_kReminder, reminderEnabled);
    await p.setDouble(_kReminderMeters, reminderMeters);
    await p.setBool(_kOnlySpeeding, onlyWhenSpeeding);
    await p.setBool(_kHotspots, hotspotsEnabled);
    await p.setInt(_kTolerance, overspeedToleranceKmh);
    await p.setDouble(_kVolume, volume);
    await p.setBool(_kMuted, muted);
    await p.setBool(_kHeadingUp, headingUp);
    await p.setBool(_kTilt, tiltWhileDriving);
    await p.setBool(_kVoice, voiceEnabled);
    await p.setStringList(_kSilenced, [for (final a in silenced) a.name]);
    await p.setString(_kHeatSpot, heatSpotAlert.name);
    await p.setInt(_kHeatSpotReports, heatSpotMinReports);
    await p.setDouble(_kDetailRadius, detailRadiusMeters);
    await p.setBool(_kCountryCameras, countryCameras);
    await p.setBool(_kMapsNavigation, mapsNavigation);
    await p.setBool(_kEnforcement, enforcementFeatures);
  }

  /// Wählbare Abstände der ersten Ansage in Metern.
  static const announceChoices = <double>[
    300, 400, 500, 600, 800, 1000, 1500, 2000, 3000, 4000, 5000, //
  ];

  /// Wählbare Mindestabstände der Erinnerung in Metern.
  static const reminderChoices = <double>[
    150, 200, 250, 300, 400, 500, 700, 1000, //
  ];

  /// Gespeicherte Stufe auf die nächste wählbare, ohne Wert der Standard.
  static int _nearestReports(int? v) {
    if (v == null) return defaultHeatSpotReports;
    var best = heatSpotReportChoices.first;
    for (final c in heatSpotReportChoices) {
      if ((c - v).abs() < (best - v).abs()) best = c;
    }
    return best;
  }

  static double _clamp(double v, List<double> choices) =>
      v.clamp(choices.first, choices.last).toDouble();

  /// Unbekannte Namen (ältere oder neuere Version) werden übergangen.
  static Set<Announcement> _decodeSilenced(List<String>? names) {
    if (names == null) return const {};
    final byName = Announcement.values.asNameMap();
    return {
      for (final n in names)
        if (byName[n] case final a? when a != Announcement.heatSpot) a,
    };
  }

  /// Abgeschaltete Sätze für die Tonausgabe: der Hotspot-Satz nur bei [HeatSpotAlert.speech].
  /// Ohne Blitzer-Funktionen schweigen auch alle Sätze dazu. Deren Punkte erreichen die
  /// Warnlogik dann gar nicht erst; so bleibt es aber auch bei einem Fehler still.
  Set<Announcement> get audioSilenced => {
    ...silenced.where((a) => a != Announcement.heatSpot),
    if (heatSpotAlert != HeatSpotAlert.speech) Announcement.heatSpot,
    if (!enforcementFeatures) ...enforcementAnnouncements,
  };

  /// Sätze, die nur Blitzer und Kontrollen betreffen, dazu der Datenstatus, weil er
  /// „Blitzerdaten“ ansagt. Der Tempo-Zusatz ([Announcement.speedLimit]) gehört nicht dazu: Er
  /// kann auch hinter Baustellen und Gefahren stehen, und Blitzer erreichen die Warnlogik bei
  /// „aus“ ohnehin nicht.
  static const enforcementAnnouncements = {
    Announcement.fixedCamera,
    Announcement.redLightCamera,
    Announcement.sectionControl,
    Announcement.sectionEnd,
    Announcement.mobileCamera,
    Announcement.distanceCheck,
    Announcement.otherControls,
    Announcement.dataUnavailable,
    Announcement.dataRestored,
    Announcement.heatSpot,
  };

  /// Ladegebiet für die Datenquellen. Ohne Blitzer-Funktionen keine Blitzer für ganz Deutschland.
  DataScope get dataScope => DataScope(
    detailRadiusMeters: detailRadiusMeters,
    countryCameras: countryCameras && enforcementFeatures,
  );

  /// Überträgt die Werte auf Warnlogik, Ton und Datenquellen. Übrige Engine-Werte bleiben.
  /// Das Ladegebiet nur bei Änderung: ein neues lädt nach.
  Future<void> applyTo(AppServices s) async {
    final e = s.engine.settings;
    s.engine.settings = e.copyWith(
      hotspotsEnabled: hotspotsEnabled,
      heatSpotsEnabled:
          heatSpotAlert != HeatSpotAlert.off && enforcementFeatures,
      heatSpotMinReports: heatSpotMinReports,
      overspeedToleranceKmh: overspeedToleranceKmh,
      announceMeters: announceMeters,
      reminderEnabled: reminderEnabled,
      reminderMeters: reminderMeters,
      onlyWhenSpeeding: onlyWhenSpeeding,
    );
    await s.audio.setVolume(volume);
    await s.audio.setMuted(muted);
    await s.audio.setVoiceEnabled(voiceEnabled);
    await s.audio.setSilenced(audioSilenced);
    if (s.alerts.dataScope != dataScope) s.alerts.dataScope = dataScope;
    await s.mapsNavigation.setEnabled(mapsNavigation);
  }

  AppSettings copyWith({
    double? announceMeters,
    bool? reminderEnabled,
    double? reminderMeters,
    bool? onlyWhenSpeeding,
    bool? hotspotsEnabled,
    int? overspeedToleranceKmh,
    double? volume,
    bool? muted,
    bool? headingUp,
    bool? tiltWhileDriving,
    bool? voiceEnabled,
    Set<Announcement>? silenced,
    HeatSpotAlert? heatSpotAlert,
    int? heatSpotMinReports,
    double? detailRadiusMeters,
    bool? countryCameras,
    bool? mapsNavigation,
    bool? enforcementFeatures,
  }) => AppSettings(
    announceMeters: announceMeters ?? this.announceMeters,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderMeters: reminderMeters ?? this.reminderMeters,
    onlyWhenSpeeding: onlyWhenSpeeding ?? this.onlyWhenSpeeding,
    hotspotsEnabled: hotspotsEnabled ?? this.hotspotsEnabled,
    overspeedToleranceKmh: overspeedToleranceKmh ?? this.overspeedToleranceKmh,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    headingUp: headingUp ?? this.headingUp,
    tiltWhileDriving: tiltWhileDriving ?? this.tiltWhileDriving,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    silenced: silenced ?? this.silenced,
    heatSpotAlert: heatSpotAlert ?? this.heatSpotAlert,
    heatSpotMinReports: heatSpotMinReports ?? this.heatSpotMinReports,
    detailRadiusMeters: detailRadiusMeters ?? this.detailRadiusMeters,
    countryCameras: countryCameras ?? this.countryCameras,
    mapsNavigation: mapsNavigation ?? this.mapsNavigation,
    enforcementFeatures: enforcementFeatures ?? this.enforcementFeatures,
  );

  /// Schaltet [a] an ([on] = true) oder ab.
  AppSettings withAnnouncement(Announcement a, {required bool on}) =>
      copyWith(silenced: on ? ({...silenced}..remove(a)) : {...silenced, a});
}

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.watch(servicesProvider).prefs);

  Future<void> change(AppSettings Function(AppSettings) edit) async {
    final next = edit(state);
    state = next;
    final services = ref.read(servicesProvider);
    await next.applyTo(services);
    await next.save(services.prefs);
  }

  Future<void> toggleMuted() => change((s) => s.copyWith(muted: !s.muted));
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );
