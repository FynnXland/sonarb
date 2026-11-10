import 'dart:async';

import 'package:sonarb/core/contracts/maps_navigation.dart';

/// Maps-Mitteilung ohne Android: Zugriff, Schalten und Lesen von außen steuerbar.
class FakeMapsNavigation implements MapsNavigation {
  bool access = false;
  final enabledCalls = <bool>[];
  int settingsOpened = 0;
  MapsReading? last;
  final _readings = StreamController<MapsReading>.broadcast();

  /// Eine neue Mitteilung, wie sie der Dienst melden würde.
  void post(MapsReading r) {
    last = r;
    _readings.add(r);
  }

  @override
  Future<bool> granted() async => access;

  @override
  Future<void> setEnabled(bool enabled) async => enabledCalls.add(enabled);

  @override
  Future<bool> openAccessSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<MapsReading?> latest() async => last;

  @override
  Stream<MapsReading> get readings => _readings.stream;
}
