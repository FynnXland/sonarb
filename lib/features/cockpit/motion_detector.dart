import '../../core/geo/geo.dart';
import '../../core/model/position_fix.dart';
import 'drive_state.dart';
import 'location_service.dart';

/// Schwellen der Fahrterkennung.
abstract final class MotionLimits {
  /// Ab hier gilt eine Messung als Fahrt. Gehen und Joggen bleiben darunter (bis etwa 12 km/h),
  /// Radfahren liegt teils darüber und zählt dann als Fahrt.
  static const driveKmh = 15.0;

  /// So viele genaue Messungen in Folge über [driveKmh] bestätigen die Fahrt. Bei 1 s Takt
  /// sind das 3 s; ein einzelner Ausreißer (Reflexion an Häuserwänden) reicht nicht.
  static const confirmFixes = 3;

  /// Darunter steht das Auto, rollt im Stau oder der Nutzer geht zu Fuß. Gehen liegt
  /// bei 4–6 km/h und muss sicher darunter bleiben, sonst endet die Fahrt nach dem Parken nie.
  static const stopKmh = 8.0;

  /// So lange ununterbrochen unter [stopKmh], dann gilt die Fahrt als beendet.
  /// Rote Ampel (1–2 min), Bahnübergang und stehender Stau (3–4 min) bleiben Fahrt;
  /// Parken endet nach 5 min. Kosten: 2 min mehr GPS im Sekundentakt nach jeder Fahrt
  /// als mit 3 min, bei rund 25 mA weniger als 1 mAh.
  static const stopAfter = Duration(minutes: 5);

  /// Wie [stopAfter], solange Bluetooth-Audio verbunden ist (Freisprechanlage, Autoradio,
  /// aber ebenso Kopfhörer). Für lange Staus und Fähren; nach dem Abschalten des Autos endet
  /// die Verbindung meist binnen Sekunden, dann gilt wieder [stopAfter].
  static const carStopAfter = Duration(minutes: 8);

  /// Prüffenster, wenn Bluetooth-Audio neu verbunden wird: Das Auto ist meist gerade
  /// gestartet, losgefahren wird in den nächsten ein, zwei Minuten.
  static const carProbeWindow = Duration(minutes: 2);

  /// Zeit für die Bestätigung mit genauem GPS. Der erste genaue Fix nach dem Umschalten
  /// braucht oft 5–20 s.
  static const probeWindow = Duration(seconds: 30);

  /// Ortswechsel zwischen Sparmessungen, der auch ohne gemeldetes Tempo auf eine Fahrt
  /// hindeutet. Deutlich über der Ungenauigkeit von WLAN- und Funkzellenortung.
  static const moveMeters = 200.0;

  /// Während der Fahrt so lange gar kein Fix (Tiefgarage, Gerät im Funkloch): zurück in
  /// den Sparmodus, statt das GPS ohne Ergebnis weiterlaufen zu lassen.
  static const noFixFallback = Duration(minutes: 5);
}

/// GPS-Prüfung im Sparmodus, falls die Netz-Ortung (WLAN, Funkzellen) nichts liefert:
/// WLAN-Scan aus, keine SIM, Funkloch, Ortung ohne Google oder ein Emulator. Dann käme im
/// Sparmodus nichts oder immer dieselbe alte Position, und eine Fahrt fiele nie auf.
///
/// Mehrverbrauch nur ohne Netz-Ortung, bei einem GPS-Empfänger um 25 mA:
/// - unter freiem Himmel alle 2 min 5–10 s bis zu fünf ruhigen Fixes, etwa 6 % Einschaltzeit;
/// - drinnen ohne Empfang alle 4 min 30 s Suche, etwa 12 %.
/// Im Mittel 1,5–3 mA, also rund 35–75 mAh am Tag (1–2 % eines üblichen Akkus).
/// Eine Fahrt fällt so nach höchstens 2 min auf, nach längerer Zeit drinnen nach höchstens 4 min.
abstract final class GpsCheck {
  /// Ohne frische Sparmessung so lange, dann prüft das GPS. Mit Netz-Ortung kommt alle 20 s
  /// eine Messung; 2 min sind sechs ausgefallene Runden.
  static const after = Duration(minutes: 2);

  /// Fand eine Prüfung keinen GPS-Empfang, verdoppelt sich die Pause bis höchstens hierhin.
  static const maxAfter = Duration(minutes: 4);

  /// So viele genaue Fixes unter [MotionLimits.stopKmh] in Folge beenden eine Prüfung vorzeitig.
  /// Ein warmes GPS braucht dafür etwa 5–10 s statt der vollen [MotionLimits.probeWindow].
  static const calmFixes = 5;

  /// Ungenauere Sparmessungen (reine Funkzelle) zählen nicht als frisch: Mit ihnen fiele eine
  /// Fahrt erst nach Kilometern auf.
  static const freshMaxAccuracyMeters = 200.0;
}

/// Entscheidet aus den Messungen, ob gefahren wird und wie oft gemessen werden soll.
/// Reine Logik ohne Uhr und Timer: Zeitpunkte kommen von außen.
///
/// Ablauf: Nach [begin] misst das GPS kurz genau ([MotionLimits.probeWindow]), damit eine
/// laufende Fahrt sofort erkannt wird. Ohne Fahrt folgt der Sparmodus. Deutet eine Sparmessung
/// auf Bewegung hin, wird wieder genau gemessen und erst nach [MotionLimits.confirmFixes]
/// schnellen Messungen auf [MotionState.driving] gewechselt. Bleibt der Sparmodus stumm,
/// prüft das GPS selbst ([GpsCheck]).
class MotionDetector {
  MotionState _motion = MotionState.unknown;
  DateTime? _probeUntil;
  int _fastFixes = 0;
  int _calmFixes = 0;
  bool _probeHadFix = false;
  DateTime? _slowSince;
  DateTime? _lastFixAt;
  GeoPoint? _anchor;

  /// Letzte frische Sparmessung bzw. Beginn des Sparmodus.
  DateTime? _freshAt;
  PositionFix? _lastEconomy;
  Duration _checkAfter = GpsCheck.after;
  bool _carLink = false;

  /// Prüfung darf nach ruhigen Fixes früh enden (nicht nach neuem Bluetooth-Audio).
  bool _probeEndsWhenCalm = true;

  MotionState get motion => _motion;

  /// Genau messen, während gefahren oder eine vermutete Fahrt geprüft wird.
  LocationMode get mode => _motion == MotionState.driving || _probeUntil != null
      ? LocationMode.precise
      : LocationMode.economy;

  /// Pause bis zur nächsten GPS-Prüfung, falls der Sparmodus stumm bleibt.
  Duration get checkAfter => _checkAfter;

  void begin(DateTime now) {
    _motion = MotionState.unknown;
    _fastFixes = 0;
    _slowSince = null;
    _lastFixAt = null;
    _anchor = null;
    _lastEconomy = null;
    _checkAfter = GpsCheck.after;
    _carLink = false;
    _probe(now);
  }

  void onFix(PositionFix fix, DateTime now) {
    _lastFixAt = now;
    final kmh = fix.speedKmh;
    if (_motion == MotionState.driving) {
      if (kmh >= MotionLimits.stopKmh) {
        _slowSince = null;
      } else if (now.difference(_slowSince ??= now) >= _stopAfter) {
        _settle(now, fix.position);
      }
      return;
    }
    if (_probeUntil != null) {
      _fastFixes = kmh >= MotionLimits.driveKmh ? _fastFixes + 1 : 0;
      if (_fastFixes >= MotionLimits.confirmFixes) {
        _motion = MotionState.driving;
        _probeUntil = null;
        _slowSince = null;
        return;
      }
      if (fix.accuracyMeters > GpsQualityLimits.poorMeters) return;
      _probeHadFix = true;
      _calmFixes = kmh < MotionLimits.stopKmh ? _calmFixes + 1 : 0;
      if (_probeEndsWhenCalm && _calmFixes >= GpsCheck.calmFixes) {
        _checkAfter = GpsCheck.after;
        _settle(now, fix.position);
      }
      return;
    }
    if (_isFresh(fix)) {
      _freshAt = now;
      _checkAfter = GpsCheck.after;
    }
    _lastEconomy = fix;
    final anchor = _anchor ??= fix.position;
    final moved = distanceMeters(anchor, fix.position);
    final farEnough =
        moved >= MotionLimits.moveMeters && moved > fix.accuracyMeters * 2;
    if (kmh >= MotionLimits.driveKmh || farEnough) _probe(now);
  }

  /// Bluetooth-Audio verbunden oder getrennt. Nur ein Hinweis, nie Beweis für eine Fahrt:
  /// Kopfhörer sehen genauso aus. Neu verbunden ohne Fahrt: länger genau prüfen.
  void onCarLink(bool connected, DateTime now) {
    final rising = connected && !_carLink;
    _carLink = connected;
    if (rising && _motion != MotionState.driving) {
      _probe(now, window: MotionLimits.carProbeWindow, endsWhenCalm: false);
    }
  }

  Duration get _stopAfter =>
      _carLink ? MotionLimits.carStopAfter : MotionLimits.stopAfter;

  /// Zeitabhängige Wechsel; etwa jede Sekunde aufrufen.
  void onTick(DateTime now) {
    final until = _probeUntil;
    if (until != null) {
      if (now.isAfter(until)) {
        // Ohne jeden Empfang (drinnen) seltener prüfen.
        _checkAfter = _probeHadFix ? GpsCheck.after : _longer(_checkAfter);
        _settle(now, null);
      }
      return;
    }
    if (_motion == MotionState.driving) {
      final last = _lastFixAt;
      if (last != null && now.difference(last) >= MotionLimits.noFixFallback) {
        _settle(now, null);
      }
      return;
    }
    final fresh = _freshAt;
    if (fresh != null && now.difference(fresh) >= _checkAfter) _probe(now);
  }

  /// Neue Messung des Anbieters: genau genug und an anderer Stelle als die vorige. Ohne
  /// Netz-Ortung wiederholt Fused die letzte Position mit neuer Zeit und wachsender
  /// Ungenauigkeit (im Emulator 5, 47, 89, dann 100 m); Zeit und Genauigkeit zählen deshalb
  /// nicht. Echte Netz-Ortung schwankt von Messung zu Messung.
  bool _isFresh(PositionFix fix) {
    if (fix.accuracyMeters > GpsCheck.freshMaxAccuracyMeters) return false;
    final last = _lastEconomy;
    return last == null || fix.position != last.position;
  }

  Duration _longer(Duration d) {
    final doubled = d * 2;
    return doubled > GpsCheck.maxAfter ? GpsCheck.maxAfter : doubled;
  }

  void _probe(
    DateTime now, {
    Duration window = MotionLimits.probeWindow,
    bool endsWhenCalm = true,
  }) {
    final until = now.add(window);
    final current = _probeUntil;
    if (current != null && current.isAfter(until)) return;
    _probeUntil = until;
    _probeEndsWhenCalm = endsWhenCalm;
    _fastFixes = 0;
    _calmFixes = 0;
    _probeHadFix = false;
  }

  /// Zurück in den Sparmodus. Bewegung wird ab [at] gemessen, sonst ab der nächsten Messung.
  void _settle(DateTime now, GeoPoint? at) {
    _motion = MotionState.stationary;
    _probeUntil = null;
    _fastFixes = 0;
    _calmFixes = 0;
    _slowSince = null;
    _anchor = at;
    _freshAt = now;
  }
}
