import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sonarb/features/cockpit/drive_controller.dart';
import 'package:sonarb/features/cockpit/google_accuracy.dart';
import 'package:sonarb/features/cockpit/location_service.dart';

import 'fakes.dart';

class MemoryStore implements GoogleAccuracyStore {
  bool declined = false;
  int writes = 0;

  @override
  Future<bool> readDeclined() async => declined;

  @override
  Future<void> writeDeclined(bool value) async {
    writes++;
    declined = value;
  }
}

Position position() => Position(
  latitude: 52.5,
  longitude: 13.4,
  timestamp: DateTime.utc(2026),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// Steht für geolocator: jedes Abo ist ein eigener Strom; Google-Abos zeigen den Dialog.
class FakeGeolocator {
  final subscriptions = <(AndroidSettings, StreamController<Position>)>[];
  bool serviceOn = true;

  int get dialogs =>
      subscriptions.where((s) => !s.$1.forceLocationManager).length;

  Stream<Position> positions(LocationSettings settings) {
    final c = StreamController<Position>();
    subscriptions.add((settings as AndroidSettings, c));
    return c.stream;
  }

  StreamController<Position> get last => subscriptions.last.$2;
  bool get lastUsesSystem => subscriptions.last.$1.forceLocationManager;

  /// Was geolocator nach „No thanks“ meldet.
  void decline() => last.addError(const LocationServiceDisabledException());
}

Future<void> settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MemoryStore store;
  late FakeGeolocator geo;
  late GeolocatorLocationService service;

  setUp(() {
    store = MemoryStore();
    geo = FakeGeolocator();
    service = GeolocatorLocationService(
      policy: GoogleAccuracyPolicy(store),
      positions: geo.positions,
      serviceEnabled: () async => geo.serviceOn,
    );
  });

  test('abgelehnt: weiter ohne Google, kein Fehler, Antwort gemerkt', () async {
    final errors = <Object>[];
    final fixes = [];
    service.fixes().listen(fixes.add, onError: errors.add);
    expect(geo.lastUsesSystem, isFalse);

    geo.decline();
    await settle();
    expect(errors, isEmpty);
    expect(geo.subscriptions, hasLength(2));
    expect(geo.lastUsesSystem, isTrue);
    expect(store.declined, isTrue);
    expect(service.googleAccuracyDeclined, isTrue);

    geo.last.add(position());
    await settle();
    expect(fixes, hasLength(1));
  });

  test('Moduswechsel nach dem Ablehnen: nie wieder der Dialog', () async {
    var sub = service.fixes().listen((_) {});
    geo.decline();
    await settle();
    for (final mode in [
      LocationMode.economy,
      LocationMode.precise,
      LocationMode.economy,
    ]) {
      await sub.cancel();
      sub = service.fixes(mode: mode).listen((_) {});
    }
    expect(geo.dialogs, 1);
    await sub.cancel();
  });

  test('Moduswechsel, solange der Dialog offen ist: kein zweiter', () async {
    var sub = service.fixes().listen((_) {});
    await sub.cancel(); // Dialog noch offen, Sparmodus übernimmt
    sub = service.fixes(mode: LocationMode.economy).listen((_) {});
    sub = service.fixes().listen((_) {});
    expect(geo.dialogs, 1);
    await sub.cancel();
  });

  test(
    'Google angenommen: weitere Abos über Google ohne neuen Dialog',
    () async {
      final sub = service.fixes().listen((_) {});
      geo.last.add(position());
      await settle();
      await sub.cancel();
      service.fixes(mode: LocationMode.economy).listen((_) {});
      expect(geo.lastUsesSystem, isFalse);
      expect(store.declined, isFalse);
    },
  );

  test('gespeicherte Ablehnung gilt auch nach dem Neustart', () async {
    store.declined = true;
    final fresh = GeolocatorLocationService(
      policy: GoogleAccuracyPolicy(store),
      positions: geo.positions,
      serviceEnabled: () async => true,
    );
    await fresh.checkAccess().catchError((_) => LocationAccess.denied);
    fresh.fixes().listen((_) {});
    expect(geo.dialogs, 0);
    expect(fresh.googleAccuracyDeclined, isTrue);
  });

  test('Standort wirklich aus: Fehler wie bisher', () async {
    geo.serviceOn = false;
    final errors = <Object>[];
    service.fixes().listen((_) {}, onError: errors.add);
    geo.decline();
    await settle();
    expect(errors.single, isA<LocationAccessError>());
    expect(
      (errors.single as LocationAccessError).access,
      LocationAccess.serviceOff,
    );
    expect(store.declined, isFalse);
  });

  test('bewusster Wunsch fragt beim nächsten Abo noch einmal', () async {
    var sub = service.fixes().listen((_) {});
    geo.decline();
    await settle();
    await sub.cancel();
    await service.allowGoogleAccuracyPrompt();
    expect(store.declined, isFalse);
    sub = service.fixes().listen((_) {});
    expect(geo.lastUsesSystem, isFalse);
    await sub.cancel();
  });

  test('Controller: Hinweis im Zustand, erneut fragen bestellt neu', () async {
    final rig = await TestRig.create();
    final c = rig.container();
    final ctl = c.read(driveControllerProvider.notifier);
    rig.location.googleAccuracyDeclined = true;
    await ctl.start();
    expect(c.read(driveControllerProvider).googleAccuracyDeclined, isTrue);
    final before = rig.location.modes.length;

    await ctl.retryGoogleAccuracy();
    expect(rig.location.googleAccuracyPrompts, 1);
    expect(c.read(driveControllerProvider).googleAccuracyDeclined, isFalse);
    expect(rig.location.modes, hasLength(before + 1));
    ctl.stop();
  });
}
