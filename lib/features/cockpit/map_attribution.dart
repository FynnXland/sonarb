import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'map_controls.dart';

/// Ecke unten rechts: Quellenhinweis der Kartendaten, darunter der Aus-Knopf.
/// Die ODbL verlangt nur den OSM-Hinweis; ein Link darauf wäre über url_launcher möglich,
/// das ist aber nicht in den Abhängigkeiten.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.bottomRight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ColoredBox(
            color: SonarColors.bg,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Text(
                '© OpenStreetMap-Mitwirkende',
                style: SonarText.small.copyWith(color: SonarColors.text),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              SonarSpace.s,
              SonarSpace.s,
              SonarSpace.s,
            ),
            child: QuitButton(),
          ),
        ],
      ),
    ),
  );
}
