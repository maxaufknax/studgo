#!/usr/bin/env python3
"""Erzeugt das StudGo-App-Icon als PNG — ohne externe Abhängigkeiten.

Vektorbeschreibung (Doktorhut auf Farbverlauf) wird mit Scanline-Füllung und
3-facher vertikaler Überabtastung gerastert, das reicht für saubere Kanten.

    ./tools/make-icon.py
"""
import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
SUBSAMPLES = 4  # vertikale Überabtastung pro Pixelzeile

# Ein Satz Farben je Erscheinungsbild. iOS 18 zeigt auf dem Hoheitsbildschirm
# je nach Einstellung eine helle, eine dunkle oder eine eingefärbte Fassung;
# ohne eigene Vorlagen rechnet das System sie sich selbst aus, meist schlechter.
# Die Achse führt von fast Schwarz zum Blau der Wortmarke (#38B6FF): Damit
# stehen Symbol und Logo (App/Resources/Assets.xcassets/AppLogo.imageset)
# erkennbar in derselben Farbwelt. Das vorige Indigo hatte mit dem Logo
# nichts zu tun — nebeneinander sahen sie nach zwei Programmen aus.
VARIANTS = {
    # hell: fast Schwarz nach Logoblau
    "": {"top": (10, 14, 34), "bottom": (33, 130, 220), "ink": (255, 255, 255)},
    # dunkel: dieselbe Achse, deutlich abgedunkelt
    "-dark": {"top": (4, 5, 12), "bottom": (16, 74, 142), "ink": (240, 247, 255)},
    # eingefärbt: iOS liest nur die Helligkeit und legt den Farbton selbst an
    "-tinted": {"top": (10, 10, 10), "bottom": (58, 58, 58), "ink": (255, 255, 255)},
}


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def coverage(polygons, width, height):
    """Deckungsgrad je Pixel (0.0–1.0) für die *Vereinigung* der Polygone.

    Jede Form wird einzeln gerastert und per Maximum überlagert — würden alle
    Kanten in einem Durchgang laufen, stanzte die Even-Odd-Regel die
    Überlappungen wieder aus.
    """
    cov = [0.0] * (width * height)
    for shape in polygons:
        for index, value in enumerate(fill(shape, width, height)):
            if value > cov[index]:
                cov[index] = value
    return cov


def fill(points, width, height):
    """Deckungsgrad je Pixel für ein einzelnes Polygon."""
    cov = [0.0] * (width * height)
    edges = []
    for i in range(len(points)):
        x0, y0 = points[i]
        x1, y1 = points[(i + 1) % len(points)]
        if y0 != y1:
            edges.append((x0, y0, x1, y1))

    weight = 1.0 / SUBSAMPLES
    for row in range(height):
        for sub in range(SUBSAMPLES):
            y = row + (sub + 0.5) / SUBSAMPLES
            crossings = []
            for x0, y0, x1, y1 in edges:
                if (y0 <= y < y1) or (y1 <= y < y0):
                    crossings.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
            if not crossings:
                continue
            crossings.sort()
            base = row * width
            for i in range(0, len(crossings) - 1, 2):
                left, right = crossings[i], crossings[i + 1]
                if right <= 0 or left >= width:
                    continue
                left, right = max(left, 0.0), min(right, float(width))
                first, last = int(left), min(int(right), width - 1)
                if first == last:
                    cov[base + first] += (right - left) * weight
                    continue
                cov[base + first] += (first + 1 - left) * weight
                for x in range(first + 1, last):
                    cov[base + x] += weight
                cov[base + last] += (right - last) * weight
    return cov


def circle(cx, cy, r, segments=64):
    return [(cx + r * math.cos(2 * math.pi * i / segments),
             cy + r * math.sin(2 * math.pi * i / segments)) for i in range(segments)]


def translate(shape, dx, dy):
    return [(x + dx, y + dy) for x, y in shape]


def cap_shapes():
    """Doktorhut: Korpus, Brett, Quaste."""
    body = [(332, 430), (692, 430), (664, 646)]
    # Leicht konkave Unterkante, damit der Hut nicht wie ein Eimer wirkt
    for i in range(21):
        t = i / 20
        x = 664 + (360 - 664) * t
        y = 646 - 46 * math.sin(math.pi * t)
        body.append((x, y))
    board = [(150, 404), (512, 250), (874, 404), (512, 558)]
    # Die Schnur beginnt ein Stück *innerhalb* des Bretts und tritt unten aus
    # ihm heraus. An der äußersten Spitze ist das Brett unendlich dünn — dort
    # angesetzt stand die Schnur darüber hinaus und riss eine sichtbare Kerbe
    # in die Silhouette.
    tassel_cord = [(819, 396), (841, 396), (841, 592), (819, 592)]
    tassel_knot = circle(830, 628, 44)
    # Die Quaste zieht das Gewicht nach rechts, das gleicht die Verschiebung aus.
    return [translate(shape, -18, 46) for shape in (body, board, tassel_cord, tassel_knot)]


def render(palette, cov):
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # Filter-Byte je Zeile
        # Diagonaler Verlauf wirkt lebendiger als ein rein vertikaler
        row_base = y * SIZE
        for x in range(SIZE):
            t = min(1.0, max(0.0, (x * 0.35 + y * 0.65) / SIZE))
            r, g, b = lerp(palette["top"], palette["bottom"], t)
            a = min(1.0, cov[row_base + x])
            if a:
                ink = palette["ink"]
                r = round(r + (ink[0] - r) * a)
                g = round(g + (ink[1] - g) * a)
                b = round(b + (ink[2] - b) * a)
            raw += bytes((r, g, b))
    return bytes(raw)


def write_png(path, raw, size):
    def chunk(tag, data):
        payload = tag + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload))

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # 8 bit, Truecolor
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", header)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    path.write_bytes(png)


if __name__ == "__main__":
    folder = (Path(__file__).resolve().parent.parent
              / "App/Resources/Assets.xcassets/AppIcon.appiconset")
    folder.mkdir(parents=True, exist_ok=True)

    # Die Deckungsmaske ist für alle Fassungen dieselbe — einmal rastern reicht.
    cov = coverage(cap_shapes(), SIZE, SIZE)

    for suffix, palette in VARIANTS.items():
        target = folder / f"icon-1024{suffix}.png"
        write_png(target, render(palette, cov), SIZE)
        print(f"{target.name} — {target.stat().st_size / 1024:.0f} KB")
