# Ortung und Akku

Stand 30.10.2026. Was Sonarb bei Fahrt und im Stand vom Gerät verlangt, und warum.
Code: `lib/features/cockpit/` (`location_service`, `motion_detector`, `drive_controller`,
`speed_filter`, `car_link`), Dienst und Benachrichtigung in `lib/features/background/`.

## Modi

| Zustand | Anfrage | Takt | Zeitregeln |
|---|---|---|---|
| Fahrt | GPS, `bestForNavigation` (HIGH_ACCURACY) | 1 s, kein Abstandsfilter | 1 s |
| Stand | `medium` (BALANCED: WLAN, Funkzellen) | 20 s, kein Abstandsfilter | 5 s |
| GPS-Prüfung im Stand | wie Fahrt | höchstens 30 s, früher nach 5 ruhigen Fixes | 1 s |
| Bluetooth-Audio neu verbunden | wie Fahrt | 2 min | 1 s |
| Beendet | nichts | – | – |

Gemessen im Emulator (`dumpsys location`): bei Fahrt eine Anfrage `@+1s HIGH_ACCURACY`, im Stand
keine GPS-Anfrage, nach „Beenden“ keine Anfrage von Sonarb.

Fahrt beginnt nach drei Messungen über 15 km/h. Sie endet nach 5 min ununterbrochen unter
8 km/h: Ampel und stehender Stau bleiben Fahrt, Parken und Weggehen nicht. Mit verbundenem
Bluetooth-Audio sind es 8 min.

## Tempo

- Quelle ist das GPS-Tempo (Doppler, `Position.speed`). Aus Positionen gerechnet wird nur, wenn
  das Gerät keins meldet (Emulator).
- `SpeedFilter`: Zeitkonstante 0,7 s. Nach 1 s zeigt die Anzeige etwa drei Viertel eines
  Tempowechsels, nach 2 s über 90 %. Sprünge über 12 m/s² werden gekappt (eine Vollbremsung
  liegt bei 10 m/s²), nach mehr als 3 s ohne Messung beginnt der Filter neu.

## Was die CPU weckt

| Quelle | Stand | Fahrt |
|---|---|---|
| Positionen | alle 20 s | jede Sekunde |
| Takt der Zeitregeln | alle 5 s | jede Sekunde |
| Warnlogik, Tempolimit, Punkte | nie | je Fix |
| Benachrichtigung | nur bei Änderung, höchstens alle 2 s | ebenso |
| Wakelock | keiner | keiner (das GPS weckt ohnehin jede Sekunde) |
| Bildschirm an | nie | nur bei sichtbarem Cockpit |

Die Benachrichtigung wurde bei Fahrt vorher jede Sekunde neu gesetzt (das Tempo ändert sich
ständig). Jedes Setzen läuft durch Systemdienst und Statusleiste; jetzt höchstens alle 2 s.

## Messung im Emulator

Debug-Version (JIT, Prüfungen an), App im Hintergrund, CPU-Zeit aus `/proc/<pid>/stat` über 60 s,
Anteil an einem Kern. Eine Release-Version braucht deutlich weniger; die Werte taugen zum
Vergleich der Zustände untereinander.

| Zustand | CPU |
|---|---|
| Beendet (App offen, keine Überwachung) | 0,3 % |
| Stand, erste Minute nach dem Start (Daten laden) | 1,5–1,6 % |
| Stand, danach (Takt 5 s) | 0,5 % |
| Fahrt, 1 Hz GPS, Benachrichtigung aktiv | 1,7 % |

Die erste Minute enthält das Laden der Blitzerdaten und Kartenkacheln. Der Takt im Sparmodus
ging von 1 s auf 5 s; sein Anteil ist mit diesen Messungen nicht von der Anlaufphase zu trennen,
er spart aber vier von fünf Weckungen ohne Nachteil.

Die Verarbeitung je Fix (Punkte, Tempolimit, Warnlogik, Zustand) kostet weniger als 2 ms: Fahrt
und Stand unterscheiden sich um rund 0,1 s CPU pro Minute. Den größten Teil bei Fahrt braucht
der GPS-Empfänger selbst (auf Geräten etwa 20–30 mA), nicht die App.

## Ohne Netz-Ortung

Ohne WLAN- und Funkzellenortung liefert der Sparmodus nichts oder immer dieselbe alte Position.
Dann prüft die App per GPS (`GpsCheck`): nach 2 min ohne neue Position bis zu 30 s, ohne Empfang
(drinnen) seltener, höchstens alle 4 min. Mehrverbrauch geschätzt 1,5–3 mA im Mittel, also
1–2 % Akku am Tag, und nur, wenn die Netz-Ortung fehlt.

## Bluetooth-Audio

Über `audio_session` (`AudioManager.getDevices`), ohne Bluetooth-Recht. Gezählt werden
Bluetooth-Musik (A2DP), Freisprechen (SCO), LE Audio und der Audio-Bus von Android Automotive.
Auto und Kopfhörer sind so nicht zu unterscheiden; deshalb nur ein Hinweis: neu verbunden heißt
2 min genau messen, verbunden heißt längeres Halten im Stand. Eine Fahrt beginnt weiter erst
mit gemessenem Tempo.

## Beenden

`DriveController.stop()` beendet Positions-, Quellen- und Bluetooth-Abo, den Takt und den
Vordergrunddienst samt Benachrichtigung. Das Future endet, wenn der Dienst weg ist; vor
`SystemNavigator.pop()` darauf warten. Neu gestartet wird nur, wenn die App danach verlassen und
wieder geöffnet wird. Der Dienst startet nicht von selbst neu (`allowAutoRestart: false`, kein
Autostart nach dem Booten, `stopWithTask`).

## Wärme bei Fahrt mit sichtbarem Cockpit (2.11.2026)

Profile-Version (kompiliert wie Release), Emulator, je 60 s, CPU als Anteil eines Kerns, aufgeteilt
nach Threads aus `/proc/<pid>/task`, Bildrate aus `dumpsys SurfaceFlinger --latency`.
„Vorher“: master 68be783. „Nachher“: master c0d9a70 mit stillem Standort-Ring (03fdfa6), Gleiten
zwischen Fixes (c0d9a70) und dem Stand-Filter der Ortung (e90ef76).

| Zustand | vorher | nachher |
|---|---|---|
| Stand, Cockpit sichtbar | 25 %, 60 fps | 0,2 %, 0,1 fps (5 Bilder in 60 s) |
| Fahrt, Karte mitgeführt | 26 %, 60 fps | 18,5 %, 18 fps (siehe unten) |
| Fahrt, App im Hintergrund | 1,1 % | 1,8 % |

Aufteilung bei Fahrt vorher: 78 % Zeichnen (raster), 18 % UI-Thread; je Bild etwa 3,4 ms Zeichnen
und 0,8 ms UI. Nachher: 68 % Zeichnen, 24 % UI; je Bild etwa 7 ms Zeichnen und 2,5 ms UI. Das
Gleiten zeichnet mehr je Bild (Kartenausschnitt bewegt sich in jedem Bild), dafür viel seltener.

Die Fahrt „nachher“ ist nicht ganz sauber: Die Fahrt wurde im Messfenster erst spät erkannt
(ohne Google-Genauigkeit und ohne Netz-Ortung greift die GPS-Prüfung nach bis zu 2–4 min). Die
18 fps stammen aus den letzten 7 s des Fensters, als gefahren wurde; die 18,5 % mischen Stand und
Fahrt, für reine Fahrt eher etwas mehr.

Verarbeitung je Fix (Punkte, Tempolimit, Warnlogik, Zustand, Benachrichtigung): etwa 8–13 ms pro
Sekunde, sichtbar an der Fahrt im Hintergrund. Netz unter 1 %, keine Wakelocks.

Anteile im Vordergrund vorher: Kartenzeichnen rund 95 % der App-CPU, Verarbeitung je Fix rund 4 %,
Netz und Audio rund 1 %. Dazu kommen außerhalb der App GPS-Empfänger und Bildschirm.

### Emulator und echtes Gerät

Der Emulator zeichnet ohne echte Grafikkarte; gemessen wurden dort 26–40 ms je Bild. Ein
aktuelles Gerät (etwa Pixel 9 Pro) zeichnet eine solche Karte in grob 3–6 ms. Folgen:
- Die Bremse in `glideFrameInterval` (höchstens jedes dreifache der Zeichenzeit) greift im Emulator
  und senkt die Bildrate dort auf 3–10 fps; auf dem Gerät gelten die festen Stufen (8, 12,5, 20 fps).
- Auf dem Gerät ist deshalb mit der vollen Stufe zu rechnen, bei 20 fps grob 5–10 % eines Kerns
  für die Karte statt 15–25 % bei vorher 60 fps, dazu entsprechend weniger Grafiklast.
- Ohne Messung am Gerät sind das Schätzungen.

### Obergrenze für die Karte

Bei den Fahrzooms (`drive_zoom.dart`) bewegt sich die Karte in jeder Tempostufe um etwa
15–25 logische Pixel pro Sekunde, im geneigten Vordergrund etwa das 1,5-Fache. Flüssig wirkt das ab
etwa 2 px je Bild. Vorschlag: im Stand keine Dauer-Bildrate, bis 100 km/h höchstens 15 fps
(20 fps beim Abbiegen über 10°/s), darüber 12 fps, im Hintergrund 0. Die heutigen Stufen in
`glideFrameInterval` (bis 20 fps ab 50 km/h) liegen leicht darüber und sind vertretbar.

### In der Ortung umgesetzt

- Im Stand (unter 0,8 m/s, weniger als 3 m Versatz) geht ein Fix nur in den Zustand, wenn sich
  die Tempoanzeige ändert, sonst spätestens alle 10 s; Tempolimit und Warnlogik ebenso selten.
  Die Karte bekommt dann keinen Anlass zum Neuzeichnen. Fahrsimulation mit 90 s Ampelhalt:
  dieselben Warnstufen am selben Abstand, höchstens 12 statt 90 Durchläufe während des Halts.
- `DriveController.positionFixes` liefert weiter jeden Fix, etwa für eine Fahrtstatistik.
- GPS bleibt bei Fahrt im Sekundentakt: Das genaue Tempo braucht ihn, und die Verarbeitung je Fix
  ist kein nennenswerter Anteil.

## Offen

- Messung auf einem echten Gerät mit Release-Version, auch mit ausgeschaltetem Bildschirm.
- Ohne jede Position (frisch gestartet, keine Netz-Ortung) weckt nichts die App, solange der
  Bildschirm aus ist; die GPS-Prüfung kommt dann erst beim nächsten Wecken.
