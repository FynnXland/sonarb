import 'package:shared_preferences/shared_preferences.dart';

/// Woher geolocator die Positionen holt.
enum LocationBackend {
  /// Google Play-Dienste (Fused). Sparsam dank WLAN und Funkzellen, prüft aber bei jedem
  /// Abo die Google-Standortgenauigkeit und zeigt bei ausgeschalteter Einstellung einen Dialog.
  google,

  /// Android-Location-Manager (`forceLocationManager`): ab Android 12 der Fused-Anbieter des
  /// Systems, sonst GPS direkt. Keine Google-Prüfung, kein Dialog.
  system,
}

/// Speichert, ob der Nutzer den Google-Dialog abgelehnt hat.
abstract interface class GoogleAccuracyStore {
  Future<bool> readDeclined();
  Future<void> writeDeclined(bool declined);
}

class PrefsGoogleAccuracyStore implements GoogleAccuracyStore {
  static const _key = 'location.googleAccuracyDeclined';

  @override
  Future<bool> readDeclined() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> writeDeclined(bool declined) async =>
      (await SharedPreferences.getInstance()).setBool(_key, declined);
}

/// Entscheidet je Positions-Abo zwischen Google und dem System, sodass Googles Dialog
/// „Standortgenauigkeit“ höchstens einmal kommt.
///
/// - Pro App-Start darf nur ein Abo über Google laufen, bis Google einen Fix geliefert hat
///   (dann passen die Einstellungen, weitere Abos lösen keinen Dialog mehr aus). Moduswechsel
///   während des offenen Dialogs nehmen das System.
/// - Lehnt der Nutzer ab, gilt das dauerhaft: nur noch das System.
/// - [allowPrompt] hebt die Ablehnung auf, nur auf ausdrücklichen Wunsch des Nutzers.
class GoogleAccuracyPolicy {
  GoogleAccuracyPolicy(this._store);

  final GoogleAccuracyStore _store;
  bool _loaded = false;
  bool _declined = false;
  bool _tried = false;
  bool _confirmed = false;

  bool get declined => _declined;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _declined = await _store.readDeclined();
    } catch (_) {
      // Ohne gespeicherten Stand fragt Google höchstens einmal pro App-Start.
    }
  }

  /// Wahl für ein neues Abo.
  LocationBackend next() {
    if (_declined) return LocationBackend.system;
    if (_confirmed) return LocationBackend.google;
    if (_tried) return LocationBackend.system;
    _tried = true;
    return LocationBackend.google;
  }

  void fixFrom(LocationBackend backend) {
    if (backend == LocationBackend.google) _confirmed = true;
  }

  /// Google meldete „Standort aus“, obwohl der Standort an ist: Dialog abgelehnt.
  Future<void> declinedByUser() async {
    _declined = true;
    try {
      await _store.writeDeclined(true);
    } catch (_) {
      // Bleibt dann nur bis zum nächsten App-Start gemerkt.
    }
  }

  /// Beim nächsten Abo noch einmal über Google fragen.
  Future<void> allowPrompt() async {
    _declined = false;
    _tried = false;
    _confirmed = false;
    try {
      await _store.writeDeclined(false);
    } catch (_) {}
  }
}
