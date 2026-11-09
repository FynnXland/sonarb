# features/osm

Feste Messstellen, Ampeln und Tempolimits aus OpenStreetMap (Overpass). Einstieg: `createOsmSource` in `osm.dart`.

| Datei | Inhalt |
|---|---|
| `osm_source.dart` | `OsmSource`: Schichten laden, Teilergebnisse, Cache im Speicher und auf Platte, In-Flight-Zusammenlegung |
| `osm_layer.dart` | die vier Schichten mit Kachelgitter, Timeouts und Overpass-Abfrage |
| `overpass_client.dart` | Anfrage, Ausweich-Endpunkt, Pause nach Überlast (429/502/503/504/406, Zeitüberschreitung) |
| `osm_category.dart` | `enforcement`/Tags → grobe `AlertKind` und feine `AlertCategory` |
| `osm_country.dart`, `osm_source_country.dart`, `country_cameras.dart` | Länderlauf: Umriss Deutschlands, Länderabfrage, Kacheln schreiben, Schnittstelle `CountryCameraSource` |
| `osm_details.dart` | Tags → deutsche `PointDetail`s, OSM-`PointSource`, Datum und Himmelsrichtung |
| `osm_result.dart` | `SourceResult` aus den Kacheln eines `load` samt Meldungen |
| `osm_gate.dart` | Warteschlange mit Dringlichkeit, begrenzt gleichzeitige Anfragen |
| `osm_parser.dart` | Overpass-JSON → `AlertPoint`s und Tempolimit-Wege |
| `osm_direction.dart` | `direction`-Auslegung (siehe unten) |
| `osm_speed.dart` | `maxspeed`-Werte und Segmentwahl für `speedLimitAt` |
| `osm_tile.dart`, `osm_tile_store.dart` | Kachelgitter (nächste zuerst), kompaktes Kachelformat, Datei-Cache (atomar) |

## Laden unter Last

Die öffentlichen Overpass-Server sind 2026 oft am Limit (Antwort 502 „at capacity“, 429 nach 40 s Wartezeit,
Abfragen von unter 100 kB brauchen über eine Minute). Darum wird in Schichten und nach Dringlichkeit geladen.
Instanzen laut OSM-Wiki: `overpass-api.de` (FOSSGIS) und `overpass.private.coffee` (vormals kumi.systems);
weitere sind kostenpflichtig oder an Schlüssel gebunden.

| Schicht | Inhalt | Gitter | Abfrage-`timeout` / HTTP |
|---|---|---|---|
| `cameras` | `speed_camera`-Knoten, `enforcement`-Relationen (über `rel(bn.cams)`), die Wege der Knoten für die Richtung | 0,1° | 60 s / 75 s |
| `signals` | `traffic_signals`-Knoten | 0,1° | 60 s / 75 s |
| `limits` | Wege mit `maxspeed*` auf `motorway` … `tertiary` (mit `out geom`) | 0,05° | 90 s / 120 s |
| `minorLimits` | Wege mit `maxspeed*` auf `unclassified`, `residential`, `living_street` | 0,05° | 90 s / 120 s |

- **Blitzer zuerst:** Die Blitzer-Abfrage enthält nur Knoten und das, was an ihnen hängt, und läuft ohne die schweren
  Wegabfragen. Alle fehlenden Blitzer-Kacheln eines `load` gehen in **einer** Anfrage über ihre gemeinsame Hülle
  (ein 10-km-Quadrat schneidet oft 4 Kacheln). Die Relationen werden über die Knoten gefunden statt per Rechteck
  (`rel(bbox)` ist auf dem Server teuer); eine Abschnittskontrolle, deren Geräteknoten nicht als `speed_camera`
  getaggt sind, fehlt damit.
- **Reihenfolge:** Warteschlange nach Schicht (Blitzer, Ampeln, Tempolimits, Nebenstraßen), innerhalb davon nach
  Abstand der Kachel zur Position (die Kachel mit der Position hat Abstand 0).
- **Parallelität:** höchstens 2 Anfragen gleichzeitig, davon höchstens 1 für Ampeln/Tempolimits. Für Blitzer bleibt
  immer ein Platz frei, auch wenn eine Wegabfrage hängt. Ampeln und Tempolimits werden von `load` erst gestartet,
  wenn die Blitzer da sind (oder 150 s um sind).
- **Backoff:** Auf 429/502/503/504/406 oder eine Zeitüberschreitung pausiert der Endpunkt 30, 60, dann 120 s
  (`Retry-After` hat Vorrang, höchstens 5 min; Erfolg setzt zurück). Währenddessen geht an ihn keine Anfrage;
  der andere Endpunkt wird gefragt. Wartet der Server nur auf Abstand (Überlast), wartet eine Blitzer-Abfrage bis zu 60 s bis zum Ende der kürzesten Pause
  und versucht es erneut (insgesamt 3 Versuche); die übrigen Schichten geben auf und werden beim nächsten `load` wiederholt.
- **Vorausladen der Blitzer bei Fahrt:** `speedLimitAt` schätzt Tempo und Kurs und holt die Blitzer-Kacheln (0,1°) entlang
  des Kurses vor, die noch fehlen: so weit, wie man in 240 s kommt, mindestens 6 km, höchstens 16 km
  (`cameraLookAheadSeconds`, `cameraLookAheadMinMeters`, `cameraLookAheadMaxMeters`), ab 18 km/h und nur mit Kurs. Dringlichkeit
  der Blitzer, nach Abstand geordnet; frische Kacheln und solche in der Pause nach einem Fehlschlag werden nicht noch einmal
  gefragt. Das Fenster der Warnlogik (3 km um die Position, Nachladen nach 750 m) holt sich die Kachel danach aus dem
  Speicher, ohne Anfrage. Vorher wurde die nächste Kachel erst geholt, wenn das Fenster sie berührte: bei 120 km/h
  gut 90 s vorher, und eine Kachel braucht 30–40 s, bei Überlast Minuten.
- **Nahdaten und Fernblock getrennt** (`alert_repository_osm.dart`): Die Umgebung (3 km) wird übernommen, sobald `load` sie
  liefert; der große Umkreis (`loadCameras`, Dringlichkeit der Übersicht, also hinter Blitzern, Ampeln und Tempolimits)
  läuft daneben und ergänzt später. Früher wartete `_loadOsm` auf beide zugleich: Ein Fernblock, der in der Warteschlange
  hing, hielt die längst vorhandenen Nahdaten zurück und blockierte jedes weitere Nachladen. Bei einem Fehlschlag bleibt der
  alte Bestand bis zum Ersatz.
- **Stufen beim Laden** (`alert_repository_osm.dart`, `load_stages.dart`, `staged_source.dart`): Wo für die Position noch
  nichts vorliegt (Start der Fahrt, neue Gegend), kommt zuerst der Cache, dann die Kachel unter dem Fahrzeug, dann das
  Fenster. Jede Stufe wird übernommen, sobald sie da ist, und das Fenster ersetzt die früheren Stände.
  0. `loadCached`: Blitzer aus Speicher und Cache-Ordner, ohne Netz, ohne Alterprüfung (eine 40 Tage alte Kachel zählt als
     verfügbar). Eine Blitzer-Kachel unter dem Fahrzeug deckt die Stelle ab, auch wenn sie keinen Blitzer enthält.
  1. `loadFirstStage`: nur die Blitzer-Kachel (0,1°) unter dem Fahrzeug, mit der Dringlichkeit der Blitzer, ohne Ampeln und
     Tempolimits und ohne die Nachbarn. Eine Kachel statt einer Hülle über bis zu vier. Teilt sich die Anfrage mit `load`.
  2. `load` (3 km): wie bisher, mit den Nachbarkacheln, Ampeln und Tempolimits.
  3. Danach der große Umkreis (`loadCameras`, Dringlichkeit der Übersicht) und die Plugins der späteren Stufen. Die Stufen
     gelten nur, wo der Bestand die Position nicht schon deckt (`coveredMeters`); beim normalen Nachladen nach 750 m
     entfallen 0 und 1.
  Plugins nach Stufe (`pluginLoadStage`, nach der Plugin-ID): 1 Blitzer (sofort), 2 Baustellen und Gefahren (ID mit
  `baustelle` oder `roadworks`), 3 Verlauf (ID mit `verlauf`). Stufe 2 wartet, bis die Blitzer der Position da sind,
  Stufe 3 bis die Umgebung fertig und Stufe 2 durch ist; höchstens 30 s bzw. 60 s nach dem ersten Fix. Wo ein Plugin
  schon Daten für die Gegend hat, gilt die Reihenfolge nicht.
- **Wiederholung ohne Daten:** Liegt für die Position gar nichts vor, fragt das Repository nach 15 s statt 60 s erneut
  (`osmRetryNoData`). Ein Abruf kostet nichts, solange der Server pausiert, und ein Hintergrundlauf kann inzwischen
  fertig sein; vorher blieb der Fehlerzustand bis zu eine Minute länger stehen als nötig. Mit Daten bleibt es bei 60 s.
- **Ausfall-Ansage:** Die Quelle gilt nur als ausgefallen, wenn der Abruf gescheitert ist, der letzte Stand weiter als
  `coveredMeters` entfernt ist **und** unter dem Fahrzeug keine Blitzer-Kachel geladen ist (`loadedCameraTilesIn`, auch aus dem
  Cache und alt). Eine Strecke ohne Blitzer, bei der eine Nachbarkachel fehlt, ist kein Ausfall mehr.
  Ebenso kein Ausfall, wenn ein Blitzer-Plugin (Stufe 1) erfolgreich Daten für die Stelle geliefert hat. Ein Baustellen-
  oder Verlaufs-Plugin zählt dafür nicht.
- **Toter Endpunkt:** Antwortet ein Endpunkt nicht (Zeitüberschreitung, Verbindung scheitert), während ein anderer in den
  letzten 10 min geantwortet hat (auch mit Überlast), gilt er 10 min lang als tot und wird übersprungen
  (`OverpassClient.deadPause`); danach wird er einmal wieder probiert, ein Erfolg setzt zurück. Das ersetzt für ihn die
  30/60/120-s-Pause, beides zählt nicht doppelt. Antwortet gar kein Endpunkt, ist vermutlich das Netz weg: kein Urteil,
  es bleibt bei der Kette von oben und bei der Funkloch-Pause der Quelle. Ein Endpunkt, der früher einmal geantwortet hat,
  kommt als Notnagel auch während der Pause dran, wenn sonst keiner mehr antwortet (der Hauptendpunkt ist nie gesperrt,
  wenn er der einzige ist, der geht); einer, der noch nie geantwortet hat, nicht. Bei Überlast der anderen wird ein toter
  Endpunkt nicht gefragt. Gemessen am 30.10.2026: `overpass.private.coffee` antwortete auf keine Abfrage (100 s), während
  `overpass-api.de` für eine Blitzer-Kachel 28 s brauchte. Modell der Zeit bis zur ersten Blitzer-Kachel (3 Versuche,
  dann 60 s Pause, Zweitserver tot, Frist 75 s): Hauptserver bis 100 s überlastet 272 → 169 s; Hauptserver bis 400 s
  still, aber eine andere Schicht hat zuvor geantwortet 693 → 543 s. Keine Wirkung, wenn vorher noch gar kein
  Endpunkt geantwortet hat (beide still: 211 und 693 s bleiben), und bei dauerhafter Überlast des Hauptservers.
- **Teilergebnisse:** `load` wartet höchstens 150 s auf die Blitzer, danach noch 8 s auf Ampeln und Tempolimits.
  Was bis dahin fehlt, lädt im Hintergrund weiter; `speedLimitAt` nutzt es sofort, der nächste `load` liefert es.
  Laden Ampeln und Tempolimits nur noch nach, steht das als Hinweis in `SourceResult.notice`: „Ampeln und
  Tempolimits werden nachgeladen“. Echte Störungen stehen in `SourceResult.error`, etwa „Overpass überlastet, Ampeln
  und Tempolimits unvollständig“ (Blitzer: „… Daten unvollständig“). In beiden Fällen fragt der Aufrufer nach einer
  Minute erneut an.

## Fehlerbilder und Selbstheilung

Der Client unterscheidet vier Gründe (`OverpassReason`) und zeigt sie kurz in `SourceResult.error`:

| Fall | Meldung | Verhalten |
|---|---|---|
| 429/502/503/504/406, `runtime error` | „Overpass überlastet“ | Endpunkt pausiert 30/60/120 s |
| Zeitüberschreitung | „Overpass antwortet nicht“ | Endpunkt pausiert |
| `ClientException`/`HttpException`/`Connection closed|reset|…` während der Übertragung, abgeschnittener gzip-Strom, JSON, das mit `{` beginnt und nicht endet | „Verbindung abgebrochen“ | vorübergehend: anderer Endpunkt, Blitzer-Kachel nach 1 s noch bis zu 2-mal, sonst beim nächsten `load` nach 60 s |
| HTML-/Textseite (auch Status 200), leere Antwort | „Antwort unbrauchbar“ | wie oben, vorübergehend |
| gültiges JSON ohne `elements` | „Antwort unbrauchbar“ | kein Warten (ändert sich nicht) |
| kein Netz, DNS, anderer Status, ungültige Kopfzeile | „Overpass nicht erreichbar“ | kein Warten |

Eine fehlgeschlagene Antwort wird nie geschrieben: Cache und Kachel bleiben, wie sie waren; veraltete Daten dienen
weiter („…, Daten aus dem Cache“). Der Text der Antwort wird immer als UTF-8 gelesen (kaputte Bytes werfen nicht).
Ein ungewöhnliches Element (fehlende `id`, Text statt Zahl, kaputte Geometrie oder Mitglieder) wird übersprungen,
nicht die Kachel verworfen. In Debug-Builds schreibt `osmLog` (`osm_log.dart`) Schicht, Kachel, Fehlertext, Größe,
Content-Type und den Anfang der Antwort auf die Konsole; im Release bleibt es still.

## Deutschland-Lauf (`loadCountryCameras`)

Alle festen Messstellen Deutschlands mit **einer** Overpass-Anfrage (`area["ISO3166-1"="DE"]`, Knoten,
`enforcement`-Relationen, Wege für die Richtung, alle Kontrollarten, `out meta`). Gemessen am 30.10.2026 auf dem
öffentlichen Server: 78 s Laufzeit, **1,2 MB übertragen** (6,5 MB entpackt), 5190 Blitzerknoten, 4822 Relationen,
732 Wege. Ende-zu-Ende mit der App-Quelle (Auswerten und Schreiben 6,5 s): 6237 Messstellen, 4775 Kacheln-Dateien,
**2,0 MB auf Platte**; danach liefern Berlin und die Deutschlandansicht ohne eine einzige Anfrage ihre Punkte.
Der Server antwortete je nach Last nach 78 s bis 232 s oder mit 502/504; der Client wiederholt später. Gegen Blöcke von 0,5° (rund 180 Anfragen, je 30 s Wartezeit) ist das die freundlichere Wahl: wenige
schwere Anfragen kosten den Server weniger als viele leichte, und die Datenmenge ist klein genug, dass keine
WLAN-Pflicht nötig ist. Ein Lauf ist entsprechend die einzige Last im Monat: einmal, danach wöchentlich.

- Die Antwort wird einmal ausgewertet (im Isolate) und nach Kacheln (0,1°) geschrieben, auch leere Kacheln
  im Land (grober Umriss `germanyOutline`, rund 4800 Kacheln, auf Platte gesamt wenige MB). Eine leere Kachel
  heißt „hier ist nichts“, sie ist geladen (blau) und löst keine Abfrage aus.
- **Randkacheln** (Abstand zum groben Umriss unter 0,12°) sind `partial`: jenseits der Grenze fehlt vielleicht
  etwas. Sie zeigen, was da ist, gelten aber als veraltet und werden beim ersten Besuch ergänzt (eine kleine
  Blitzer-Abfrage). Eine frische, vollständige Kachel im Cache überschreibt der Länderlauf nicht.
- Der Lauf steht in der Warteschlange hinter allem anderen (`countryPriority`) und nutzt den Einzelplatz der
  Nachbarschichten; die Blitzer der Fahrt haben immer einen freien Platz. Fehler (Überlast, Abbruch, Müll)
  kommen als `CountryLoadResult.error`; nichts wird geschrieben, wenn die Antwort nicht lesbar ist.
- Wann er läuft, entscheidet das Repository (`CountryLoader` in `features/alerts`).

## Umkreis und Datenmenge

Zwei Radien (`DataScope`): **Blitzer, Kontrollen und Plugins** folgen `detailRadiusMeters` (2–50 km). **Ampeln und
Tempolimits** (beide Schichten) laden nur im festen kleinen Umkreis `layersRadiusMeters` (das Kleinere aus
Einstellung und 3 km), denn sie machen fast die gesamte Datenmenge aus und werden nur dort gebraucht, wo man gerade
fährt.

- **Blitzer im großen Umkreis:** das Repository zerlegt den Kreis in Blöcke bis 0,49° und ruft `loadCameras` je
  Block (nur Fehlendes, eine Anfrage je Block); 50 km sind 6 Blöcke. Neu laden nach einem Viertel des Radius.
- **Ampeln und Tempolimits:** `load` um die Position mit dem kleinen Radius, neu nach einem Viertel davon
  (750 m bei 3 km, mindestens 300 m).
- **Reihenfolge der Warteschlange:** Blitzer, dann die Tempolimits (Hauptstraßen und Nebenstraßen der gleichen Zelle
  zusammen, die Zelle unter der Position zuerst), dann Ampeln, dann Übersicht, dann Deutschland. Die erste Anfrage
  läuft sofort und ist die Zelle unter der Position.
- **Obergrenzen:** Ein `load` fordert höchstens 16 Ampel-Kacheln und je 20 Tempolimit-Zellen an (`OsmLayer.maxTilesPerLoad`),
  die nächsten zuerst; im 3-km-Kreis sind das nur rund 4 und 12.
- **Vorausladen (`speedLimitAt`):** Jeder Aufruf stellt sicher, dass die Tempolimit-Zellen unter der Position und
  3,5 km voraus (Kurs) geladen sind, mit Abstand 0 in der Warteschlange, also vor dem Rest der Umgebung. Fehlendes
  wird angefordert, Frisches und Gesperrtes nicht; ohne Netz greift die Funkloch-Pause.
- **Kleinere Zellen helfen auf der Autobahn nicht:** Eine Abfrage dauert 25–40 s, egal ob 2 kB oder 2,9 MB groß
  (Wartezeit beim Server, gemessen). Kleinere Zellen bedeuten mehr Anfragen je Kilometer, also weniger Durchsatz
  (rund 90 Anfragen je Stunde). Die Vorausschau (150 s) ist länger als eine Abfrage samt einer laufenden davor
  (bis 80 s), die Zelle voraus ist also meist rechtzeitig da; eine Verspätung über 100 s (überlasteter Server)
  ändert auch eine kleinere Zelle nicht. Darum bleiben die Zellen bei 0,05°.

### Schnell oder langsam

`speedLimitAt` schätzt aus den Aufrufen (Positionen und Zeit) das Tempo und merkt sich den Kurs (`_Motion`). Ab
**65 km/h über 8 s** gilt „schnell“ (Landstraße, Autobahn), zurück auf „langsam“ unter **50 km/h über 8 s**. Ein
kurzer Ausreißer oder ein kurzes Bremsen kippt nichts; nach einer Lücke von über 15 s (Tunnel) bleibt der Zustand
und das Tempo wird neu gemessen. Unbekanntes Tempo zählt als langsam (alles laden). Die Fahrterkennung (15 und
8 km/h) ist davon unabhängig. Schnell heißt:

- **keine Nebenstraßen und keine Ampeln.** Fehlt eine Nebenstraße, bleibt es bei „Limit unbekannt“, nie ein
  falscher Wert; sobald man wieder langsam fährt, kommt die Zelle unter der Position zuerst.
- **Tempolimit-Zellen nur entlang des Kurses:** Stichproben alle 1,5 km bis zur Vorausschau (Tempo × 150 s, mindestens
  3,5 km, höchstens 8 km, bei 120 km/h knapp 5 km). Ohne Kurs nur die eigene Zelle. Seitenzellen kommen erst, wenn
  der Kurs dorthin zeigt. Das gilt für `load` (Zellen im 3-km-Kreis) und für das Vorausladen in `speedLimitAt`.

## Datensparen

- **Nur Fehlendes:** Eine Kachel wird nur geladen, wenn sie fehlt oder älter ist als ihre Frist: Blitzer 7 Tage,
  Ampeln und Tempolimits 30 Tage (`maxAge`, `detailMaxAge`). Gleiche Kacheln laufender Abfragen teilen sich eine
  Anfrage. Der Umkreis wandert nach einem Viertel des Radius weiter (`DataScope`); bekannte Kacheln kosten nichts.
- **gzip:** Jede Anfrage sendet `Accept-Encoding: gzip`, Overpass komprimiert auf rund ein Fünftel. Alle Größen
  hier sind übertragene Bytes.
- **Schlanke Tempolimit-Abfrage:** Statt `out geom` (alle Tags, Knoten-IDs, Geometrie) liefert `convert item` nur
  `highway`, `maxspeed`, `maxspeed:forward/backward`, `oneway`, `junction` und die Geometrie als GeoJSON; der Parser
  macht daraus dieselben Wege wie vorher (leere Tags gelten als fehlend, Flächen als äußerer Ring). Keine
  Information geht verloren, die `speedLimitAt` nutzt. Gemessen am 30.10.2026 (übertragen, vorher → nachher):
  Berlin Hauptstraßen-Zelle 445 → 101 kB (−77 %, 2,9 → 0,85 MB Text), Berlin Nebenstraßen-Zelle 445 → 118 kB (−73 %),
  A9-Nebenstraßen 5,0 → 2,8 kB, Uckermark 2,75 → 1,7 kB. `out tags geom` hätte die Knoten-IDs gespart, aber nicht die
  Tags und ließ sich wegen Serverüberlast nicht messen.
- **Funkloch:** Ohne Netz wird eine Kachel nach dem ersten Fehlschlag 1 min, dann 2, 5, 15 und höchstens 30 min nicht
  mehr angefragt (`osm_source_backoff.dart`); ein Erfolg setzt zurück. Überlast hat eigene Pausen (30/60/120 s).
- **Deutschland:** standardmäßig aus, höchstens wöchentlich (1,2 MB). Eine WLAN-Erkennung gibt es nicht; ohne
  Paket dafür ist das Wochenmaß die Grenze.

Schätzung je Stunde Fahrt auf Neuland (erste Fahrt, nichts im Cache), übertragene Bytes, mit schlanker Abfrage
und Tempoverhalten. Gemessen sind die Zellgrößen (Berlin dicht: Hauptstraßen 5,3 + Nebenstraßen 6,2 = 11,5 kB/km²,
Ampeln 0,4 kB/km²; mittelgroße Stadt rund 40 %; Kassel-Rand Hauptstraßen 0,8 kB/km², Thüringer A9 rund 0,4 kB/km²,
Uckermark rund 0,1 kB/km²), die Fahrten selbst sind gerechnet. Stadt (langsam): Weg × 10,5 km Streifen (2 × 3 km
plus Zelle) × Dichte, dazu Ampeln im 15-km-Streifen. Autobahn (schnell): nur Hauptstraßen und nur die Zellen auf dem
Weg, 120 km ÷ 4,5 km ≈ 27 Zellen zu 4 kB (Land), 15 kB (Stadtrand), 100 kB (Stadtautobahn). Blitzer: Weg × (2 × Radius
+ eine Kachel) × 14 B/km² (Berlin) bzw. 5 B/km² (Autobahn).

| Fahrt | 5 km Umkreis | 25 km Umkreis |
|---|---|---|
| Stadt, 30 km/h (30 km Weg) | rund 1,5 MB (mittelgroße Stadt), Berlin-dicht bis 3,8 MB; davon Blitzer 7 kB | gleich; davon Blitzer 24 kB |
| Autobahn, 120 km/h (120 km Weg) | rund 0,4 MB (0,1 MB auf dem Land bis 1 MB mit Stadtdurchfahrt); davon Blitzer 10 kB | gleich; davon Blitzer 35 kB |

Vorher (ohne schlanke Abfrage, alle Schichten): Stadt rund 6 MB bis 15 MB, Autobahn rund 4 MB. Der Umkreis ändert die
Datenmenge kaum, weil Ampeln und Tempolimits fest bei 3 km bleiben und Blitzer klein sind. Plugins sind nicht
eingerechnet. Wiederholte Strecken kosten nichts (Tempolimits 30 Tage, Blitzer 7 Tage). Anfragen je Stunde: Stadt rund
40, Autobahn rund 22–35 (vorher 55–130) bei 90 möglichen.

## Wenn das Tempolimit fehlt

Gemessen am 30.10.2026 in Hamburg-Wandsbek (53,57–53,60 N, 10,05–10,11 O): 1542 Straßenabschnitte (Hauptstraße bis
Wohnstraße), Stichprobe alle 40 m in Fahrtrichtung durch `speedLimitAt`, nachdem die Zellen vollständig geladen waren.
4671 Stichproben, **100 ohne Limit (2 %)**: Hauptstraßen 0 %, Wohnstraßen mit `maxspeed` 1 %, Straßen ohne Tag selten
(`living_street` 76 %, siehe unten). Hamburg ist also fast lückenlos getaggt; die Zuordnung (Weg, Kurs, Einbahn) ist
nicht die Ursache. **Ursache ist die Verfügbarkeit:** Dieselben 8 Zellen (4 Hauptstraßen, 4 Nebenstraßen) brauchten
auf dem öffentlichen Server **21 Minuten** (Überlast 502/504, Pausen von 30–120 s je Endpunkt, Abfragen von 25–40 s);
der Server war im Test zeitweise zu 30–50 % der Anfragen nicht erreichbar. Auf der Landstraße kommt dazu, dass
dort meist kein `maxspeed` steht (die Uckermark-Zelle liefert 1,7 kB für 5 km²): gesetzlich 100 km/h, in OSM nicht erfasst.

Was die App jetzt tut:

- **Limit halten:** Findet `speedLimitAt` keinen Weg, gilt das letzte Limit weiter, wenn es nicht länger als 15 s her ist,
  höchstens 150 m Strecke und höchstens 35° Kursabweichung (Kreuzung, Lücke im Tagging, Knick). Danach unbekannt.
- **Verkehrsberuhigter Bereich:** `living_street` ohne `maxspeed` gilt als 7 km/h (Schrittgeschwindigkeit), mit Angabe
  gilt die Angabe. Andere Klassen werden nicht geraten.
- **Speicher:** Blitzer- und Ampelkacheln verdrängen zuerst, die Tempolimit-Zellen zuletzt und gelten bei jeder
  Abfrage als benutzt. Vorher konnten 40 Kamerakacheln (großer Umkreis) die Wege aus dem Speicher werfen, das Limit
  war dann bis zum erneuten Lesen unbekannt.

Vorschläge, nach Wirkung und Aufwand:

1. **Größere Zellen für die Tempolimits (0,1° statt 0,05°)**, Aufwand mittel (ein Tag, viele Tests ändern sich, der
   alte Cache wird nicht mehr genutzt). Seit der schlanken Abfrage kostet eine Zelle in Berlin nur noch 100 kB; die
   Wartezeit je Abfrage (25–40 s) ist fest. Vier Mal größere Zellen heißen vier Mal weniger Abfragen und damit etwa
   ein Viertel der Zeit bis zum Limit (aus 21 Minuten würden rund 6), bei gleichen Gesamtdaten. Auf dem Land gewinnt
   das am meisten.
2. **Bis auf Weiteres der gleiche Mechanismus mit Vorlauf im Stand:** Beim Start und bei Fahrtbeginn die Zellen im
   3-km-Kreis sofort holen (macht `load` schon); Aufwand klein, bringt nur, wenn der Server gerade antwortet.
3. **Abgleich für die Landstraße** (Gesetz: 100 außerorts, 50 innerorts): braucht ein Merkmal „geschätzt“ am Limit
   (Vertrag: `speedLimitAt` liefert nur eine Zahl) und die Siedlungsflächen aus OSM (`place`, `landuse`), um innerorts
   nicht 100 zu zeigen. Aufwand mittel bis groß; ohne Kennzeichnung nicht umsetzen, ein falsches Limit ist schlimmer
   als keines.
4. **Vorab gebautes Tempolimit-Paket je Bundesland** (siehe unten), Aufwand groß, löst Verfügbarkeit und Landstraße
   ohne Live-Abfrage.
5. **Weitere Overpass-Spiegel:** Es gibt keinen freien, global abdeckenden dritten Spiegel: laut OSM-Wiki sind die
   übrigen Instanzen kostenpflichtig, an Schlüssel gebunden oder regional (CH, GB, Virginia); `maps.mail.ru` ist
   erreichbar, aber russisch, und würde Standortausschnitte dorthin senden. Nicht empfohlen.

### Tempolimit-Paket je Bundesland

> Die Pakete erscheinen in einem eigenen Paket-Repository, das noch nicht öffentlich ist. Bis dahin ist die
> Auswahl in der App ausgeblendet (`limitPackagesPublished` in `limit_download.dart`); die Verweise unten auf dieses
> Repository und seine Werkzeuge gelten, sobald es öffentlich ist.

Stand: `limits_format.dart` (Format, Schreiben, Lesen) und `osm_way_limits.dart` (die Regeln „Weg → Limits“, von
Parser, Abfrage und Paket gemeinsam benutzt) liegen hier. Den **Generator** und den Wochenlauf, der die Pakete baut
und veröffentlicht, liegt im Paket-Repository (noch nicht öffentlich); dort sind Format und
Regeln als Kopie, geprüft über gemeinsame Fixtures (`test/osm/parity/` hier, `test/fixtures/` dort,
`test/osm/limits_parity_test.dart`). Ändert sich Format oder Regel, ändern sich Fixtures und Versionsnummer in
beiden Repositories.

- **Format:** eine Datei je Land, Zellen von 0,05° wie der Overpass-Cache (`fineTilesPerDegree`), je Zelle ein
  einzeln deflateter Block, dazu ein Index: man liest nur die Zellen, die man braucht. Je Weg: Einbahn, Nebenstraße
  (nur bei langsamer Fahrt nötig), Limit vor/zurück (0 = keines), Punkte als Zickzack-Varints in 1e-7° (Auflösung von
  OSM, verlustfrei) oder gröber (`Raster` 10 oder 100). Wege über Zellkanten werden in Stücke je Zelle geteilt, die den
  Kantenpunkt teilen. Kopf: Kennung, Stand (JJJJMMTT), Raster; je Zelle ein Flag „liegt ganz im Gebiet“ (für
  „hier braucht es kein Overpass“, nur mit `--poly` gesetzt).
- **Gleichstände:** An Kreuzungen liegen Haupt- und Nebenstraße mit Abstand 0 am Punkt; `pickSpeedLimit` nimmt den
  ersten. Overpass liefert erst die Haupt-, dann die Nebenschicht, das Paket schreibt je Zelle ebenso Hauptstraßen
  zuerst; der Leser setzt die Wege aller Zellen in dieser Reihenfolge zusammen (erst alle Haupt-, dann alle Nebenstraßen).
- **Gemessen (Hamburg, Auszug vom 28.10.2026):** 35 609 Wege mit Tempoangabe, 230 239 Punkte, 69 Zellen.
  Raster 1: 968 kB (27,8 Byte je Weg), Raster 10: 762 kB, Raster 100: 520 kB. Bremen (15 695 Wege): 417 kB.
  Hochgerechnet auf 2,56 Mio. Wege in Deutschland: 71 MB (Raster 1), 56 MB (10), 38 MB (100); je Land 0,4–11 MB.
  Der Block ist schon deflatet, ein weiteres Zippen spart nichts. Getrennte Ströme für Breite und Länge oder
  Vorhersage der Richtung brachten höchstens 2,5 %, deshalb nicht übernommen.
- **Gleichheit mit Overpass** (Wandsbek 53,55–53,65 N / 10,05–10,15 O, die vier Zellen, die der frühere Overpass-Lauf
  geladen hatte, 67 512 Stichproben je 40 m in beide Richtungen, schnell und langsam): mit Raster 1 in **allen**
  Stichproben dasselbe Limit (30 630 + 15 602 mit Limit, dazu 18 162 ohne Limit in beiden). Raster 10: 99,9 % gleich
  (55 abweichende Gleichstände an Kreuzungen), Raster 100: 99,8 % (132 von 64 400). Wo Overpass die Nebenzelle nicht geliefert hatte
  (`minorLimits` 1072/201), liefert das Paket in 143 Stichproben ein Limit mehr oder ein anderes: das ist der Gewinn.
- **Etappe 2 (in der App eingebunden, ohne Oberfläche):**
  - `LimitPackages` (`limit_packages.dart`) verwaltet `<kennung>.sblp` in `<cacheDir>/limit_packages/`; das Leeren
    des Kachel-Caches lässt sie stehen und `cacheSizeBytes` zählt sie nicht. `OsmSource.packages` ist das Objekt,
    `createOsmSource(limitPackages: …)` nimmt ein eigenes (Etappe 3 teilt es mit der Oberfläche).
  - `speedLimitAt` nimmt die Wege der 3×3 Zellen aus dem Overpass-Speicher **und** aus den Paketen (Hauptstraßen vor
    Nebenstraßen; bei schneller Fahrt ohne Nebenstraßen, wie bei den Overpass-Schichten). Zellen eines Pakets werden
    einzeln gelesen und bleiben 80 Stück im Speicher.
  - Zellen mit Flag „ganz im Gebiet“ gehen weder in `load` noch in die Zellenvorausschau (`_ensureRoadCells`): keine
    Overpass-Abfrage nach Tempolimits dort. Randzellen (Gebietsgrenze schneidet sie) nutzen das Paket **und** fragen
    Overpass weiter. Blitzer und Ampeln bleiben unberührt. Aus einem Einzelauszug (am Landesumriss abgeschnitten)
    waren nur 38 von 82 Hamburger und 6 von 44 Bremer Zellen vollständig; mit dem Deutschland-Auszug (unten) sind es alle
    Zellen im Inland.
  - `LimitDownloader` (`limit_download.dart`) liest das Verzeichnis `packages.json` und lädt ein Paket erst auf Aufruf:
    Größe und SHA-256 aus dem Verzeichnis werden beim Laden geprüft, danach Kopf (Kennung und Stand müssen zum
    Verzeichnis passen); erst dann wird atomar installiert. Bei jedem Fehler (Netz, Größe, Prüfsumme, kein Paket)
    bleibt die ältere Fassung und es bleibt keine Teil-Datei. Unterwegs im Zählen und Hashen, ohne das Paket im
    Speicher zu halten. Das Verzeichnis hat die Form
    `{"format":1,"packages":[{"id","name","date","bytes","sha256","file"}]}`, `file` relativ zur Adresse des Verzeichnisses.
  - Echtlauf: das Hamburg-Paket (Raster 10, mit Umriss) in einer `OsmSource` ohne Netz gegen die Overpass-Zellen von
    Wandsbek: 9 309 Stichproben mit Overpass-Limit, 9 292 gleich, 17 anders (Gleichstände an Kreuzungen, wie bei Raster 10
    zu erwarten), **0 Overpass-Anfragen**, 449 ms für alle.
- **Alle 16 Länder (Deutschland-Auszug):** Der Generator im Paket-Repository liest `germany-261029.osm.pbf` (4,87 GB) einmal
  (rund 3 Minuten, 2 788 110 Wege mit Tempoangabe) und schreibt alle Pakete mit Raster 10. Jede Zelle bekommt alle
  ihre Wege, auch über Landesgrenzen hinweg, und gehört genau einem Land (Mitte der Zelle); Berlin, Bremen und Hamburg
  stehen in der Reihenfolge vorn, weil Geofabriks Umrisse von Brandenburg und Niedersachsen sie einschließen.
  „Vollständig“ ist jede Zelle, deren neun Prüfpunkte in irgendeinem Land liegen: 19 570 von 20 364; unvollständig
  bleiben nur Zellen an der Außengrenze und an der Küste (Saarland 112 von 140, Sachsen 906 von 997).

| Land | Größe | Zellen | davon vollständig |
|---|---:|---:|---:|
| Baden-Württemberg | 9.495 kB | 1845 | 1745 |
| Bayern | 11.018 kB | 3530 | 3362 |
| Berlin | 1.409 kB | 52 | 52 |
| Brandenburg | 2.310 kB | 1637 | 1586 |
| Bremen | 298 kB | 21 | 21 |
| Hamburg | 730 kB | 69 | 69 |
| Hessen | 5.352 kB | 1078 | 1078 |
| Mecklenburg-Vorpommern | 1.439 kB | 1814 | 1759 |
| Niedersachsen | 7.057 kB | 2973 | 2896 |
| Nordrhein-Westfalen | 11.609 kB | 1812 | 1707 |
| Rheinland-Pfalz | 3.987 kB | 1015 | 964 |
| Saarland | 968 kB | 140 | 112 |
| Sachsen | 3.241 kB | 997 | 906 |
| Sachsen-Anhalt | 3.450 kB | 1067 | 1067 |
| Schleswig-Holstein | 2.440 kB | 1522 | 1454 |
| Thüringen | 1.813 kB | 792 | 792 |
| **Summe** | **65,1 MB** | **20 364** | **19 570** |

  Hamburg aus dem Deutschland-Auszug gibt in den Wandsbek-Stichproben dieselben Zahlen wie das Einzelpaket (9 292 von
  9 309 gleich, 17 Gleichstände, 0 Overpass-Anfragen); die Zellen sind jetzt alle vollständig (69 statt 38). Bremen hat
  21 statt 6 vollständige Zellen; gegenüber dem Bremen-Einzelpaket fehlt kein Stück, 1 025 kommen in 12 Randzellen dazu.
- **Etappe 3 (Einstellungen, Einstieg in der App):**
  - `AppServices` hält `limitPackages` und `limitDownloader`; dasselbe `LimitPackages` liest die Quelle. Die Adresse ist
    fest (`limitCatalogUrl` in `limit_download.dart`) und zeigt auf das jeweils neueste Release des Paket-Repositorys;
    sie antwortet erst, wenn dieses öffentlich ist.
  - **Einstellungen → Daten → „Tempolimits ohne Netz“** (`lib/features/settings/limit_packages_*.dart`): Liste der 16
    Länder mit Größe und Stand, Laden mit Rückfrage („am besten im WLAN“) und Fortschritt, Aktualisieren, wenn ein neuerer
    Stand da ist, Löschen mit Rückfrage. Berlin, Bremen und Hamburg tragen den Hinweis, in welchem Paket ihr Umland liegt
    (`cityStateHints`); darunter steht „© OpenStreetMap-Mitwirkende, ODbL“.
  - **Vorschlag fürs eigene Land:** `land_at.dart` ordnet eine Position über ein grobes Raster von 0,1° (`land_grid.dart`,
    aus den Landesumrissen erzeugt von einem Werkzeug im Paket-Repository) einem Land zu. Solange kein Paket
    geladen ist, nennt die Zeile in „Daten“ das Land („Du bist in Hamburg: Paket laden empfohlen“) und der Bildschirm
    zeigt oben eine Karte mit Größe und „Laden“. Am Landesrand kann das Raster daneben liegen; es ist nur ein Vorschlag.
  - **Netz nur auf Wunsch:** das Verzeichnis wird nur beim Öffnen des Bildschirms abgerufen, ein Paket nur nach der
    Rückfrage. Nichts läuft im Hintergrund oder während der Fahrt. Antwortet die Adresse nicht (kein Netz, Repository noch
    nicht öffentlich, 404), steht im Bildschirm ruhig „Pakete gerade nicht erreichbar“ mit „Erneut versuchen“; geladene
    Pakete funktionieren weiter. Kein Ton, kein roter Hinweis.
  - **Offen:** eine Prüfung auf neuere Stände ohne den Bildschirm (zum Beispiel einmal die Woche im WLAN) gibt es noch nicht;
    wer aktuell bleiben will, öffnet den Bildschirm.
- **Datenschutz:** Das Paket kommt von einem festen Server (später GitHub Releases o. ä.) und enthält keine
  Nutzerdaten; der Server sieht nur IP-Adresse und den Dateinamen des gewählten Landes (also grob, in welchem Land
  man sich aufhält), nie Positionen. Das ist ein **neuer Abrufort** neben Overpass; die Datenschutzerklärung nennt
  ihn, sobald die App ihn benutzt (Etappe 2).

## Weite Ausschnitte (nur Cache)

`loadCameras` für einen Ausschnitt über 0,5° Kantenlänge (`cacheOnlySpanDeg`) lädt nichts: es liest die
Blitzer-Kacheln aus Speicher und Cache-Ordner, egal wie alt (`fromCache: true`). Höchstens 6000 Kacheln (ganz Deutschland hat rund 4800)
(`maxCachedTilesPerView`), die mittennächsten zuerst. Die Kacheln werden dabei nicht in den Speicher
übernommen, damit sie die Tempolimit-Wege nicht verdrängen. So zeigt die Deutschlandansicht, was einmal
geladen wurde.

## Kartenübersicht (`loadCameras`)

Nur die Blitzer-Schicht für einen größeren Ausschnitt (das Repository begrenzt auf `maxOverviewSpanDeg`).
Gleiche Kacheln und gleicher Cache wie `load`: Treffer kommen sofort, fehlende Kacheln gehen gemeinsam in einer
Anfrage über ihre Hülle. Die Anfrage läuft über den Einzelplatz der Nachbarschicht-Abfragen (dieselbe Schlange
wie Ampeln und Tempolimits) mit der Dringlichkeit `overviewPriority`: nach Blitzern und Ampeln der Fahrt, vor den
Tempolimits. So blockiert sie die Blitzer-Abfrage der Fahrt nie, die immer einen freien Platz hat. Eine Kachel,
die die Fahrt schon holt, wird mitbenutzt; umgekehrt hängt sich die Fahrt nie an eine wartende Übersichts-Anfrage.
Kein Wiederholen mit Wartezeit: bei Überlast kommt `SourceResult.error`, und das Repository fragt später neu.

## Details und Quellen am Punkt

Jede Messstelle trägt `AlertPoint.details` (Antippen auf der Karte) und `AlertPoint.sources`. Übersetzt werden nur
verständliche Werte, rohe Tags und leere Angaben erscheinen nicht. Reihenfolge: Kontrolle (`enforcement`), Erlaubt
(`maxspeed`, auch aus der Relation oder dem Geräteknoten), Seit (`start_date`), Richtung (in Worten, „beide
Richtungen“ nur bei `direction=both`, sonst „unbekannt, warnt in beide Richtungen“), Straße (Name und Kennung des
wichtigsten Wegs am Knoten, den die Abfrage ohnehin liefert), Bauart (`camera:type`), Montage (`camera:mount`),
Technik (`surveillance:type`), Zuletzt geprüft (`check_date`, `survey:date`), Betreiber, Name, Kennung, Hinweis
(`note`), Beschreibung (`description`). Daten wie `~2015` oder `2021-13` werden nicht gezeigt. Bei Relationen gelten
die Tags der Relation vor denen des Geräteknotens.

`PointSource`: `OpenStreetMap`, „© OpenStreetMap-Mitwirkende, ODbL“, Link auf `node/…` bzw. `relation/…`, Stand =
`timestamp` der letzten Bearbeitung (Relation und Geräteknoten: der neuere). Dafür holt die Blitzer-Abfrage Knoten
und Relationen mit `out meta`; das ergänzt je Element nur Version, Zeitstempel und Bearbeiter (bei 91 Messstellen
rund 10 kB mehr) und lässt die Abfrage sonst unverändert. Die Wege (`.camways`) kommen weiter ohne `meta`.
Ampeln und Tempolimit-Wege haben keine Details.

Im Cache liegen Details und Quellen mit (`d`, `q`; nur Zeitstempel und Link der Quelle, der Rest ist fest).
Blitzer-Kacheln tragen `x: 2` (`pointDetailVersion`). Eine Datei ohne `x` lädt weiter, gilt aber als veraltet und
wird beim nächsten Abruf erneuert; schlägt der fehl, dient sie als Rückfall.

Tempolimit-Kacheln (`limits`, `minorLimits`) haben eine eigene Version: `x: 5` (`wayDetailVersion`; 4: „kein Limit“ als
`speedWayNoLimit` statt `null`; 5: Straßenart `h`, Nebenstraße `mi`, Name `n`, ref `r`, Rampe ohne Limit `u`). Ältere Kacheln
(`x: 4` und älter) laden weiter, ohne Straßenart, also ohne Linie voraus. Sie gelten als veraltet und werden beim nächsten Bedarf erneuert, bis dahin bleiben sie in
Gebrauch; die Blitzer-Kacheln (`pointDetailVersion` 3) und die Ampeln bleiben unberührt, ein Nutzer lädt also nur die
Tempolimit-Zellen neu, durch die er fährt (etwa 100 kB je Zelle). Wird die Version der Tempolimit-Kacheln wieder
angehoben, nur `wayDetailVersion` erhöhen.

### Dubletten aus zwei Quellen

`lib/features/alerts/merge_points.dart` legt feste Blitzer aus OSM und aus Plugins zusammen (OSM vor Plugin, Richtung aus
der Quelle, die eine hat). Worauf die Regeln Rücksicht nehmen:

- **Ein Punkt oder zwei je Stelle:** Manche Quellen liefern einen Punkt mit beiden Richtungen (`175°/355°`), OSM oft je
  einen Punkt je Richtung.
- **Abstand:** Dieselbe Messstelle liegt in zwei Quellen meist wenige Meter, oft bis gut 30 m und im Einzelfall bis
  100 m auseinander. Eine feste Grenze von 40 m allein ließ solche Paare getrennt.
- **Richtung:** Quellen geben teils die Blickrichtung der Kamera an, teils die Straßenachse oder die Fahrtrichtung;
  dieselbe Kamera kann deshalb um 90° und mehr abweichende Richtungen tragen.
- **Regel:** Richtungen vertragen sich bis 75° (`mergeBearingToleranceDeg`; unter 90° bleiben Gegenrichtungs-Punkte sicher
  getrennt, und ein Punkt mit beiden Richtungen passt nie zu beiden Gegenrichtungs-Punkten). Bis 40 m immer,
  bis 100 m (`fixedWideMergeMeters`) nur, wenn keine weitere Messstelle der anderen Quelle im Umkreis zur Richtung passt.
- Nahe Paare mit größerem Richtungsunterschied bleiben getrennt; ob es echte Doppel (Kreuzung, zwei Straßen) oder
  uneinheitliche Richtungsangaben sind, lässt sich aus den Daten nicht sagen.

#### Abstände je Art (Stand 3.11.2026)

Gemeinsame Regeln: verschiedene Quellen, gleiche Gruppe, Richtungen widersprechen sich nicht (bis 75°); je Quelle nimmt ein
Kern nur den nächsten Punkt auf; Quellen, Details und Richtung bleiben am zusammengeführten Punkt. Kern (Position, ID,
Art): bei festen Blitzern, Baustellen und Gefahren OSM vor den Plugins (die Kamera steht als Symbol auf der Karte), bei
mobilen Blitzern die Plugins vor OSM (sie kennen die aktuelle Stelle).

| Gruppe | immer derselbe | weiter nur bei eindeutigem Partner |
|---|---|---|
| feste Blitzer (Tempo, Rotlicht, Abschnittsanfang) | bis 40 m | bis 100 m; Plugin-Punkt an OSM-Kamera bis 200 m, wenn die Richtungen bestätigt übereinstimmen (höchstens 30°) oder beide dasselbe Tempolimit kennen |
| mobile Blitzer, Blitzeranhänger | bis 150 m | bis 250 m, wenn beide Richtungen angeben und höchstens 30° auseinanderliegen |
| Baustellen (Dauer, Tag, Sperrung) | bis 150 m, wächst mit der Summe der Radien beider Punkte, höchstens 1,5 km | nein |
| Gefahrenmeldungen, nur gleiche Art | bis 150 m, wächst mit der Summe der Radien, höchstens 300 m | nein |

„Eindeutig“: Keine weitere Stelle der Gruppe aus der Quelle des Partners liegt im weiten Umkreis, die zur Richtung passt.
Ausnahme feste Blitzer, OSM gegen Plugin: Die Paare entstehen nach Abstand, das nächste Paar zuerst. OSM führt an
Straßen mit Blitzern in beiden Richtungen oft zwei Knoten 100 bis 150 m auseinander. Jede OSM-Kamera nimmt je Anbieter den nächsten passenden Punkt auf, auch wenn ein weiterer OSM-Knoten in der Nähe
liegt. Was übrig bleibt, bleibt ein eigener Punkt, nichts wird verworfen. Zwei Punkte derselben Quelle neben einer
Kamera: der nähere wird aufgenommen. Ohne OSM gilt weiter die strenge Regel.

Richtung bei festen Blitzern, OSM gegen Plugin: Ein Plugin-Punkt bis 30 m von einer OSM-Kamera, von jeder anderen OSM-Kamera
mindestens dreimal so weit (und 60 m) entfernt, gehört zu ihr, auch wenn die Richtungen bis 150° abweichen (Quellen geben
Fahrtrichtung, Blickrichtung und Straßenachse an). Gegenrichtung (über 150°) bleibt eine eigene Kamera. Punkte mit dem Detail
„Ausrichtung: Drehbar“ (so von manchen Quellen geliefert) messen in jede Richtung, ihre Richtung zählt nie. Zwei OSM-Knoten am selben Mast bleiben getrennt.

„Anbieter“: Bündelt ein Plugin mehrere Quellen, zählen die Einträge in `AlertPoint.sources` einzeln. Liefert ein
solches Plugin an einer Kamera zwei Punkte (weil seine Anbieter weiter auseinanderliegen, als es selbst zusammenführt),
verschmelzen beide mit der OSM-Kamera. Punkte desselben Plugins untereinander werden nicht zusammengeführt.
Zwei echte Stellen hintereinander (je Quelle zwei Punkte, 120 m fest oder 200 m mobil) bleiben deshalb zwei. Nie
zusammengeführt: Abschnittsende, Höhen-, Gewichts-, Einfahrts- und Überholkontrollen, Ampeln, Hotspots, vergangene
Beobachtungen. Radien von Baustellen sind die Ausdehnung der Strecke, die von Gefahren Warnradien: darum die kleinere Grenze.

## Feine Art (`AlertPoint.category`)

`classifyEnforcement` (`osm_category.dart`) setzt Kind und Kategorie aus `enforcement` (Semikolon-Liste), den
Tags von Relation und Geräteknoten und dem Weg am Gerät. Bei mehreren Werten gilt die Reihenfolge Abschnitt,
Rotlicht, Tempo, Abstand, Höhe, Gewicht, Einfahrt, Überholverbot.

| OSM | Kind | Kategorie |
|---|---|---|
| Blitzerknoten, `enforcement=maxspeed` | `speedCamera` | `fixedSpeed`; Weg mit `tunnel=yes` oder Knoten-Tag → `tunnelSpeed`; `camera:type=mobile` → `mobileSpeed`; `camera:mount=trailer` → `semiStationary` |
| `traffic_signals` | `redLightCamera` | `fixedRedLight`; zusammen mit `maxspeed` → `speedCamera`/`fixedRedLightSpeed` |
| `average_speed`, `section_control` | `sectionControl` | `sectionStart` (Rolle `from`); mit Rolle `to` ein zweiter Punkt `osm:relation/<id>#end` → `sectionEnd` |
| `mindistance` | fest: `speedCamera`, `camera:type=mobile`: `live` | `fixedSpeed` bzw. `mobileDistance` |
| `maxheight`, `maxweight`/`weight`, `access`, `noovertaking`/`no_overtaking` | `construction` (nur Ansage) | `heightControl`, `weightControl`, `accessControl`, `noOvertaking` |

`check`, `toll`, `seatbelt`, `mobile_phone` ergeben keine Relation-Punkte; ein Blitzerknoten mit unbekanntem
`enforcement` bleibt `fixedSpeed`. `maxSpeed` tragen nur Kategorien mit `showsSpeed`. Die Relationssuche für
Höhe, Gewicht, Einfahrt und Überholverbot läuft per Rechteck (`rel(bbox)`), weil diese Geräte keine
`speed_camera`-Knoten sind; die übrigen Relationen kommen weiter über `rel(bn.cams)`. Der Filter auf `enforcement`
ist ohne `^…$`, damit Listen wie `maxspeed;traffic_signals` treffen. Die Kategorie liegt im Cache (`c`), eine
unbekannte oder fehlende Kategorie ergibt `null` (dann gilt die Standardableitung); `pointDetailVersion` ist 3.

## Cache

Eine JSON-Datei je Schicht und Kachel direkt in `cacheDir` (`<schicht>_<iy>_<ix>.json`, atomar geschrieben).
Gespeichert werden geparste Punkte und Tempolimit-Wege, nicht das rohe Overpass-JSON. Älter als 7 Tage = neu
laden; schlägt das fehl, werden die alten Daten mit `SourceResult.error` geliefert. Nach einem Fehlschlag wird
dieselbe Kachel mindestens 60 s (oder bis zum Ende der Endpunkt-Pause) nicht erneut abgefragt. Kaputte Dateien
gelten als fehlend. Frühere Fassungen (`osm/osm/t_*.json`, 0,1°-Kacheln mit allem) werden beim ersten Zugriff
gelöscht; `clearCache` entfernt nur eigene Dateien.

## Auslegung von `direction` bei `highway=speed_camera`

Quellen: OSM-Wiki `Tag:highway=speed_camera` (nennt `direction` nur als „the way the speed camera faces“, ohne
Festlegung), `DE:Tag:highway=speed_camera` („Richtung der Messung“), `Key:direction` (Grad, Himmelsrichtungen mit
bis zu 16 Punkten, `forward`/`backward`/`both` für Knoten auf einem Weg) und `Relation:enforcement`
(Wirkrichtung = Reihenfolge `from` → `to`/`device`). Die Wiki ist bei Kameras nicht eindeutig. Gewählt:

- `direction` gilt als **Fahrtrichtung der kontrollierten Fahrzeuge** (Richtung der Messung), nicht als Blickrichtung
  des Geräts. `AlertPoint.travelBearings` enthält genau diese Kurse. Ein Frontblitzer, der gegen den Verkehr blickt,
  müsste nach strenger Wiki-Lesart „faces“ die Gegenrichtung tragen; das wird nicht umgedeutet, weil Mapper meist
  die Messrichtung eintragen.
- Grad (`90`, `87,5`), Himmelsrichtungen (`N` … `NNW`, auch `north`), Listen (`90;270`), Bereiche (`67-292` → Mitte
  des Bogens) werden gelesen.
- `forward`/`backward` sind relativ zur Wegrichtung am Knoten (`out geom` des Weges, Peilung des Segments ab dem
  Knoten). Liegt der Knoten auf mehreren Wegen, zählt der wichtigste Straßentyp. Ohne Weg: leer.
- `both`, `all`, `forward;backward` → leer (gilt in jede Richtung).
- `camera:direction` wird genutzt, wenn `direction` fehlt oder unverständlich ist.
- Ohne verwertbare Angabe auf einer Einbahnstraße (`oneway`, Kreisverkehr, Autobahn) gilt die Einbahnrichtung,
  sonst leer.
- Unbekannt oder unverständlich → leer: lieber in beide Richtungen warnen als gar nicht.
- Enforcement-Relationen: Richtung = Peilung `from` → `device` (bei `maxspeed`/`traffic_signals`) bzw. `from` → `to`
  (Abschnittskontrolle). Fehlt `from`, fällt es auf die Tags des Geräte-Knotens zurück. Position: Gerät; bei
  Abschnittskontrolle der Start (`from`). Gerätknoten einer Relation werden nicht zusätzlich einzeln ausgegeben.
  Zwei Relationen (je Richtung) ergeben zwei Punkte.

## Tempolimit

`speedLimitAt` nutzt nur geladene Kacheln der Tempolimit-Schichten: nächstes Wegsegment ≤ 30 m, Segmente passend zum Kurs (≤ 60° Abweichung)
werden bevorzugt, Einbahnstraßen zählen nur in ihrer Richtung, `maxspeed:forward/backward` werden beachtet.
`none`, `signals`, `DE:motorway` → null.
Wege ohne Limit-Tag (`limitTagged = false`, nur Rampen für die Linie voraus) überspringt `pickSpeedLimit` ganz: Sie
werden nie gewählt und setzen kein Limit auf „unbekannt“.

## Linie voraus (`roadAheadAt`)

Für Baustellen und andere Hinweise: die Strecke, der man wahrscheinlich folgt, bis 2,5 km voraus
(`osm_road_ahead.dart`). Sie entsteht aus denselben Tempolimit-Wegen im Speicher und in den Paketen, ohne eigene
Abfrage und ohne Netz.

- **Eigener Weg** wie beim Tempolimit: nächstes Segment bis 25 m, Kurs höchstens 45° daneben, Einbahn nur in ihrer
  Richtung.
- **An jedem Wegende** weiter auf den Weg, der dort beginnt oder durchläuft (Eckpunkt höchstens 3 m vom Ende), in
  dieser Reihenfolge: gleiche Nummer (`ref`) oder gleicher Name, dann gleiche Straßenart, dann die wichtigere, dann
  der kleinste Knick. Mehr als 110° Knick (fast umdrehen) führt nicht weiter. Vorfahrt ist in OSM selten getaggt;
  Name, Nummer und Art stehen dafür. So folgt die Linie einer abknickenden Vorfahrtsstraße und nach einer Abfahrt
  der Rampe.
- **Rampen** (`*_link`) holt die Abfrage der Hauptstraßen-Schicht auch ohne `maxspeed`, weil sie dort meist fehlt.
- **Null**, wenn kein Weg passt oder dessen Art unbekannt ist. Die Warnlogik prüft dann wie bisher an der geraden
  Linie.

Kosten: keine weitere Abfrage. Je Fix läuft die Suche über die Wege der Zellen entlang des Kurses (unter 1 ms).
Die Antworten der Tempolimit-Schichten werden durch `name`, `ref` und die Rampen größer. Gemessen am 9.11.2026
(overpass-api.de, je eine 0,05°-Zelle, Bytes der Antwort):

| Zelle | Schicht | vorher | nachher | mehr |
|---|---|---|---|---|
| Berlin-Mitte (52,50 N / 13,40 O) | Hauptstraßen | 844 865 | 949 801 | +12,4 % (Rampen davon +0,2 %) |
| Berlin-Mitte | Nebenstraßen | 990 650 | 1 102 280 | +11,3 % |
| Kassel, A 7 / A 44 (51,25 N / 9,45 O) | Hauptstraßen | 195 175 | 225 573 | +15,6 % (Rampen davon +5,8 %) |
| Kassel, A 7 / A 44 | Nebenstraßen | 232 285 | 255 843 | +10,1 % |

Alle Hauptstraßen auch ohne `maxspeed` zu holen, kostete in Kassel +24,5 % und bleibt deshalb aus; nur die Rampen.

**Grenze der Offline-Pakete:** Paketformat 1 kennt je Weg nur „Haupt- oder Nebenstraße“, keine Straßenart, keinen
Namen und keine Rampen ohne Limit. In Zellen aus einem Paket entscheidet an Kreuzungen nur Haupt- vor Nebenstraße
und der kleinste Knick. Eine abknickende Vorfahrt zwischen zwei Hauptstraßen erkennt das nicht sicher: Die Linie
kann geradeaus laufen, dann warnt eine Baustelle auf der geraden Straße wie bisher. Nach einer Abfahrt ohne Rampe
in den Daten bricht die Linie ab, die zuletzt verlassene Strecke schweigt dann (`RoadCourse` in der Warnlogik).
Sauber geht das erst mit einem Paketformat 2 mit Straßenart und Namen (Generator).
