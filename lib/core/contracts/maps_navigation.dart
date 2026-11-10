/// Was Sonarb zuletzt aus der Navigationsmitteilung von Google Maps gelesen hat. Liegt nur im
/// Speicher, wird nie gespeichert oder gesendet.
class MapsReading {
  const MapsReading({
    this.title,
    this.text,
    this.subText,
    this.bigText,
    this.ongoing = false,
    this.category,
    this.active = true,
    required this.at,
  });

  /// Aus dem Ereignis des Android-Dienstes; unbekannte oder fehlende Felder bleiben leer.
  factory MapsReading.fromMap(Map<Object?, Object?> m) {
    String? text(String key) {
      final v = m[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final at = m['at'];
    return MapsReading(
      title: text('title'),
      text: text('text'),
      subText: text('subText'),
      bigText: text('bigText'),
      ongoing: m['ongoing'] == true,
      category: text('category'),
      active: m['active'] != false,
      at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : DateTime.now(),
    );
  }

  final String? title;
  final String? text;
  final String? subText;
  final String? bigText;
  final bool ongoing;
  final String? category;

  /// Die Mitteilung steht noch (Navigation läuft); false, wenn Maps sie entfernt hat.
  final bool active;
  final DateTime at;

  /// Die Teile mit Inhalt, ohne Wiederholung (der lange Text wiederholt oft den kurzen).
  List<String> get parts {
    final out = <String>[];
    for (final p in [title, text, bigText, subText]) {
      if (p != null && !out.contains(p)) out.add(p);
    }
    return out;
  }

  /// Steht in der Mitteilung lesbarer Text? Mit „Live Updates“ oder eigenem Layout fehlt er.
  bool get readable => parts.isNotEmpty;
}

/// Zugriff auf die Navigationsmitteilung von Google Maps (Android `NotificationListenerService`).
/// Implementierung: `features/maps_nav`.
abstract interface class MapsNavigation {
  /// Hat der Nutzer in Android den Zugriff auf Mitteilungen erlaubt?
  Future<bool> granted();

  /// Schaltet den Dienst ein oder aus. Aus bindet Android ihn nicht, er kostet dann nichts.
  Future<void> setEnabled(bool enabled);

  /// Öffnet die Systemseite für die Freigabe. False, wenn das nicht ging.
  Future<bool> openAccessSettings();

  /// Zuletzt Gelesenes seit dem Start der App, sonst null.
  Future<MapsReading?> latest();

  /// Jede Änderung der Mitteilung, auch ihr Ende (`active` false).
  Stream<MapsReading> get readings;
}
