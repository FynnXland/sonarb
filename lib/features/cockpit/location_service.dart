import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/geo/geo.dart';
import '../../core/model/position_fix.dart';
import 'google_accuracy.dart';
import 'heading_estimator.dart';
import 'speed_filter.dart';

/// Ob Standortdaten nutzbar sind.
enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// Fehler im Positionsstrom, der den Zugriff betrifft (GPS ausgeschaltet, Recht entzogen).
class LocationAccessError implements Exception {
  const LocationAccessError(this.access);
  final LocationAccess access;
}

/// Wie oft und wie genau gemessen wird.
enum LocationMode {
  /// Stand oder unklar: selten, über WLAN und Funkzellen, GPS nur gelegentlich.
  economy,

  /// Fahrt: GPS jede Sekunde.
  precise,
}

/// Einstellungen des Sparmodus. Das Handy soll im Stand weder warm werden noch Akku verlieren.
abstract final class EconomyLocation {
  /// Android BALANCED_POWER_ACCURACY: etwa 100 m genau, meist ohne GPS.
  static const accuracy = LocationAccuracy.medium;

  /// Höchstens alle 20 s. Eine beginnende Fahrt fällt so nach spätestens einer Messung auf.
  static const interval = Duration(seconds: 20);

  /// Jede Messung zustellen, auch im Stand. Der Anbieter rechnet im Intervall ohnehin; ein
  /// Abstandsfilter spart dort nichts, verbirgt aber, ob die Netz-Ortung überhaupt liefert.
  /// Bleiben die Messungen aus, prüft die Fahrterkennung per GPS (`GpsCheck`).
  static const distanceFilterMeters = 0;
}

abstract interface class LocationService {
  /// Prüft Dienst und Berechtigung. Mit [request] wird bei Bedarf nach der Berechtigung gefragt.
  Future<LocationAccess> checkAccess({bool request = false});

  /// Positionen im gewählten Takt ([LocationMode.precise]: etwa jede Sekunde).
  /// Fehler als [LocationAccessError]. Für einen anderen Modus abbestellen und neu abrufen.
  Stream<PositionFix> fixes({LocationMode mode = LocationMode.precise});

  Future<void> openAppSettings();
  Future<void> openLocationSettings();

  /// Der Nutzer hat Googles Dialog „Standortgenauigkeit“ abgelehnt; geortet wird ohne Google.
  bool get googleAccuracyDeclined;

  /// Nur auf ausdrücklichen Wunsch: beim nächsten Abo Googles Dialog noch einmal zeigen.
  Future<void> allowGoogleAccuracyPrompt();
}

/// Unter dieser Geschwindigkeit ist der GPS-Kurs Rauschen.
const double minHeadingSpeedMps = 2;

/// Kurs mit größerer Unsicherheit wird verworfen.
const double maxHeadingAccuracyDeg = 45;

/// Wandelt eine geolocator-Messung; Kurs nur, wenn er verlässlich ist.
PositionFix fixFromPosition(Position p) {
  final speed = p.hasSpeed && p.speed > 0 ? p.speed : 0.0;
  final headingOk =
      p.hasHeading &&
      speed >= minHeadingSpeedMps &&
      (!p.hasHeadingAccuracy || p.headingAccuracy <= maxHeadingAccuracyDeg);
  return PositionFix(
    position: GeoPoint(p.latitude, p.longitude),
    speedMps: speed,
    accuracyMeters: p.accuracy,
    time: p.timestamp,
    headingDeg: headingOk ? normalizeDegrees(p.heading) : null,
  );
}

typedef PositionStreamFactory = Stream<Position> Function(
  LocationSettings settings,
);

/// Einstellungen je Modus und Quelle.
AndroidSettings locationSettingsFor(
  LocationMode mode,
  LocationBackend backend,
) {
  final system = backend == LocationBackend.system;
  return switch (mode) {
    LocationMode.precise => AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      forceLocationManager: system,
    ),
    LocationMode.economy => AndroidSettings(
      accuracy: EconomyLocation.accuracy,
      distanceFilter: EconomyLocation.distanceFilterMeters,
      intervalDuration: EconomyLocation.interval,
      forceLocationManager: system,
    ),
  };
}

class GeolocatorLocationService implements LocationService {
  GeolocatorLocationService({
    GoogleAccuracyPolicy? policy,
    PositionStreamFactory? positions,
    Future<bool> Function()? serviceEnabled,
  }) : _policy = policy ?? GoogleAccuracyPolicy(PrefsGoogleAccuracyStore()),
       _positions =
           positions ??
           ((settings) =>
               Geolocator.getPositionStream(locationSettings: settings)),
       _serviceEnabled = serviceEnabled ?? Geolocator.isLocationServiceEnabled;

  final GoogleAccuracyPolicy _policy;
  final PositionStreamFactory _positions;
  final Future<bool> Function() _serviceEnabled;

  @override
  Future<LocationAccess> checkAccess({bool request = false}) async {
    await _policy.load();
    if (!await _serviceEnabled()) {
      return LocationAccess.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && request) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
  }

  @override
  Stream<PositionFix> fixes({LocationMode mode = LocationMode.precise}) {
    final headings = HeadingEstimator();
    final speeds = SpeedFilter();
    StreamSubscription<Position>? sub;
    late final StreamController<PositionFix> out;

    void subscribe() {
      final backend = _policy.next();
      sub = _positions(locationSettingsFor(mode, backend)).listen(
        (p) {
          _policy.fixFrom(backend);
          out.add(speeds.apply(headings.apply(fixFromPosition(p))));
        },
        onError: (Object e) => _onError(e, backend, out, () {
          sub?.cancel();
          sub = null;
          if (out.hasListener) subscribe();
        }),
      );
    }

    out = StreamController<PositionFix>(
      onListen: subscribe,
      onCancel: () {
        final s = sub;
        sub = null;
        return s?.cancel();
      },
    );
    return out.stream;
  }

  /// „Standort aus“ von Google bei eingeschaltetem Standort heißt: Dialog abgelehnt.
  /// Dann ohne Google weiter, ohne Fehler nach außen; sonst entstünde eine Schleife
  /// aus Fehler, Neustart und neuem Dialog.
  Future<void> _onError(
    Object e,
    LocationBackend backend,
    StreamController<PositionFix> out,
    void Function() resubscribe,
  ) async {
    if (e is LocationServiceDisabledException) {
      if (backend == LocationBackend.google && await _serviceEnabled()) {
        await _policy.declinedByUser();
        resubscribe();
        return;
      }
      out.addError(const LocationAccessError(LocationAccess.serviceOff));
      return;
    }
    if (e is PermissionDeniedException) {
      out.addError(const LocationAccessError(LocationAccess.denied));
      return;
    }
    out.addError(e);
  }

  @override
  bool get googleAccuracyDeclined => _policy.declined;

  @override
  Future<void> allowGoogleAccuracyPrompt() => _policy.allowPrompt();

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);
