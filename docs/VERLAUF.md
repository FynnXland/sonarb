# Eigener Verlauf mobiler Blitzer

Stand 03.11.2026. Sonarb merkt sich selbst, wo mobile Blitzer standen, und baut daraus über Wochen
eine eigene Wärme- und Hotspot-Ebene auf. Code: `lib/features/alerts/mobile_history.dart`.

## Was gespeichert wird

Jeder nicht vergangene mobile Blitzer, den irgendein Plugin liefert: `mobileSpeed`, `mobileRedLight`,
`mobileDistance`, `semiStationary` (und Punkte der groben Art `live` ohne feine Art, die als mobiler
Blitzer gelten). Nicht: feste Blitzer, Baustellen, Gefahren, eigene Meldungen, vergangene
Beobachtungen.

Je Eintrag: Position (auf 1 m gerundet), Art, Richtung (Grad, falls bekannt), Tag der Beobachtung.
Der Tag ist der `observedAt` des Plugins, sonst der Tag des Abrufs. Keine Uhrzeit, keine Quelle,
kein Gerät, keine Fahrt.

- **Gleiche Stelle:** Liegt am selben Tag schon ein Eintrag höchstens 50 m entfernt, zählt der neue
  nicht. Das gilt auch zwischen Quellen: Zwei Plugins, die denselben Blitzer melden, ergeben einen
  Eintrag.
- **Aufbewahrung:** höchstens 2 Jahre (`mobileHistoryKeep`) und 20 000 Einträge
  (`mobileHistoryMax`). Darüber gehen die ältesten zuerst; es wird auf 19 000 gekürzt.
- **Nur lokal:** `mobile_history.json` im Datenordner der App (derselbe wie `hotspots.json`).
  Nichts wird gesendet.

## Wie er benutzt wird

`AlertRepository.pointsAround(withHistory: true)` liefert die Einträge im Umkreis als
`historical: true` mit `observedAt` (Mittag des Beobachtungstags), `source: own_history`, Kategorie
und Richtung. Damit rechnen die Wärme-Ebene der Karte und die Hotspots der Warnlogik wie bisher:

- Wärme: Halbwertszeit 1 Jahr, Zellen von 300 m, Gewicht nach Alter.
- Hotspot: ab der eingestellten Zahl von Meldungen im Umkreis von 300 m (`heatSpotMinReports`).
- Sie lösen selbst keine Warnung aus und erscheinen nicht als Symbol.

Hat ein Plugin dieselbe Sichtung noch im Speicher (manche halten sie bis zum Neustart),
zählt sie einmal: ein Eintrag mit gleichem Tag und höchstens 50 m Abstand zu einer vergangenen
Beobachtung eines Plugins wird nicht zusätzlich geliefert.

## Speicher

Gemessen mit 20 000 Einträgen (volle Datei, Richtung und Tag bei jedem):

| Größe | Wert |
|---|---|
| Datei | 574 KB (rund 29 Byte je Eintrag) |
| Aufnahme | 20 000 Einträge in 1,3 s, also 65 µs je Eintrag |
| Arbeitsspeicher | schätzungsweise 2 bis 3 MB (je Eintrag ein kleines Objekt und der Rasterplatz) |
| Schreiben | höchstens alle 30 s nach einer Änderung, atomar (`.tmp`, dann umbenennen), beim Beenden sofort |

Eine Stadt mit regelmäßigen Blitzermeldungen liefert grob 10 bis 30 neue Einträge am Tag. Die
2-Jahres-Grenze erreicht der Bestand dann bei 7 000 bis 22 000 Einträgen; die Obergrenze greift nur
bei sehr dichter Meldelage.

## Verhalten bei Fehlern

- Fehlt die Datei, beginnt der Verlauf leer.
- Eine unlesbare Datei wird zu `mobile_history.json.bad` umbenannt, der Verlauf beginnt leer.
  Einzelne ungültige Einträge werden übersprungen, die übrigen bleiben.
- Vor dem Lesen der Datei wird nichts geschrieben: Meldungen, die in dieser Zeit eintreffen, werden
  nach dem Lesen mit dem Bestand vereint.
- Schlägt das Schreiben fehl, bleibt der Bestand im Speicher und wird beim nächsten Mal erneut
  versucht.

## Grenzen

- Nur der Umkreis der Position (`pointsAround`) bekommt den Verlauf, wie bisher auch der Verlauf der
  Plugins. Beim Verschieben der Karte weit weg von der Position erscheint die Wärme erst, wenn die
  Fahrtansicht dort ist.
- Löschen geht nur über die Datei oder „Daten löschen“ des Systems; eine Einstellung dafür gibt es
  noch nicht.
- Die Stelle eines Blitzers wird nicht auf die Straße gelegt; Hotspots stehen an der Meldung
  nächst dem Mittelpunkt (siehe `findHeatSpots`).
