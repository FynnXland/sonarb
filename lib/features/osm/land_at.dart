import 'land_grid.dart';

/// Kennung des Bundeslands (wie bei den Tempolimit-Paketen, etwa `bayern`) an einer Position, nach
/// einem groben Raster von 0,1°. Gedacht für Vorschläge; an Landesgrenzen kann es daneben liegen.
/// Null außerhalb Deutschlands.
String? landAt(double lat, double lon) {
  final row = (lat * 10).floor() - landGridSouth;
  final col = (lon * 10).floor() - landGridWest;
  if (row < 0 || row >= landGridRows.length) return null;
  final line = landGridRows[row];
  if (col < 0 || col >= line.length) return null;
  final letter = line.codeUnitAt(col) - 97;
  return letter >= 0 && letter < landGridIds.length
      ? landGridIds[letter]
      : null;
}

/// Anzeigename je Kennung.
const Map<String, String> landNames = {
  'baden-wuerttemberg': 'Baden-Württemberg',
  'bayern': 'Bayern',
  'berlin': 'Berlin',
  'brandenburg': 'Brandenburg',
  'bremen': 'Bremen',
  'hamburg': 'Hamburg',
  'hessen': 'Hessen',
  'mecklenburg-vorpommern': 'Mecklenburg-Vorpommern',
  'niedersachsen': 'Niedersachsen',
  'nordrhein-westfalen': 'Nordrhein-Westfalen',
  'rheinland-pfalz': 'Rheinland-Pfalz',
  'saarland': 'Saarland',
  'sachsen': 'Sachsen',
  'sachsen-anhalt': 'Sachsen-Anhalt',
  'schleswig-holstein': 'Schleswig-Holstein',
  'thueringen': 'Thüringen',
};
