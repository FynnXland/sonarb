/// Reihenfolge des Ladens nach Wichtigkeit für die Warnungen der nächsten Minuten.
///
/// 1. Blitzer: feste aus OSM (Cache, dann die Kachel unter dem Fahrzeug, dann das Fenster von 3 km)
///    und die Plugins mit festen und mobilen Blitzern.
/// 2. Baustellen und Gefahren (Plugins).
/// 3. Der Verlauf (Wärme-Ebene), der große Umkreis und die Kartenübersicht.
///
/// Spätere Stufen warten, solange für die Position noch keine Blitzer da sind, höchstens aber
/// [stageWait]; sie nehmen dem Netz nichts weg, was die erste Stufe braucht.
const Duration stageWait = Duration(seconds: 30);

/// Stufe eines Plugins nach seiner ID (die Ordnernamen der Plugins): Baustellen und Gefahren sind
/// Stufe 2, der Verlauf Stufe 3, alles andere Stufe 1. Plugins melden ihre Art nicht eigens; deshalb
/// entscheiden Namensteile wie `verlauf`, `baustelle` oder `roadworks` in der ID über die Stufe.
int pluginLoadStage(String id) {
  if (id.contains('verlauf')) return 3;
  if (id.contains('baustelle') || id.contains('roadworks')) return 2;
  return 1;
}
