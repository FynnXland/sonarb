import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/contracts/alert_audio.dart';
import '../../core/contracts/warning_engine.dart';
import 'cue.dart';
import 'cue_player.dart';
import 'just_audio_output.dart';
import 'tts_speech.dart';

/// Einstieg Modul Audio. Signatur ist Vertrag mit `app/`.
AlertAudio createAlertAudio() => _DuckingAlertAudio();

/// Sprache (flutter_tts) und Piepe (just_audio) unter einem gemeinsamen Audiofokus.
/// Ablauf und Grenzen: docs/AUDIO.md.
/// Kein Fehler dringt nach außen: ein Tonproblem darf die Fahrt nicht stören.
class _DuckingAlertAudio implements AlertAudio {
  final SessionFocus _focus = SessionFocus();
  final JustAudioBeeps _beeps = JustAudioBeeps();
  final TtsSpeech _speech = TtsSpeech();
  late final CuePlayer _player = CuePlayer(
    speech: _speech,
    beeps: _beeps,
    focus: _focus,
  );
  bool _ready = false;
  Set<Announcement> _silenced = const {};

  @override
  Future<void> init() async {
    if (_ready) return;
    _focus.onLost = () => unawaited(_player.interrupt());
    try {
      await _focus.init();
      await _beeps.init();
      _ready = true;
    } catch (e) {
      debugPrint('Audio: Initialisierung fehlgeschlagen: $e');
    }
    unawaited(_speech.warmUp());
  }

  void _enqueue(Cue cue) {
    if (_ready) _player.enqueue(cue);
  }

  @override
  Future<void> play(WarningSound sound) async =>
      _enqueue(cueForSound(sound, DateTime.now()));

  @override
  Future<void> announce(WarningEvent event) async =>
      _enqueue(cueForEvent(event, DateTime.now(), silenced: _silenced));

  @override
  Future<void> announceStatus(StatusMessage message) async {
    final cue = cueForStatus(message, DateTime.now(), silenced: _silenced);
    if (cue != null) _enqueue(cue);
  }

  @override
  Future<void> preview(Announcement announcement) async =>
      _enqueue(previewCue(announcement, DateTime.now()));

  @override
  Set<Announcement> get silenced => _silenced;

  @override
  Future<void> setSilenced(Set<Announcement> silenced) async =>
      _silenced = Set.unmodifiable(silenced);

  @override
  bool get voiceEnabled => _player.voiceEnabled;

  @override
  Future<void> setVoiceEnabled(bool enabled) async =>
      _player.voiceEnabled = enabled;

  @override
  Future<void> setVolume(double volume) async {
    await _beeps.setVolume(volume);
    await _speech.setVolume(volume);
  }

  @override
  bool get muted => _player.muted;

  @override
  Future<void> setMuted(bool muted) => _player.setMuted(muted);

  @override
  Future<void> dispose() async {
    _ready = false;
    await _player.dispose();
    await _beeps.dispose();
  }
}
