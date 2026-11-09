"""Erzeugt das Launcher-Icon von Sonarb (alle Dichten + adaptives Icon).

Aufruf: python tool/gen_icon.py   (braucht Pillow)
Motiv: Punkt mit drei Sonar-Bögen in Fahrtrichtung (oben), Bernstein auf Fast-Schwarz.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"

BG = (14, 17, 20, 255)
AMBER = (255, 176, 32, 255)
S = 1024  # Arbeitsgröße, danach herunterskalieren


def motiv(size: int, scale: float) -> Image.Image:
    """Motiv auf transparentem Grund. scale < 1 lässt Rand für adaptive Masken."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx, cy = size / 2, size / 2
    unit = size * scale
    outer = unit * 0.46

    # Peilsektor: nach außen schwächer werdender Keil Richtung Norden.
    keil = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    kd = ImageDraw.Draw(keil)
    for i in range(40, 0, -1):
        r = outer * i / 40
        a = int(150 * (1 - i / 40) + 40)
        kd.pieslice([cx - r, cy - r, cx + r, cy + r], start=-118, end=-62, fill=AMBER[:3] + (a,))
    img.alpha_composite(keil)

    d = ImageDraw.Draw(img)
    ring = max(2, int(unit * 0.035))
    for r, a in ((0.46, 255), (0.29, 170)):
        rad = unit * r
        d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], outline=AMBER[:3] + (a,), width=ring)
    dot = unit * 0.085
    d.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=AMBER)
    return img


def legacy() -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=S * 0.22, fill=255)
    bg = Image.new("RGBA", (S, S), BG)
    img.paste(bg, (0, 0), mask)
    img.alpha_composite(motiv(S, 0.9))
    return img


def main() -> None:
    dichten = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    icon = legacy()
    fg = motiv(S, 0.62)  # sichere Zone des adaptiven Icons: 66 von 108 dp
    for name, f in dichten.items():
        ordner = RES / f"mipmap-{name}"
        ordner.mkdir(parents=True, exist_ok=True)
        icon.resize((int(48 * f),) * 2, Image.LANCZOS).save(ordner / "ic_launcher.png")
        fg.resize((int(108 * f),) * 2, Image.LANCZOS).save(ordner / "ic_launcher_foreground.png")

    any_dpi = RES / "mipmap-anydpi-v26"
    any_dpi.mkdir(parents=True, exist_ok=True)
    (any_dpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    values = RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#0E1114</color>\n</resources>\n',
        encoding="utf-8",
    )
    icon.resize((512, 512), Image.LANCZOS).save(ROOT / "docs" / "icon-512.png")
    print("Icons geschrieben nach", RES)


if __name__ == "__main__":
    main()
