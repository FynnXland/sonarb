# Fahrstatistik

Stand 02.11.2026. Was Sonarb über das eigene Fahren messen kann, ohne Eingriff ins Auto und ohne
spürbar mehr Akku. Code: `lib/features/stats/`.

## Quellen

| Quelle | Takt | Genauigkeit | Mehrverbrauch |
|---|---|---|---|
| GPS-Fixes der Fahrt (`PositionFix`) | 1 s, läuft ohnehin | Tempo (Doppler) etwa ±0,2 m/s, Kurs etwa ±1–2° ab 20 km/h, Position 3–10 m | keiner |
| Tempolimit der Straße (`roadLimitAt`) | je Fix, läuft ohnehin | so gut wie OSM; Straßenart nur aus dem Limit geschätzt | keiner |
| Warnlogik (`WarningUpdate`) | je Fix, läuft ohnehin | exakt (eigene Daten) | keiner |
| Sonnenstand aus Ort und Uhrzeit | Rechnung, je Minute | einige Minuten | keiner |
| Beschleunigungssensor | 25–100 Hz | kurze Spitzen genauer, aber Lage des Handys unbekannt | 2–10 mA ohne Bündelung, vor allem durch das Wecken der CPU |
| Gyroskop | 25–100 Hz | Kurven genauer | Sensor 1–5 mA, dazu das Wecken der CPU |
| Aktivitätserkennung (Play-Dienste) | Minuten | Auto/Rad/Fuß, oft mit Verzögerung | gering, braucht aber ein neues Recht |

Die Auswertung je Fix sind einige Dutzend Rechenschritte (unter 0,05 ms). Gespeichert wird einmal
je Fahrt eine Zusammenfassung von unter 1 KB. Der Mehrverbrauch liegt unter der Messgrenze; die
Wärme kommt vom GPS-Empfänger und vom Bildschirm, nicht von dieser Rechnung.

**Entscheidung:** nur GPS-Fixes, Limit und Warnlogik. Keine Sensoren, kein zusätzlicher GPS-Takt.

- Beschleunigungssensor verworfen: `sensors_plus` kann nicht bündeln (Android `maxReportLatency`),
  jeder Messwert weckt die Dart-Seite. Das Handy liegt in Halterung, Ablage oder Tasche, die Achsen
  müssten erst gegen die Fahrtrichtung geeicht werden. Gewinn nur bei Spitzen unter einer Sekunde;
  die Einteilung „hart“ ab 3 m/s² gelingt auch aus dem GPS-Tempo.
- Gyroskop verworfen: kostet am meisten, der GPS-Kurs reicht für „zügige Kurve“ ab 3,5 m/s².
- Aktivitätserkennung verworfen (für die Statistik): neues Recht `ACTIVITY_RECOGNITION`,
  Abhängigkeit von Google-Diensten, und sie gehört zur Fahrterkennung (`lib/features/background/`). Sie wäre der
  einzige Weg, Radfahrten sicher von Autofahrten zu trennen (siehe offene Fragen).

## Anbindung

`DriveController._onFix` gibt jeden Fix der Fahrt an `TripLog.fix`, vor dem Stand-Filter
(`StandstillGate`); Stand an der Ampel zählt so lückenlos. Tempolimit und Warnungen kommen aus
`_process` über `TripLog.context` und gelten bis zur nächsten vollen Verarbeitung. Im Stand
fragt die Statistik weder Limit noch Warnlogik neu an.

## Vorverarbeitung

- Fixes mit Genauigkeit über 30 m (`GpsQualityLimits.poorMeters`) fallen heraus.
- Das Tempo ist schon von `SpeedFilter` geglättet (Zeitkonstante 0,7 s, Sprünge über 12 m/s²
  gekappt). Ein einzelner Ausreißer kommt dort noch zu drei Vierteln durch. Für Beschleunigung,
  Bremsungen, Ruhe-Anteil und Schwankung nimmt der Recorder deshalb zuerst den Median aus drei
  Fixen (Zeit des mittleren), das wirft einzelne Ausreißer ganz heraus. Beschleunigung daraus über
  2 s: a = (u₂ − u₀) / (t₂ − t₀), also über vier Fixe. Rauschen etwa ±0,15 m/s².
- Geglättet über 11 m/s² ist ein Messfehler: Die Kette bricht ab, nichts davon zählt.
- Delle statt Bremsung: Folgt einer Verzögerung binnen 2,5 s eine Beschleunigung mit mindestens
  5 m/s², die mindestens 70 % des Verlusts zurückholt, zählen beide nicht. So kräftig beschleunigt
  im Alltag kein Auto; so sieht ein kurzer Einbruch des GPS-Tempos aus (Test „Rauschen“ in
  `test/stats/trip_detail_test.dart`).
- Lücken über 2,5 s brechen Beschleunigungs- und Kurvenrechnung ab. Strecke über eine Lücke
  (Tunnel) zählt als Luftlinie, wenn das Tempo daraus plausibel ist (unter 70 m/s).
- Strecke = Integral des Tempos (nicht Summe der Positionssprünge). Im Stand addiert das
  Positionsrauschen so keine Meter.
- Die Fahrterkennung beendet eine Fahrt erst nach 5 min Stand. Diese Standzeit am Ende wird
  abgeschnitten; Ende ist der letzte Fix in Bewegung.
- Fahrten unter 500 m oder unter 1 min Bewegung werden nicht gespeichert.

## Kennzahlen

„Stand“ heißt: mittleres Tempo eines Schritts unter 1 m/s (3,6 km/h).

| Kennzahl | Formel | Genauigkeit | Schätzung? |
|---|---|---|---|
| Fahrten | erkannte Fahrten (`MotionState.driving`) | Radfahrten über 15 km/h zählen mit | nein |
| Strecke | Σ v·Δt, Lücken als Luftlinie | ±1–2 %, Tunnel kürzer | nein |
| Dauer | erster bis letzter Fix in Bewegung | ±1 s | nein |
| Fahrzeit, Standzeit | Zeit in Bewegung bzw. im Stand innerhalb der Fahrt | ±1 s je Halt | nein |
| Halte | Standphasen ab 5 s | Kriechen im Stau zählt nicht als Halt | nein |
| Tempoverteilung | Fahrzeit je 10-km/h-Stufe | ±1 km/h an den Grenzen | nein |
| Häufigstes Tempo | Stufe mit der meisten Fahrzeit | Stufe | nein |
| Höchsttempo | höchstes Tempo, das 3 Fixes in Folge (≥ 2 s) gehalten wurde | ±2 km/h; GPS misst echtes Tempo, der Tacho zeigt mehr | nein |
| Durchschnitt | Strecke / Fahrzeit | ±1 km/h | nein |
| Über dem Limit | Fahrzeit mit bekanntem Limit in Stufen: bis +3, +4 bis +10, +11 bis +20, ab +21 km/h | ±1 km/h; Limit so gut wie OSM | Limit aus Daten, nicht vom Schild |
| Straßenart | aus dem Limit: kein Limit oder über 100 = Autobahn, bis 50 = innerorts, sonst außerorts | 60/70 in Städten gilt als außerorts, Autobahn-Baustelle mit 80 ebenso | ja |
| Stadtanteil | Fahrzeit innerorts / Fahrzeit mit bekannter Straßenart | wie Straßenart | ja |
| Nachtanteil | Fahrzeit bei Sonne unter −6° (nach der bürgerlichen Dämmerung) | einige Minuten | nein |
| Verzögerungen | Abschnitt mit a ≤ −0,5 m/s² bis a > −0,25 m/s², mindestens 2 m/s (7 km/h) Tempoverlust | Beginn und Ende ±1 s | nein |
| Bremsungen | Verzögerung mit Spitze über 1,5 m/s² | Spitzen unter 1 s werden unterschätzt | nein |
| Harte Bremsungen | Spitze ab 3,0 m/s² (gut 0,3 g) | wie oben; eine Vollbremsung (8–10 m/s²) zeigt sich als 6–8 m/s² | nein |
| Sanft verzögert (Motorbremse) | Anteil des Tempoverlusts aus Verzögerungen mit Spitze höchstens 1,5 m/s² und mindestens 3 s | Motorbremse, Ausrollen und leichtes Bremsen sind ohne Fahrzeugdaten nicht zu trennen | **immer geschätzt** |
| Anfahrten | Beschleunigung (a ≥ 0,5 bis < 0,25 m/s², mindestens 2 m/s Gewinn) ab unter 7 km/h | ±1 s | nein |
| Kräftig beschleunigt | Beschleunigung mit Spitze ab 3,0 m/s² | wie Bremsungen | nein |
| Zügige Kurven | Querbeschleunigung v·ω (ω aus der Kursänderung über 2 s, ab 18 km/h) ab 3,5 m/s², endet unter 2,5 m/s² | ±0,6 m/s²; enge Kreisel bei 1 Hz unterschätzt | Näherung |
| Höchste Querbeschleunigung | größter Wert v·ω | wie oben | Näherung |
| Warnungen | erste Ansagen der Warnlogik (alle Arten) | exakt | nein |
| Blitzer passiert | feste Messstellen und gemeldete mobile Blitzer, die bis auf 100 m nahekamen und dann aus der Warnliste fielen | exakt, soweit in den Daten | nein |
| davon zu schnell | Tempo beim nächsten Fix vor der Stelle über Limit der Stelle (sonst Straße) + 3 km/h | ±1 km/h, Fix bis 1 s vor der Stelle | nein |
| Vorausschauend (0–100) | siehe unten | so gut wie die Teilwerte | ja, Bewertungsformel |
| Schnitt mit Stand | Strecke / (Fahrzeit + Standzeit) | ±1 km/h | nein |
| Längster Halt, mittlere Haltedauer | Dauer der Halte ab 5 s; Mittel = Summe / Anzahl | ±1 s je Halt | nein |
| Verteilung der Verzögerungen bzw. Beschleunigungen | Anzahl je Stufe der Spitze, 0,5 m/s² breit ab 0,5; sanft unter 1,5, mittel 1,5 bis 3, hart ab 3 m/s² | wie Bremsungen | nein |
| Stärkste Bremsung bzw. Beschleunigung | größte Spitze a über 2 s | wie Bremsungen | nein |
| Ruhig gefahren | Fahrzeit mit \|a\| < 0,5 m/s² / Fahrzeit mit bekanntem a (a über 2 s) | ±0,15 m/s² Rauschen | nein |
| Schwankung | Abschnitte ab 20 s ohne laufende Verzögerung oder Beschleunigung, Tempo ab 30 km/h; je Abschnitt Varianz des Tempos, nach Dauer gemittelt, Wurzel daraus | ±0,3 km/h | nein |
| Je Tempolimit | Fahrzeit je Limit und Stufe über dem Limit; Höchsttempo (über 3 Fixes gehalten) je Limit | wie „Über dem Limit“ | Limit aus Daten |
| Tempoverlauf | ein Wert je Sekunde (ganze km/h), Limit bei Wechsel, Bremsungen und Beschleunigungen mit Spitze über 1,5 m/s² | ±1 km/h | nein |

Jede Kennzahl hat in der App ein ⓘ mit dieser Herleitung in einfachen Worten
(`stats_explain.dart`). Tempoänderungen zeigt die App groß in km/h pro Sekunde
(1 m/s² = 3,6 km/h/s), m/s² klein daneben: sanft unter 5, hart ab 11 km/h/s.

### Vorausschauend

Gewichtetes Mittel aus vier Teilwerten zwischen 0 und 1:

| Teil | Gewicht | Wert |
|---|---|---|
| sanft verzögert | 35 | Anteil des Tempoverlusts ohne Bremsung über 1,5 m/s² |
| harte Bremsungen | 25 | 1 − H/5, H = harte Bremsungen je 100 km |
| zügige Kurven | 20 | 1 − K/10, K = zügige Kurven je 100 km |
| über dem Limit | 20 | 1 − Ü/0,2, Ü = Anteil der Fahrzeit mit bekanntem Limit ab +11 km/h |

Teilwerte werden auf 0 bis 1 begrenzt. Je-100-km-Werte rechnen mit mindestens 10 km Strecke,
damit eine einzelne Bremsung auf 2 km nicht alles bestimmt. Fehlt ein Teil (keine Verzögerung,
unter 1 min mit bekanntem Limit), zählen nur die übrigen. Unter 1 km Strecke gibt es keinen Wert.

### Verworfen

- **Tacho-Tempo und Drehzahl**: nur über OBD, also ein Eingriff ins Auto.
- **Motorbremse sicher erkennen**: ohne Drehzahl und Pedalstellung nicht möglich; nur die
  Schätzung oben.
- **Abstand zum Vordermann, Spurwechsel**: GPS zu ungenau (3–10 m), Kamera wäre nötig.
- **Schlaglöcher, Fahrbahnzustand, Gangwechsel**: nur mit Beschleunigungssensor bei hohem Takt.
- **Verbrauch und CO₂**: hängt am Fahrzeug, aus Tempo allein zu grob.
- **Handy-Nutzung während der Fahrt**: nicht Aufgabe dieser App.
- **Straßenart direkt aus OSM (`highway=*`)**: wäre genauer als die Ableitung aus dem Limit, die
  Datenschicht gibt sie aber nicht heraus (offene Frage).

## Speicherung

- Datei `stats/trips.json` im App-Speicher (`getApplicationSupportDirectory`), nur auf dem Gerät.
- Je Fahrt: Beginn, Ende, die Zahlen oben (Summen, Verteilung, Zähler). Keine Positionen, kein
  Fahrtverlauf, keine Ortsnamen.
- Aufbewahrung einstellbar: 1 Monat, 3 Monate oder 1 Jahr (Standard), höchstens 1000 Fahrten.
  Ältere fallen beim nächsten Speichern oder Öffnen weg.
- Aufzeichnung abschaltbar, einzelne Fahrten oder alle löschbar (Einstellungen → Fahrstatistik).
- Zwischenspeichern: Die laufende Fahrt wird alle 5 min und einmal je Halt ab 30 s als „offen“
  in `trips.json` gesichert (erst ab 500 m und 1 min Bewegung). Geschrieben wird atomar in
  `trips.json.tmp` und dann umbenannt. Wird die App hart beendet, schließt der nächste Start die
  offene Fahrt mit ihrem letzten gesicherten Stand ab (Ende = letzter Fix in Bewegung davor).
  Laufende Bremsungen, Kurven und Blitzer seit dem letzten Sichern fehlen dann.

### Tempoverlauf

- Datei `stats/traces/<id>.json` je Fahrt, getrennt von `trips.json`, nur beim Öffnen der Fahrt
  gelesen. Inhalt: Tempo je Sekunde ab dem ersten Fix in ganzen km/h (1 Byte, Base64; 255 = keine
  Messung), Limit nur bei Wechsel, Vorgänge mit Spitze über 1,5 m/s² (Beginn, Dauer, Spitze, Tempo
  davor und danach). Keine Positionen.
- Zwischen zwei Fixes wird linear gefüllt (Kette bis 2,5 s), über längere Lücken mit 0, wenn die
  Luftlinie Stand ergibt, sonst als Lücke. Ende ist der letzte Fix in Bewegung.
- Größe: etwa 5 KB je Stunde Fahrt, dazu rund 20 Byte je markiertem Vorgang. `trips.json` wächst
  um rund 0,3 KB je Fahrt (Verteilungen, Werte je Limit).
- Geschrieben mit dem Zwischenspeichern (alle 5 min, je Halt ab 30 s, Fahrtende), nach der
  Zusammenfassung. Fällt eine Fahrt weg (Löschen, Aufbewahrung), löscht das Speichern von
  `trips.json` ihren Verlauf mit.
- Fahrten von vor diesem Ausbau haben weder Verlauf noch die neuen Kennzahlen; die App zeigt dort
  „–“ bzw. einen Hinweis (`DriveFigures.detailSeconds` = 0).

## Offene Fragen

- Radfahrten über 15 km/h zählen als Fahrt (Fahrterkennung). Trennen ließe sich das nur mit der
  Aktivitätserkennung.
- Straßenart aus OSM statt aus dem Limit (braucht eine kleine Erweiterung von `RoadLimit`).
