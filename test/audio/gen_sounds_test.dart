import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonarb/features/audio/cue.dart';

import '../../tool/gen_sounds.dart';

void main() {
  final all = buildAllSounds();
  // Die Stille für den Vorlauf hat keinen Pegel; sie wird eigens geprüft.
  final sounds = {
    for (final e in all.entries)
      if (e.key != 'silence.wav') e.key: e.value,
  };

  String tag(ByteData d, int o) =>
      String.fromCharCodes([for (var i = 0; i < 4; i++) d.getUint8(o + i)]);

  ByteData view(Uint8List b) => ByteData.sublistView(b);

  Int16List samples(Uint8List b) {
    final copy = Uint8List.fromList(b.sublist(44));
    return copy.buffer.asInt16List();
  }

  test('erzeugt genau die Dateien, die die Tonausgabe lädt', () {
    expect(all.keys.toSet(), {
      for (final path in [...beepAssets.values, silenceAsset])
        path.split('/').last,
    });
  });

  test('Stille: nur Nullen und länger als der längste Vorlauf', () {
    final s = samples(all['silence.wav']!);
    expect(s.every((v) => v == 0), isTrue);
    expect(s.length / 44100, greaterThan(0.45));
  });

  test('erzeugte Dateien stimmen mit assets/sounds überein', () {
    final dir = Directory('assets/sounds');
    final onDisk = {
      for (final f in dir.listSync().whereType<File>()) f.uri.pathSegments.last,
    };
    expect(onDisk, all.keys.toSet(), reason: 'alte Dateien entfernen');
    all.forEach((name, bytes) {
      expect(
        File('assets/sounds/$name').readAsBytesSync(),
        bytes,
        reason: name,
      );
    });
  });

  group('WAV-Header', () {
    for (final entry in sounds.entries) {
      test(entry.key, () {
        final d = view(entry.value);
        expect(tag(d, 0), 'RIFF');
        expect(tag(d, 8), 'WAVE');
        expect(tag(d, 12), 'fmt ');
        expect(d.getUint32(4, Endian.little), entry.value.length - 8);
        expect(d.getUint32(16, Endian.little), 16);
        expect(d.getUint16(20, Endian.little), 1, reason: 'PCM');
        expect(d.getUint16(22, Endian.little), 1, reason: 'mono');
        expect(d.getUint32(24, Endian.little), 44100);
        expect(d.getUint32(28, Endian.little), 88200);
        expect(d.getUint16(32, Endian.little), 2);
        expect(d.getUint16(34, Endian.little), 16);
        expect(tag(d, 36), 'data');
        expect(d.getUint32(40, Endian.little), entry.value.length - 44);
      });
    }
  });

  test('Muster: 1 und 2 Piepe, schnelle Folge, Doppelton', () {
    int onsets(String name) {
      final s = samples(sounds[name]!);
      // Einsatz = Pegel steigt nach mindestens 20 ms Ruhe über die Schwelle.
      const quietRun = 882;
      var count = 0, quiet = quietRun;
      for (final v in s) {
        if (v.abs() > 3000) {
          if (quiet >= quietRun) count++;
          quiet = 0;
        } else {
          quiet++;
        }
      }
      return count;
    }

    expect(onsets('beep_1.wav'), 1);
    expect(onsets('beep_2.wav'), 2);
    expect(onsets('beep_rapid.wav'), greaterThanOrEqualTo(5));
  });

  test('kurz: kein Muster länger als 0,8 s', () {
    for (final entry in sounds.entries) {
      final seconds = samples(entry.value).length / 44100;
      expect(seconds, lessThanOrEqualTo(0.8), reason: entry.key);
    }
  });

  test('gleiche Lautheit, Spitze höchstens -1 dBFS', () {
    final limit = (math.pow(10, -1 / 20) * 32767).round();
    final levels = <String, double>{};
    for (final entry in sounds.entries) {
      final s = samples(entry.value);
      final peak = s.map((v) => v.abs()).reduce(math.max);
      expect(peak, lessThanOrEqualTo(limit + 1), reason: entry.key);
      final x = Float64List.fromList([for (final v in s) v / 32767]);
      levels[entry.key] = 20 * math.log(windowLoudness(x)) / math.ln10;
    }
    for (final entry in levels.entries) {
      expect(entry.value, closeTo(-8, 1.5), reason: entry.key);
    }
  });

  test('Start und Ende nahe Null (keine Klicks)', () {
    for (final entry in sounds.entries) {
      final s = samples(entry.value);
      expect(s.first.abs(), lessThan(100), reason: entry.key);
      expect(s.last.abs(), lessThan(100), reason: entry.key);
      // Kein Sprung zwischen zwei Samples, der als Klick hörbar wäre.
      for (var i = 1; i < s.length; i++) {
        expect((s[i] - s[i - 1]).abs(), lessThan(6000), reason: entry.key);
      }
    }
  });

  test('Signal ist nicht leer und hat hörbare Energie', () {
    for (final entry in sounds.entries) {
      final s = samples(entry.value);
      final rms = math.sqrt(s.fold<double>(0, (a, v) => a + v * v) / s.length);
      expect(rms, greaterThan(1500), reason: entry.key);
    }
  });
}
