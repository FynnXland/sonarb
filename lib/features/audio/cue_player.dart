import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cue.dart';

/// Sprachausgabe. [speak] endet, wenn der Satz fertig gesprochen ist.
abstract interface class SpeechOutput {
  /// false: keine Sprache verfügbar oder Fehler. Wirft nie.
  Future<bool> speak(String text);
  Future<void> stop();
}

/// Piepausgabe. [play] endet, wenn das Muster fertig oder gestoppt ist.
abstract interface class BeepOutput {
  Future<void> play(Beep beep);
  Future<void> stop();

  /// Spielt [length] Stille: weckt eine ruhende Bluetooth-Strecke auf, bevor Ton kommt,
  /// und überbrückt die Zeit, in der das System andere Apps leiser regelt.
  Future<void> leadIn(Duration length);
}

/// Wofür der Fokus geholt wird. Beide ducken (nie pausieren), Sprache aber länger.
enum FocusKind { speech, beep }

/// Kurzzeitiger Audiofokus, bei dem andere Apps leiser werden.
abstract interface class AudioFocus {
  Future<bool> acquire(FocusKind kind);
  Future<void> release();

  /// true, wenn gerade Medien laufen (die Ausgabestrecke ist dann wach).
  Future<bool> mediaActive();
}

/// Zeiten rund um den Fokus. Die Tiefe der Absenkung bestimmt Android, nicht die App;
/// beeinflussen lässt sich nur, wie lange die Musik unten bleibt.
class FocusTiming {
  const FocusTiming({
    this.speechLead = const Duration(milliseconds: 300),
    this.beepLead = const Duration(milliseconds: 120),
    this.coldLead = const Duration(milliseconds: 450),
    this.speechGap = const Duration(milliseconds: 150),
    this.speechHold = const Duration(milliseconds: 450),
    this.beepHold = const Duration(milliseconds: 150),
  });

  /// Musik läuft: warten, bis sie leiser ist, bevor gesprochen wird.
  final Duration speechLead;

  /// Musik läuft: ein Piep wartet kürzer, die Absenkung wirkt dadurch schwächer.
  final Duration beepLead;

  /// Nichts läuft: Bluetooth-Strecke ruht vermutlich und braucht Anlauf, sonst fehlt
  /// der Anfang der Ansage.
  final Duration coldLead;

  /// Pause zwischen Satz und Piep.
  final Duration speechGap;

  /// Fokus nach der letzten Ausgabe noch halten, damit die Musik nicht zwischen dicht
  /// folgenden Ausgaben hochspringt.
  final Duration speechHold;
  final Duration beepHold;

  static const zero = FocusTiming(
    speechLead: Duration.zero,
    beepLead: Duration.zero,
    coldLead: Duration.zero,
    speechGap: Duration.zero,
    speechHold: Duration.zero,
    beepHold: Duration.zero,
  );
}

/// Spielt Ausgaben nacheinander, nie gleichzeitig. Ablauf je Folge: Fokus holen, Vorlauf,
/// Sprache, Piep, kurz halten, Fokus zurückgeben.
class CuePlayer {
  CuePlayer({
    required this._speech,
    required this._beeps,
    required this._focus,
    DateTime Function()? clock,
    void Function(String message)? log,
    Future<void> Function(Duration)? wait,
    this.timing = const FocusTiming(),
    this.maxBeepWait = const Duration(seconds: 4),
    this.maxSpeechWait = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now,
       _log = log ?? debugPrint,
       _wait = wait ?? Future<void>.delayed;

  final SpeechOutput _speech;
  final BeepOutput _beeps;
  final AudioFocus _focus;
  final DateTime Function() _clock;
  final void Function(String) _log;
  final Future<void> Function(Duration) _wait;
  final FocusTiming timing;

  /// Ein Piep, der länger wartet, kommt zu spät und entfällt.
  final Duration maxBeepWait;

  /// Eine Ansage darf etwas länger warten als ein Piep.
  final Duration maxSpeechWait;

  final List<Cue> _queue = [];
  bool _running = false;
  int _generation = 0;
  Completer<void>? _idle;
  Cue? _current;

  bool muted = false;
  bool voiceEnabled = true;

  Cue? get current => _current;
  List<Cue> get pending => List.unmodifiable(_queue);

  /// Endet, wenn nichts mehr läuft oder wartet.
  Future<void> get idle =>
      _running ? (_idle ??= Completer<void>()).future : Future.value();

  bool _speaks(Cue cue) => cue.speech != null && (voiceEnabled || cue.preview);

  void enqueue(Cue cue) {
    if (muted && !cue.preview) return;
    if (!_speaks(cue) && cue.beep == null) return;
    var next = cue;
    final key = cue.key;
    if (key != null) {
      final i = _queue.indexWhere((q) => q.key == key);
      if (i >= 0) next = cue.replacing(_queue.removeAt(i));
    }
    // Stabil einsortieren: bei gleicher Priorität bleibt die Ankunftsfolge.
    final at = _queue.indexWhere((q) => q.priority < next.priority);
    _queue.insert(at < 0 ? _queue.length : at, next);
    if (!_running) unawaited(_drain());
  }

  Future<void> setMuted(bool value) async {
    muted = value;
    if (value) await _stopAll();
  }

  /// Fokus an eine andere App verloren (z. B. Anruf): laufende Ausgabe abbrechen.
  Future<void> interrupt() async {
    if (!_running) return;
    _log('Audio: Fokus verloren, Ausgabe abgebrochen');
    await _stopAll();
  }

  Future<void> dispose() => _stopAll();

  Future<void> _stopAll() async {
    _generation++;
    _queue.clear();
    if (_current == null) return;
    await _guard('Sprache stoppen', _speech.stop);
    await _guard('Piep stoppen', _beeps.stop);
  }

  Future<void> _drain() async {
    _running = true;
    final generation = _generation;
    var focused = false;
    var spoke = false;
    try {
      while (_queue.isNotEmpty && generation == _generation) {
        final cue = _queue.removeAt(0);
        if (_tooLate(cue)) {
          _log('Audio: $cue kam zu spät und entfällt');
          continue;
        }
        if (!focused) {
          final kind = _speaks(cue) ? FocusKind.speech : FocusKind.beep;
          final warm = await _mediaActive();
          focused = await _acquire(kind);
          if (!focused) {
            _log(
              'Audio: Audiofokus abgelehnt, ${_queue.length + 1} Ausgaben entfallen',
            );
            _queue.clear();
            break;
          }
          final lead = !warm
              ? timing.coldLead
              : kind == FocusKind.speech
              ? timing.speechLead
              : timing.beepLead;
          await _guard('Vorlauf', () => _beeps.leadIn(lead));
          if (generation != _generation) break;
        }
        spoke |= _speaks(cue);
        _current = cue;
        await _play(cue, generation);
        _current = null;
        if (_queue.isEmpty && generation == _generation) {
          await _wait(spoke ? timing.speechHold : timing.beepHold);
        }
      }
    } finally {
      _current = null;
      if (focused) await _guard('Fokus freigeben', _focus.release);
      _running = false;
      final idle = _idle;
      _idle = null;
      // Während des Stummschaltens oder Freigebens neu eingetroffen.
      if (_queue.isNotEmpty) {
        unawaited(_drain());
        if (idle != null) _idle = idle;
      } else {
        idle?.complete();
      }
    }
  }

  bool _tooLate(Cue cue) {
    final wait = _clock().difference(cue.createdAt);
    return wait > (_speaks(cue) ? maxSpeechWait : maxBeepWait);
  }

  Future<bool> _mediaActive() async {
    try {
      return await _focus.mediaActive();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _acquire(FocusKind kind) async {
    try {
      return await _focus.acquire(kind);
    } catch (e) {
      _log('Audio: Audiofokus fehlgeschlagen: $e');
      return false;
    }
  }

  Future<void> _play(Cue cue, int generation) async {
    final text = cue.speech;
    if (text != null && _speaks(cue)) {
      var spoke = false;
      try {
        spoke = await _speech.speak(text);
      } catch (e) {
        _log('Audio: Sprache fehlgeschlagen: $e');
      }
      if (generation != _generation) return;
      if (spoke && cue.beep != null) {
        await _wait(timing.speechGap);
        if (generation != _generation) return;
      }
    }
    final beep = cue.beep;
    if (beep != null) await _guard('Piep $beep', () => _beeps.play(beep));
  }

  Future<void> _guard(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _log('Audio: $what fehlgeschlagen: $e');
    }
  }
}
