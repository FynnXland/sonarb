import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'stats_explain.dart';
import 'stats_format.dart';
import 'trip_summary.dart';
import 'trip_trace.dart';

/// Farbe je Stufe über dem Limit. Die Stufe steht immer auch als Text daneben.
Color overLimitColor(OverLimit o) => switch (o) {
  OverLimit.within => SonarColors.hotspot,
  OverLimit.upTo10 => SonarColors.amber,
  OverLimit.upTo20 => SonarColors.red,
  OverLimit.above20 => SonarColors.signRim,
};

class StatsHeader extends StatelessWidget {
  const StatsHeader(this.title, {super.key, this.explain});

  final String title;

  /// Mit ⓘ: Tippen zeigt, wie der Abschnitt berechnet ist.
  final Explain? explain;

  @override
  Widget build(BuildContext context) {
    final e = explain;
    final text = Text(
      title,
      style: SonarText.label.copyWith(color: SonarColors.amber),
    );
    const pad = EdgeInsets.fromLTRB(
      SonarSpace.l,
      SonarSpace.xl,
      SonarSpace.l,
      SonarSpace.s,
    );
    if (e == null) {
      return Padding(
        padding: pad,
        child: Semantics(header: true, child: text),
      );
    }
    return Semantics(
      header: true,
      button: true,
      label: title,
      hint: 'Berechnung anzeigen',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showExplain(context, e),
        child: Padding(
          padding: pad,
          child: Row(
            children: [
              Expanded(child: text),
              const ExplainMark(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kleiner Hinweis unter einem Abschnitt.
class StatsNote extends StatelessWidget {
  const StatsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      SonarSpace.xs,
      SonarSpace.l,
      0,
    ),
    child: Text(text, style: SonarText.small),
  );
}

/// Kachel mit Zahl und Beschriftung.
class FigureTile extends StatelessWidget {
  const FigureTile({
    super.key,
    required this.label,
    required this.value,
    this.explain,
  });

  final String label;
  final String value;

  /// Tippen zeigt, wie die Zahl berechnet ist.
  final Explain? explain;

  @override
  Widget build(BuildContext context) {
    final e = explain;
    final content = Padding(
      padding: const EdgeInsets.all(SonarSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: SonarText.small)),
              if (e != null) const ExplainMark(),
            ],
          ),
          const SizedBox(height: SonarSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: SonarColors.text,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: e != null,
      label: '$label: $value',
      hint: e == null ? null : 'Berechnung anzeigen',
      excludeSemantics: true,
      child: Material(
        color: SonarColors.surface,
        borderRadius: BorderRadius.circular(SonarRadius.m),
        clipBehavior: Clip.antiAlias,
        child: e == null
            ? content
            : InkWell(onTap: () => showExplain(context, e), child: content),
      ),
    );
  }
}

/// Kacheln in zwei Spalten.
class FigureGrid extends StatelessWidget {
  const FigureGrid(this.tiles, {super.key});

  final List<FigureTile> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: SonarSpace.s));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: SonarSpace.s),
              Expanded(
                child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
      child: Column(children: rows),
    );
  }
}

/// Eine Zeile „Beschriftung … Wert“.
class FigureRow extends StatelessWidget {
  const FigureRow(
    this.label,
    this.value, {
    super.key,
    this.detail,
    this.explain,
  });

  final String label;
  final String value;
  final String? detail;

  /// Tippen zeigt, wie die Zahl berechnet ist.
  final Explain? explain;

  @override
  Widget build(BuildContext context) {
    final e = explain;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SonarSpace.l,
        vertical: SonarSpace.s,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SonarText.label),
                if (detail != null) Text(detail!, style: SonarText.small),
              ],
            ),
          ),
          const SizedBox(width: SonarSpace.m),
          Text(
            value,
            style: SonarText.label.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (e != null) ...[
            const SizedBox(width: SonarSpace.s),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: ExplainMark(),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      button: e != null,
      label: '$label: $value${detail == null ? '' : ', $detail'}',
      hint: e == null ? null : 'Berechnung anzeigen',
      excludeSemantics: true,
      child: e == null
          ? row
          : InkWell(onTap: () => showExplain(context, e), child: row),
    );
  }
}

/// Überschrift eines Diagramms oder einer Tabelle mit ⓘ.
class ExplainHeading extends StatelessWidget {
  const ExplainHeading(this.label, this.explain, {super.key});

  final String label;
  final Explain explain;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    hint: 'Berechnung anzeigen',
    excludeSemantics: true,
    child: InkWell(
      onTap: () => showExplain(context, explain),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SonarSpace.l,
          vertical: SonarSpace.s,
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: SonarText.label)),
            const ExplainMark(),
          ],
        ),
      ),
    ),
  );
}

/// Fahrzeit je Tempostufe als waagrechte Balken, von der kleinsten bis zur größten belegten Stufe.
class SpeedHistogram extends StatelessWidget {
  const SpeedHistogram(this.figures, {super.key});

  final DriveFigures figures;

  @override
  Widget build(BuildContext context) {
    final s = figures.speedSeconds;
    final used = [
      for (var i = 0; i < s.length; i++)
        if (s[i] > 0) i,
    ];
    if (used.isEmpty) return const SizedBox.shrink();
    final total = s.fold(0.0, (a, b) => a + b);
    final peak = s.reduce(math.max);
    final best = figures.mostFrequentKmh;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
      child: Column(
        children: [
          for (var i = used.first; i <= used.last; i++)
            _Bar(
              label: '${i * StatsLimits.binKmh}',
              fraction: s[i] / peak,
              value: formatShare(s[i] / total),
              highlight: best == i * StatsLimits.binKmh,
              semantics:
                  '${formatSpeedBin(i * StatsLimits.binKmh)}: '
                  '${formatShare(s[i] / total)} der Fahrzeit',
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.fraction,
    required this.value,
    required this.highlight,
    required this.semantics,
  });

  final String label;
  final double fraction;
  final String value;
  final bool highlight;
  final String semantics;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics,
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: SonarText.small,
            ),
          ),
          const SizedBox(width: SonarSpace.s),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.02, 1.0),
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: highlight ? SonarColors.amber : SonarColors.outline,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: SonarSpace.s),
          SizedBox(
            width: 52,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: SonarText.small,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Fahrzeit mit bekanntem Limit je Straßenart, aufgeteilt nach [OverLimit].
class OverLimitTable extends StatelessWidget {
  const OverLimitTable(this.figures, {super.key});

  final DriveFigures figures;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final c in RoadClass.values)
        if (_sum(figures.overLimitSeconds[c]!) >= 1)
          _OverLimitRow(
            label: roadClassLabel(c),
            seconds: figures.overLimitSeconds[c]!,
          ),
    ];
    if (rows.isEmpty) {
      return const StatsNote('Kein Tempolimit bekannt.');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rows,
          const SizedBox(height: SonarSpace.s),
          Wrap(
            spacing: SonarSpace.m,
            runSpacing: SonarSpace.xs,
            children: [
              for (final o in OverLimit.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: overLimitColor(o),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: SonarSpace.xs),
                    Text('${overLimitLabel(o)} km/h', style: SonarText.small),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

double _sum(List<double> v) => v.fold(0.0, (a, b) => a + b);

class _OverLimitRow extends StatelessWidget {
  const _OverLimitRow({required this.label, required this.seconds});

  final String label;
  final List<double> seconds;

  @override
  Widget build(BuildContext context) {
    final total = _sum(seconds);
    final parts = [
      for (final o in OverLimit.values) (o, seconds[o.index] / total),
    ];
    final text = [
      for (final (o, share) in parts)
        if (share > 0) '${overLimitLabel(o)}: ${formatShare(share)}',
    ].join(', ');
    return Semantics(
      container: true,
      label: '$label, ${formatSeconds(total)} mit Limit. $text',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SonarSpace.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: SonarText.label)),
                Text(
                  'über Limit ${formatShare(1 - parts.first.$2)}',
                  style: SonarText.small,
                ),
              ],
            ),
            const SizedBox(height: SonarSpace.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (o, share) in parts)
                      if (share > 0)
                        Expanded(
                          flex: math.max(1, (share * 1000).round()),
                          child: ColoredBox(color: overLimitColor(o)),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: SonarSpace.xs),
            Text(text, style: SonarText.small),
          ],
        ),
      ),
    );
  }
}

/// Farbe je Stärke einer Brems- oder Beschleunigungsspitze.
Color peakColor(double fromMps2) => fromMps2 >= StatsLimits.hardPeakMps2
    ? SonarColors.red
    : fromMps2 >= StatsLimits.gentlePeakMps2
    ? SonarColors.amber
    : SonarColors.hotspot;

/// Verzögerungen oder Beschleunigungen je Stufe ihrer Spitze als stehende Balken, darunter die
/// Anteile sanft, mittel und hart.
class PeakHistogram extends StatelessWidget {
  const PeakHistogram(this.bins, {super.key, this.hardLabel = 'hart'});

  final List<double> bins;
  final String hardLabel;

  @override
  Widget build(BuildContext context) {
    final shares = peakSharesOf(bins);
    if (shares == null) return const StatsNote('Keine Vorgänge.');
    final peak = bins.reduce(math.max);
    final text =
        'sanft ${formatShare(shares.gentle)} · mittel ${formatShare(shares.medium)} · '
        '$hardLabel ${formatShare(shares.hard)}';
    return Semantics(
      container: true,
      label: '${shares.count} Vorgänge: $text',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < bins.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FractionallySizedBox(
                          heightFactor: bins[i] <= 0
                              ? 0.03
                              : (bins[i] / peak).clamp(0.08, 1.0),
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              color: bins[i] <= 0
                                  ? SonarColors.surfaceHigh
                                  : peakColor(peakBinFrom(i)),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: SonarSpace.xs),
            Row(
              children: [
                for (var i = 0; i < bins.length; i++)
                  Expanded(
                    child: Text(
                      _peakLabel(i),
                      textAlign: TextAlign.center,
                      style: SonarText.small.copyWith(fontSize: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: SonarSpace.xs),
            Text(
              '${shares.count} Vorgänge, Spitze in km/h pro Sekunde: $text',
              style: SonarText.small,
            ),
          ],
        ),
      ),
    );
  }
}

/// Beschriftung in km/h pro Sekunde, nur an den Grenzen sanft/mittel/hart und an den Enden.
String _peakLabel(int bin) {
  final from = peakBinFrom(bin);
  final last = bin == StatsLimits.peakBins - 1;
  final shown =
      bin == 0 ||
      last ||
      from == StatsLimits.gentlePeakMps2 ||
      from == StatsLimits.hardPeakMps2;
  if (!shown) return '';
  final text = '${(from * 3.6).round()}';
  return last ? '$text+' : text;
}

/// Fahrzeit, Anteil zu schnell und Höchsttempo je Tempolimit.
List<Widget> limitRows(DriveFigures f) {
  final entries = [
    for (final e in f.limits.entries)
      if (e.value.totalSeconds >= 1) e,
  ]..sort((a, b) => a.key.compareTo(b.key));
  return [
    for (final e in entries)
      FigureRow(
        'Limit ${e.key}',
        'max ${formatKmh(e.value.maxKmh)}',
        detail:
            '${formatSeconds(e.value.totalSeconds)}, davon zu schnell '
            '${formatShare(e.value.overShare)}, ab +11: '
            '${formatShare(e.value.over10Share)}',
        explain: Explains.perLimit,
      ),
  ];
}

/// Stärkster Vorgang einer Art im Verlauf.
TraceEvent? strongestEvent(TripTrace trace, TraceEventKind kind) {
  TraceEvent? best;
  for (final e in trace.events) {
    if (e.kind != kind) continue;
    if (best == null || e.peakMps2 > best.peakMps2) best = e;
  }
  return best;
}

String _eventDetail(TraceEvent e, DateTime start) =>
    '${formatMps2(e.peakMps2)} · von ${e.fromKmh} auf ${e.toKmh} km/h um '
    '${formatClock(start.add(Duration(seconds: e.second)))}';

/// Alle Kennzahlen zu [f] untereinander, für die Übersicht und je Fahrt. Für eine Fahrt
/// kommen [chart] (Tempoverlauf), [trace] und [start] dazu.
List<Widget> figureSections(
  DriveFigures f, {
  int? trips,
  Widget? chart,
  TripTrace? trace,
  DateTime? start,
}) {
  final score = f.anticipationScore;
  final detail = f.hasDetail;
  final partial = detail && f.detailSeconds < f.movingSeconds - 1;
  final decel = f.decelShares;
  final strongestBrake = trace == null
      ? null
      : strongestEvent(trace, TraceEventKind.decel);
  final strongestAccel = trace == null
      ? null
      : strongestEvent(trace, TraceEventKind.accel);
  return [
    FigureGrid([
      if (trips != null) FigureTile(label: 'Fahrten', value: '$trips'),
      FigureTile(
        label: 'Strecke',
        value: formatKm(f.distanceMeters),
        explain: Explains.distance,
      ),
      FigureTile(
        label: 'Fahrzeit',
        value: formatSeconds(f.movingSeconds),
        explain: Explains.moving,
      ),
      FigureTile(
        label: 'Standzeit',
        value: formatSeconds(f.standSeconds),
        explain: Explains.stand,
      ),
      FigureTile(label: 'Halte', value: '${f.stops}', explain: Explains.stops),
    ]),
    if (!detail)
      const StatsNote(
        'Tempoverlauf, Gleichmäßigkeit, Verteilung der Bremsungen und Werte je Limit '
        'gibt es nur für Fahrten, die nach dem Update aufgezeichnet wurden.',
      )
    else if (partial)
      const StatsNote(
        'Gleichmäßigkeit, Verteilungen, Halte-Dauer und Werte je Limit stammen nur aus '
        'Fahrten, die nach dem Update aufgezeichnet wurden.',
      ),
    ?chart,
    const StatsHeader('Tempo'),
    FigureGrid([
      FigureTile(
        label: 'Schnitt in Fahrt',
        value: formatKmh(f.averageKmh),
        explain: Explains.average,
      ),
      FigureTile(
        label: 'Schnitt mit Stand',
        value: formatKmh(f.tripAverageKmh),
        explain: Explains.tripAverage,
      ),
      FigureTile(
        label: 'Höchsttempo',
        value: formatKmh(f.maxKmh),
        explain: Explains.maxSpeed,
      ),
    ]),
    if (f.mostFrequentKmh case final kmh?)
      FigureRow(
        'Am häufigsten',
        formatSpeedBin(kmh),
        explain: Explains.frequent,
      ),
    SpeedHistogram(f),
    const StatsNote('Anteil der Fahrzeit je 10 km/h, GPS-Tempo.'),
    if (detail) ...[
      const StatsHeader('Gleichmäßigkeit'),
      FigureGrid([
        FigureTile(
          label: 'Ruhig gefahren',
          value: formatShare(f.calmShare),
          explain: Explains.calm,
        ),
        FigureTile(
          label: 'Schwankung',
          value: formatSwing(f.cruiseSwingKmh),
          explain: Explains.swing,
        ),
      ]),
      StatsNote(
        f.cruiseSwingKmh == null
            ? 'Für die Schwankung fehlte gleichmäßige Fahrt ab 30 km/h.'
            : 'Schwankung auf ${formatSeconds(f.cruiseSeconds)} gleichmäßiger Fahrt '
                  'ab 30 km/h.',
      ),
    ],
    const StatsHeader('Bremsen'),
    FigureRow(
      'Bremsungen',
      '${f.brakes}',
      detail: '${f.hardBrakes} hart (ab 11 km/h/s)',
      explain: Explains.brakes,
    ),
    if (detail)
      FigureRow(
        'Stärkste Bremsung',
        f.maxDecelMps2 > 0 ? formatKmhPerS(f.maxDecelMps2) : '–',
        detail: strongestBrake != null
            ? _eventDetail(strongestBrake, start!)
            : f.maxDecelMps2 > 0
            ? formatMps2(f.maxDecelMps2)
            : null,
        explain: Explains.maxDecel,
      ),
    FigureRow(
      'Sanft verzögert',
      formatShare(f.gentleShare),
      detail: 'Geschätzt: Motorbremse oder Ausrollen, Anteil am Tempoabbau',
      explain: Explains.gentle,
    ),
    if (detail && decel != null) ...[
      const ExplainHeading(
        'Verteilung der Verzögerungen',
        Explains.decelSpread,
      ),
      PeakHistogram(f.decelPeaks),
    ],
    const StatsHeader('Beschleunigen'),
    FigureRow(
      'Anfahrten',
      '${f.starts}',
      detail:
          '${f.strongAccelerations} Mal kräftig beschleunigt (ab 11 km/h/s)',
      explain: Explains.starts,
    ),
    if (detail)
      FigureRow(
        'Stärkste Beschleunigung',
        f.maxAccelMps2 > 0 ? formatKmhPerS(f.maxAccelMps2) : '–',
        detail: strongestAccel != null
            ? _eventDetail(strongestAccel, start!)
            : f.maxAccelMps2 > 0
            ? formatMps2(f.maxAccelMps2)
            : null,
        explain: Explains.maxAccel,
      ),
    if (detail && f.accelShares != null) ...[
      const ExplainHeading(
        'Verteilung der Beschleunigungen',
        Explains.accelSpread,
      ),
      PeakHistogram(f.accelPeaks, hardLabel: 'kräftig'),
    ],
    const StatsHeader('Fahrweise'),
    FigureRow(
      'Vorausschauend',
      score == null ? '–' : '$score von 100',
      detail:
          'Sanft verzögert, wenig harte Bremsungen und zügige Kurven, '
          'selten mehr als 10 km/h zu schnell',
      explain: Explains.score,
    ),
    FigureRow(
      'Zügige Kurven',
      '${f.sharpCurves}',
      detail: 'Höchste Querbeschleunigung ${formatMps2(f.maxLateralMps2)}',
      explain: Explains.curves,
    ),
    const StatsHeader('Tempolimit'),
    const ExplainHeading('Nach Straßenart', Explains.overLimit),
    OverLimitTable(f),
    const StatsNote(
      'Fahrzeit mit bekanntem Limit aus OpenStreetMap. GPS misst das echte Tempo, '
      'der Tacho zeigt etwas mehr. Straßenart aus dem Limit geschätzt.',
    ),
    if (detail && f.limits.isNotEmpty) ...[
      const SizedBox(height: SonarSpace.m),
      ...limitRows(f),
    ],
    if (detail && f.stops > 0) ...[
      const StatsHeader('Halte'),
      FigureRow(
        'Längster Halt',
        formatSeconds(f.longestStopSeconds),
        detail: 'im Mittel ${formatSeconds(f.meanStopSeconds ?? 0)} je Halt',
        explain: Explains.stopLength,
      ),
    ],
    const StatsHeader('Umfeld'),
    FigureRow('Innerorts', formatShare(f.urbanShare), explain: Explains.urban),
    FigureRow(
      'Bei Dunkelheit',
      formatShare(f.nightShare),
      explain: Explains.night,
    ),
    const StatsHeader('Warnungen'),
    FigureRow('Warnungen', '${f.warnings}', explain: Explains.warnings),
    FigureRow(
      'Blitzer passiert',
      '${f.camerasPassed}',
      detail: 'davon ${f.camerasTooFast} zu schnell (über Limit + 3 km/h)',
      explain: Explains.cameras,
    ),
  ];
}
