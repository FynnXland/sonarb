import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'cue.dart';
import 'cue_player.dart';

/// Audiofokus über den Android-AudioManager. Beide Arten fordern
/// `gainTransientMayDuck` an: Android senkt andere Apps um einen festen Wert ab und
/// pausiert sie nicht. Die Attribute weisen den Ton als Navigationshinweis aus.
class SessionFocus implements AudioFocus {
  final AndroidAudioManager _manager = AndroidAudioManager();

  /// Fokus an eine andere App verloren (Anruf, Sprachassistent).
  void Function()? onLost;

  /// Attribute für die Piep-Player (just_audio liest sie aus der Session).
  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.assistanceNavigationGuidance,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ),
    );
  }

  @override
  Future<bool> acquire(FocusKind kind) => _manager.requestAudioFocus(
    AndroidAudioFocusRequest(
      gainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      audioAttributes: AndroidAudioAttributes(
        contentType: kind == FocusKind.speech
            ? AndroidAudioContentType.speech
            : AndroidAudioContentType.sonification,
        usage: AndroidAudioUsage.assistanceNavigationGuidance,
      ),
      willPauseWhenDucked: false,
      onAudioFocusChanged: (focus) {
        if (focus == AndroidAudioFocus.loss ||
            focus == AndroidAudioFocus.lossTransient) {
          onLost?.call();
        }
      },
    ),
  );

  @override
  Future<void> release() async {
    await _manager.abandonAudioFocus();
  }

  @override
  Future<bool> mediaActive() => _manager.isMusicActive();
}

/// Piepe über just_audio, ein vorgeladener Player je Muster.
class JustAudioBeeps implements BeepOutput {
  final Map<Beep, AudioPlayer> _players = {};
  final Map<Beep, Duration> _durations = {};
  AudioPlayer? _silence;
  double _volume = 1;
  AudioPlayer? _playing;

  Future<void> init() async {
    try {
      final player = _newPlayer();
      await player.setAsset(silenceAsset);
      _silence = player;
    } catch (e) {
      debugPrint('Audio: Laden von $silenceAsset fehlgeschlagen: $e');
    }
    for (final entry in beepAssets.entries) {
      try {
        final player = _newPlayer();
        final duration = await player.setAsset(entry.value);
        _players[entry.key] = player;
        _durations[entry.key] = duration ?? const Duration(seconds: 2);
      } catch (e) {
        debugPrint('Audio: Laden von ${entry.value} fehlgeschlagen: $e');
      }
    }
  }

  // Den Fokus verwaltet SessionFocus, nicht der Player.
  static AudioPlayer _newPlayer() => AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );

  /// [volume] 0.0–1.0; die Piepe liegen um [beepTrim] unter der Sprache.
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0) * beepTrim;
  }

  @override
  Future<void> leadIn(Duration length) async {
    final player = _silence;
    if (player == null || length <= Duration.zero) {
      if (length > Duration.zero) await Future<void>.delayed(length);
      return;
    }
    try {
      await player.seek(Duration.zero);
      unawaited(player.play());
      await Future<void>.delayed(length);
    } finally {
      await _pause(player);
    }
  }

  @override
  Future<void> play(Beep beep) async {
    final player = _players[beep];
    if (player == null) return;
    _playing = player;
    try {
      await player.setVolume(_volume);
      await player.seek(Duration.zero);
      // play() bleibt danach "playing"; deshalb nach dem Ende selbst pausieren.
      await player.play().timeout(
        _durations[beep]! + const Duration(seconds: 1),
      );
    } on TimeoutException {
      debugPrint('Audio: Piep $beep hat nicht rechtzeitig geendet');
    } finally {
      await _pause(player);
      if (identical(_playing, player)) _playing = null;
    }
  }

  @override
  Future<void> stop() async {
    final player = _playing;
    if (player != null) await _pause(player);
  }

  Future<void> _pause(AudioPlayer player) async {
    try {
      await player.pause();
    } catch (e) {
      debugPrint('Audio: Pause fehlgeschlagen: $e');
    }
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      try {
        await player.dispose();
      } catch (e) {
        debugPrint('Audio: Player freigeben fehlgeschlagen: $e');
      }
    }
    _players.clear();
    await _silence?.dispose();
    _silence = null;
  }
}
