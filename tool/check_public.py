"""Wächter für das öffentliche Repository. Aufruf aus dem Repo-Root, Exit 1 bei Fund.

Prüft alle verfolgten Dateien auf
- Zugangsdaten und Schlüsseldateien,
- lokale Plugins (lib/plugins/local/) und eine erzeugte installed_plugins.dart,
- Namen, die hier nicht hingehören (Datenquellen ohne passende Lizenz, private Kennungen).
  Die Namen stehen nur als SHA-256 im Skript, damit es sie nicht selbst verbreitet.
"""
import hashlib
import os
import re
import subprocess
import sys

# Aus Teilen zusammengesetzt, damit die Datei sich nicht selbst meldet.
SCHLUESSEL = re.compile(r"\b(?:" + "|".join([
    "gh" + r"[opsur]_[A-Za-z0-9]{30,}", "github" + r"_pat_[A-Za-z0-9_]{30,}",
    "sk" + r"-(?:ant-|proj-)?[A-Za-z0-9_-]{32,}", "AI" + r"za[0-9A-Za-z_-]{35}",
    "AK" + r"IA[0-9A-Z]{16}", "xo" + r"x[abprs]-[A-Za-z0-9-]{10,}",
    "sk" + r"_live_[A-Za-z0-9]{20,}", "hf" + r"_[A-Za-z0-9]{30,}",
    "npm" + r"_[A-Za-z0-9]{36}", "pypi" + r"-[A-Za-z0-9_-]{50,}",
]) + r")|-----BEGIN [A-Z ]*PRI" + "VATE KEY")

SCHLUESSELDATEI = re.compile(
    r"(^|/)\.env(\.(?!(example|sample|template)$)[^/]+)?$"
    r"|\.(pem|key|p12|pfx|jks|keystore)$|(^|/)key\.properties$|(^|/)local\.properties$")

HEIMATPFAD = re.compile(r"[A-Za-z]:[\\/]+Users[\\/]+[A-Za-z]|/Users/[a-z]|/home/[a-z]")

# Erste 16 Hex-Zeichen des SHA-256 kleingeschriebener Wörter, die nicht im öffentlichen
# Repository stehen dürfen. Neuen Eintrag erzeugen:
#   python -c "import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:16])" <wort>
VERBOTEN_PRAEFIXE = {
    "d2bca6e839c2d3fd", "35703759921d4828", "4c8feff2416c8a39", "dc9ef7c70f5f4002",
    "ef484b125ef349d0", "0afdf071d6f32a2d", "0e09b14fc22a842b", "394ff4bc42a560c0",
    "e7cbb9ab10f6c3bf", "171fce460de388e8", "20bb2d9d36841aaf", "83d512876997e675",
}

# Private Wörter im Klartext, ein Wort je Zeile. Die Datei liegt nur auf dem privaten Stand
# (tool/public-exclude.txt); tool/publish.ps1 reicht sie beim Export mit --woerter herein.
PRIVATE_WOERTER = "tool/private-woerter.txt"
WORT = re.compile(r"[a-z0-9_]+(?:\.[a-z0-9_]+)*")

LEERE_PLUGINLISTE = re.compile(r"=>\s*const\s*\[\s*\];")


def verboten(wort: str, privat: set[str]) -> bool:
    teile = {t for t in {wort, *wort.split("."), *wort.split("_")} if t}
    return any(t in privat or hashlib.sha256(t.encode()).hexdigest()[:16] in VERBOTEN_PRAEFIXE
               for t in teile)


def private_woerter() -> set[str]:
    """Wörter aus --woerter DATEI, sonst aus tool/private-woerter.txt, falls vorhanden."""
    pfad = PRIVATE_WOERTER
    if "--woerter" in sys.argv:
        i = sys.argv.index("--woerter")
        if i + 1 >= len(sys.argv):
            sys.exit("--woerter braucht einen Dateinamen")
        pfad = sys.argv[i + 1]
    try:
        zeilen = open(pfad, encoding="utf-8").read().splitlines()
    except OSError:
        if pfad != PRIVATE_WOERTER:
            sys.exit(f"Wortliste nicht lesbar: {pfad}")
        return set()
    return {z.strip().lower() for z in zeilen if z.strip() and not z.strip().startswith("#")}


def verfolgte_dateien() -> list[str]:
    """Dateien laut git; außerhalb eines Repositorys (Export) alle Dateien unter dem aktuellen Ordner."""
    try:
        roh = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True).stdout
        return [d for d in roh.decode("utf-8").split("\0") if d]
    except (OSError, subprocess.CalledProcessError):
        ueberspringen = {".git", ".dart_tool", "build", ".idea"}
        dateien = []
        for wurzel, ordner, namen in os.walk("."):
            ordner[:] = [o for o in ordner if o not in ueberspringen]
            for n in namen:
                dateien.append(os.path.relpath(os.path.join(wurzel, n), ".").replace(os.sep, "/"))
        return dateien


def privat_ausgeschlossen() -> list[str]:
    """Pfade aus tool/public-exclude.txt. Gibt es nur auf dem privaten Stand, nie im Export."""
    try:
        zeilen = open("tool/public-exclude.txt", encoding="utf-8").read().splitlines()
    except OSError:
        return []
    return [z.strip() for z in zeilen if z.strip() and not z.strip().startswith("#")]


def main() -> int:
    ausgeschlossen = privat_ausgeschlossen()
    privat = private_woerter()
    dateien = [
        d for d in verfolgte_dateien()
        if not any(d == p or (p.endswith("/") and d.startswith(p)) for p in ausgeschlossen)
    ]
    funde = []
    for d in dateien:
        if SCHLUESSELDATEI.search(d):
            funde.append(f"Schlüsseldatei verfolgt: {d}")
        if d.startswith("lib/plugins/local/"):
            funde.append(f"Lokales Plugin verfolgt: {d}")
    for d in dateien:
        try:
            text = open(d, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue  # Binärdatei
        zeile = lambda pos: text.count("\n", 0, pos) + 1  # noqa: E731
        for m in SCHLUESSEL.finditer(text):
            funde.append(f"{d}:{zeile(m.start())}: sieht aus wie ein Schlüssel ({m.group(0)[:4]}…)")
        for m in HEIMATPFAD.finditer(text):
            funde.append(f"{d}:{zeile(m.start())}: lokaler Heimatpfad")
        if d == "tool/check_public.py":
            continue
        gemeldet = set()
        for m in WORT.finditer(text.lower()):
            w = m.group(0)
            if w not in gemeldet and verboten(w, privat):
                gemeldet.add(w)
                funde.append(f"{d}:{zeile(m.start())}: Name, der nicht ins öffentliche Repo gehört")
    liste = "lib/plugins/installed_plugins.dart"
    if liste in dateien:
        inhalt = open(liste, encoding="utf-8").read()
        if "local/" in inhalt or not LEERE_PLUGINLISTE.search(inhalt):
            funde.append(f"{liste}: nicht die leere Fassung (dart run tool/plugins.dart --reset)")
    print("\n".join(funde) or "keine Funde")
    return 1 if funde else 0


if __name__ == "__main__":
    sys.exit(main())
