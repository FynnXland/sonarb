import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/app/theme.dart';
import 'package:sonarb/core/model/road_limit.dart';
import 'package:sonarb/features/settings/settings_screen.dart';
import 'package:sonarb/features/stats/speed_chart.dart';
import 'package:sonarb/features/stats/stats_explain.dart';
import 'package:sonarb/features/stats/stats_screen.dart';
import 'package:sonarb/features/stats/trip_log.dart';
import 'package:sonarb/features/stats/trip_recorder.dart';
import 'package:sonarb/features/stats/trip_store.dart';
import 'package:sonarb/features/stats/trip_summary.dart';

import '../cockpit/fakes.dart';
import 'trip_sim.dart';

/// Ortszeit, damit Datum und Uhrzeit auf jedem Rechner gleich aussehen.
final now = DateTime(2026, 11, 2, 18);

TripSummary simulated(String id, DateTime start, int limit) =>
    recorded(start, limit).finish(id)!;

TripRecorder recorded(DateTime start, int limit) {
  final sim = TripSim(start: start)
    ..begin()
    ..stand(3)
    ..ramp(50, 2)
    ..hold(50, 240)
    ..ramp(0, 4)
    ..stand(40)
    ..ramp(70, 3.5)
    ..hold(70, 300)
    ..hold(70, 4, turnDegPerSecond: 22)
    ..ramp(30, 0.8)
    ..hold(30, 60)
    ..ramp(0, 1.5)
    ..stand(300);
  final r = TripRecorder();
  for (final f in sim.fixes) {
    r.add(f, road: RoadLimit.kmh(limit));
  }
  return r;
}

void main() {
  late TestRig rig;
  late MemoryTripStore store;

  setUp(() async {
    rig = await TestRig.create();
    final a = recorded(DateTime(2026, 11, 2, 7, 30), 50);
    final b = recorded(DateTime(2026, 10, 30, 17, 5), 60);
    store = MemoryTripStore([a.finish('a')!, b.finish('b')!]);
    store.traces['a'] = a.trace()!;
    store.traces['b'] = b.trace()!;
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    double height = 800,
  }) async {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...rig.overrides,
          tripStoreProvider.overrideWithValue(store),
          statsClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(theme: buildSonarTheme(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Übersicht zeigt Summen und Fahrten', (tester) async {
    await pump(tester, const StatsScreen(), height: 5200);
    expect(find.text('Fahrstatistik'), findsOneWidget);
    expect(find.text('Fahrten'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp(r'^Fahrten: 2$')), findsOneWidget);
    expect(find.text('Mo 02.11.2026, 07:30'), findsOneWidget);
    expect(find.text('Fr 30.10.2026, 17:05'), findsOneWidget);
    expect(find.text('Innerorts'), findsWidgets);
    expect(find.text('Außerorts'), findsOneWidget);
    expect(find.text('Vorausschauend'), findsOneWidget);

    await tester.tap(find.text('7 Tage'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Fahrten: 2$')), findsOneWidget);
  });

  testWidgets('Zeitraum ohne Fahrt', (tester) async {
    store.trips = [simulated('alt', DateTime(2026, 9, 1, 8), 50)];
    await pump(tester, const StatsScreen());
    expect(find.text('In diesem Zeitraum keine Fahrt.'), findsOneWidget);
    await tester.tap(find.text('Alle'));
    await tester.pumpAndSettle();
    expect(find.text('In diesem Zeitraum keine Fahrt.'), findsNothing);
  });

  testWidgets('Fahrt öffnen und löschen', (tester) async {
    await pump(tester, const StatsScreen(), height: 5200);
    await tester.tap(find.text('Mo 02.11.2026, 07:30'));
    await tester.pumpAndSettle();
    expect(find.text('Fahrt'), findsOneWidget);
    expect(find.text('Mo 02.11.2026, 07:30 bis 07:41'), findsOneWidget);
    expect(find.text('Bremsungen'), findsOneWidget);

    await tester.tap(find.byTooltip('Fahrt löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Mo 02.11.2026, 07:30'), findsNothing);
    expect([for (final t in store.trips) t.id], ['b']);
  });

  testWidgets('Fahrt mit Tempoverlauf: Ablesen und Berechnung zeigen', (
    tester,
  ) async {
    await pump(tester, TripScreen(store.trips.first), height: 4400);
    expect(find.byType(SpeedChart), findsOneWidget);
    expect(find.text('Ruhig gefahren'), findsOneWidget);
    expect(find.text('Stärkste Bremsung'), findsOneWidget);
    expect(find.text('Limit 50'), findsOneWidget);
    expect(find.text('Verteilung der Verzögerungen'), findsOneWidget);

    final chart = tester.getRect(find.byType(SpeedChart));
    await tester.tapAt(Offset(chart.left + 120, chart.top + 100));
    await tester.pump();
    expect(find.textContaining('km/h · Limit 50'), findsOneWidget);

    await tester.tap(find.text('Strecke'));
    await tester.pumpAndSettle();
    expect(find.text(Explains.distance.text), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text(Explains.distance.text), findsNothing);
  });

  testWidgets('ältere Fahrt ohne neue Werte', (tester) async {
    final json = store.trips.first.toJson()..remove('detail');
    final old = TripSummary.fromJson(json)!;
    await pump(tester, TripScreen(old), height: 4400);
    expect(find.byType(SpeedChart), findsNothing);
    expect(
      find.textContaining('nach dem Update aufgezeichnet'),
      findsOneWidget,
    );
    expect(find.text('Ruhig gefahren'), findsNothing);
    expect(find.text('Bremsungen'), findsOneWidget);
  });

  testWidgets('Golden: Fahrt', (tester) async {
    await pump(tester, TripScreen(store.trips.first), height: 3000);
    await expectLater(
      find.byType(TripScreen),
      matchesGoldenFile('goldens/stats_trip.png'),
    );
  }, skip: _goldenSkip);

  testWidgets('alle löschen und Aufzeichnung abschalten', (tester) async {
    await pump(tester, const StatsScreen(), height: 5200);
    await tester.tap(find.byTooltip('Alle Fahrten löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(store.trips, isEmpty);
    expect(
      find.textContaining('Noch keine Fahrt aufgezeichnet'),
      findsOneWidget,
    );

    await tester.tap(find.text('Fahrten aufzeichnen'));
    await tester.pumpAndSettle();
    expect(rig.prefs.getBool('stats.enabled'), isFalse);
  });

  testWidgets('Einstieg aus den Einstellungen', (tester) async {
    await pump(tester, const SettingsScreen(), height: 2400);
    await tester.tap(find.text('Fahrstatistik'));
    await tester.pumpAndSettle();
    expect(find.byType(StatsScreen), findsOneWidget);
  });

  testWidgets('Golden: Übersicht', (tester) async {
    await pump(tester, const StatsScreen(), height: 1400);
    await expectLater(
      find.byType(StatsScreen),
      matchesGoldenFile('goldens/stats_overview.png'),
    );
  }, skip: _goldenSkip);

  test('nachgestellte Fahrt hat alle Teile', () {
    final f = simulated('x', now, 50).figures;
    expect(f.hardBrakes, 1);
    expect(f.starts, 2);
    expect(f.strongAccelerations, 1);
    expect(f.sharpCurves, 1);
    expect(f.gentleShare, greaterThan(0));
  });
}

/// Die Vergleichsbilder sind unter Windows erzeugt; Linux und macOS zeichnen Schrift und Kanten
/// minimal anders. Dort (z. B. in der CI) laufen die Golden-Tests deshalb nicht.
final bool _goldenSkip = !Platform.isWindows;
