#!/usr/bin/env python3
"""Erzeugt die Markenbilder von StudGo aus den Logo-Entwürfen.

Ein Bild, drei Verwendungen: die Wortmarke „StudGo" (blaues „Stud", weißes
„Go") mit Doktorhut über dem „o", auf schwarzem Grund mit fein angedeuteten
Schul-Kritzeleien — genau die Anmutung der Entwürfe.

    ./tools/make-brand.py

Ergebnis:
  App/Resources/Assets.xcassets/AppLogo.imageset/studgo-logo.png   (In-App-Logo)
  App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024*.png  (App-Symbol)

Die Symbol-Fassung trägt die Wortmarke bewusst mit: So steht das App-Symbol in
derselben Bildwelt wie Anmeldebildschirm und „Über StudGo". Für iOS 18 gibt es
zusätzlich eine dunkle und eine eingefärbte Fassung (dort steht die Wortmarke
einfarbig weiß, damit die Systemtönung sauber greift).
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App/Resources/Assets.xcassets"

# Meistermaß: großzügig gerechnet, am Ende auf die Zielgröße verkleinert —
# das gibt saubere, glatte Kanten (Supersampling).
S = 2048

BLUE = (56, 182, 255)        # #38B6FF — das Blau der Wortmarke
WHITE = (255, 255, 255)
NIGHT = (11, 11, 14)         # fast schwarzer Grund wie in den Entwürfen
NIGHT_DARK = (6, 6, 9)       # für die dunkle Symbol-Fassung
DOODLE = (32, 33, 40)        # die Kritzeleien: knapp über dem Grund

FONT_PATH = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"


# ---------------------------------------------------------------- Kritzeleien

def doodle_layer(size, color, seed=7):
    """Eine Ebene mit verstreuten, gedrehten Schul-Kritzeleien.

    Dünn gestrichelt und nur knapp heller als der Grund: eine Textur, kein
    Muster, das mit der Wortmarke um Aufmerksamkeit ringt.
    """
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rng = random.Random(seed)
    lw = max(2, size // 380)

    def glyph(kind, box):
        """Zeichnet ein Kritzel in einen eigenen, später gedrehten Kasten."""
        tile = Image.new("RGBA", (box, box), (0, 0, 0, 0))
        d = ImageDraw.Draw(tile)
        c = color + (255,)
        m = box // 2
        if kind == "triangle":  # Geodreieck
            d.polygon([(box * 0.12, box * 0.82), (box * 0.88, box * 0.82),
                       (box * 0.5, box * 0.16)], outline=c, width=lw)
            d.line([(box * 0.24, box * 0.82), (box * 0.5, box * 0.34)], fill=c, width=lw)
        elif kind == "ruler":  # Lineal mit Teilstrichen
            d.rectangle([box * 0.14, box * 0.40, box * 0.86, box * 0.60], outline=c, width=lw)
            for i in range(1, 7):
                x = box * (0.14 + 0.72 * i / 7)
                d.line([(x, box * 0.40), (x, box * 0.40 + box * (0.10 if i % 2 else 0.16))],
                       fill=c, width=lw)
        elif kind == "pencil":  # Bleistift
            d.line([(box * 0.20, box * 0.80), (box * 0.74, box * 0.26)], fill=c, width=lw)
            d.polygon([(box * 0.74, box * 0.26), (box * 0.84, box * 0.16),
                       (box * 0.80, box * 0.34)], outline=c, width=lw)
            d.line([(box * 0.20, box * 0.80), (box * 0.16, box * 0.84)], fill=c, width=lw)
        elif kind == "atom":  # Atommodell
            d.ellipse([box * 0.16, box * 0.34, box * 0.84, box * 0.66], outline=c, width=lw)
            d.ellipse([box * 0.34, box * 0.16, box * 0.66, box * 0.84], outline=c, width=lw)
            d.ellipse([m - lw, m - lw, m + lw, m + lw], fill=c)
        elif kind == "bulb":  # Glühbirne (Idee)
            d.ellipse([box * 0.30, box * 0.18, box * 0.70, box * 0.58], outline=c, width=lw)
            d.line([(box * 0.42, box * 0.58), (box * 0.42, box * 0.70)], fill=c, width=lw)
            d.line([(box * 0.58, box * 0.58), (box * 0.58, box * 0.70)], fill=c, width=lw)
            d.line([(box * 0.42, box * 0.70), (box * 0.58, box * 0.70)], fill=c, width=lw)
        elif kind == "star":
            pts = []
            for i in range(10):
                r = box * (0.34 if i % 2 == 0 else 0.15)
                a = math.pi / 2 + i * math.pi / 5
                pts.append((m + r * math.cos(a), m - r * math.sin(a)))
            d.polygon(pts, outline=c, width=lw)
        elif kind == "molecule":  # verbundene Punkte
            nodes = [(box * 0.28, box * 0.34), (box * 0.60, box * 0.26),
                     (box * 0.72, box * 0.60), (box * 0.40, box * 0.72)]
            for a in range(len(nodes)):
                for b in range(a + 1, len(nodes)):
                    if rng.random() < 0.6:
                        d.line([nodes[a], nodes[b]], fill=c, width=lw)
            for nx, ny in nodes:
                d.ellipse([nx - box * 0.05, ny - box * 0.05,
                           nx + box * 0.05, ny + box * 0.05], fill=c)
        elif kind == "percent":
            d.ellipse([box * 0.24, box * 0.24, box * 0.40, box * 0.40], outline=c, width=lw)
            d.ellipse([box * 0.60, box * 0.60, box * 0.76, box * 0.76], outline=c, width=lw)
            d.line([(box * 0.30, box * 0.72), (box * 0.70, box * 0.28)], fill=c, width=lw)
        elif kind == "compass":  # Zirkel
            d.line([(m, box * 0.20), (box * 0.34, box * 0.80)], fill=c, width=lw)
            d.line([(m, box * 0.20), (box * 0.66, box * 0.80)], fill=c, width=lw)
            d.ellipse([m - box * 0.04, box * 0.16, m + box * 0.04, box * 0.24], fill=c)
        return tile.rotate(rng.uniform(-38, 38), expand=True, resample=Image.BICUBIC)

    kinds = ["triangle", "ruler", "pencil", "atom", "bulb", "star",
             "molecule", "percent", "compass"]
    # Ein lockeres Raster mit Zufallsversatz — deckt die Fläche gleichmäßig,
    # ohne wie ein Raster auszusehen.
    step = size // 5
    for gy in range(-1, 6):
        for gx in range(-1, 6):
            kind = rng.choice(kinds)
            box = int(step * rng.uniform(0.72, 1.05))
            g = glyph(kind, box)
            cx = int(gx * step + step * 0.5 + rng.uniform(-step * 0.28, step * 0.28))
            cy = int(gy * step + step * 0.5 + rng.uniform(-step * 0.28, step * 0.28))
            layer.alpha_composite(g, (cx - g.width // 2, cy - g.height // 2))
    return layer


# --------------------------------------------------------------- Doktorhut

def cap_layer(width, ink=WHITE):
    """Ein Doktorhut (Brett, Kopfteil, Quaste) als eigene, drehbare Ebene.

    Koordinaten in einem 1000×1000-Feld, danach auf `width` skaliert.
    """
    F = 1000
    tile = Image.new("RGBA", (F, F), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    c = ink + (255,)

    # Kopfteil (leicht konkave Unterkante, damit es kein Eimer ist)
    body = [(332, 470), (668, 470), (632, 688)]
    for i in range(21):
        t = i / 20
        x = 632 + (368 - 632) * t
        y = 688 - 44 * math.sin(math.pi * t)
        body.append((x, y))
    d.polygon(body, fill=c)

    # Brett (Raute)
    d.polygon([(150, 452), (512, 300), (874, 452), (512, 604)], fill=c)

    # Knopf in der Mitte
    d.ellipse([512 - 26, 430 - 26, 512 + 26, 430 + 26], fill=c)
    # Quastenschnur + Quaste rechts
    d.line([(830, 440), (830, 660)], fill=c, width=18)
    d.ellipse([830 - 40, 660 - 20, 830 + 40, 660 + 74], fill=c)

    scale = width / F
    tile = tile.resize((int(F * scale), int(F * scale)), Image.LANCZOS)
    return tile


# --------------------------------------------------------------- Zusammenbau

def gradient_background(size, top, bottom):
    """Sehr sanfter Verlauf von oben nach unten — gibt dem Schwarz Tiefe,
    ohne dass es bunt wirkt."""
    grad = Image.new("RGB", (size, size))
    for y in range(size):
        t = (y / (size - 1)) ** 2  # weiche Kurve: unten nur wenig heller
        col = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        grad.paste(col, (0, y, size, y + 1))
    return grad


def build(size, night, mono=False):
    img = gradient_background(size, night, tuple(min(255, c + 10) for c in night)).convert("RGBA")

    # Kritzeleien
    img.alpha_composite(doodle_layer(size, DOODLE if not mono else (30, 30, 30)))

    # sanfte Vignette, damit die Ränder ruhiger sind und die Wortmarke trägt
    vig = Image.new("L", (size, size), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-size * 0.15, -size * 0.15, size * 1.15, size * 1.15], fill=90)
    vig = vig.point(lambda v: 255 - v)
    shade = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shade.putalpha(vig)
    img.alpha_composite(shade)

    # Wortmarke
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT_PATH, int(size * 0.235))
    stud, go = "Stud", "Go"
    w_stud = draw.textlength(stud, font=font)
    w_go = draw.textlength(go, font=font)
    total = w_stud + w_go
    ascent, descent = font.getmetrics()
    text_h = ascent + descent

    x0 = (size - total) / 2
    y0 = size * 0.5 - text_h * 0.5 + size * 0.02  # eine Idee unter die Mitte

    blue = WHITE if mono else BLUE
    draw.text((x0, y0), stud, font=font, fill=blue + (255,))
    draw.text((x0 + w_stud, y0), go, font=font, fill=WHITE + (255,))

    # Doktorhut über das „o" von „Go" setzen, leicht gekippt
    go_start = x0 + w_stud
    o_center_x = go_start + w_go * 0.74
    cap_w = size * 0.30
    cap = cap_layer(int(cap_w), ink=WHITE)
    cap = cap.rotate(12, expand=True, resample=Image.BICUBIC)
    cap_x = int(o_center_x - cap.width * 0.5)
    cap_y = int(y0 - cap.height * 0.62)
    img.alpha_composite(cap, (cap_x, cap_y))

    return img


def save_opaque(img, path, size):
    """Als undurchsichtiges RGB in Zielgröße speichern — App-Symbole dürfen
    keinen Alphakanal tragen."""
    out = img.resize((size, size), Image.LANCZOS).convert("RGB")
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path)
    print(f"{path.name} — {size}px — {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    # In-App-Logo: volle Auflösung, mit Alpha erlaubt (wird ohnehin als Kachel
    # mit runden Ecken gezeigt) — aber undurchsichtig gehalten.
    logo = build(S, NIGHT)
    save_opaque(logo, ASSETS / "AppLogo.imageset/studgo-logo.png", 1024)

    # App-Symbol: hell, dunkel, eingefärbt
    save_opaque(build(S, NIGHT), ASSETS / "AppIcon.appiconset/icon-1024.png", 1024)
    save_opaque(build(S, NIGHT_DARK), ASSETS / "AppIcon.appiconset/icon-1024-dark.png", 1024)
    save_opaque(build(S, (8, 8, 8), mono=True), ASSETS / "AppIcon.appiconset/icon-1024-tinted.png", 1024)
