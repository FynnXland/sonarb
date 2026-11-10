# Bilder der README

| Datei | Was sie zeigt |
|---|---|
| `ansage.png` | Cockpit während der Fahrt, Ansage „Fester Blitzer“ 400 m vorher |
| `melden.png` | Dieselbe Fahrt 260 m vor dem Blitzer, mit dem Blatt „Was melden?“ |
| `start.png` | Startbildschirm „Vor der ersten Fahrt“ beim ersten Öffnen |

Alle Bilder stammen aus der echten App (Release-Build ohne Plugins) auf einem Android-Emulator. Die Fahrt ist
erfunden: nordwärts über die Saarlandstraße in Hamburg bis zu einem festen Blitzer, der in OpenStreetMap
eingetragen ist (`tool/media/route.json`). Die Statusleiste steht im Demo-Modus von Android (12:00 Uhr, voller
Akku, keine Benachrichtigungen). Kartenbild © OpenStreetMap-Mitwirkende; im Melden-Bild liegt der Hinweis der
App unter dem Blatt.

Neu erzeugen mit `tool/media/screenshots.sh` (Emulator, Flutter, Python 3, ffmpeg). Das Skript braucht
erreichbare Overpass-Server; ist einer überlastet, wartet es bis zu 15 Minuten auf die Wiederholungen der App.
Danach jedes Bild ansehen und mit ffmpeg auf 128 Farben verkleinern:

```bash
ffmpeg -i ansage-roh.png -vf "split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=none" ansage.png
```

Der Emulator meldet als Kurs immer Norden. Eine neue Strecke muss deshalb nach Norden auf den Blitzer zuführen,
sonst liegt er für die App nicht voraus.
