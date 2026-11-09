import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'speed_chart.dart';
import 'stats_explain.dart';
import 'stats_format.dart';
import 'stats_widgets.dart';
import 'trip_log.dart';
import 'trip_summary.dart';
import 'trip_trace.dart';

/// Zeitraum der Übersicht.
enum StatsPeriod {
  week('7 Tage', 7),
  month('30 Tage', 30),
  year('Jahr', 365),
  all('Alle', null);

  const StatsPeriod(this.label, this.days);

  final String label;
  final int? days;

  /// Fahrten, die im Zeitraum bis [now] begonnen haben.
  List<TripSummary> select(List<TripSummary> trips, DateTime now) {
    final d = days;
    if (d == null) return trips;
    final from = now.subtract(Duration(days: d));
    return [
      for (final t in trips)
        if (!t.start.isBefore(from)) t,
    ];
  }
}

/// Unten die Systemleiste und Luft darüber, wie in den Einstellungen.
EdgeInsets _listPadding(BuildContext context) => EdgeInsets.only(
  bottom: MediaQuery.viewPaddingOf(context).bottom + SonarSpace.xl * 2,
);

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Löschen'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Fahrstatistik: Übersicht für einen Zeitraum, Liste der Fahrten, Aufzeichnung und Löschen.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  StatsPeriod _period = StatsPeriod.month;

  Future<void> _clear() async {
    final ok = await _confirm(
      context,
      title: 'Alle Fahrten löschen?',
      body: 'Die gesamte Fahrstatistik wird gelöscht. Lässt sich nicht rückgängig machen.',
    );
    if (!ok) return;
    try {
      await ref.read(tripsProvider.notifier).clear();
    } catch (e) {
      _say('Löschen fehlgeschlagen: $e');
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(tripsProvider);
    final hasTrips = trips.value?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fahrstatistik'),
        actions: [
          if (hasTrips)
            IconButton(
              tooltip: 'Alle Fahrten löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: _clear,
            ),
        ],
      ),
      body: switch (trips) {
        AsyncData(:final value) => _body(value),
        AsyncError(:final error) => _Message('Statistik nicht lesbar: $error'),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(List<TripSummary> all) {
    final now = ref.watch(statsClockProvider)();
    final trips = _period.select(all, now);
    return ListView(
      padding: _listPadding(context),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SonarSpace.l,
            SonarSpace.s,
            SonarSpace.l,
            SonarSpace.m,
          ),
          child: SegmentedButton<StatsPeriod>(
            showSelectedIcon: false,
            segments: [
              for (final p in StatsPeriod.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
        ),
        if (trips.isEmpty)
          _Message(
            all.isEmpty
                ? 'Noch keine Fahrt aufgezeichnet. Die Statistik füllt sich von '
                      'selbst, sobald Sonarb eine Fahrt erkennt.'
                : 'In diesem Zeitraum keine Fahrt.',
          )
        else ...[
          ...figureSections(totalOf(trips), trips: trips.length),
          const StatsHeader('Fahrten'),
          for (final t in trips) _TripTile(t),
        ],
        const StatsHeader('Aufzeichnung'),
        const _RecordingControls(),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(SonarSpace.l),
    child: Text(text, style: SonarText.label),
  );
}

class _TripTile extends StatelessWidget {
  const _TripTile(this.trip);

  final TripSummary trip;

  @override
  Widget build(BuildContext context) {
    final f = trip.figures;
    return ListTile(
      title: Text(formatTripStart(trip.start)),
      subtitle: Text(
        '${formatKm(f.distanceMeters)} · ${formatSeconds(trip.duration.inSeconds.toDouble())}'
        ' · Ø ${formatKmh(f.averageKmh)}${trip.open ? ' · läuft' : ''}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context)
              .push<void>(MaterialPageRoute(builder: (_) => TripScreen(trip))),
    );
  }
}

class _RecordingControls extends ConsumerWidget {
  const _RecordingControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(statsSettingsProvider);
    final ctrl = ref.read(statsSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('Fahrten aufzeichnen'),
          subtitle: const Text(
            'Nur Zahlen je Fahrt, keine Orte. Bleibt auf dem Gerät.',
          ),
          value: s.enabled,
          onChanged: ctrl.setEnabled,
        ),
        ListTile(
          title: const Text('Aufbewahren'),
          subtitle: const Text('Ältere Fahrten werden gelöscht.'),
          trailing: DropdownButton<int>(
            value: s.keepDays,
            underline: const SizedBox.shrink(),
            items: [
              for (final d in statsKeepChoices)
                DropdownMenuItem(value: d, child: Text(_keepLabel(d))),
            ],
            onChanged: (d) {
              if (d != null) ctrl.setKeepDays(d);
            },
          ),
        ),
      ],
    );
  }
}

String _keepLabel(int days) => switch (days) {
  30 => '1 Monat',
  90 => '3 Monate',
  365 => '1 Jahr',
  _ => '$days Tage',
};

/// Eine Fahrt mit allen Kennzahlen; löschbar.
class TripScreen extends ConsumerWidget {
  const TripScreen(this.trip, {super.key});

  final TripSummary trip;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Fahrt löschen?',
      body:
          '${formatTripStart(trip.start)}. Lässt sich nicht rückgängig machen.',
    );
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(tripsProvider.notifier).delete(trip.id);
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trace = ref.watch(tripTraceProvider(trip.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fahrt'),
        actions: [
          IconButton(
            tooltip: 'Fahrt löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: _listPadding(context),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SonarSpace.l,
              SonarSpace.s,
              SonarSpace.l,
              SonarSpace.m,
            ),
            child: Text(
              '${formatTripStart(trip.start)} bis ${formatClock(trip.end)}',
              style: SonarText.label,
            ),
          ),
          ...figureSections(
            trip.figures,
            trace: trace.value,
            start: trip.start,
            chart: trip.figures.hasDetail ? _chart(trace) : null,
          ),
        ],
      ),
    );
  }

  Widget _chart(AsyncValue<TripTrace?> trace) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const StatsHeader('Tempoverlauf', explain: Explains.chart),
      switch (trace) {
        AsyncData(:final value?) when value.length >= 2 => SpeedChart(
          trace: value,
          start: trip.start,
        ),
        AsyncData() || AsyncError() => const StatsNote(
          'Für diese Fahrt ist kein Tempoverlauf gespeichert.',
        ),
        _ => const SizedBox(height: 240),
      },
    ],
  );
}
