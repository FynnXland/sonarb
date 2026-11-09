import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// „600 m“, „1,5 km“, „5 km“.
String distanceText(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  final text = km == km.roundToDouble()
      ? km.round().toString()
      : km.toStringAsFixed(1).replaceAll('.', ',');
  return '$text km';
}

/// Kurzer Erklärtext über einer Gruppe von Einstellungen.
class SettingsExplainer extends StatelessWidget {
  const SettingsExplainer(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      0,
      SonarSpace.l,
      SonarSpace.s,
    ),
    child: Text(text, style: SonarText.small),
  );
}

/// Regler über eine feste Liste von Werten. Die Abstände sind ungleich (300 m bis 5 km),
/// deshalb rastet der Regler auf den Listeneinträgen ein statt linear zu laufen.
class ChoiceSliderTile extends StatelessWidget {
  const ChoiceSliderTile({
    super.key,
    required this.title,
    required this.valueText,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String valueText;
  final List<double> choices;
  final double value;
  final ValueChanged<double> onChanged;

  int get _index {
    var best = 0;
    for (var i = 1; i < choices.length; i++) {
      if ((choices[i] - value).abs() < (choices[best] - value).abs()) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      SonarSpace.s,
      SonarSpace.l,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SonarText.label),
        Text(valueText, style: SonarText.small),
        Slider(
          value: _index.toDouble(),
          max: (choices.length - 1).toDouble(),
          divisions: choices.length - 1,
          label: distanceText(choices[_index]),
          semanticFormatterCallback: (_) => valueText,
          onChanged: (v) {
            final next = choices[v.round()];
            if (next != value) onChanged(next);
          },
        ),
      ],
    ),
  );
}

/// Regler über einen linearen Bereich, mit Wert in Worten darunter.
class ValueSliderTile extends StatelessWidget {
  const ValueSliderTile({
    super.key,
    required this.title,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SonarSpace.l,
      SonarSpace.s,
      SonarSpace.l,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SonarText.label),
        Text(valueText, style: SonarText.small),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueText,
          semanticFormatterCallback: (_) => valueText,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}
