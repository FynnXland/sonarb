// Die Geräte-Schnittstelle von audio_session ist als experimentell markiert. Bewusst genutzt:
// Sie braucht kein Bluetooth-Recht, die Version ist auf 0.2.x festgelegt, und eine Änderung
// fiele beim Bauen auf, nicht im Betrieb.
// ignore_for_file: experimental_member_use

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ob gerade ein Bluetooth-Audiogerät als Ausgang verbunden ist. Gelesen über die
/// Audio-Ausgänge des Systems (AudioManager.getDevices), dafür braucht es kein
/// Bluetooth-Recht. Auto und Kopfhörer lassen sich so nicht unterscheiden; der Wert ist
/// deshalb nur ein Hinweis für die Fahrterkennung.
abstract interface class CarLink {
  /// Erst der aktuelle Stand, danach jede Änderung.
  Stream<bool> watch();
}

/// Ausgänge, die im Auto vorkommen: Bluetooth-Musik (A2DP), Freisprechen (SCO),
/// Bluetooth LE Audio und der Audio-Bus von Android Automotive.
const carAudioTypes = {
  AudioDeviceType.bluetoothA2dp,
  AudioDeviceType.bluetoothSco,
  AudioDeviceType.bluetoothLe,
  AudioDeviceType.carAudio,
  AudioDeviceType.bus,
};

bool hasCarAudio(Iterable<AudioDevice> devices) =>
    devices.any((d) => d.isOutput && carAudioTypes.contains(d.type));

class AudioSessionCarLink implements CarLink {
  @override
  Stream<bool> watch() async* {
    final session = await AudioSession.instance;
    var last = hasCarAudio(await session.getDevices(includeInputs: false));
    yield last;
    await for (final devices in session.devicesStream) {
      final now = hasCarAudio(devices);
      if (now == last) continue;
      last = now;
      yield now;
    }
  }
}

final carLinkProvider = Provider<CarLink>((ref) => AudioSessionCarLink());
