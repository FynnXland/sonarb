# Sonarb – Architektur

Fahrerassistenz für Android (Flutter 3.47, Dart 3.13). Paket `de.fynn.handy.sonarb`, Debug `…sonarb.debug`, minSdk 29.

## Grundsätze

- **Core = Open Source:** OSM/Overpass (feste Blitzer, Ampeln, Tempolimits) + eigene Hotspots. Keine proprietären Quellen im Repo.
- **Plugins** (`DataSourcePlugin`) sind optional und lokal. Ohne Plugin ist die App vollständig.
- **Verträge in `lib/core/`**, Module in `lib/features/<modul>/`. Ein Feature importiert nie ein anderes Feature, nur `core/`.
  Einzige Ausnahme: `lib/app/` verdrahtet alles über die Einstiegsfunktionen.
- Reine Logik (OSM-Parsing, Richtungsfilter, Warnlogik, Hotspot-JSON) ohne Flutter-Imports → mit `dart test`-artigen Unit-Tests prüfbar.

## Ordner

```
lib/
  main.dart
  app/                 Verdrahtung (Riverpod-Provider), Theme, Router, Startlogik
  core/
    geo/geo.dart       GeoPoint, GeoBounds, Distanz, Peilung, Winkeldifferenz
    model/             AlertPoint/AlertKind, PositionFix
    contracts/         FixedPointSource, HotspotRepository, AlertAudio,
                       DataSourcePlugin, AlertRepository, WarningEngine
  features/
    osm/osm.dart       createOsmSource(...)            Overpass, Cache, Richtung, Tempolimit
    hotspots/hotspots.dart  createHotspotRepository(...) Speicher, Import/Export
    audio/audio.dart   createAlertAudio()              Ducking, Signale
    warning/warning.dart createWarningEngine(...)      Vor-/Hauptwarnung, Hotspot-Ding
    alerts/alerts.dart createAlertRepository(...)      Zusammenführen + Plugin-Verwaltung
    cockpit/           Karte, Tacho, Warnanzeige, Fahrtablauf (GPS → Engine → Audio)
    settings/          Einstellungen, Hotspot-Liste, Quellenstatus
  plugins/installed_plugins.dart   im Repo leere Liste
assets/sounds/         erzeugte WAV-Signale
test/<modul>/          Tests je Modul
```

Die Einstiegsfunktionen in `features/*/<modul>.dart` sind der Vertrag mit `app/`: **Signatur nicht ändern**, nur den Inhalt
(Platzhalter) durch die echte Implementierung ersetzen. Weitere Dateien im eigenen Modulordner sind frei.

## Datenfluss während der Fahrt

```
geolocator → PositionFix ─┬→ AlertRepository.pointsAround(pos)  (OSM-Cache + Hotspots + Plugins)
                          ├→ AlertRepository.speedLimitAt(pos, heading)
                          └→ WarningEngine.update(fix, punkte, tempolimit)
                                     ├→ UI (Cockpit: nächster Punkt, Entfernung, Tempolimit)
                                     └→ AlertAudio.play(sounds)   (mit Ducking)
```

## Karte: geneigte Fahrtansicht (Entscheidung)

Bei Fahrt, Mitführen und „Fahrtrichtung oben“ neigt sich die Karte um 55° (Schalter „Karte bei Fahrt neigen“,
an als Standard). Verschieben oder Zoomen macht sie flach, „Zentrieren“ neigt sie wieder.

**Gewählt: flutter_map mit perspektivischer Transformation** (`cockpit/map_tilt.dart`). Die Karte wird größer gerendert
(oben so breit, wie die Verkürzung verlangt, nach vorn höchstens 2,8 Bildhöhen) und per `Transform` um die eigene
Position gekippt. Die Kamera sitzt vor der Position (`MapController.move(offset:)`), damit diese im unteren Drittel
liegt. Am Horizont deckt ein Dunst das Kartenende ab. Gesten und Hit-Tests laufen durch die Matrix (Flutter rechnet
Zeigerpositionen über die Homographie zurück). Wärme-Flecken und eigene Position liegen flach auf dem Boden; Punkte
stehen als aufrechte Nadeln in einer Ebene darüber (`map_pins.dart`), feste Blitzer mit ihrem Tempolimit.

Verworfen: MapLibre (`maplibre_gl` 0.27, Vektor-Kacheln von OpenFreeMap, Stil „Dark“). Optisch besser (Neigung nativ,
Beschriftung aufrecht, Straßenname aus den Vektordaten), OpenFreeMap ist frei und ohne Schlüssel (Quellenhinweis
Pflicht, keine Zusage zur Verfügbarkeit). Dagegen: native Plattform-Ansicht, die sich im Widget-Test nicht rendern lässt
(Kartenbaustein müsste austauschbar werden, Wärme, Bündelung, Übersicht und Symbole neu als Stil-Ebenen), zusätzliches
natives SDK im ohnehin empfindlichen Gradle-Build, mehr Wartung. Für eine Ansicht mit wenigen Punkten lohnt das nicht.

Kosten der Lösung: in der Neigung lädt die Karte etwa fünf- bis siebenmal so viele Kacheln wie flach (einmalig je
Ausschnitt, danach aus dem Cache). Beschriftungen der Raster-Kacheln liegen flach und werden zum Horizont klein. Einen
Straßennamen gibt es nicht: Raster-Kacheln enthalten keine Namen, und `AlertRepository` liefert keinen.

## Regeln für Beiträge

- Änderungen an den Verträgen in `lib/core/` vorher in einem Issue absprechen.
- Abhängigkeiten stehen schon in `pubspec.yaml` (flutter_riverpod, http, path_provider, flutter_map, latlong2, geolocator,
  just_audio, audio_session, wakelock_plus, share_plus, file_picker, uuid, shared_preferences; dev: mocktail).
- Dateien ≤ 400 Zeilen. Kommentare knapp, auf Deutsch, nur wo sie etwas erklären, das der Code nicht sagt.
- Prüfen: `flutter analyze lib/features/<modul> test/<modul>` und `flutter test test/<modul>` müssen sauber sein.
- Netz in Tests nie echt: `http.Client` per `MockClient` (package:http/testing.dart) ersetzen.
