import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'cue_player.dart';

const _language = 'de-DE';

/// Ohne Engine hängen flutter_tts-Aufrufe unbegrenzt; jeder Aufruf hat deshalb eine Frist.
const _callTimeout = Duration(seconds: 3);

/// Nach einem Fehlschlag beim Einrichten erst nach dieser Zeit erneut versuchen.
const _retryAfter = Duration(minutes: 1);

/// Deutsche Sprachausgabe über die System-TTS. Fehlt eine deutsche Stimme, liefert
/// [speak] false und die Tonausgabe bleibt bei Piepen.
class TtsSpeech implements SpeechOutput {
  TtsSpeech({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  DateTime? _failedAt;
  Future<bool>? _setup;
  double _volume = 1;

  /// Richtet die Engine im Hintergrund ein, damit die erste Ansage nicht wartet.
  Future<bool> warmUp() => _ensure();

  Future<bool> _ensure() {
    if (_ready) return Future.value(true);
    final failed = _failedAt;
    if (failed != null && _clock().difference(failed) < _retryAfter) {
      return Future.value(false);
    }
    return _setup ??= _init().whenComplete(() => _setup = null);
  }

  Future<bool> _init() async {
    try {
      await _tts.awaitSpeakCompletion(true).timeout(_callTimeout);
      if (Platform.isAndroid) {
        // usage assistanceNavigationGuidance wie die Piepe, content speech.
        await _tts.setAudioAttributesForNavigation().timeout(_callTimeout);
      }
      final available = await _tts
          .isLanguageAvailable(_language)
          .timeout(_callTimeout);
      if (available != true) {
        debugPrint('Sprache: keine deutsche Stimme, nur Piepe');
        _failedAt = _clock();
        return false;
      }
      await _tts.setLanguage(_language).timeout(_callTimeout);
      await _preferLocalVoice();
      await _tts.setSpeechRate(0.5).timeout(_callTimeout);
      await _tts.setPitch(1).timeout(_callTimeout);
      await _tts.setVolume(_volume).timeout(_callTimeout);
      _ready = true;
      _failedAt = null;
      debugPrint('Sprache: bereit ($_language)');
      return true;
    } catch (e) {
      debugPrint('Sprache: Einrichten fehlgeschlagen: $e');
      _failedAt = _clock();
      return false;
    }
  }

  /// Server-Stimmen brauchen Netz und antworten spürbar später; eine lokale Stimme
  /// spricht sofort und auch ohne Empfang.
  Future<void> _preferLocalVoice() async {
    try {
      final voices = await _tts.getVoices.timeout(_callTimeout);
      final voice = pickLocalVoice(voices is List ? voices : const []);
      if (voice == null) {
        debugPrint('Sprache: keine lokale deutsche Stimme, Standardstimme');
        return;
      }
      await _tts.setVoice(voice).timeout(_callTimeout);
      debugPrint('Sprache: Stimme ${voice['name']}');
    } catch (e) {
      debugPrint('Sprache: Stimmenwahl fehlgeschlagen: $e');
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (!_ready) return;
    try {
      await _tts.setVolume(_volume).timeout(_callTimeout);
    } catch (e) {
      debugPrint('Sprache: Lautstärke fehlgeschlagen: $e');
    }
  }

  @override
  Future<bool> speak(String text) async {
    if (!await _ensure()) return false;
    // Großzügig: ein kurzer Satz dauert gut eine Sekunde.
    final limit = Duration(milliseconds: 2000 + 150 * text.length);
    try {
      final result = await _tts.speak(text).timeout(limit);
      debugPrint('Sprache: „$text“ ($result)');
      return result == 1;
    } on TimeoutException {
      debugPrint('Sprache: „$text“ nicht rechtzeitig fertig');
      await stop();
      return false;
    } catch (e) {
      debugPrint('Sprache: „$text“ fehlgeschlagen: $e');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_ready) return;
    try {
      await _tts.stop().timeout(_callTimeout);
    } catch (e) {
      debugPrint('Sprache: Stoppen fehlgeschlagen: $e');
    }
  }
}

const _qualityRank = ['very low', 'low', 'normal', 'high', 'very high'];

/// Beste installierte deutsche Stimme ohne Netzbedarf, als `{name, locale}` für
/// `FlutterTts.setVoice`. Null, wenn es keine gibt.
Map<String, String>? pickLocalVoice(List<Object?> voices) {
  Map<String, String>? best;
  var bestRank = -1;
  for (final v in voices) {
    if (v is! Map) continue;
    final name = v['name'];
    final locale = v['locale'];
    if (name is! String || locale is! String) continue;
    if (locale.toLowerCase() != _language.toLowerCase()) continue;
    if (v['network_required'] == '1') continue;
    if ('${v['features'] ?? ''}'.contains('notInstalled')) continue;
    final rank = _qualityRank.indexOf('${v['quality']}');
    if (rank > bestRank) {
      best = {'name': name, 'locale': locale};
      bestRank = rank;
    }
  }
  return best;
}
