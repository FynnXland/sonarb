/// Entprellter Fehlerzustand: Ein Wechsel gilt erst, wenn der neue Zustand
/// eine Weile ununterbrochen anhält. So flattern Meldungen nicht, etwa bei
/// kurzen Unterführungen oder einem Netzaussetzer.
class StatusLatch {
  StatusLatch({required this.raiseAfter, required this.clearAfter});

  /// So lange muss das Problem bestehen, bis es gemeldet wird.
  final Duration raiseAfter;

  /// So lange muss es weg sein, bis die Rückkehr gemeldet wird.
  final Duration clearAfter;

  bool _active = false;
  DateTime? _since;

  bool get active => _active;

  /// Neuer Rohzustand. Gibt den neuen Wert zurück, wenn der entprellte Zustand gewechselt hat.
  bool? update(bool problem, DateTime now) {
    if (problem == _active) {
      _since = null;
      return null;
    }
    final since = _since ??= now;
    final hold = problem ? raiseAfter : clearAfter;
    if (now.difference(since) < hold) return null;
    _active = problem;
    _since = null;
    return problem;
  }

  /// Vergisst den Zustand ohne Meldung.
  void reset() {
    _active = false;
    _since = null;
  }
}

/// Regeln für die Ansagen zum Datenausfall: „wieder da“ nur nach einer gesprochenen „nicht
/// verfügbar“-Ansage, und zwischen zwei „nicht verfügbar“-Ansagen liegt mindestens
/// [StatusHold.dataPairGap]. Der Ausfall selbst (Entprellung) ist Sache des [StatusLatch].
class DataAnnouncer {
  bool _spoken = false;
  DateTime? _spokenAt;

  /// Soll jetzt „nicht verfügbar“ angesagt werden? Merkt sich die Ansage, wenn ja.
  bool lost(DateTime now) {
    if (_spoken) return false;
    final last = _spokenAt;
    if (last != null && now.difference(last) < StatusHold.dataPairGap) {
      return false;
    }
    _spoken = true;
    _spokenAt = now;
    return true;
  }

  /// Soll jetzt „wieder da“ angesagt werden? Nur nach einer gesprochenen Ansage.
  bool restored() {
    final speak = _spoken;
    _spoken = false;
    return speak;
  }

  /// Rückkehr ohne Ansage (im Stand): der nächste Ausfall darf wieder angesagt werden.
  void restoredSilently() => _spoken = false;

  void reset() {
    _spoken = false;
    _spokenAt = null;
  }
}

/// Entprellzeiten der Statusmeldungen.
abstract final class StatusHold {
  /// Zusätzlich zu den 5 s bis „stale“: Ansage nach 10 s ohne Fix.
  /// Kurze Unterführungen bleiben stumm.
  static const gpsLost = Duration(seconds: 5);

  /// Drei Sekunden mit Fixes, bevor „GPS wieder da“ angesagt wird.
  static const gpsBack = Duration(seconds: 3);

  /// Overpass braucht 25–40 s je Abfrage und pausiert bei Überlast: ein Fehlschlag ist kein Ausfall.
  /// Erst wenn zwei Minuten lang keine brauchbaren Blitzerdaten für die Position da sind, melden.
  static const dataLost = Duration(minutes: 2);

  /// „Wieder da“ erst, wenn es 20 s ununterbrochen so bleibt (und nur nach einer echten Ansage).
  static const dataBack = Duration(seconds: 20);

  /// Zwischen zwei „nicht verfügbar“-Ansagen liegen mindestens so viele Minuten, damit ein Wechselpaar
  /// aus Ausfall und Rückkehr nicht ständig wiederholt wird.
  static const dataPairGap = Duration(minutes: 5);
}
