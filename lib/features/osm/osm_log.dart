/// Debug-Ausgabe des OSM-Moduls. Nur in Debug-Builds (`assert`), im Release bleibt es still.
/// Bewusst `print` statt `debugPrint`: das Modul läuft auch ohne Flutter (Skripte, Tests).
void osmLog(String message) {
  assert(() {
    // ignore: avoid_print
    print('[osm] $message');
    return true;
  }());
}
