# App-Vorschauvideo

Das Video für den App Store (App Preview), iPhone hochkant **886 × 1920**,
28 Sekunden, mit eigens synthetisierter Musik. Es wird vollständig aus
diesem Ordner erzeugt - kein Schnittprogramm, keine fremden Dateien.

```bash
./tools/app-preview/build.sh
```

Ergebnis in `store/app-preview/` (nicht versioniert, siehe `.gitignore`):
`StudGo-App-Preview-886x1920.mp4` und `poster.png`. Der Lauf dauert einige
Minuten und braucht `node` mit Playwright (Chromium), `python3` mit `numpy`
und `ffmpeg` - alles im Container vorhanden.

## Ablauf

| Zeit | Szene | Zeile |
| --- | --- | --- |
| 0-2 s | Symbol, Telefon steigt auf | „Dein Stud.IP. In deiner Tasche." |
| 2-7,7 s | **Heute**: Karten fliegen ein, „Als Nächstes" hebt ab | „Keine Vorlesung mehr verpassen." |
| 7,7-12,7 s | **Plan**: Blöcke setzen sich ins Raster, Kamerafahrt über die Woche | „Deine Woche. Auf einen Blick." |
| 12,7-17,7 s | **Kurs**: Schwenk, die Kacheln heben nacheinander ab | „Jeder Kurs. Alles an einem Ort." |
| 17,7-22,7 s | **Mensa**: das erste Gericht hebt ab | „Mittagspause? Mensa inklusive." |
| 22,7-28 s | Drei Telefone, Symbol, Merkmale | „Bereit für das Semester?" |

Gewechselt wird jeweils über einen sichtbaren Tipp auf die Tab-Leiste.

## Wie es gebaut ist

- **`screens/`** - die echten Bildschirmfotos (Demo-Modus, dunkel). Sie
  werden nicht nachgebaut, sondern in Ebenen zerschnitten: Kopfzeile,
  Karten, Kacheln, Stundenplanblöcke. Die Schnitte liegen auf rein schwarzen
  Zeilen, deshalb fügen sie sich am Ende wieder lückenlos zum Original. Unter
  den Stundenplanblöcken wird das leere Raster aus einer freien Nachbarspalte
  eingesetzt, damit die Blöcke einzeln einfliegen können. Verändert wird nur
  die Statusleiste: volle Balken, voller Akku statt Stromsparmodus.
- **`preview.html`** - die Szene. `renderFrame(t)` setzt jeden Zustand aus
  der Zeit; nichts läuft von selbst, jedes Bild ist reproduzierbar.
- **`render.mjs`** - fotografiert die Seite mit doppelter Pixeldichte, Bild
  für Bild, mit vier Chromium-Seiten parallel.
- **`soundtrack.py`** - Musik und Geräusche (120 BPM, A-Dur): Der Beat setzt
  ein, wenn das Telefon aufsteigt, jeder Tipp klickt, die Stundenplanblöcke
  und Kacheln spielen eine Tonleiter, im Abspann landet alles auf dem
  Grundakkord. Etwa -16 LUFS, Spitzen unter -1 dBTP.
- **`timeline.json`** - die Zeitmarken, die Bild und Ton gemeinsam nutzen.
  Wer eine Szene verschiebt, verschiebt sie hier; die Musik folgt.

Ansehen ohne Aufnahme:

```bash
node tools/app-preview/render.mjs --serve
# http://127.0.0.1:8642/tools/app-preview/preview.html?t=5   Standbild
# http://127.0.0.1:8642/tools/app-preview/preview.html?play  Echtzeit
node tools/app-preview/render.mjs --stills 3,9,15 --out /tmp/stills   # einzelne Bilder
```

Neue Bildschirmfotos (andere Sprache, neue Fassung) gehören in `screens/`
unter denselben Namen. Ändert sich das Layout der App, stimmen die
Ebenengrenzen in `SCREENS` (preview.html) nicht mehr und müssen neu
ausgemessen werden.

## Hochladen

App Store Connect → App → Version → *Vorschauen und Bildschirmfotos* →
iPhone 6,9" (gilt auch für 6,7" und 6,5"). Als Posterbild eignet sich die
Stelle um 5 s - die herausgehobene Karte „Als Nächstes"; `poster.png` zeigt
genau dieses Bild.

`build.sh` prüft am Ende Apples Vorgaben: 886 × 1920, H.264 High Profile
Level 4.0, 30 fps konstant, 15-30 s, AAC Stereo, unter 500 MB.

Zu Richtlinie 2.3.4 (Vorschauen zeigen die App selbst): Alles, was im iPhone
zu sehen ist, stammt aus Bildschirmfotos der App; Text, Symbol und Musik
liegen als Überlagerung darüber. Preise kommen im Video nicht vor.
