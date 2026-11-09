import 'dart:math' as math;

/// Zoom der geneigten Fahrtansicht je Tempobereich (bis einschließlich [upToKmh]).
typedef DriveZoomBand = ({double upToKmh, double zoom});

/// Stadt nah (Straßenblock, Abzweige und eigene Spur lesbar), Autobahn etwas weiter, damit
/// der nächste Blitzer früh im Bild ist. Bei 17,25 ist ein Bildpunkt in Berlin rund 0,6 m.
const driveZoomBands = <DriveZoomBand>[
  (upToKmh: 35, zoom: 17.25),
  (upToKmh: 65, zoom: 16.75),
  (upToKmh: 100, zoom: 16.25),
  (upToKmh: double.infinity, zoom: 15.75),
];

/// So weit muss das Tempo über bzw. unter eine Grenze, bevor die Stufe wechselt. Kleine
/// Schwankungen (Ampelanfahrt, Tempomat bei 100) lassen den Zoom stehen.
const driveZoomHysteresisKmh = 8.0;

/// Je neuem Fix rückt der Zoom um diesen Anteil auf das Ziel zu: ein Stufenwechsel dauert
/// rund zehn Sekunden und wirkt wie ein ruhiges Schwenken, nicht wie ein Sprung.
const driveZoomEase = 0.25;

/// Unterhalb dieser Abweichung gilt das Ziel als erreicht.
const _settled = 0.01;

/// Zoom der Fahrtansicht nach Tempo, mit Hysterese zwischen den Stufen und sanftem Übergang.
class DriveZoom {
  int _band = -1;
  double? _zoom;

  /// Aktueller Zoom, null vor dem ersten Schritt.
  double? get current => _zoom;

  /// Stufe für [kmh] ohne Rücksicht auf die bisherige.
  static int bandFor(double kmh) {
    for (var i = 0; i < driveZoomBands.length; i++) {
      if (kmh <= driveZoomBands[i].upToKmh) return i;
    }
    return driveZoomBands.length - 1;
  }

  /// Zielzoom für [kmh]. Die Stufe wechselt erst, wenn das Tempo die Grenze um
  /// [driveZoomHysteresisKmh] überschreitet.
  double targetFor(double kmh) {
    final speed = kmh.isFinite ? math.max(0.0, kmh) : 0.0;
    if (_band < 0) {
      _band = bandFor(speed);
    } else {
      while (_band < driveZoomBands.length - 1 &&
          speed > driveZoomBands[_band].upToKmh + driveZoomHysteresisKmh) {
        _band++;
      }
      while (_band > 0 &&
          speed < driveZoomBands[_band - 1].upToKmh - driveZoomHysteresisKmh) {
        _band--;
      }
    }
    return driveZoomBands[_band].zoom;
  }

  /// Ein Schritt je neuem Fix. Beginnt bei [from] (der Zoom beim Einstieg in die Fahrtansicht),
  /// danach nähert er sich dem Ziel.
  double step(double kmh, {required double from}) {
    final target = targetFor(kmh);
    final z = _zoom ?? from;
    final next = z + (target - z) * driveZoomEase;
    _zoom = (target - next).abs() < _settled ? target : next;
    return _zoom!;
  }

  /// Direkt auf das Ziel, etwa beim Zentrieren.
  double jump(double kmh) => _zoom = targetFor(kmh);

  /// Fahrtansicht verlassen: der nächste Einstieg beginnt beim dann aktuellen Zoom.
  void reset() {
    _band = -1;
    _zoom = null;
  }
}
