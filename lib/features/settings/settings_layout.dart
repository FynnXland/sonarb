import 'package:flutter/widgets.dart';

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
