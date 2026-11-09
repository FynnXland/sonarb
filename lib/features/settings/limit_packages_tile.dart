import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../osm/land_at.dart';
import 'format.dart';
import 'limit_packages_controller.dart';
import 'limit_packages_screen.dart';

/// Zeile in „Daten“, die zu den Tempolimit-Paketen führt. Zeigt, was geladen ist, sonst den
/// Vorschlag für das Land, in dem man gerade ist.
class LimitPackagesTile extends ConsumerWidget {
  const LimitPackagesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(limitPackagesProvider);
    final land = ref.watch(currentLandProvider);
    return ListTile(
      leading: const Icon(Icons.speed_outlined),
      title: const Text('Tempolimits ohne Netz'),
      subtitle: Text(limitPackagesSummary(state, land)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const LimitPackagesScreen()),
      ),
    );
  }
}

/// Kurzfassung für die Einstellungsliste.
String limitPackagesSummary(LimitPackagesState state, String? land) {
  final installed = state.installed;
  if (installed.isNotEmpty) {
    final names = [for (final p in installed) landNames[p.id] ?? p.id];
    final bytes = installed.fold<int>(0, (a, p) => a + p.bytes);
    return '${names.join(', ')} · ${formatBytes(bytes)}';
  }
  if (land != null && landNames.containsKey(land)) {
    return 'Du bist in ${landNames[land]}: Paket laden empfohlen';
  }
  return 'Noch kein Paket geladen';
}
