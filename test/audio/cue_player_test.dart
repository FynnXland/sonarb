import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/features/audio/cue.dart';
import 'package:sonarb/features/audio/cue_player.dart';

/// Gemeinsames Protokoll aller Fakes, damit die Reihenfolge prüfbar ist.
class Log {
  final entries = <String>[];
  void add(String e) => entries.add(e);
}

class FakeSpeech implements SpeechOutput {
  FakeSpeech(this.log);
  final Log log;
  bool available = true;
  Completer<void>? hold;

  @override
  Future<bool> speak(String text) async {
    if (!available) {
      log.add('keine Sprache');
      return false;
    }
    log.add('sprich $text');
    await hold?.future;
    return true;
  }

  @override
  Future<void> stop() async {
    log.add('stop Sprache');
    final h = hold;
    if (h != null && !h.isCompleted) h.complete();
  }
}

class FakeBeeps implements BeepOutput {
  FakeBeeps(this.log);
  final Log log;
  Completer<void>? hold;

  @override
  Future<void> play(Beep beep) async {
    log.add('piep ${beep.name}');
    await hold?.future;
  }

  @override
  Future<void> leadIn(Duration length) async =>
      log.add('vorlauf ${length.inMilliseconds}');

  @override
  Future<void> stop() async {
    log.add('stop Piep');
    final h = hold;
    if (h != null && !h.isCompleted) h.complete();
  }
}

class FakeFocus implements AudioFocus {
  FakeFocus(this.log);
  final Log log;
  bool grant = true;
  bool music = true;

  @override
  Future<bool> acquire(FocusKind kind) async {
    log.add(grant ? 'fokus ${kind.name}' : 'fokus abgelehnt');
    return grant;
  }

  @override
  Future<void> release() async => log.add('fokus zurück');

  @override
  Future<bool> mediaActive() async => music;
}

void main() {
  late Log log;
  late FakeSpeech speech;
  late FakeBeeps beeps;
  late FakeFocus focus;
  late DateTime now;
  late CuePlayer player;

  CuePlayer build({SpeechOutput? speechOut}) => CuePlayer(
    speech: speechOut ?? speech,
    beeps: beeps,
    focus: focus,
    clock: () => now,
    log: (_) {},
    wait: (d) async => log.add('warte ${d.inMilliseconds}'),
  );

  setUp(() {
    log = Log();
    speech = FakeSpeech(log);
    beeps = FakeBeeps(log);
    focus = FakeFocus(log);
    now = DateTime.utc(2026, 10, 29, 12);
    player = build();
  });

  Cue cue({
    String? say,
    Beep? beep,
    int priority = 10,
    String? key,
    bool preview = false,
  }) => Cue(
    speech: say,
    beep: beep,
    priority: priority,
    createdAt: now,
    key: key,
    preview: preview,
  );

  group('Fokus und Ducking', () {
    test(
      'Sprache: Fokus, Vorlauf, Sprache, Piep, halten, Fokus zurück',
      () async {
        player.enqueue(cue(say: 'Fester Blitzer voraus', beep: Beep.one));
        await player.idle;
        expect(log.entries, [
          'fokus speech',
          'vorlauf 300',
          'sprich Fester Blitzer voraus',
          'warte 150',
          'piep one',
          'warte 450',
          'fokus zurück',
        ]);
      },
    );

    test(
      'nur Piep: kürzerer Vorlauf und kürzer halten, Musik weniger lang unten',
      () async {
        player.enqueue(cue(beep: Beep.two));
        await player.idle;
        expect(log.entries, [
          'fokus beep',
          'vorlauf 120',
          'piep two',
          'warte 150',
          'fokus zurück',
        ]);
      },
    );

    test('keine Musik: langer Vorlauf, damit Bluetooth den Anfang nicht abschneidet', () async {
      focus.music = false;
      player.enqueue(cue(beep: Beep.one));
      await player.idle;
      expect(log.entries.take(2), ['fokus beep', 'vorlauf 450']);
    });

    test(
      'Folge unter einem Fokus: ein Vorlauf, gehalten wie für Sprache',
      () async {
        speech.hold = Completer();
        player.enqueue(cue(beep: Beep.two, key: 'a'));
        player.enqueue(
          cue(say: 'Baustelle voraus', beep: Beep.chime, key: 'b'),
        );
        await pumpEventQueue();
        speech.hold!.complete();
        await player.idle;
        expect(log.entries, [
          'fokus beep',
          'vorlauf 120',
          'piep two',
          'sprich Baustelle voraus',
          'warte 150',
          'piep chime',
          'warte 450',
          'fokus zurück',
        ]);
      },
    );

    test('Fokus abgelehnt (z. B. Telefonat): nichts wird ausgegeben', () async {
      focus.grant = false;
      player.enqueue(cue(say: 'Fester Blitzer voraus', beep: Beep.one));
      await player.idle;
      expect(log.entries, ['fokus abgelehnt']);
      focus.grant = true;
      player.enqueue(cue(beep: Beep.one));
      await player.idle;
      expect(log.entries.last, 'fokus zurück');
    });

    test('Fokus verloren: laufende Ausgabe bricht ab, Rest entfällt', () async {
      speech.hold = Completer();
      player.enqueue(
        cue(say: 'Fester Blitzer voraus', beep: Beep.one, key: 'a'),
      );
      player.enqueue(cue(beep: Beep.rapid, key: 'b'));
      await pumpEventQueue();
      await player.interrupt();
      await player.idle;
      expect(log.entries.take(4), [
        'fokus speech',
        'vorlauf 300',
        'sprich Fester Blitzer voraus',
        'stop Sprache',
      ]);
      expect(log.entries.where((e) => e.startsWith('piep')), isEmpty);
      expect(log.entries.last, anyOf('fokus zurück', 'stop Piep'));
      expect(log.entries, contains('fokus zurück'));
    });
  });

  group('Sprache und Stumm', () {
    test('Sprache aus: nur Piepe, reine Ansagen entfallen', () async {
      player.voiceEnabled = false;
      player.enqueue(cue(say: 'Fester Blitzer voraus', beep: Beep.one));
      player.enqueue(cue(say: 'GPS-Signal verloren', key: 'status'));
      await player.idle;
      expect(log.entries, [
        'fokus beep',
        'vorlauf 120',
        'piep one',
        'warte 150',
        'fokus zurück',
      ]);
    });

    test(
      'keine deutsche Stimme: Piep kommt trotzdem, ohne Pause davor',
      () async {
        speech.available = false;
        player.enqueue(cue(say: 'Fester Blitzer voraus', beep: Beep.one));
        await player.idle;
        expect(log.entries, [
          'fokus speech',
          'vorlauf 300',
          'keine Sprache',
          'piep one',
          'warte 450',
          'fokus zurück',
        ]);
      },
    );

    test('stumm: gar nichts, laufende Ausgabe bricht ab', () async {
      beeps.hold = Completer();
      player.enqueue(cue(beep: Beep.two, key: 'a'));
      player.enqueue(cue(beep: Beep.rapid, key: 'b'));
      await pumpEventQueue();
      await player.setMuted(true);
      await player.idle;
      player.enqueue(cue(say: 'Fester Blitzer voraus', beep: Beep.one));
      await player.idle;
      expect(log.entries, [
        'fokus beep',
        'vorlauf 120',
        'piep two',
        'stop Sprache',
        'stop Piep',
        'fokus zurück',
      ]);
    });

    test('Probe kommt auch bei Stumm und ausgeschalteter Sprache', () async {
      await player.setMuted(true);
      player.voiceEnabled = false;
      player.enqueue(
        cue(say: 'Baustelle voraus', beep: Beep.chime, preview: true),
      );
      await player.idle;
      expect(log.entries, contains('sprich Baustelle voraus'));
      expect(log.entries, contains('piep chime'));
    });

    test('Fehler in der Sprache stoppen die Warteschlange nicht', () async {
      final failing = build(speechOut: _ThrowingSpeech());
      failing.enqueue(cue(say: 'Fester Blitzer voraus', beep: Beep.one));
      await failing.idle;
      expect(log.entries, contains('piep one'));
      expect(log.entries.last, 'fokus zurück');
    });
  });

  group('Warteschlange', () {
    test('wichtigere Ausgabe überholt wartende, gleiche Priorität in Ankunftsfolge', () async {
      beeps.hold = Completer();
      player.enqueue(cue(beep: Beep.one, priority: 10, key: 'a'));
      await pumpEventQueue();
      player.enqueue(cue(beep: Beep.chime, priority: 11, key: 'b'));
      player.enqueue(cue(beep: Beep.two, priority: 11, key: 'c'));
      player.enqueue(cue(beep: Beep.rapid, priority: 40, key: 'd'));
      beeps.hold!.complete();
      beeps.hold = null;
      await player.idle;
      expect(log.entries.where((e) => e.startsWith('piep')), [
        'piep one',
        'piep rapid',
        'piep chime',
        'piep two',
      ]);
    });

    test(
      'gleicher Punkt: wartende Meldung wird ersetzt, Ansage bleibt',
      () async {
        beeps.hold = Completer();
        player.enqueue(cue(beep: Beep.chime, key: 'other'));
        await pumpEventQueue();
        player.enqueue(
          cue(say: 'Fester Blitzer voraus', beep: Beep.one, key: 'cam'),
        );
        player.enqueue(cue(beep: Beep.two, priority: 20, key: 'cam'));
        beeps.hold!.complete();
        beeps.hold = null;
        await player.idle;
        expect(
          log.entries.where(
            (e) => e.startsWith('piep') || e.startsWith('sprich'),
          ),
          ['piep chime', 'sprich Fester Blitzer voraus', 'piep two'],
        );
      },
    );

    test(
      'zu lange gewartet: Piep entfällt, Ansage darf länger warten',
      () async {
        beeps.hold = Completer();
        player.enqueue(cue(beep: Beep.chime, key: 'first'));
        await pumpEventQueue();
        player.enqueue(cue(beep: Beep.two, key: 'late'));
        player.enqueue(
          cue(say: 'Baustelle voraus', beep: Beep.chime, key: 's'),
        );
        now = now.add(const Duration(seconds: 6));
        beeps.hold!.complete();
        beeps.hold = null;
        await player.idle;
        expect(
          log.entries.where(
            (e) => e.startsWith('piep') || e.startsWith('sprich'),
          ),
          ['piep chime', 'sprich Baustelle voraus', 'piep chime'],
        );
      },
    );
  });
}

class _ThrowingSpeech implements SpeechOutput {
  @override
  Future<bool> speak(String text) => Future.error(StateError('kaputt'));

  @override
  Future<void> stop() async {}
}
