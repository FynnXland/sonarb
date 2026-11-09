#!/usr/bin/env bash
# Erzeugt die Bilder für die README aus der echten App auf einem Android-Emulator.
#
#   tool/media/screenshots.sh            Debug-Build (Paket de.fynn.handy.sonarb.debug)
#   BUILD=release tool/media/screenshots.sh   Release-Build (braucht den Keystore)
#
# Voraussetzungen: genau ein laufender Emulator (adb), Flutter, Python 3 (PYTHON=…), ffmpeg.
# Die App-Daten des gewählten Pakets werden gelöscht. Die Fahrt ist erfunden und folgt
# tool/media/route.json (Amsinckstraße, Hamburg). Ergebnis in docs/media/.
#
#
# Im Stand ortet Sonarb nur sparsam über WLAN und Funkzellen; geo fix geht ans GPS. Deshalb schaltet das
# Skript nach dem Laden WLAN und mobile Daten ab, wartet, bis die App selbst aufs GPS schaut (GPS-Prüfung
# nach etwa 2 min, siehe docs/ORTUNG.md), und startet erst dann die Fahrt. Am Ende ist beides wieder an.
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

# geo LAT LON [KNOTEN]: GPS-Fix mit Tempo, sonst erkennt die App keine Fahrt.
geo() { "$ADB" emu geo fix "$2" "$1" 10 12 "${3:-0}" > /dev/null; }
KMH=40
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
sleep 30   # Messstellen der Umgebung laden
shot geladen
"$ADB" shell uiautomator dump /sdcard/sonarb-ui.xml > /dev/null
if "$ADB" shell cat /sdcard/sonarb-ui.xml | grep -q "Laden gescheitert"; then
  echo "Blitzerdaten nicht geladen (Overpass nicht erreichbar?). Abbruch." >&2; exit 1
fi

echo "=== Warten auf GPS-Prüfung (WLAN und Daten aus)"
"$ADB" shell svc wifi disable
"$ADB" shell svc data disable
for _ in $(seq 1 180); do
  # Nur aktive Anfragen zählen, keine Zeilen aus dem Verlauf (die beginnen mit Datum).
  if "$ADB" shell dumpsys location | grep -v -E "^ *[0-9]{2}-[0-9]{2} " \n      | grep "/$PKG/" | grep -q "Request\[@+1s.*HIGH_ACCURACY"; then
    echo "GPS-Abfrage aktiv"; break
  fi
  sleep 2
done

echo "=== Fahrt"
n=0
while read -r LAT LON; do
  geo "$LAT" "$LON" "$KNOTEN"; sleep 1; n=$((n + 1))
  case $n in
    30) shot ansage ;;
    45) tap_text "Melden"; sleep 1; shot melden; "$ADB" shell input keyevent BACK ;;
  esac
done < "$TMP/fixes.txt"

echo "=== Bilder zusammensetzen"
# Hero: Fahrt mit Ansage, Melden, Startbildschirm nebeneinander, je 540 px breit.
ffmpeg -v error -y -i "$TMP/ansage.png" -i "$TMP/melden.png" -i "$TMP/start.png" \
  -filter_complex "[0]scale=540:-1[a];[1]scale=540:-1[b];[2]scale=540:-1[c];[a][b][c]hstack=3,pad=iw+80:ih+60:40:30:color=0x0E1114" \
  -frames:v 1 "$OUT/hero.png"
for name in ansage melden start; do
  ffmpeg -v error -y -i "$TMP/$name.png" -vf scale=540:-1 -frames:v 1 "$OUT/$name.png"
done
echo "Fertig: $OUT/hero.png und Einzelbilder. Jedes Bild vor dem Commit ansehen."
