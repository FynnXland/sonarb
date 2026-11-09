import 'package:flutter/material.dart';

import 'legal.dart';
import 'theme.dart';

const _body = TextStyle(fontSize: 15, height: 1.4, color: SonarColors.text);

/// Datenschutzhinweise, erreichbar aus dem Startbildschirm und unter Einstellungen → Über.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Datenschutz')),
    body: ListView(
      // Unten die Gesten- bzw. Systemleiste und Luft, damit der letzte Absatz ganz frei scrollt.
      padding: EdgeInsets.fromLTRB(
        SonarSpace.l,
        SonarSpace.s,
        SonarSpace.l,
        MediaQuery.viewPaddingOf(context).bottom + SonarSpace.xl * 2,
      ),
      children: [
        for (final s in privacySections) ...[
          Semantics(header: true, child: Text(s.title, style: SonarText.label)),
          const SizedBox(height: SonarSpace.xs),
          Text(s.body, style: _body),
          const SizedBox(height: SonarSpace.l),
        ],
      ],
    ),
  );
}
