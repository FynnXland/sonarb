import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/model/alert_point.dart';
import '../../core/model/speed_stage.dart';
import 'settings_layout.dart';

/// Zeichnet das Kartensymbol einer Art. Kommt von außen, weil Einstellungen das Cockpit nicht
/// importieren (siehe `app.dart`).
typedef CategorySymbolBuilder = Widget Function(
  AlertCategory category, {
  int? speed,
  required double size,
});

/// Tempolimit-Schild aus dem Cockpit: [kmh] als Zahl, ohne Zahl mit [none] das Zeichen für
/// „kein Limit“. Kommt wie [CategorySymbolBuilder] von außen.
typedef LimitSignBuilder = Widget Function({
  int? kmh,
  bool none,
  required double size,
});

/// Alle Kartensymbole nach Gruppen, mit Bezeichnung. Nur zum Nachschlagen, ohne Schalter.
class LegendScreen extends StatelessWidget {
  const LegendScreen({super.key, required this.symbol, this.limitSign});

  final CategorySymbolBuilder symbol;

  /// Ohne gibt es den Abschnitt zum Tempolimit im Cockpit nicht.
  final LimitSignBuilder? limitSign;

  /// Beispielzahlen, wie sie auf den Schildern stehen.
  static const sampleSpeeds = {
    AlertCategory.fixedSpeed: 50,
    AlertCategory.tunnelSpeed: 80,
    AlertCategory.fixedRedLightSpeed: 50,
    AlertCategory.sectionStart: 100,
    AlertCategory.semiStationary: 60,
    AlertCategory.mobileSpeed: 30,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Legende')),
    body: ListView(
      padding: pageListPadding(context),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            SonarSpace.l,
            SonarSpace.s,
            SonarSpace.l,
            0,
          ),
          child: Text(
            'So erscheinen Stellen auf der Karte. Die Form zeigt die Gruppe, '
            'das Bild darin die Art.',
            style: TextStyle(fontSize: 15, color: SonarColors.textMuted),
          ),
        ),
        for (final group in CategoryGroup.values) ...[
          _Header(title: group.label, hint: _groupHint(group)),
          for (final c in AlertCategory.values)
            if (c.group == group)
              _LegendRow(
                label: c.label,
                symbol: symbol(c, speed: sampleSpeeds[c], size: 28),
              ),
        ],
        if (limitSign case final sign?) ...[
          const _Header(
            title: 'Tempolimit im Cockpit',
            hint: 'Steht beim Fahren neben dem Tempo.',
          ),
          _LegendRow(
            label: 'Tempolimit der Straße',
            symbol: sign(kmh: 50, size: 32),
          ),
          _LegendRow(
            label:
                'Kein Tempolimit, etwa auf der Autobahn. '
                'Wegen Tempo piept es dann nicht.',
            symbol: sign(none: true, size: 32),
          ),
          const _LegendRow(
            label: 'Keine Angabe in den Daten',
            // Verkleinert wie im Cockpit, statt „unbekannt“ mitten im Wort umzubrechen.
            symbol: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Limit\nunbekannt',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: SonarColors.textMuted),
              ),
            ),
          ),
        ],
        const _Header(
          title: 'Tempo über dem Limit',
          hint: 'Die Farbe der Zahl zeigt, wie weit du drüber bist. Beispiel bei Limit 50.',
        ),
        for (final (stage, kmh, label) in _stageSamples)
          _LegendRow(
            label: label,
            symbol: _StageSample(stage: stage, kmh: kmh),
          ),
      ],
    ),
  );
}

const _stageSamples = [
  (SpeedStage.normal, 50, 'Bis zum Limit'),
  (
    SpeedStage.tolerance,
    52,
    'Drüber, aber in der eingestellten Toleranz. Es piept noch nicht.',
  ),
  (SpeedStage.over, 58, 'Zu schnell, bis 10 km/h drüber'),
  (SpeedStage.high, 65, '11 bis 20 km/h drüber, das Bußgeld steigt'),
  (SpeedStage.points, 72, 'Ab 21 km/h drüber gibt es einen Punkt in Flensburg'),
];

class _StageSample extends StatelessWidget {
  const _StageSample({required this.stage, required this.kmh});

  final SpeedStage stage;
  final int kmh;

  @override
  Widget build(BuildContext context) {
    final colors = speedStageColors(stage);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(SonarRadius.s),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SonarSpace.xs),
        child: Text(
          '$kmh',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
        ),
      ),
    );
  }
}

String _groupHint(CategoryGroup g) => switch (g) {
  CategoryGroup.camera =>
    'Nadel, die Spitze steht auf der Messstelle. Rot fest, Orange mobil, '
        'Violett Anhänger. Die Zahl ist das Tempolimit; ist es unbekannt, '
        'zeigt die Nadel eine Kamera.',
  CategoryGroup.hazard => 'Dreieck wie ein Gefahrzeichen.',
  CategoryGroup.other => 'Rundes Zeichen wie ein Verbotsschild.',
};

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      SonarSpace.xl,
      SonarSpace.l,
      SonarSpace.xs,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: SonarColors.text,
            ),
          ),
        ),
        const SizedBox(height: SonarSpace.xs),
        Text(hint, style: SonarText.small),
      ],
    ),
  );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.label, required this.symbol});

  final String label;
  final Widget symbol;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SonarSpace.l,
          vertical: SonarSpace.xs,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Center(child: ExcludeSemantics(child: symbol)),
            ),
            const SizedBox(width: SonarSpace.m),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 16, color: SonarColors.text),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
