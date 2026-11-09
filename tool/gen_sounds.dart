// Synthetisiert die Piepmuster als 16-bit-PCM-Mono-WAV (44,1 kHz).
// Aufruf: dart run tool/gen_sounds.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 44100;

/// Höchster Spitzenpegel: -1 dBFS.
final double peakLimit = math.pow(10, -1 / 20).toDouble();

/// Ziel-Lautheit: RMS des lautesten 50-ms-Fensters bei -8 dBFS. Gleiche Werte für alle
/// Signale, damit kein Muster lauter wirkt als das andere.
final double loudnessTarget = math.pow(10, -8 / 20).toDouble();
const double loudnessWindow = 0.05;

/// Ein Teilton eines Klangs: Vielfaches der Grundfrequenz, Pegel, Abklingzeit-Faktor.
class Partial {
  const Partial(this.ratio, this.gain, [this.decayScale = 1]);
  final double ratio;
  final double gain;
  final double decayScale;
}

/// Ein Ton im Signal.
class Tone {
  const Tone({
    required this.start,
    required this.length,
    required this.freq,
    required this.partials,
    this.decay = 0.12,
    this.gain = 1,
  });

  /// Beginn und Dauer in Sekunden.
  final double start;
  final double length;
  final double freq;
  final List<Partial> partials;

  /// Zeitkonstante des exponentiellen Abklingens in Sekunden.
  final double decay;
  final double gain;
}

/// Beschreibung eines Signals: Gesamtdauer plus Töne.
class SoundSpec {
  const SoundSpec(this.name, this.duration, this.tones);
  final String name;
  final double duration;
  final List<Tone> tones;
}

// Fast reiner Sinus mit leichtem Oberton: weich, aber auf Handylautsprechern gut hörbar.
const _soft = [Partial(1, 1), Partial(2, 0.12, 0.6), Partial(3, 0.03, 0.4)];

// Glockenartig, länger ausklingend.
const _bell = [Partial(1, 1), Partial(2, 0.2, 0.7), Partial(3, 0.06, 0.5)];

// Tiefe Töne tragen auf Handylautsprechern schlecht, daher kräftigere Obertöne.
const _low = [
  Partial(1, 1),
  Partial(2, 0.6, 0.9),
  Partial(3, 0.3, 0.7),
  Partial(4, 0.1, 0.5),
];

const double _beepHz = 987.8; // H5
const double _rapidHz = 1174.7; // D6, etwas höher für „gleich da“

Tone _beep(double start) => Tone(
  start: start,
  length: 0.2,
  freq: _beepHz,
  partials: _soft,
  decay: 0.09,
);

Tone _rapid(double start) => Tone(
  start: start,
  length: 0.075,
  freq: _rapidHz,
  partials: _soft,
  decay: 0.05,
);

const double _beepStep = 0.24;
const double _rapidStep = 0.11;
const int _rapidCount = 6;

final List<SoundSpec> soundSpecs = [
  SoundSpec('beep_1', 0.22, [_beep(0)]),
  SoundSpec('beep_2', 0.22 + _beepStep, [_beep(0), _beep(_beepStep)]),
  SoundSpec('beep_rapid', 0.09 + (_rapidCount - 1) * _rapidStep, [
    for (var i = 0; i < _rapidCount; i++) _rapid(i * _rapidStep),
  ]),
  // Sanfter Doppelton abwärts (große Terz) für Baustelle und Gefahrenstelle.
  const SoundSpec('chime', 0.75, [
    Tone(start: 0, length: 0.42, freq: 659.3, partials: _bell, decay: 0.2),
    Tone(start: 0.3, length: 0.45, freq: 523.3, partials: _bell, decay: 0.22),
  ]),
  // Blitzer-Hotspot: kurzer Dreiklang aufwärts (G5, H5, D6). Alle anderen Signale bleiben
  // auf einer Höhe oder fallen, so ist er auch nebenbei zu erkennen.
  const SoundSpec('hotspot', 0.5, [
    Tone(start: 0, length: 0.12, freq: 784.0, partials: _soft, decay: 0.08),
    Tone(start: 0.1, length: 0.12, freq: _beepHz, partials: _soft, decay: 0.08),
    Tone(
      start: 0.2,
      length: 0.28,
      freq: _rapidHz,
      partials: _soft,
      decay: 0.12,
    ),
  ]),
  const SoundSpec('overspeed', 0.5, [
    Tone(start: 0, length: 0.24, freq: 440, partials: _low, decay: 0.16),
    Tone(start: 0.26, length: 0.24, freq: 330, partials: _low, decay: 0.16),
  ]),
];

const double _attack = 0.008;
const double _release = 0.025;

/// Rendert [spec] als Gleitkomma-Samples, auf [loudnessTarget] angeglichen.
Float64List renderSound(SoundSpec spec) {
  final n = (spec.duration * sampleRate).round();
  final out = Float64List(n);
  for (final tone in spec.tones) {
    final first = (tone.start * sampleRate).round();
    final count = math.min((tone.length * sampleRate).round(), n - first);
    final norm = tone.partials.fold<double>(0, (s, p) => s + p.gain);
    for (var i = 0; i < count; i++) {
      final t = i / sampleRate;
      final env = _envelope(t, tone.length);
      var v = 0.0;
      for (final p in tone.partials) {
        final f = tone.freq * p.ratio;
        if (f >= sampleRate / 2) continue;
        v +=
            p.gain *
            math.exp(-t / (tone.decay * p.decayScale)) *
            math.sin(2 * math.pi * f * t);
      }
      out[first + i] += tone.gain * env * v / norm;
    }
  }
  return _normalize(out);
}

/// Anstieg (Attack) und Ausblendung (Release) als Halbkosinus gegen Klicks.
double _envelope(double t, double length) {
  var e = 1.0;
  if (t < _attack) e = 0.5 - 0.5 * math.cos(math.pi * t / _attack);
  final toEnd = length - t;
  if (toEnd < _release) {
    e *= 0.5 - 0.5 * math.cos(math.pi * math.max(toEnd, 0) / _release);
  }
  return e;
}

/// RMS des lautesten Fensters von [loudnessWindow] Sekunden.
double windowLoudness(Float64List x) {
  final n = math.max(1, (loudnessWindow * sampleRate).round());
  var sum = 0.0, best = 0.0;
  for (var i = 0; i < x.length; i++) {
    sum += x[i] * x[i];
    if (i >= n) sum -= x[i - n] * x[i - n];
    if (i >= n - 1) best = math.max(best, sum);
  }
  return math.sqrt(best / n);
}

double peakOf(Float64List x) =>
    x.fold<double>(0, (p, v) => math.max(p, v.abs()));

Float64List _normalize(Float64List x) {
  final loud = windowLoudness(x);
  if (loud == 0) return x;
  var k = loudnessTarget / loud;
  final peak = peakOf(x) * k;
  if (peak > peakLimit) k *= peakLimit / peak;
  for (var i = 0; i < x.length; i++) {
    x[i] *= k;
  }
  return x;
}

/// Kodiert Samples (-1..1) als WAV-Datei: 16 bit, mono.
Uint8List encodeWav(Float64List samples, {int rate = sampleRate}) {
  final dataLen = samples.length * 2;
  final bytes = ByteData(44 + dataLen);
  void tag(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLen, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i] * 32767).round().clamp(-32768, 32767);
    bytes.setInt16(44 + i * 2, v, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Länge der Stille für den Vorlauf; länger als jeder Vorlauf der Tonausgabe.
const double silenceSeconds = 0.6;

/// Alle Signale als Dateiname -> WAV-Bytes, dazu `silence.wav`.
Map<String, Uint8List> buildAllSounds() => {
  for (final spec in soundSpecs)
    '${spec.name}.wav': encodeWav(renderSound(spec)),
  'silence.wav': encodeWav(Float64List((silenceSeconds * sampleRate).round())),
};

void main() {
  final projectRoot = File.fromUri(Platform.script).parent.parent;
  final dir = Directory(
    '${projectRoot.path}${Platform.pathSeparator}assets'
    '${Platform.pathSeparator}sounds',
  )..createSync(recursive: true);
  buildAllSounds().forEach((name, data) {
    File('${dir.path}${Platform.pathSeparator}$name').writeAsBytesSync(data);
    stdout.writeln('$name  ${data.length} Bytes');
  });
}
