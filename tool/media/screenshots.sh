#!/usr/bin/env bash
# Erzeugt die Bilder für die README aus der echten App auf einem Android-Emulator.
#
#   tool/media/screenshots.sh            Debug-Build (Paket de.fynn.handy.sonarb.debug)
#   BUILD=release tool/media/screenshots.sh   Release-Build (braucht den Keystore)
#   KEEP=ordner tool/media/screenshots.sh     legt die Rohbilder zusätzlich dort ab
#
# Voraussetzungen: genau ein laufender Emulator (adb), Flutter, Python 3 (PYTHON=…), ffmpeg.
# Die App-Daten des gewählten Pakets werden gelöscht. Die Fahrt ist erfunden und folgt
# tool/media/route.json (Saarlandstraße, Hamburg, nordwärts bis zum Blitzer). Ergebnis in docs/media/.
#
# Im Stand ortet Sonarb nur sparsam über WLAN und Funkzellen; geo fix geht ans GPS. Deshalb schaltet das
# Skript nach dem Laden das WLAN ab, wartet, bis die App selbst aufs GPS schaut (GPS-Prüfung nach etwa
# 2 min, siehe docs/ORTUNG.md), und startet erst dann die Fahrt. Die mobilen Daten bleiben an, damit die
# App unterwegs Kartenbilder und Messstellen nachladen kann. Am Ende ist das WLAN wieder an.
# Der Emulator meldet als Kurs immer Norden (geo fix kennt keinen Kurs). Deshalb führt die Strecke nach
# Norden, sonst läge der Blitzer für die App nicht voraus.
set -euo pipefail
cd "$(dirname "$0")/../.."

BUILD="${BUILD:-debug}"
ADB="${ADB:-adb}"
PY="${PYTHON:-python3}"
export MSYS_NO_PATHCONV=1   # Git Bash unter Windows: /sdcard nicht umschreiben
OUT=docs/media
TMP="$(mktemp -d)"
command -v cygpath > /dev/null && TMP="$(cygpath -m "$TMP")"   # Windows-Python versteht /tmp nicht
if [ "$BUILD" = release ]; then PKG=de.fynn.handy.sonarb; else PKG=de.fynn.handy.sonarb.debug; fi
mkdir -p "$OUT"

shot() { "$ADB" exec-out screencap -p > "$TMP/$1.png"; echo "Bild: $1"; }

# Tippt auf das erste Element mit genau diesem Text (Accessibility-Baum).
tap_text() {
  "$ADB" shell uiautomator dump /sdcard/sonarb-ui.xml > /dev/null
  "$ADB" shell cat /sdcard/sonarb-ui.xml > "$TMP/ui.xml"
  "$PY" - "$TMP/ui.xml" "$1" <<'PY' | { read -r x y && "$ADB" shell input tap "$x" "$y"; }
import re, sys
xml, text = open(sys.argv[1], encoding="utf-8").read(), sys.argv[2]
for node in re.findall(r"<node [^>]*>", xml):
    attrs = dict(re.findall(r'([\w-]+)="([^"]*)"', node))
    if text in (attrs.get("text"), attrs.get("content-desc")):
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", attrs["bounds"]))
        print((x1 + x2) // 2, (y1 + y2) // 2)
        sys.exit(0)
sys.exit(f"nicht gefunden: {text}")
PY
}

# Alle sichtbaren Texte (text und content-desc) aus dem Accessibility-Baum.
ui_text() {
  "$ADB" shell uiautomator dump /sdcard/sonarb-ui.xml > /dev/null
  "$ADB" shell cat /sdcard/sonarb-ui.xml | grep -o -E '(text|content-desc)="[^"]+"' || true
}

# geo LAT LON [KNOTEN]: GPS-Fix mit Tempo, sonst erkennt die App keine Fahrt.
geo() { "$ADB" emu geo fix "$2" "$1" 10 12 "${3:-0}" > /dev/null; }
KMH=40
# Aufnahmen nach so vielen Fixes (je 1 s): Ansage etwa 400 m vor dem Blitzer, Melden etwa 240 m davor.
ANSAGE_BEI=86
MELDEN_BEI=99
KNOTEN=$(awk "BEGIN {printf \"%.1f\", $KMH / 1.852}")

# Statusleiste neutral: 12:00, voller Akku, keine Benachrichtigungen.
demo() { "$ADB" shell am broadcast -a com.android.systemui.demo -e command "$@" > /dev/null; }
DEMO_ALT="$("$ADB" shell settings get global sysui_demo_allowed | tr -dc '0-9')"
"$ADB" shell settings put global sysui_demo_allowed 1
demo enter
demo clock -e hhmm 1200
demo battery -e level 100 -e plugged false
demo network -e wifi show -e level 4 -e mobile hide
demo notifications -e visible false
cleanup() {
  demo exit || true
  "$ADB" shell svc wifi enable || true
  "$ADB" shell svc data enable || true
  "$ADB" shell settings put global sysui_demo_allowed "${DEMO_ALT:-0}" || true
  if [ -n "${KEEP:-}" ]; then mkdir -p "$KEEP" && cp "$TMP"/*.png "$KEEP"/ 2> /dev/null || true; fi   # Rohbilder zum Nachsehen
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "=== Build ($BUILD)"
flutter build apk "--$BUILD"
"$ADB" install -r "build/app/outputs/flutter-apk/app-$BUILD.apk" > /dev/null
"$ADB" shell pm clear "$PKG" > /dev/null
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS; do
  "$ADB" shell pm grant "$PKG" "android.permission.$p"
done

# Strecke im Sekundentakt bei $KMH km/h, als Zeilen "lat lon".
"$PY" - tool/media/route.json "$KMH" > "$TMP/fixes.txt" <<'PY'
import json, math, sys
pts = json.load(open(sys.argv[1], encoding="utf-8"))["points"]
def d(a, b):
    la = math.radians((a[0] + b[0]) / 2)
    return 6371000 * math.hypot(math.radians(b[0] - a[0]), math.radians(b[1] - a[1]) * math.cos(la))
step, rest = float(sys.argv[2]) / 3.6, 0.0
print(*pts[0])
for a, b in zip(pts, pts[1:]):
    seg = d(a, b); t = step - rest
    while t <= seg:
        f = t / seg
        print(f"{a[0] + (b[0] - a[0]) * f:.6f} {a[1] + (b[1] - a[1]) * f:.6f}")
        t += step
    rest = seg - (t - step)
PY

echo "=== Start"
read -r LAT LON < "$TMP/fixes.txt"
geo "$LAT" "$LON"
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 8
shot start
tap_text "Weiter zur Standortfreigabe"
sleep 4
# Google fragt im Emulator manchmal nach der Standortgenauigkeit; ablehnen ändert nichts am System.
tap_text "No thanks" 2> /dev/null || tap_text "Nein danke" 2> /dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do geo "$LAT" "$LON"; sleep 1; done
# Messstellen der Umgebung laden. Ist Overpass überlastet, versucht die App es selbst erneut; deshalb
# höchstens 15 min warten, bis sie weder lädt noch einen Fehlschlag oder veraltete Daten zeigt.
geladen=
for _ in $(seq 1 300); do
  ui="$(ui_text)"
  if ! grep -q -e "Lädt Blitzer" -e "Wartet auf Standort" -e "Laden gescheitert" -e "nicht aktuell" <<< "$ui"; then
    geladen=1; break
  fi
  geo "$LAT" "$LON"
  sleep 2
done
if [ -z "$geladen" ]; then
  echo "Blitzerdaten nach 15 min nicht geladen (Overpass nicht erreichbar?). Abbruch." >&2; exit 1
fi
sleep 5
shot geladen

echo "=== Warten auf GPS-Prüfung (WLAN aus)"
"$ADB" shell svc wifi disable
for _ in $(seq 1 180); do
  # Nur aktive Anfragen zählen, keine Zeilen aus dem Verlauf (die beginnen mit Datum).
  if "$ADB" shell dumpsys location | grep -v -E "^ *[0-9]{2}-[0-9]{2} " \
      | grep "/$PKG/" | grep -q "Request\[@+1s.*HIGH_ACCURACY"; then
    echo "GPS-Abfrage aktiv"; break
  fi
  sleep 2
done

echo "=== Fahrt"
n=0
# Eigener Kanal für die Strecke: adb shell liest sonst die Standardeingabe leer.
while read -r LAT LON <&3; do
  geo "$LAT" "$LON" "$KNOTEN"; sleep 1; n=$((n + 1))
  case $n in
    "$ANSAGE_BEI") shot ansage
        if grep -q "Laden gescheitert" <<< "$(ui_text)"; then
          echo "Während der Fahrt fehlen Blitzerdaten. Abbruch." >&2; exit 1
        fi ;;
    "$MELDEN_BEI") tap_text "Melden"; sleep 1; shot melden; "$ADB" shell input keyevent BACK ;;
  esac
done 3< "$TMP/fixes.txt"

echo "=== Bilder verkleinern"
for name in ansage melden start; do
  ffmpeg -v error -y -i "$TMP/$name.png" -vf scale=540:-1 -frames:v 1 "$OUT/$name.png"
done
echo "Fertig: ansage, melden und start in $OUT. Jedes Bild vor dem Commit ansehen."
