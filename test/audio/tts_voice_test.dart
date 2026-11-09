import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/features/audio/tts_speech.dart';

Map<String, String> voice(
  String name, {
  String locale = 'de-DE',
  String network = '0',
  String quality = 'normal',
  String features = '',
}) => {
  'name': name,
  'locale': locale,
  'network_required': network,
  'quality': quality,
  'features': features,
};

void main() {
  test('wählt die beste lokale deutsche Stimme', () {
    final picked = pickLocalVoice([
      voice('de-de-x-dea-network', network: '1', quality: 'very high'),
      voice('en-us-x-iog-local', locale: 'en-US', quality: 'very high'),
      voice('de-de-x-nfh-local', quality: 'normal'),
      voice('de-de-x-dea-local', quality: 'high'),
      voice(
        'de-de-x-deb-local',
        quality: 'very high',
        features: 'notInstalled',
      ),
    ]);
    expect(picked, {'name': 'de-de-x-dea-local', 'locale': 'de-DE'});
  });

  test('keine passende Stimme: null', () {
    expect(pickLocalVoice([voice('a', network: '1')]), isNull);
    expect(pickLocalVoice(const [null, 'kaputt']), isNull);
  });
}
