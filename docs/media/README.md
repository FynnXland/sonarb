# Bilder der README

| Datei | Was sie zeigt |
|---|---|
| `start.png` | Startbildschirm „Vor der ersten Fahrt“ beim ersten Öffnen |
| `melden.png` | Cockpit im Stand mit dem Blatt „Was melden?“ |

Beide Bilder stammen aus der echten App (Release-Build ohne Plugins) auf einem Android-Emulator. Die Position
ist erfunden: eine Testfahrt entlang der Amsinckstraße in Hamburg (`tool/media/route.json`). Die Statusleiste
steht im Demo-Modus von Android (12:00 Uhr, voller Akku, keine Benachrichtigungen). Kartenbild
© OpenStreetMap-Mitwirkende; der Hinweis der App liegt im Melden-Bild unter dem Blatt.

Neu erzeugen mit `tool/media/screenshots.sh` (Emulator, Flutter, Python 3, ffmpeg). Danach jedes Bild ansehen
und mit ffmpeg auf 128 Farben verkleinern:

```bash
ffmpeg -i start-roh.png -vf "split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=none" start.png
```

Ein Bild der Fahrt mit Ansage fehlt noch: Dafür muss die App Blitzerdaten von den öffentlichen Overpass-Servern
laden können, und die simulierte Fahrt muss die Fahrterkennung erreichen (siehe Kopf von `screenshots.sh`).
