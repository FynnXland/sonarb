import 'package:flutter/material.dart';

import 'stats_screen.dart';

/// Einziger Einstieg in die Fahrstatistik, in den Einstellungen.
class StatsEntryTile extends StatelessWidget {
  const StatsEntryTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.query_stats),
    title: const Text('Fahrstatistik'),
    subtitle: const Text('Strecke, Tempo, Fahrweise. Nur auf dem Gerät'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () =>
        Navigator.of(context)
            .push<void>(MaterialPageRoute(builder: (_) => const StatsScreen())),
  );
}
