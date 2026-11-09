import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';

/// Abstand einer Einstellungsliste: unten die Gesten- bzw. Systemleiste und Luft darüber, damit
/// der letzte Eintrag ganz frei scrollt. Eine Liste mit eigenem Padding rechnet die Leiste
/// sonst nicht mit ein.
EdgeInsets pageListPadding(
  BuildContext context, {
  double top = 0,
  double horizontal = 0,
}) => EdgeInsets.fromLTRB(
  horizontal,
  top,
  horizontal,
  MediaQuery.viewPaddingOf(context).bottom + SonarSpace.xl * 2,
);

/// Aufgeklappte Abschnitte, nur für diese Sitzung gemerkt.
class ExpandedGroups extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(String id, {required bool open}) =>
      state = open ? {...state, id} : ({...state}..remove(id));
}

final expandedGroupsProvider = NotifierProvider<ExpandedGroups, Set<String>>(
  ExpandedGroups.new,
);

/// Aufklappbarer Abschnitt: eingeklappt Titel und eine Zeile Zusammenfassung, aufgeklappt die
/// Regler und Schalter darunter.
class SettingsGroup extends ConsumerWidget {
  const SettingsGroup({
    super.key,
    required this.id,
    required this.title,
    required this.summary,
    required this.children,
    this.icon,
  });

  /// Schlüssel für den gemerkten Zustand.
  final String id;
  final String title;
  final String summary;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(
      expandedGroupsProvider.select((s) => s.contains(id)),
    );
    return ExpansionTile(
      key: PageStorageKey('settings-group-$id'),
      initiallyExpanded: open,
      onExpansionChanged: (v) =>
          ref.read(expandedGroupsProvider.notifier).set(id, open: v),
      leading: icon == null ? null : Icon(icon),
      title: Text(title),
      subtitle: Text(summary, style: SonarText.small),
      // Ohne Trennlinien: der Abschnitt soll sich ruhig öffnen, nicht wie eine Karte wirken.
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.only(bottom: SonarSpace.s),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
