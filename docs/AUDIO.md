# Tonausgabe: Ducking, Bluetooth, Lautstärke

Stand: Oktober 2026, geprüft auf dem Emulator (Android 16, API 36, Google-TTS). Code: `lib/features/audio/`.

## Ablauf einer Ausgabe

```
Fokus holen (gainTransientMayDuck)
  → Vorlauf: Stille über den Piep-Player
  → Sprache (flutter_tts, falls an und der Satz nicht abgeschaltet ist)
  → 150 ms Pause → Piep
  → Fokus kurz halten → Fokus zurückgeben, die Musik fährt wieder hoch
```

Folgen mehrere Ausgaben dicht aufeinander, laufen sie nacheinander unter einem einzigen Fokus.
Vorlauf und Haltezeit stehen in `FocusTiming` (`cue_player.dart`):

| Lage | Vorlauf | Halten danach |
|---|---|---|
| Musik läuft, Ausgabe mit Sprache | 300 ms | 450 ms |
| Musik läuft, nur Piep | 120 ms | 150 ms |
| Keine Medien aktiv | 450 ms | wie oben |

Ob Medien laufen, fragt die App vor dem Fokus mit `AudioManager.isMusicActive()` ab.

## Was Android beim Ducking erlaubt

- Die App kann nur die Art des Fokus wählen: `gain`, `gainTransient`, `gainTransientMayDuck` oder
  `gainTransientExclusive`. Wie stark andere Apps leiser werden, kann sie nicht festlegen.
- Seit Android 8 duckt das System die Player anderer Apps selbst um einen festen Wert. Laut AOSP-Quelltext
  sind das etwa 20 % der Lautstärke, also rund −14 dB, mit kurzer Rampe. Hersteller können davon abweichen.
  Am Gerät gemessen ist der Wert nicht.
- Manche Apps ducken sich selbst, statt das System machen zu lassen. Auf dem Emulator tat Chrome das: Es erhielt
  `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK` 4 ms nach unserer Anfrage, in `dumpsys audio` blieb die Liste
  „ducked players“ leer. Wie weit eine solche App leiser wird, entscheidet sie selbst.
- Podcast- und Hörbuch-Apps (Inhaltstyp Sprache) werden vom System nicht automatisch geduckt. Sie bekommen nur
  die Meldung und pausieren oft. Das kann die App nicht verhindern.

**Gewählt:** Sprache und Piep fordern beide `gainTransientMayDuck` an. Musik wird damit nie pausiert.
`gainTransient` (ohne MayDuck) kommt nicht vor, weil die meisten Player darauf pausieren.
„Bei Piepen weniger leiser“ lässt sich deshalb nur über die Zeit umsetzen: Ein Piep wartet kürzer und gibt den
Fokus früher zurück. Die Musik ist also kürzer unten, aber nicht weniger tief.

Attribute der Fokusanfrage: `usage = assistanceNavigationGuidance`, dazu `contentType = speech` bei Ausgaben mit
Sprache und `sonification` bei reinen Piepen. Die TTS spricht mit `assistanceNavigationGuidance` und `speech`
(`setAudioAttributesForNavigation`), die Piep-Player nutzen `assistanceNavigationGuidance` und `sonification`.

Verliert die App den Fokus ganz oder vorübergehend (Anruf, Sprachassistent), bricht sie die laufende Ausgabe ab
und verwirft die wartenden.

## Bluetooth im Auto

- Über Bluetooth (A2DP) bekommt das Autoradio einen einzigen, im Telefon fertig gemischten Tonstrom. Ob gerade
  Musik oder ein Navigationshinweis läuft, erfährt das Radio dabei nicht. Das Ducking passiert also vollständig
  im Telefon, und der Hinweis kommt in der Lautstärke an, die das Radio für Bluetooth-Audio eingestellt hat.
- `assistanceNavigationGuidance` läuft auf Telefonen über denselben Weg und dieselbe Lautstärke wie Medien,
  also auch über A2DP. Bei Android Auto ordnet das Telefon Töne nach dieser Usage dem Navigationskanal des Autos
  zu. Das Auto regelt seine Medien dann selbst herunter. Geprüft ist das nicht.
- Ruht die Bluetooth-Strecke, weil gerade nichts spielt, brauchen viele Radios einige hundert Millisekunden,
  bis Ton ankommt. Dabei geht der Anfang verloren. Dagegen läuft ein stiller Vorlauf (`assets/sounds/silence.wav`):
  450 ms, wenn keine Medien laufen. Spielt Musik, ist die Strecke ohnehin wach und der Vorlauf deckt nur die
  Duck-Rampe ab.
- Schaltet das Radio gerade nicht auf Bluetooth (UKW, DAB, USB), hört man die Ansage im Auto nicht. Manche Radios
  wechseln von selbst die Quelle, viele nicht.
- Ist das Telefon nur als Freisprecheinrichtung verbunden (HFP ohne A2DP), kommt der Ton aus dem Telefon selbst.
  Eine Ausgabe über den Telefonkanal (SCO), wie sie Navigations-Apps anbieten, ist nicht umgesetzt.

**Ungeprüft:** jedes echte Autoradio und Android Auto. Ob 450 ms Vorlauf für jedes Radio reichen und ob ein Radio
den Hinweis anders behandelt als Musik, lässt sich nur im Auto prüfen. Die Zeiten lassen sich in `FocusTiming`
anpassen, ohne an anderer Stelle etwas zu ändern.

## Lautstärke

- Der Regler „Lautstärke“ in den Einstellungen gilt für Sprache und Piepe, relativ zur Medienlautstärke des Telefons.
- Gemessen (Google-TTS, lokale Stimme `de-de-x-nfh-local`, „Fester Blitzer voraus, Tempo 50“): lautestes
  50-ms-Fenster −11,7 dBFS, Spitze −4,5 dBFS, Mittel der gesprochenen Teile −18,8 dBFS.
- Die Piepe sind auf −8 dBFS im lautesten 50-ms-Fenster gemastert (`tool/gen_sounds.dart`). Zur Laufzeit werden sie
  mit `beepTrim = 0,56` auf rund −13 dBFS gesetzt, knapp unter die Sprachspitzen. Ein Sinuston fällt bei gleichem
  Pegel stärker auf als Sprache.
- Bei 100 % liegt die Sprache damit etwa auf Höhe üblicher, laut gemasterter Musik. Weil die Musik dabei um rund
  14 dB abgesenkt ist, steht die Ansage klar davor, ohne lauter als die Musik vorher zu sein.
- Andere TTS-Engines (etwa die von Samsung) können lauter oder leiser sprechen. Gemessen ist nur die Google-TTS.

## Stufen und Abstände

| Stufe | Ton | Zone (Standard) | Wann |
|---|---|---|---|
| Erste Ansage | Sprache und ein Piep | max(600 m, 30 s × Tempo), Zeitanteil höchstens 2 km | immer |
| Erinnerung | zwei Piepe | max(250 m, 15 s × Tempo, Ausrollweg bis zum Limit) | nur zu schnell |
| Unmittelbar | schnelle Folge | max(60 m, 4 s × Tempo) | nur zu schnell |

„Zu schnell“ heißt: über dem Limit der Messstelle (sonst dem der Straße) plus Toleranz. Ohne bekanntes Limit bleibt
es bei der ersten Ansage. Ist das Tempo unsicher (Genauigkeit schlechter als 30 m oder mehr als 4 s ohne Fix), kommt
die Erinnerung trotzdem. Baustelle, Gefahrenstelle und Sonstiges haben nur die erste Ansage.

Ausrollweg = 2 s Reaktion × Tempo + (v² − v_Limit²) / (2 × 0,7 m/s²). 0,7 m/s² entspricht Gas weg mit Motorbremse.

| Fahrt | Erste Ansage | Erinnerung | Unmittelbar |
|---|---|---|---|
| 50 km/h, Limit 30 | 600 m | 250 m | 60 m |
| 100 km/h, Limit 70 | 833 m | 417 m (Ausrollen braucht 337 m) | 111 m |
| 130 km/h, Limit 100 | 1083 m | 542 m (Ausrollen braucht 452 m) | 144 m |
| 130 km/h, Limit 80 | 1083 m | 651 m (Ausrollweg) | 144 m |

Wer passend fährt, hört je Messstelle nur die erste Ansage. Einstellbar sind der Mindestabstand der ersten Ansage
(300 m bis 5 km), die Erinnerung (an/aus, Mindestabstand 150 m bis 1 km) und „Nur piepen, wenn ich zu schnell bin“.
Die Warnlogik braucht Punkte bis `WarningSettings.lookAheadMeters` voraus (Standard 2,5 km, bei 5 km Ansage 5,5 km).

## Baustellen nach Straßenverlauf

Baustellen, Gefahrenstellen, weitere Kontrollen und Blitzer-Hotspots (alles mit nur einer Ansage) warnen nur, wenn
sie auf der Strecke liegen, der man wahrscheinlich folgt. Blitzer bleiben bei der geraden Linie. Code:
`lib/features/warning/road_course.dart`, die Strecke kommt aus `AlertRepository.roadAheadAt`
(`lib/features/osm/README.md`, „Linie voraus“).

- **Mit Straßendaten:** Die Strecke ist die eigene Straße und ihre Fortsetzung, an Kreuzungen gleicher Name oder
  gleiche Nummer, sonst gleiche Straßenart. Nach einer Abfahrt ist das die Rampe. Ein Hinweis höchstens 30 m neben
  dieser Strecke gilt als voraus, auch hinter einer Kurve oder Kreuzung. Weiter weg bleibt er still, auch wenn er
  geradeaus liegt.
- **Laufende Warnung:** Liegt der Hinweis zwei Fixes in Folge mehr als 40 m neben der Strecke (abgefahren, Vorfahrt
  knickt ab), endet sie still.
- **Ohne Straßendaten** (Zelle nicht geladen, alter Cache, Weg ohne Daten): wie bisher an der geraden Linie, eng und
  drei Fixes in Folge. Lieber vorsichtig warnen als stumm sein.
- **Abgewichen ohne neue Daten:** Liegt die Position mehr als 30 m neben der zuletzt bekannten Strecke (etwa auf einer
  Rampe ohne Daten), schweigen Hinweise auf dieser alten Strecke für die nächsten 3 km.
- **Grenze Offline-Pakete:** Die Pakete kennen nur Haupt- und Nebenstraße, keine Namen und keine Rampen ohne Limit.
  Eine abknickende Vorfahrt zwischen zwei Hauptstraßen erkennt die Linie dort nicht sicher und kann geradeaus laufen.
  Dann warnt eine Baustelle auf der geraden Straße wie bisher.

## Sätze nach feiner Art

Der Satz richtet sich nach `AlertPoint.category`. Fehlt sie (eigene Meldung, ältere Plugins), gilt der Satz der groben
Art, etwa „Baustelle voraus“. Tabelle: `phraseOf` in `lib/features/audio/cue.dart`.

- **Blitzer** (gestuft wie oben): „Fester Blitzer voraus“, „Blitzer im Tunnel voraus“, „Rotlicht- und Tempoblitzer
  voraus“, „Rotlichtblitzer voraus“, „Abschnittskontrolle voraus“, „Blitzeranhänger voraus“, „Mobiler Blitzer
  voraus“, „Abstandsmessung voraus“. Mit bekanntem Limit folgt „…, Tempo 50“.
- **Gefahrenstellen und Weitere** (nur die erste Ansage, sanfter Doppelton): „Baustelle“, „Tagesbaustelle“,
  „Stauende“, „Unfall“, „Hindernis“, „Glätte“, „Sichtbehinderung“, „Pannenfahrzeug“, „Verkehrsmeldung“,
  „Höhenkontrolle“, „Gewichtskontrolle“, „Einfahrtskontrolle“, „Überholverbot“, „Sperrung“, „Busspur“, jeweils
  „… voraus“.
- Stauende, Unfall, Hindernis, Pannenfahrzeug, Glätte und Sichtbehinderung kommen früher: mindestens 1 km oder
  40 s vorher (Zeitanteil höchstens 2 km). Davor muss man oft stark bremsen.
- **Ende der Abschnittskontrolle** (`sectionEnd`): nur „Ende der Abschnittskontrolle“, ohne Piep und ohne Stufen,
  erst unmittelbar davor (mindestens 50 m oder 2,5 s). Eine frühere Ansage könnte dazu verleiten, noch in der
  Messstrecke zu beschleunigen. Eigener Schalter.

Im Bildschirm „Sprachansagen“ deckt ein Schalter teils mehrere Arten ab (Gruppen wie in der Legende):
„Fester Blitzer“ auch Tunnel, „Rotlichtblitzer“ auch Rotlicht und Tempo, „Mobiler Blitzer“ auch Anhänger,
„Baustelle“ auch Tagesbaustelle, „Gefahrenstelle“ für Hindernis, Panne, Glätte, Sicht und Verkehrsmeldung,
eine Zeile für Höhen-, Gewichts- und Einfahrtskontrolle.

## Blitzer-Hotspots

Ein Hotspot ist eine Stelle, an der früher geblitzt wurde. Grundlage sind die vergangenen Meldungen der Plugins
(`AlertPoint.historical`, rote Wärme auf der Karte). Eigene Meldungen zählen nicht. Code:
`lib/features/warning/heat_spots.dart`. Karte und Ton nutzen dieselbe Erkennung und dieselbe Stufe
(`AppServices.heatSpots` liest `WarningSettings.heatSpotMinReports`).

- **Bündelung wie auf der Karte:** Raster mit 300-m-Zellen, je Zelle alle Meldungen im Umkreis von 300 m um ihren
  Mittelpunkt (`heatNeighbourMeters` in `map_heat.dart`).
- **Stufe** (einstellbar): Jede gemeldete Stelle (Standard), ab 2, ab 3 oder ab 5 Meldungen im Umkreis. Gezählt
  werden Meldungen, nicht Tage: Die Verlaufsdaten tragen oft grobe Datumsstufen (viele Punkte mit genau demselben
  Tag), eine Regel nach Tagen hätte ganze Altersstufen zu einem Tag zusammengelegt. Jede Meldung zählt gleich, egal
  wie alt. Nur dieselbe Meldung aus zwei Quellen (gleicher Zeitpunkt, höchstens 5 m auseinander) zählt einmal.
- **Welche Meldungen:** jede vergangene Beobachtung, die eine Tempo- oder Abstandskontrolle sein kann. Ohne
  Kategorie gilt die der groben Art (meist mobiler Blitzer), „Sonstiges“ zählt mit. Nicht mit zählt nur, was
  eindeutig etwas anderes ist: Baustellen, Gefahren und Verkehrsmeldungen, Rotlicht, Ende der Abschnittskontrolle,
  Höhen-, Gewichts- und Einfahrtskontrolle, Busspur, Überholverbot, Sperrung, Ampel (`mayBeSpeedCheck`).
- **Lage:** Der Hotspot steht an der Meldung, die dem Mittelpunkt am nächsten liegt, also auf einer Straße.
  Liegen zwei Hotspots näher als 300 m, bleibt der mit mehr und jüngeren Meldungen (eine Meldung zählt dabei
  nach einem Jahr halb).
- **Warnung:** gleicher Maßstab wie bei Baustellen. Der Hotspot muss eng auf der Fahrtlinie liegen, in Kurven
  gemessen am Bogen, und das drei Fixes in Folge. Eine Ansage je Durchfahrt, ohne Erinnerung, ohne Stufen und ohne
  Hinweisfeld im Cockpit. Steht im Umkreis von 300 m ein aktueller Blitzer für die eigene Fahrtrichtung, kommt
  nur dessen Warnung.
- **Dichte Folge:** höchstens eine Hotspot-Ansage je 20 s, die übrigen in dieser Zeit bleiben still. In der
  Simulation mit einer Meldung alle 100 m über 10 km: 20 Hotspots, angesagt 19 bei 50 km/h, 13 bei 100 km/h,
  9 bei 130 km/h. Mit einer Meldung je Kilometer: 9 bis 10 Ansagen. Berliner Verlaufsdaten (12 Bezirke, 233
  mobile Meldungen, rund 136 Stellen) ergeben auf einer typischen Stadtfahrt von 20 km grob 1 bis 4 Ansagen,
  auf Hauptstraßen mit vielen Kontrollen mehr.
- **Ton:** eigenes Signal, ein kurzer Dreiklang aufwärts (G5, H5, D6, `hotspot.wav`). Alle anderen Signale bleiben
  auf einer Höhe oder fallen. Gleicher Pegel wie die übrigen Piepe.
- **Einstellung** unter „Sprachansagen“, direkt nach den Blitzern: Aus, Ansage („Blitzer-Hotspot voraus“, dann das
  Signal) oder Nur Signalton (Standard), darunter „Welche Stellen“ mit den Stufen. Beide Arten haben eine Probe.
  Bei ausgeschalteter Sprache bleibt auch bei „Ansage“ nur das Signal. Gespeichert unter `settings.heatSpotAlert`
  und `settings.heatSpotMinReports`. „Aus“ schaltet die Erkennung in der Warnlogik ab; die Warnlogik holt die
  vergangenen Meldungen dann nicht (`pointsAround(withHistory: false)`).

## Einstellungen

Unter Einstellungen, „Sprachansagen“: Hauptschalter, dann jeder Satz mit eigenem Schalter und einer Probe zum
Anhören. Ein abgeschalteter Satz wird nicht gesprochen, der Piep kommt trotzdem. Der Tempo-Zusatz („…, Tempo 50“)
ist ein eigener Schalter. Gespeichert unter `settings.voiceEnabled` und `settings.silencedAnnouncements`
(Namen aus `Announcement`).

Einen Piep-Schalter je Art gibt es bewusst nicht. Die Piepe tragen den Abstand, und bei abgeschalteter Sprache
sind sie das einzige Signal. Ein zweiter Schalter je Zeile hätte die Liste verdoppelt.
