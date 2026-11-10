import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/contracts/maps_navigation.dart';

export '../../core/contracts/maps_navigation.dart';

/// Einstieg Modul: auf Android über den Dienst `NavNotificationListener`, sonst ohne Wirkung.
MapsNavigation createMapsNavigation() =>
    Platform.isAndroid ? ChannelMapsNavigation() : const NoMapsNavigation();

/// Ohne Android oder in Tests: kein Zugriff, nie etwas gelesen.
class NoMapsNavigation implements MapsNavigation {
  const NoMapsNavigation();

  @override
  Future<bool> granted() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<bool> openAccessSettings() async => false;

  @override
  Future<MapsReading?> latest() async => null;

  @override
  Stream<MapsReading> get readings => const Stream.empty();
}

/// Über MethodChannel und EventChannel zum Kotlin-Dienst. Fehler im Kanal gelten als „kein
/// Zugriff“: Die App läuft dann genau wie ohne die Funktion.
class ChannelMapsNavigation implements MapsNavigation {
  static const _method = MethodChannel('sonarb/maps_nav');
  static const _events = EventChannel('sonarb/maps_nav/events');
  Stream<MapsReading>? _readings;

  @override
  Future<bool> granted() async {
    try {
      return await _method.invokeMethod<bool>('granted') ?? false;
    } catch (e) {
      debugPrint('Maps-Navigation: Zugriff unbekannt: $e');
      return false;
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    try {
      await _method.invokeMethod<void>('setEnabled', enabled);
    } catch (e) {
      debugPrint('Maps-Navigation: Schalten fehlgeschlagen: $e');
    }
  }

  @override
  Future<bool> openAccessSettings() async {
    try {
      return await _method.invokeMethod<bool>('openSettings') ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<MapsReading?> latest() async {
    try {
      final m = await _method.invokeMethod<Map<Object?, Object?>>('latest');
      return m == null ? null : MapsReading.fromMap(m);
    } catch (e) {
      return null;
    }
  }

  @override
  Stream<MapsReading> get readings => _readings ??= _events
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => MapsReading.fromMap(e as Map<Object?, Object?>))
      .handleError((Object e) => debugPrint('Maps-Navigation: $e'))
      .asBroadcastStream();
}
