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

/// Unterzeile wie bei einer Listenzeile (Material 3: 14 sp, grau).
const settingsSubtitle = TextStyle(
  fontSize: 14,
  height: 1.35,
  color: SonarColors.textMuted,
);

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
    child: Text(text, style: settingsSubtitle),
  );
}

/// Titel, Wert in Worten und Regler darunter. Der Titel steht wie bei einem Schalter (16 sp,
/// normal), die Bahn beginnt an derselben Kante wie der Text, und TalkBack liest den Titel mit.
class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.valueText,
    required this.slider,
  });

  final String title;
  final String valueText;
  final Widget slider;

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
        ExcludeSemantics(
          child: Text(title, style: Theme.of(context).textTheme.bodyLarge),
        ),
        ExcludeSemantics(child: Text(valueText, style: settingsSubtitle)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            // Leere Strecke mit 3:1 gegen den Hintergrund statt kaum sichtbar.
            inactiveTrackColor: SonarColors.outline,
            inactiveTickMarkColor: SonarColors.textMuted,
            // Knopf (20 dp) bündig mit dem Text darüber, Höhe 48 dp zum Tippen.
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          ),
          child: MergeSemantics(
            child: Semantics(label: title, child: slider),
          ),
        ),
      ],
    ),
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
  Widget build(BuildContext context) => _SliderTile(
    title: title,
    valueText: valueText,
    slider: Slider(
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
  Widget build(BuildContext context) => _SliderTile(
    title: title,
    valueText: valueText,
    slider: Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      label: valueText,
      semanticFormatterCallback: (_) => valueText,
      onChanged: onChanged,
    ),
  );
}

/// Zeile, die eine Unterseite öffnet. Auf der Übersicht mit Symbol, auf Unterseiten ohne.
class SettingsLinkTile extends StatelessWidget {
  const SettingsLinkTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.page,
    this.icon,
    this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final WidgetBuilder page;
  final IconData? icon;

  /// Für eine Störung, etwa eine Quelle mit Fehler.
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: icon == null ? null : Icon(icon),
    title: Text(title),
    subtitle: Text(
      subtitle,
      style: subtitleColor == null ? null : TextStyle(color: subtitleColor),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () =>
        Navigator.of(context).push<void>(MaterialPageRoute(builder: page)),
  );
}

/// Zeile mit Erklärung und einem Knopf darunter statt rechts daneben: Bei großer Schrift bleibt
/// so der Titel lesbar.
class SettingsActionTile extends StatelessWidget {
  const SettingsActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onPressed,
    this.icon,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(
        leading: icon == null ? null : Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
      Padding(
        padding: EdgeInsets.only(
          left: icon == null ? SonarSpace.s : 48,
          bottom: SonarSpace.xs,
        ),
        child: TextButton(onPressed: onPressed, child: Text(action)),
      ),
    ],
  );
}
