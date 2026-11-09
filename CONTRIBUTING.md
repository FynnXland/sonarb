# Mitmachen

Danke für dein Interesse an Sonarb. Fehlerberichte und Ideen sind willkommen, auf Deutsch oder Englisch.

Sonarb pflegt eine Person in ihrer Freizeit. Deshalb gilt:

- **Issues:** gern, über die [Formulare](https://github.com/FynnXland/sonarb/issues/new/choose).
- **Pull Requests:** bitte erst nach Absprache in einem Issue. So geht keine Arbeit verloren, falls eine
  Änderung nicht zur App passt.
- **Sicherheitsprobleme:** nie öffentlich, sondern wie in [SECURITY.md](SECURITY.md) beschrieben.

Wie die App aufgebaut ist, steht in [docs/ARCHITEKTUR.md](docs/ARCHITEKTUR.md); eine Übersicht aller Dokumente
in [docs/README.md](docs/README.md).

## Was in dieses Repository gehört

Sonarb nutzt nur offene Daten aus OpenStreetMap und Meldungen, die Nutzer selbst auf ihrem Gerät anlegen.
Daten von kommerziellen Blitzerdiensten oder anderen Quellen ohne passende Lizenz nehmen wir nicht auf, auch
nicht als Plugin, Beispiel oder Testdaten. Eigene Plugins lassen sich lokal einbinden
([docs/PLUGINS.md](docs/PLUGINS.md)); sie liegen in `lib/plugins/local/` und werden nie committet.

## Entwicklungsumgebung

- Flutter **3.47.4** (stable) mit Dart 3.13, Android SDK mit Plattform 36. CI nutzt dieselbe Version.
- Ein Android-Gerät oder Emulator mit Android 10 (API 29) oder neuer.

```bash
git clone https://github.com/FynnXland/sonarb.git
cd sonarb
flutter pub get
flutter run
```

Entwickelt wird unter Windows; CI baut und testet unter Linux. `tool/build-play.ps1` (Bundle für Google Play)
braucht PowerShell 7.

**Release-Builds** brauchen einen eigenen Keystore, beschrieben in `~/.handy-keys/key.properties`
(`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). Ohne ihn bricht `flutter build apk --release` mit
einem Hinweis ab. Für die Entwicklung reicht `flutter build apk --debug`.

## Tests

```bash
flutter analyze
flutter test
```

Die Suite hat gut tausend Tests und läuft in etwa einer Minute. Netz, Standort, Ton und Hintergrunddienst sind
in den Tests durch Attrappen ersetzt (`test/cockpit/fakes.dart`); kein Test braucht Internet oder ein Gerät.

- Neues Verhalten braucht einen Test, eine Fehlerkorrektur einen Test, der ohne die Korrektur scheitert.
- CI (`.github/workflows/tests.yml`) führt auf jedem Pull Request `flutter analyze`, `flutter test`, einen
  Debug-Build und die Prüfungen aus `tool/check_public.py` aus.

## Konventionen

- Aufbau: Verträge in `lib/core/`, je Bereich ein Ordner unter `lib/features/`. Ein Bereich importiert nur
  `core/`, nie einen anderen Bereich; `lib/app/` verdrahtet alles. Tests liegen spiegelbildlich unter `test/`.
- Texte in der App und Kommentare sind deutsch. Kommentare nur dort, wo sie etwas erklären, das der Code nicht sagt.
- `dart format` vor dem Commit.
- Eine neue Abhängigkeit braucht eine verträgliche Lizenz. Danach `dart run tool/third_party_notices.dart`
  ausführen und `THIRD-PARTY-NOTICES.md` mit committen; CI prüft, dass die Datei aktuell ist.
- Screenshots und Beispieldaten nur mit erfundenen Orten und Namen.

## Privatsphäre

Alles, was committet wird, ist für immer öffentlich, auch nach dem Löschen. Nie hinein gehören:

- Zugangsdaten, Schlüssel, Keystores, `key.properties`
- echte Standorte, Fahrten, Exporte eigener Meldungen, Logs vom eigenen Gerät
- Nutzernamen, lokale Pfade, private Mailadressen
- lokale Plugins aus `lib/plugins/local/` und eine erzeugte `lib/plugins/installed_plugins.dart`

## Version, Änderungen und Veröffentlichung

Version und Veröffentlichung pflegt der Maintainer. Beschreib im Pull Request in ein, zwei Sätzen, was sich
für Nutzer ändert.

## Lizenz

Unless you explicitly state otherwise, any contribution you submit for inclusion in this project is licensed
under the MIT License, without additional terms or conditions.

Sofern du nichts anderes angibst, steht jeder Beitrag, den du zur Aufnahme einreichst, unter der MIT-Lizenz,
ohne zusätzliche Bedingungen.
