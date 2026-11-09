import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/osm_source.dart';

import 'osm_fixtures.dart';
import 'source_env.dart';

/// Startpunkt: Zelle 8,00–8,05 / 52,05–52,10.
const _start = GeoPoint(52.07, 8.01);

/// Kantenwert einer Zelle, wie ihn die Abfrage schreibt (2 mm Rand).
String edge(int index) => (index / 20 - 0.00002).toStringAsFixed(5);

/// Zelle (West, Süd) unter [p] im Format der Abfrage.
(String, String) ownCell(GeoPoint p) =>
    (edge((p.lon * 20).floor()), edge((p.lat * 20).floor()));

void main() {
  final env = SourceEnv();
  setUp(env.setUp);
  tearDown(env.tearDown);

  /// Wartet, bis die Quelle nichts mehr lädt (auch das Nachladen im Hintergrund).
  Future<void> settle() => env.whenIdle();

  late List<(OsmLayer, String, String)> seen;
  late OsmSource source;
  late GeoPoint pos;

  setUp(() {
    seen = [];
    pos = _start;
    source = env.make(
      MockClient((req) async {
        seen.add((layerOf(req), westOf(req), southOf(req)));
        return ok(req);
      }),
      grace: const Duration(milliseconds: 20),
    );
  });

  Set<OsmLayer> layers() => {for (final s in seen) s.$1};
  Set<(String, String)> cellsOf(OsmLayer l) => {
    for (final s in seen)
      if (s.$1 == l) (s.$2, s.$3),
  };

  /// Fährt [seconds] Sekunden mit [mps] nach [heading] und fragt jede Sekunde das Limit ab.
  Future<void> drive(int seconds, double mps, {double? heading = 90}) async {
    final rad = (heading ?? 90) * math.pi / 180;
    for (var i = 0; i < seconds; i++) {
      env.clock = env.clock.add(const Duration(seconds: 1));
      pos = GeoPoint(
        pos.lat + mps * math.cos(rad) / 111320,
        pos.lon +
            mps * math.sin(rad) / (111320 * math.cos(pos.lat * math.pi / 180)),
      );
      await source.speedLimitAt(pos, heading);
    }
    await settle();
  }

  /// Lädt die 3-km-Umgebung um die Position ohne Cache und merkt sich die dabei angefragten Zellen.
  Future<void> loadHere() async {
    await settle();
    await source.clearCache();
    seen.clear();
    final r = await source.load(GeoBounds.around(pos, 3000));
    await settle();
    expect(r.error, isNull);
  }

  group('Tempo und Hysterese', () {
    test(
      'langsam oder unbekannt: alle Schichten und Zellen der Umgebung',
      () async {
        await loadHere(); // noch keine Bewegung bekannt
        expect(layers(), OsmLayer.values.toSet());
        await drive(20, 10); // 36 km/h
        await loadHere();
        expect(layers(), OsmLayer.values.toSet());
      },
    );

    test('ab 65 km/h über 8 s: schnell', () async {
      await drive(6, 25); // 90 km/h, aber erst 6 s
      await loadHere();
      expect(layers(), contains(OsmLayer.minorLimits));
      await drive(10, 25);
      await loadHere();
      expect(layers(), isNot(contains(OsmLayer.minorLimits)));
      expect(layers(), isNot(contains(OsmLayer.signals)));
      expect(layers(), containsAll([OsmLayer.limits, OsmLayer.cameras]));
    });

    test('kurzer Ausreißer nach oben kippt nicht', () async {
      await drive(10, 10);
      await drive(4, 28); // 100 km/h für 4 s
      await drive(10, 10);
      await loadHere();
      expect(layers(), contains(OsmLayer.minorLimits));
    });

    test(
      'schnell bleibt bei kurzem Bremsen, wird nach 8 s unter 50 km/h langsam',
      () async {
        await drive(20, 28);
        await drive(4, 8); // kurz langsam (Stau, Ausfahrt)
        await drive(8, 28);
        await loadHere();
        expect(layers(), isNot(contains(OsmLayer.minorLimits)));

        await drive(30, 8); // 29 km/h anhaltend
        await loadHere();
        expect(layers(), containsAll([OsmLayer.minorLimits, OsmLayer.signals]));
      },
    );

    test(
      'Lücke in den Positionen setzt das Tempo zurück, der Zustand bleibt',
      () async {
        await drive(20, 28);
        env.clock = env.clock.add(const Duration(minutes: 2)); // Tunnel, Pause
        await source.speedLimitAt(pos, 90);
        await loadHere();
        expect(layers(), isNot(contains(OsmLayer.minorLimits)));
      },
    );
  });

  group('Schnell: nur Zellen entlang des Kurses', () {
    test('Kurs Ost: eigene Zelle und die voraus, keine Seitenzellen', () async {
      await drive(25, 28); // 100 km/h
      await loadHere();
      final (w, s) = ownCell(pos);
      final cells = cellsOf(OsmLayer.limits);
      expect(cells, contains((w, s)));
      expect(cells.length, greaterThan(1), reason: 'Zellen voraus');
      expect(
        cells.every((c) => c.$2 == s),
        isTrue,
        reason: 'eine Reihe: $cells',
      );
      expect(
        cells.every((c) => double.parse(c.$1) >= double.parse(w) - 1e-6),
        isTrue,
        reason: 'nichts westlich: $cells',
      );
    });

    test('ohne Kurs nur die eigene Zelle', () async {
      await drive(25, 28, heading: null);
      await loadHere();
      expect(cellsOf(OsmLayer.limits), {ownCell(pos)});
    });

    test(
      'Abbiegen nach Norden: dann kommen die Zellen im Norden dran',
      () async {
        await drive(25, 28);
        await drive(2, 28, heading: 0);
        await loadHere();
        await source.speedLimitAt(
          pos,
          0,
        ); // Zellen voraus: außerhalb des 3-km-Kreises
        await settle();
        final (w, s) = ownCell(pos);
        final cells = cellsOf(OsmLayer.limits);
        expect(cells.length, greaterThan(1));
        expect(
          cells.every((c) => c.$1 == w),
          isTrue,
          reason: 'eine Spalte: $cells',
        );
        expect(
          cells.every((c) => double.parse(c.$2) >= double.parse(s) - 1e-6),
          isTrue,
          reason: 'nichts südlich: $cells',
        );
      },
    );

    test(
      'Vorausschau wächst mit dem Tempo: 150 s, bei 120 km/h knapp 5 km',
      () async {
        await drive(25, 33);
        await loadHere();
        await source.speedLimitAt(pos, 90);
        await settle();
        final east = cellsOf(OsmLayer.limits)
            .map((c) => double.parse(c.$1))
            .reduce(math.max);
        // 4,95 km sind 0,0727° Länge; die weiteste Zelle beginnt höchstens eine Zelle (0,05°) davor.
        expect(east, greaterThan(pos.lon + 0.0727 - 0.05 - 0.001));
      },
    );

    test('schnell holt keine Nebenstraßen, langsam wieder schon', () async {
      await drive(25, 28);
      seen.clear();
      await drive(3, 28);
      expect(layers(), isNot(contains(OsmLayer.minorLimits)));

      await drive(40, 6);
      pos = const GeoPoint(52.12, 8.22); // neue Gegend, ungeladen
      seen.clear();
      await source.speedLimitAt(pos, 90);
      await settle();
      expect(layers(), containsAll([OsmLayer.limits, OsmLayer.minorLimits]));
    });
  });

  test('schnelle Fahrt meldet keinen Rückstand', () async {
    await drive(25, 28);
    final r = await source.load(GeoBounds.around(pos, 3000));
    await settle();
    expect(r.error, isNull);
  });
}
