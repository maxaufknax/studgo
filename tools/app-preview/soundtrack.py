#!/usr/bin/env python3
"""Musik und Geräusche zum Vorschauvideo, synthetisiert - kein Sample, keine Lizenz.

    python3 soundtrack.py <ausgabe.wav>

Alles hängt an `timeline.json`: Der Beat setzt ein, wenn das Telefon
aufsteigt, jeder Tipp klickt, jede herausgehobene Karte klingt, die Blöcke
im Stundenplan spielen eine kleine Tonleiter, und im Abspann landet alles
auf dem Grundakkord. 120 BPM, A-Dur, 48 kHz Stereo.

Braucht nur numpy. Filter und Hall laufen über FFT, deshalb ohne scipy.
"""

import json
import sys
import wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
TL = json.loads((HERE / "timeline.json").read_text())

SR = 48000
DUR = TL["duration"]
N = int(round(DUR * SR))
BEAT = 60 / TL["bpm"]
BAR = 4 * BEAT
STEP = BEAT / 4
rng = np.random.default_rng(7)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def secs(n):
    return np.arange(int(round(n * SR))) / SR


# ---------------------------------------------------------------------------
# Spuren
# ---------------------------------------------------------------------------

class Bus:
    """Eine Stereospur; `add` legt ein Mono- oder Stereosignal an Stelle t."""

    def __init__(self):
        self.x = np.zeros((2, N))

    def add(self, sig, t, gain=1.0, pan=0.0):
        i0 = int(round(t * SR))
        sig = np.atleast_2d(sig)
        if sig.shape[0] == 1:
            a = (pan + 1) * np.pi / 4
            sig = np.vstack([sig[0] * np.cos(a), sig[0] * np.sin(a)]) * np.sqrt(2)
        # Jedes Signal endet mit 5 ms Ausblendung - abgeschnittene Hüllkurven
        # knacken sonst.
        k = min(sig.shape[1], int(0.005 * SR))
        sig = sig.copy()
        sig[:, sig.shape[1] - k:] *= np.linspace(1, 0, k)
        if i0 < 0:
            sig, i0 = sig[:, -i0:], 0
        n = min(sig.shape[1], N - i0)
        if n > 0:
            self.x[:, i0:i0 + n] += sig[:, :n] * gain


# ---------------------------------------------------------------------------
# Filter (Nullphase, im Frequenzbereich)
# ---------------------------------------------------------------------------

def _apply(x, resp):
    x = np.atleast_2d(x)
    n = x.shape[-1]
    size = 1 << int(np.ceil(np.log2(n + 1)))
    f = np.fft.rfftfreq(size, 1 / SR)
    spec = np.fft.rfft(x, size, axis=-1) * resp(f)
    y = np.fft.irfft(spec, size, axis=-1)[..., :n]
    return y if y.shape[0] > 1 else y[0]


def lowpass(x, fc, order=2):
    return _apply(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return _apply(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, lo, hi, order=2):
    return highpass(lowpass(x, hi, order), lo, order)


def sweep_filter(x, center_of_t, q=1.2):
    """Bandpass mit wanderndem Mittelpunkt (STFT), für Rauschfahnen."""
    win = 2048
    hop = win // 4
    w = np.hanning(win)
    n = len(x)
    pad = np.concatenate([np.zeros(win), x, np.zeros(win)])
    out = np.zeros_like(pad)
    norm = np.zeros_like(pad)
    f = np.fft.rfftfreq(win, 1 / SR)
    for start in range(0, len(pad) - win, hop):
        tc = (start + win / 2 - win) / SR
        c = center_of_t(np.clip(tc, 0, n / SR))
        resp = np.exp(-0.5 * (np.log2(np.maximum(f, 1) / c) / q) ** 2)
        seg = np.fft.irfft(np.fft.rfft(pad[start:start + win] * w) * resp, win)
        out[start:start + win] += seg * w
        norm[start:start + win] += w * w
    return (out / np.maximum(norm, 1e-6))[win:win + n]


# ---------------------------------------------------------------------------
# Klangerzeuger
# ---------------------------------------------------------------------------

def saw(freq, n, phase=0.0):
    """Sägezahn mit PolyBLEP - ohne die Spiegelfrequenzen des naiven Sägezahns."""
    dt = freq / SR
    ph = (phase + dt * np.arange(n)) % 1.0
    y = 2 * ph - 1
    a = ph < dt
    x = ph[a] / dt
    y[a] -= x + x - x * x - 1
    b = ph > 1 - dt
    x = (ph[b] - 1) / dt
    y[b] -= x * x + x + x + 1
    return y


def adsr(n, a, d, s, r, hold):
    """Hüllkurve: Anstieg, Abfall auf s, halten bis `hold`, Ausklang r (Sekunden)."""
    t = np.arange(n) / SR
    env = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = t > hold
    env[rel] *= np.exp(-(t[rel] - hold) / max(r, 1e-4))
    return env


def pad_note(m, length, bright=1800):
    n = int((length + 1.4) * SR)
    voices = []
    for det, pan in ((-0.09, -0.6), (0.0, 0.0), (0.09, 0.6)):
        v = saw(midi(m + det), n, rng.random())
        a = (pan + 1) * np.pi / 4
        voices.append(np.vstack([v * np.cos(a), v * np.sin(a)]))
    sig = sum(voices) / 3
    sig = lowpass(sig, bright, 2)
    return sig * adsr(n, 0.35, 0.8, 0.8, 0.45, length)


def pluck(m, vel=1.0, decay=7.0, ratio=2.0, index=2.4):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    f = midi(m)
    mod = index * np.exp(-t * 16) * np.sin(2 * np.pi * f * ratio * t)
    env = np.minimum(t / 0.002, 1) * np.exp(-t * decay)
    return vel * env * np.sin(2 * np.pi * f * t + mod)


def bell(m, vel=1.0, length=2.5):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = midi(m)
    mod = 1.6 * np.exp(-t * 3) * np.sin(2 * np.pi * f * 3.5 * t)
    env = np.minimum(t / 0.003, 1) * np.exp(-t * 2.2)
    return vel * env * (np.sin(2 * np.pi * f * t + mod) + 0.25 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 5))


def bass_note(m, length):
    n = int((length + 0.2) * SR)
    t = np.arange(n) / SR
    f = midi(m)
    body = np.sin(2 * np.pi * f * t) + 0.55 * np.sin(2 * np.pi * f / 2 * t)
    grit = lowpass(saw(f, n), 420, 2) * 0.45
    env = adsr(n, 0.004, 0.09, 0.55, 0.03, length)
    return np.tanh(1.4 * (body + grit) * env) * 0.8


def kick(big=False):
    n = int((0.9 if big else 0.45) * SR)
    t = np.arange(n) / SR
    f = 44 + 120 * np.exp(-t * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * (3.2 if big else 6.5))
    click = highpass(rng.standard_normal(n) * np.exp(-t * 900), 1500) * 0.35
    return np.tanh(1.6 * (body + click))


def clap():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    env = np.zeros(n)
    for k, off in enumerate((0, 0.011, 0.022)):
        m = t >= off
        env[m] += np.exp(-(t[m] - off) * (220 if k < 2 else 20))
    return bandpass(noise * env, 900, 3200) * 0.9


def hat(open_=False):
    n = int((0.28 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    return highpass(rng.standard_normal(n), 7500, 3) * np.exp(-t * (16 if open_ else 75))


def whoosh(length, lo=300, hi=5000, up=True):
    n = int(length * SR)
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    if up:
        c = lambda tt: lo * (hi / lo) ** (tt / length) ** 1.6
    else:
        c = lambda tt: hi * (lo / hi) ** (tt / length)
    y = sweep_filter(x, c, q=0.9)
    shape = np.sin(np.pi * np.clip(t / length, 0, 1)) ** (1.5 if up else 1.0)
    pan = np.linspace(-0.7, 0.7, n)
    return np.vstack([y * shape * np.cos((pan + 1) * np.pi / 4), y * shape * np.sin((pan + 1) * np.pi / 4)]) * np.sqrt(2)


def riser(length):
    n = int(length * SR)
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    y = sweep_filter(x, lambda tt: 400 * (9000 / 400) ** (tt / length) ** 2, q=1.3)
    f = 180 * (4 ** (t / length) ** 2)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.25
    env = (t / length) ** 2.2
    return (y + tone) * env


def tap_click():
    n = int(0.05 * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * 2300 * t) * np.exp(-t * 320) + 0.6 * np.sin(2 * np.pi * 1150 * t) * np.exp(-t * 180)
    s += highpass(rng.standard_normal(n) * np.exp(-t * 700), 3000) * 0.3
    return s


def blip(f0, f1, length=0.12):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = f0 * (f1 / f0) ** (t / length)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.minimum(t / 0.004, 1) * np.exp(-t * 26) + 0.3 * np.sin(2 * ph) * np.exp(-t * 40)


def crash(length=2.4):
    n = int(length * SR)
    t = np.arange(n) / SR
    x = highpass(rng.standard_normal((2, n)), 3800, 2)
    return x * np.exp(-t * 1.9) * np.minimum(t / 0.002, 1)


def boom():
    n = int(2.0 * SR)
    t = np.arange(n) / SR
    f = 34 + 40 * np.exp(-t * 6)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 2.0)


# ---------------------------------------------------------------------------
# Hall und Echo
# ---------------------------------------------------------------------------

def reverb(x, seconds=2.4, predelay=0.02, damp=6500):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal((2, n)) * np.exp(-t * 6.9 / seconds)
    ir = lowpass(ir, damp, 1)
    ir = np.concatenate([np.zeros((2, int(predelay * SR))), ir], axis=1)
    ir /= np.sqrt((ir ** 2).sum(axis=1, keepdims=True))
    size = 1 << int(np.ceil(np.log2(x.shape[1] + ir.shape[1])))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:, :x.shape[1]]
    return y


def pingpong(x, delay, feedback=0.38, taps=6):
    y = x.copy()
    d = int(delay * SR)
    g = 1.0
    for k in range(1, taps + 1):
        g *= feedback
        src = x[0] + x[1]
        ch = k % 2
        if k * d < x.shape[1]:
            y[ch, k * d:] += src[:x.shape[1] - k * d] * g * 0.5
    return y


# ---------------------------------------------------------------------------
# Satz
# ---------------------------------------------------------------------------

CHORDS = {
    #       Bass, Flächenstimmen
    "Esus": (40, [52, 57, 59, 64, 66]),
    "A":    (45, [57, 61, 64, 68, 71]),
    "F#m":  (42, [54, 57, 61, 64, 68]),
    "D":    (38, [54, 57, 61, 64, 69]),
    "E":    (40, [56, 59, 61, 64, 66]),
}
# (Beginn in Takten, Länge in Takten, Akkord)
SONG = [(0, 1, "Esus")]
for bar in range(1, 11):
    SONG.append((bar, 1, ["A", "F#m", "D", "E"][(bar - 1) % 4]))
SONG += [(11, .5, "D"), (11.5, .5, "E"), (12, 2, "A")]

groove = TL["groove"]
impact = TL["impact"]
drums_end = impact - BAR / 2          # eine halbe Phrase Stille vor dem Aufschlag

pad, bass, keys, drums, sfx, sends = Bus(), Bus(), Bus(), Bus(), Bus(), Bus()

# Fläche
for b0, length, name in SONG:
    _, notes = CHORDS[name]
    t0 = b0 * BAR
    dur = length * BAR
    bright = 1100 if b0 == 0 else 2200
    for m in notes:
        pad.add(pad_note(m, dur, bright), t0, 0.16)

# Bass: Achtel auf dem Grundton, der Sidechain macht daraus das Pumpen.
for b0, length, name in SONG:
    root = CHORDS[name][0]
    t0 = b0 * BAR
    if t0 < groove:
        continue
    if t0 >= impact:
        bass.add(bass_note(root, 2.2), t0, 0.6)
        continue
    steps = int(round(length * 8))
    for k in range(steps):
        t = t0 + k * BEAT / 2
        if drums_end <= t < impact:
            continue
        bass.add(bass_note(root + (12 if k % 8 == 7 else 0), BEAT / 2 * 0.8), t, 0.55)

# Arpeggio (FM-Zupfer) mit Ping-Pong-Echo
PATTERN = [(0, 0), (2, 2), (3, 4), (5, 3), (6, 1), (8, 2), (10, 4), (11, 3), (13, 2), (14, 1)]
for b0, length, name in SONG:
    notes = sorted(n + 12 for n in CHORDS[name][1])
    t0 = b0 * BAR
    for step, idx in PATTERN:
        if step >= length * 16:
            break
        t = t0 + step * STEP
        if t >= impact + 2 * BAR:
            break
        vel = 0.55 if t < groove else (0.8 if step % 4 == 0 else 0.62)
        if drums_end <= t < impact:
            vel *= 0.5
        if t >= impact:
            vel *= max(0.0, 1 - (t - impact) / 3.2)
        keys.add(pluck(notes[idx], vel), t, 0.20, pan=(-0.35 if step % 2 else 0.35))
        # Ab Takt 5 eine Oktave darüber, leise - mehr Glanz zur Mitte hin.
        if 5 <= b0 < 11 and step in (0, 6, 10):
            keys.add(pluck(notes[idx] + 12, 0.4, decay=9), t, 0.12, pan=0.5)

# Schlagzeug
beat_times = np.arange(groove, drums_end - 1e-6, BEAT)
for t in beat_times:
    drums.add(kick(), t, 0.95)
for t in np.arange(groove, drums_end - 1e-6, STEP):
    pos = int(round((t - groove) / STEP)) % 4
    if pos == 2:
        drums.add(hat(open_=True), t, 0.14, pan=0.25)
    else:
        drums.add(hat(), t, 0.13 if pos == 0 else 0.08, pan=-0.2)
for bar in range(2, int(drums_end / BAR) + 1):
    for off in (BEAT, 3 * BEAT):
        t = bar * BAR + off
        if t < drums_end:
            drums.add(clap(), t, 0.42)
            sends.add(clap(), t, 0.12)
# Kleine Wirbel vor den Szenenwechseln
for t_end in (TL["screens"]["plan"] + 0.25, TL["screens"]["mensa"] + 0.25):
    for k in range(4):
        drums.add(clap(), t_end - (4 - k) * STEP / 2 - 0.25, 0.10 + 0.05 * k)

# Abspann: Aufschlag
drums.add(kick(big=True), impact, 1.0)
sfx.add(boom(), impact, 0.4)
sfx.add(crash(), impact, 0.16)
sends.add(crash(), impact, 0.12)
sfx.add(riser(impact - drums_end), drums_end, 0.22)
for m, dt in ((76, 0.0), (81, 0.06), (85, 0.12), (88, 0.18)):
    sfx.add(bell(m, 0.5), impact + dt, 0.16, pan=(dt * 4 - 0.35))
    sends.add(bell(m, 0.5), impact + dt, 0.12)

# Geräusche zur Bildhandlung
sfx.add(bell(76, 0.6), 0.12, 0.12, pan=-0.2)
sfx.add(bell(81, 0.6), 0.22, 0.10, pan=0.2)
sends.add(bell(88, 0.5), 0.3, 0.10)
sfx.add(whoosh(1.1, 200, 4000), TL["phoneRise"] - 0.35, 0.14)
for key in ("plan", "kurs", "mensa"):
    sfx.add(whoosh(0.45, 600, 7000, up=False), TL["screens"][key] - 0.05, 0.08)
sfx.add(whoosh(1.0, 250, 5000), TL["screens"]["outro"] - 0.2, 0.12)
for tp in TL["taps"]:
    sfx.add(tap_click(), tp["t"], 0.22, pan=0.1)

ha, hb = TL["pops"]["heute"]
ma, mb = TL["pops"]["mensa"]
for a, b in ((ha, hb), (ma, mb)):
    sfx.add(blip(520, 980, 0.16), a, 0.16)
    sends.add(blip(520, 980, 0.16), a, 0.08)
    sfx.add(blip(760, 430, 0.14), b - 0.42, 0.10)

ka, step = TL["pops"]["kursTiles"]
SCALE = [81, 83, 85, 88, 90, 93, 95, 97, 100]       # A-Dur pentatonisch
for i in range(6):
    sfx.add(pluck(SCALE[i], 0.7, decay=10, ratio=3, index=1.4), ka + i * step, 0.12, pan=-0.4 + 0.16 * i)
plan_in = TL["screens"]["plan"] + 0.38
for i in range(9):
    sfx.add(pluck(SCALE[i] - 12, 0.6, decay=12, ratio=3, index=1.2), plan_in + i * 0.075 + 0.05, 0.10,
            pan=-0.5 + i * 0.12)
for i in range(6):
    sfx.add(pluck(SCALE[i % 5] + 12, 0.45, decay=14, ratio=3, index=1.0), TL["captions"]["outro"][0] + 0.55 + i * 0.09,
            0.07, pan=-0.4 + 0.16 * i)

# ---------------------------------------------------------------------------
# Mischung
# ---------------------------------------------------------------------------

t = np.arange(N) / SR
# Sidechain: Fläche und Bass weichen jedem Kick aus.
duck = np.ones(N)
for kt in list(beat_times) + [impact]:
    m = t >= kt
    duck[m] *= 1 - 0.62 * np.exp(-(t[m] - kt) / 0.11)
pad.x *= duck
bass.x *= duck ** 1.3

# Im Vorspann öffnet sich die Fläche langsam.
open_ = np.clip(t / groove, 0, 1)
pad_dark = lowpass(pad.x, 500)
pad.x = pad_dark * (1 - open_) + pad.x * open_

keys.x = pingpong(keys.x, 3 * STEP, 0.36)
wet = reverb(keys.x * 0.5 + pad.x * 0.35 + sfx.x * 0.4 + sends.x, 2.6)

mix = (pad.x * 0.9 + bass.x * 0.55 + keys.x * 1.0 + drums.x * 0.75 + sfx.x * 0.9 + wet * 0.38)

# Für Telefonlautsprecher: weniger Tiefbass, etwas mehr Präsenz und Luft.
def tilt(f):
    db = (-4.0 / (1 + (f / 90) ** 4)
          + 2.5 * np.exp(-0.5 * np.log2(np.maximum(f, 1) / 3000) ** 2)
          + 1.5 / (1 + (10000 / np.maximum(f, 1)) ** 4))
    return 10 ** (db / 20) / np.sqrt(1 + (28 / np.maximum(f, 1e-3)) ** 4)


mix = _apply(mix, tilt)

# Ein- und Ausblenden: das Video endet mit dem ausklingenden Akkord.
fade = np.clip(t / 0.03, 0, 1) * np.clip((DUR - t) / 1.6, 0, 1) ** 1.5
mix *= fade



def loudness(x):
    """Lautheit nach ITU-R BS.1770 (K-Filter, 400-ms-Blöcke, beide Schwellen)."""
    def k(f):
        f = np.maximum(f, 1e-3)
        shelf = 10 ** ((4.0 / (1 + (1681 / f) ** 2)) / 20)
        return shelf / np.sqrt(1 + (38 / f) ** 4)
    y = _apply(x, k)
    blk, hop = int(0.4 * SR), int(0.1 * SR)
    ms = np.array([(y[:, i:i + blk] ** 2).mean(axis=1).sum() for i in range(0, y.shape[1] - blk, hop)])
    lk = -0.691 + 10 * np.log10(ms + 1e-12)
    ms = ms[lk > -70]
    rel = -0.691 + 10 * np.log10(ms.mean()) - 10
    ms = ms[-0.691 + 10 * np.log10(ms) > rel]
    return -0.691 + 10 * np.log10(ms.mean())  # nähert ffmpeg ebur128 auf etwa 1 LU


def true_peak(x):
    up = np.fft.irfft(np.fft.rfft(x, axis=1), 4 * x.shape[1], axis=1) * 4
    return 20 * np.log10(np.abs(up).max())


# Sanft begrenzen, dann auf -16 LUFS; die Spitzen bleiben unter -1 dBTP.
mix /= np.max(np.abs(mix)) + 1e-9
mix = np.tanh(mix * 1.3) / np.tanh(1.3)
mix *= 10 ** ((-16.0 - loudness(mix)) / 20)
over = true_peak(mix) + 1.0
if over > 0:
    mix *= 10 ** (-over / 20)

out = Path(sys.argv[1] if len(sys.argv) > 1 else "soundtrack.wav")
pcm = mix.T + rng.uniform(-0.5, 0.5, mix.T.shape) / 32768 + rng.uniform(-0.5, 0.5, mix.T.shape) / 32768
pcm = np.clip(np.round(pcm * 32767), -32768, 32767).astype("<i2")
with wave.open(str(out), "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(f"{out}: {DUR:.2f} s, 48 kHz Stereo, {loudness(mix):.1f} LUFS, Spitze {true_peak(mix):.1f} dBTP")
