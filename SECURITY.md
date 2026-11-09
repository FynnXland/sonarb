# Sicherheit

## Unterstützte Versionen

Sicherheitskorrekturen bekommt nur die jeweils neueste Version der App.

## Eine Lücke melden

**Bitte kein öffentliches Issue.** Melde Sicherheitsprobleme privat über GitHub:
[**Lücke melden**](https://github.com/FynnXland/sonarb/security/advisories/new) (auch im Reiter *Security*).
Alternativ per E-Mail an kontakt@fynnland.xyz.

Hilfreich sind: App-Version (Einstellungen → Über), Android-Version und Gerät, was ein Angreifer erreichen
kann, die Schritte zum Nachstellen und ob du genannt werden möchtest. Lass echte persönliche Daten weg, auch
in einer privaten Meldung, insbesondere echte Standorte.

Sonarb pflegt eine Person in ihrer Freizeit. Rechne mit einer Antwort innerhalb von 7 Tagen. Ist die
Korrektur veröffentlicht, wird die Meldung öffentlich gemacht, auf Wunsch mit deinem Namen.

## Was dazugehört

- **Tempolimit-Pakete** (folgt, sobald das Paket-Repository öffentlich ist; bis dahin ist die Auswahl in der App
  ausgeblendet): Das Verzeichnis kommt per HTTPS von GitHub-Releases. Jedes Paket wird mit der im
  Verzeichnis angegebenen Größe und SHA-256-Prüfsumme verglichen und erst danach installiert; Kennung und Datum
  im Paketkopf müssen zum Verzeichniseintrag passen.
- **Kartendaten:** Abfragen an Overpass und an den Kachelserver laufen über HTTPS. Antworten werden geparst,
  nicht ausgeführt.
- **Import eigener Meldungen:** Die JSON-Datei, die beim Import gewählt wird, ist fremde Eingabe.
- **Daten auf dem Gerät:** Einstellungen, Zwischenspeicher, Meldungen und Fahrstatistik liegen im privaten
  Speicher der App.

## Was nicht dazugehört

- Plugins, die jemand selbst einbindet (`lib/plugins/local/`). Sie sind nicht Teil dieses Repositorys.
- Fehler in Abhängigkeiten selbst (bitte dort melden), außer Sonarb nutzt sie unsicher.
- Angriffe, die ein entsperrtes Gerät, Root-Rechte oder ein bereits übernommenes Konto voraussetzen.
- Ungenaue oder fehlende Daten in OpenStreetMap (bitte dort korrigieren).
