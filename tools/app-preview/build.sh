#!/usr/bin/env bash
# Baut das App-Store-Vorschauvideo (App Preview) für das iPhone, 886 × 1920.
#
#   ./tools/app-preview/build.sh
#
# Schritte: Soundtrack synthetisieren, preview.html Bild für Bild mit
# doppelter Pixeldichte aufnehmen, auf 886 × 1920 verkleinern und nach
# Apples Vorgaben kodieren:
#   H.264 High Profile, Level 4.0, ~11 Mbit/s (2 Durchgänge), 30 fps konstant,
#   AAC Stereo 256 kbit/s, 48 kHz, 28 s (erlaubt sind 15-30 s), BT.709.
#
# Ergebnis in store/ (nicht versioniert):
#   store/app-preview/StudGo-App-Preview-886x1920.mp4
#   store/app-preview/poster.png        Vorschlag für das Posterbild (bei 5 s)
#
# Braucht: node mit playwright (Chromium), python3 mit numpy, ffmpeg.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$ROOT/store/app-preview"
FRAMES="$OUT/frames"
VIDEO="$OUT/StudGo-App-Preview-886x1920.mp4"
POSTER_AT="${POSTER_AT:-5.0}"

mkdir -p "$OUT"

echo "== Soundtrack"
python3 "$HERE/soundtrack.py" "$OUT/soundtrack.wav"

echo "== Bilder"
rm -rf "$FRAMES"
node "$HERE/render.mjs" --out "$FRAMES" --scale 2 --workers "${WORKERS:-4}"

echo "== Kodieren"
FPS="$(python3 -c "import json;print(json.load(open('$HERE/timeline.json'))['fps'])")"
VF="scale=886:1920:flags=lanczos+accurate_rnd+full_chroma_int:out_color_matrix=bt709:out_range=tv,format=yuv420p"
X264=(-c:v libx264 -profile:v high -level:v 4.0 -preset slow -tune animation
      -b:v 11M -maxrate 12M -bufsize 12M -g 60 -bf 2
      -x264-params "colorprim=bt709:transfer=bt709:colormatrix=bt709"
      -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv)
cd "$OUT"
ffmpeg -hide_banner -loglevel warning -y -framerate "$FPS" -i "$FRAMES/%04d.png" \
  -vf "$VF" "${X264[@]}" -pass 1 -passlogfile "$OUT/x264" -an -f mp4 /dev/null
ffmpeg -hide_banner -loglevel warning -y -framerate "$FPS" -i "$FRAMES/%04d.png" -i "$OUT/soundtrack.wav" \
  -vf "$VF" "${X264[@]}" -pass 2 -passlogfile "$OUT/x264" -r "$FPS" \
  -c:a aac -b:a 256k -ar 48000 -ac 2 \
  -map 0:v:0 -map 1:a:0 -shortest -movflags +faststart "$VIDEO"
rm -f "$OUT"/x264*.log*

ffmpeg -hide_banner -loglevel error -y -ss "$POSTER_AT" -i "$VIDEO" -frames:v 1 "$OUT/poster.png"

echo "== Prüfen"
python3 - "$VIDEO" <<'EOF'
import json, subprocess, sys
info = json.loads(subprocess.check_output(
    ["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", sys.argv[1]]))
v = next(s for s in info["streams"] if s["codec_type"] == "video")
a = next(s for s in info["streams"] if s["codec_type"] == "audio")
dur = float(info["format"]["duration"])
num, den = map(int, v["r_frame_rate"].split("/"))
checks = [
    ("Auflösung 886 × 1920", (v["width"], v["height"]) == (886, 1920)),
    ("H.264 High, Level 4.0", v["codec_name"] == "h264" and v["profile"] == "High" and v["level"] == 40),
    ("yuv420p", v["pix_fmt"] == "yuv420p"),
    ("30 fps konstant", num / den == 30 and v["avg_frame_rate"] == v["r_frame_rate"]),
    ("Länge 15-30 s", 15 <= dur <= 30),
    ("AAC Stereo 48 kHz", a["codec_name"] == "aac" and a["channels"] == 2 and a["sample_rate"] == "48000"),
    ("unter 500 MB", int(info["format"]["size"]) < 500e6),
]
for name, ok in checks:
    print(("  ok    " if ok else "  FEHLT ") + name)
print(f"  {dur:.2f} s, {int(info['format']['bit_rate']) / 1e6:.1f} Mbit/s, {int(info['format']['size']) / 1e6:.1f} MB")
sys.exit(0 if all(ok for _, ok in checks) else 1)
EOF
echo "fertig: $VIDEO"
