#!/usr/bin/env python3
"""Short sound effects for phase UI-2 (owner 2026-10-02: "more animations, WOW when a house is finished, more
sounds, a sound when going to sleep"). All synthesised here except the coins (Kenney RPG Audio, CC0 – needs the raw
bundle, see AGENTS.md).

    python3 tools/audio/make_sfx.py              # writes assets/audio/fx_*.caf
    python3 tools/audio/make_sfx.py wow sleep    # only the named ones (the others stay byte-identical)
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, os.path.dirname(__file__))
from make_alarms import env, note_hz, tone  # noqa: E402

SR = 44100
OUT = "assets/audio"
KENNEY = "assets/Kenney Game Assets All-in-1 3/Audio"
rng = np.random.default_rng(2026)


def place(buf, x, at):
    i = int(at * SR)
    end = min(len(buf), i + len(x))
    buf[i:end] += x[: end - i]


def write(name, x, peak_db=-3.0):
    x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)
    fade = int(0.02 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    out = os.path.join(OUT, f"fx_{name}.caf")
    with tempfile.NamedTemporaryFile(suffix=".wav") as f:
        wavfile.write(f.name, SR, (x * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f.name, "-c:a", "pcm_s16le", out], check=True)
    print(out, f"{len(x) / SR:.2f} s")


def lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def sleep():
    """Going to sleep: a slow descending music-box lullaby over a soft pad – "lights out"."""
    buf = np.zeros(int(3.2 * SR))
    for i, n in enumerate(["G5", "E5", "C5", "D5", "G4"]):
        place(buf, tone(note_hz(n), 1.6, "bell") * (0.9 - 0.08 * i), 0.05 + i * 0.32)
    t = np.arange(int(3.0 * SR)) / SR
    pad = sum(np.sin(2 * np.pi * note_hz(n) * t) for n in ["C4", "G4", "E5"]) / 3
    place(buf, pad * 0.18 * np.minimum(1, t / 0.6) * np.exp(-t / 1.4), 0.1)
    return buf


def wow():
    """A building is finished: quick rising arpeggio, a bright major chord and twinkles – the WOW."""
    buf = np.zeros(int(3.0 * SR))
    for i, n in enumerate(["C5", "E5", "G5", "C6"]):
        place(buf, tone(note_hz(n), 0.6, "marimba") * 0.8, i * 0.075)
        place(buf, tone(note_hz(n), 1.0, "bell") * 0.35, i * 0.075)
    for n in ["C5", "E5", "G5", "C6", "E6"]:
        place(buf, tone(note_hz(n), 2.4, "bell") * 0.45, 0.32)
    for k in range(14):                                     # twinkles, pentatonic, high
        n = rng.choice(["C7", "D7", "E7", "G7", "A7", "C8"])
        place(buf, tone(note_hz(n), 0.35, "bell") * rng.uniform(0.08, 0.2), 0.4 + k * 0.11 + rng.uniform(0, 0.05))
    return buf


def sparkle():
    """A tiny magic glissando (coins appear, an achievement, the island)."""
    buf = np.zeros(int(1.0 * SR))
    for i, n in enumerate(["E6", "G6", "A6", "C7", "D7", "E7", "G7"]):
        place(buf, tone(note_hz(n), 0.5, "bell") * (0.5 + 0.05 * i), i * 0.045)
    return buf


def whoosh():
    """Soft rising air – the night screen slides in."""
    n = int(0.8 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    sweep = np.concatenate([lowpass(noise[i:i + 2205], 0.02 + 0.25 * i / n) for i in range(0, n, 2205)])[:n]
    return sweep * np.sin(np.pi * t / t[-1]) ** 2


def pop():
    """Bubble pop for badges and cards."""
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    f = 380 + 900 * t / t[-1]
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, decay=0.035)


def coins():
    """Kenney RPG Audio handleCoins (CC0)."""
    src = os.path.join(KENNEY, "RPG Audio", "Audio", "handleCoins.ogg")
    with tempfile.NamedTemporaryFile(suffix=".wav") as f:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-ac", "1", "-ar", str(SR), f.name], check=True)
        _, x = wavfile.read(f.name)
    return x.astype(np.float64) / 32768


ALL = {"sleep": sleep, "wow": wow, "sparkle": sparkle, "whoosh": whoosh, "pop": pop, "coins": coins}

if __name__ == "__main__":
    for name in sys.argv[1:] or ALL:
        write(name, ALL[name]())
