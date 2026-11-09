part of 'osm_source.dart';

/// So weit voraus (Meter) liegt mindestens die Zelle, die beim Fahren als Nächstes gebraucht wird.
const double roadLookAheadMeters = 3500;

/// Bei schneller Fahrt: so viele Sekunden voraus (eine Abfrage dauert 25–40 s, mit Warteschlange mehr).
const double roadLookAheadSeconds = 150;
const double roadLookAheadMaxMeters = 8000;

/// Blitzer-Kacheln werden bei Fahrt so weit voraus geholt, wie man in dieser Zeit kommt, mindestens
/// [cameraLookAheadMinMeters], höchstens [cameraLookAheadMaxMeters]. Eine Kachel braucht 30–40 s, bei
/// Überlast Minuten; so ist die nächste da, bevor das 3-km-Fenster der Warnlogik sie berührt.
const double cameraLookAheadSeconds = 240;
const double cameraLookAheadMinMeters = 6000;
const double cameraLookAheadMaxMeters = 16000;

/// Unter diesem Tempo (m/s, rund 18 km/h) lohnt kein Vorausladen: das Fenster der Position reicht.
const double cameraAheadMinSpeed = 5;

/// Abstand der Stichproben entlang des Wegs voraus, kleiner als eine Zelle (3,4–5,5 km).
const double _sampleMeters = 1500;

/// Schätzt Tempo und Kurs aus den Aufrufen von `speedLimitAt` und entscheidet mit Hysterese, ob
/// man schnell fährt (Landstraße, Autobahn). Schnell: ab 65 km/h, wenn das 8 s lang so bleibt;
/// wieder langsam: unter 50 km/h, 8 s lang. Ein kurzer Ausreißer kippt es nicht; die Fahrterkennung
/// (15 und 8 km/h) ist davon unabhängig, hier geht es nur um die Schicht der Nebenstraßen.
class _Motion {
  static const double fastMps = 65 / 3.6;
  static const double slowMps = 50 / 3.6;
  static const Duration hold = Duration(seconds: 8);

  GeoPoint? _pos;
  DateTime? _at;
  DateTime? _flipSince;

  /// Geglättetes Tempo in m/s, null solange unbekannt.
  double? speed;
  double? heading;
  DateTime? _headingAt;
  bool fast = false;

  void update(GeoPoint p, double? h, DateTime now) {
    if (h != null) {
      heading = h;
      _headingAt = now;
    }
    final last = _pos, at = _at;
    if (last == null || at == null) {
      _pos = p;
      _at = now;
      return;
    }
    final dt = now.difference(at).inMilliseconds / 1000;
    // Zu kurz für ein Tempo: weiter vom alten Punkt aus messen.
    if (dt < 0.5) return;
    _pos = p;
    _at = now;
    if (dt > 15) {
      speed = null; // Lücke (Tunnel, Pause): Zustand bleibt, Tempo neu messen
      _flipSince = null;
      return;
    }
    final v = distanceMeters(last, p) / dt;
    speed = speed == null ? v : 0.7 * speed! + 0.3 * v;
    final wantsFlip = fast ? speed! < slowMps : speed! > fastMps;
    if (!wantsFlip) {
      _flipSince = null;
    } else {
      _flipSince ??= now;
      if (now.difference(_flipSince!) >= hold) {
        fast = !fast;
        _flipSince = null;
      }
    }
  }

  /// Kurs, wenn er nicht älter als 15 s ist.
  double? headingAt(DateTime now) {
    final t = _headingAt;
    return t != null && now.difference(t).inSeconds <= 15 ? heading : null;
  }
}

/// Hält das letzte Limit über kurze Lücken: eine Kreuzung, ein Abschnitt ohne `maxspeed`, ein
/// Knick im Weg. Nur auf demselben Kurs (höchstens 35° Abweichung), höchstens 150 m und 15 s
/// weit. Danach „unbekannt“: ein falscher Wert ist schlimmer als keiner.
class _LimitHold {
  static const double maxMeters = 150;
  static const Duration maxAge = Duration(seconds: 15);
  static const double maxTurnDeg = 35;

  int? _limit;
  GeoPoint? _pos;
  double? _heading;
  DateTime? _at;

  int? resolve(int? picked, GeoPoint p, double? heading, DateTime now) {
    if (picked != null) {
      _limit = picked;
      _pos = p;
      _heading = heading;
      _at = now;
      return picked;
    }
    final limit = _limit, pos = _pos, at = _at;
    if (limit == null || pos == null || at == null) return null;
    final turned =
        heading != null &&
        _heading != null &&
        angleDifference(heading, _heading!) > maxTurnDeg;
    if (now.difference(at) > maxAge ||
        distanceMeters(pos, p) > maxMeters ||
        turned) {
      _limit = null;
      return null;
    }
    return limit;
  }
}

extension _RoadCells on OsmSource {
  /// Liegt die Zelle dieser Tempolimit-Schicht ganz im Gebiet eines installierten Pakets?
  bool _packaged(TileSlot s) => s.layer.hasWays && packages.isComplete(s.id);

  /// Alle Tempolimit-Wege rund um die Position: aus dem Overpass-Speicher (eigene Kachel und die
  /// Nachbarn im Umkreis von rund 60 m, Wege über die Kachelkante) und aus den Paketen.
  Future<List<SpeedWay>> _waysAround(GeoPoint position) async {
    const d = 0.0006;
    final ids = <TileId>{
      for (final dLat in const [-d, 0.0, d])
        for (final dLon in const [-d, 0.0, d])
          TileId.of(
            position.lat + dLat,
            position.lon + dLon,
            OsmLayer.limits.perDegree,
          ),
    };
    final ways = <SpeedWay>[];
    for (final layer in OsmLayer.values.where((l) => l.hasWays)) {
      for (final id in ids) {
        final key = _key(layer, id);
        final tile = _memory[key];
        if (tile == null) continue;
        ways.addAll(tile.ways);
        _remember(key, tile); // in Benutzung
      }
    }
    await packages.ready;
    if (!packages.isEmpty) {
      // Schnell nur Hauptstraßen, wie bei den Overpass-Schichten.
      final fromPackages = await packages.around(ids, withMinor: !_motion.fast);
      ways.addAll([for (final w in fromPackages) w.way]);
    }
    return ways;
  }

  /// Linie voraus aus den Tempolimit-Wegen unter der Position und entlang des Kurses (Speicher
  /// und Pakete), ohne Netz. Fehler: null, die Warnlogik nimmt dann die gerade Linie.
  Future<List<GeoPoint>?> _roadAhead(GeoPoint position, double heading) async {
    try {
      final ids = {
        ..._corridor(position, heading, roadAheadMeters),
        for (final b in const [-90.0, 90.0])
          TileId.of(
            destinationPoint(position, heading + b, 100).lat,
            destinationPoint(position, heading + b, 100).lon,
            fineTilesPerDegree,
          ),
      };
      final ways = <SpeedWay>[];
      for (final layer in OsmLayer.values.where((l) => l.hasWays)) {
        for (final id in ids) {
          final tile = _memory[_key(layer, id)];
          if (tile != null) ways.addAll(tile.ways);
        }
      }
      await packages.ready;
      if (!packages.isEmpty) {
        final fromPackages = await packages.around(
          ids,
          withMinor: !_motion.fast,
        );
        ways.addAll([for (final w in fromPackages) w.way]);
      }
      return roadAhead(ways, position, heading);
    } catch (_) {
      return null;
    }
  }

  /// Ampeln und Tempolimits in der Reihenfolge der Warteschlange (Schicht, dann Abstand): die erste
  /// Anfrage läuft sofort, und das soll die Zelle unter der Position sein.
  List<TileSlot> _detailOrder(List<TileSlot> slots, GeoPoint center) =>
      [
        for (final s in slots)
          if (s.layer != OsmLayer.cameras) s,
      ]..sort((a, b) {
        final p = a.layer.priority.compareTo(b.layer.priority);
        return p != 0
            ? p
            : a.id.distanceTo(center).compareTo(b.id.distanceTo(center));
      });

  /// Wie weit voraus gebraucht wird: bei Autobahntempo 150 s, mindestens 3,5 km.
  double _lookAhead() {
    final v = _motion.speed;
    if (!_motion.fast || v == null) return roadLookAheadMeters;
    return (v * roadLookAheadSeconds).clamp(
      roadLookAheadMeters,
      roadLookAheadMaxMeters,
    );
  }

  /// Zellen der Tempolimit-Schicht unter [from] und entlang des Kurses bis [lookAhead] Meter voraus.
  /// Ohne Kurs nur die eigene Zelle.
  Set<TileId> _corridor(
    GeoPoint from,
    double? heading,
    double lookAhead, {
    int perDegree = fineTilesPerDegree,
  }) {
    final cells = {TileId.of(from.lat, from.lon, perDegree)};
    if (heading == null) return cells;
    for (
      var d = _sampleMeters;
      d < lookAhead + _sampleMeters;
      d += _sampleMeters
    ) {
      final p = destinationPoint(from, heading, d > lookAhead ? lookAhead : d);
      cells.add(TileId.of(p.lat, p.lon, perDegree));
    }
    return cells;
  }

  /// Bei schneller Fahrt: keine Nebenstraßen und Ampeln, Tempolimit-Zellen nur entlang des Kurses
  /// (Seitenzellen erst, wenn man abbiegt). Langsam oder unbekannt: alles.
  List<TileSlot> _forMotion(List<TileSlot> slots, GeoPoint center) {
    if (!_motion.fast) return slots;
    final keep = _corridor(center, _motion.headingAt(_now()), _lookAhead());
    return [
      for (final s in slots)
        if (s.layer == OsmLayer.cameras ||
            (s.layer == OsmLayer.limits && keep.contains(s.id)))
          s,
    ];
  }

  /// Sorgt dafür, dass die Tempolimit-Zellen unter der Position und voraus geladen sind, mit der
  /// höchsten Dringlichkeit der Warteschlange (Abstand 0). Schnell nur die Hauptstraßen.
  Future<void> _ensureRoadCells(GeoPoint position) async {
    _inBackground(_ensureCameraCells(position));
    try {
      await packages.ready;
      final now = _now();
      final ids = _corridor(position, _motion.headingAt(now), _lookAhead());
      final layers = _motion.fast
          ? const [OsmLayer.limits]
          : const [OsmLayer.limits, OsmLayer.minorLimits];
      for (final id in ids) {
        if (packages.isComplete(id)) continue; // das Paket kennt die Zelle
        for (final layer in layers) {
          await _warm(TileSlot(layer, id));
          // Frisch oder nach einem Fehlschlag in Pause: nichts zu tun. Sonst anfordern.
          if (_runningFor(layer, id) != null ||
              _readyOutcome(layer, id) != null) {
            continue;
          }
          unawaited(_obtain(layer, id, 0));
        }
      }
    } catch (_) {}
  }

  /// Holt bei Fahrt die Blitzer-Kacheln entlang des Kurses vor, die noch fehlen: die Kacheln
  /// der nächsten [cameraLookAheadSeconds] Sekunden (nach Tempo, mindestens 6 km). Mit der Dringlichkeit
  /// der Blitzer, nach dem Abstand geordnet: die nächste Kachel zuerst. Frische Kacheln und solche in
  /// der Pause nach einem Fehlschlag gibt es nicht noch einmal; liegt eine im Speicher oder Cache,
  /// kostet ein späteres `load` für sie keine Anfrage mehr.
  Future<void> _ensureCameraCells(GeoPoint position) async {
    try {
      final now = _now();
      final v = _motion.speed, heading = _motion.headingAt(now);
      if (v == null || heading == null || v < cameraAheadMinSpeed) return;
      final ahead = (v * cameraLookAheadSeconds).clamp(
        cameraLookAheadMinMeters,
        cameraLookAheadMaxMeters,
      );
      final ids = _corridor(
        position,
        heading,
        ahead,
        perDegree: OsmLayer.cameras.perDegree,
      );
      for (final id in ids) {
        await _warm(TileSlot(OsmLayer.cameras, id));
        if (_runningFor(OsmLayer.cameras, id) != null ||
            _readyOutcome(OsmLayer.cameras, id) != null) {
          continue;
        }
        unawaited(_obtain(OsmLayer.cameras, id, id.distanceTo(position)));
      }
    } catch (_) {}
  }
}
