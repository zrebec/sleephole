#!/usr/bin/env python3
"""Short sound effects for phase UI-2 (owner 2026-10-02: "more animations, WOW when a house is finished, more
sounds, a sound when going to sleep"). All synthesised here except the coins (Kenney RPG Audio, CC0 – needs the raw
bundle, see AGENTS.md) and the buddy's purr and meow (phase P2b: CC0 Freesound recordings listed in
tools/audio/freesound.json with use = "fx"; fetch them first with tools/audio/fetch_freesound.py – the raw files live
in the git-ignored assets/freesound/).

    python3 tools/audio/make_sfx.py              # writes assets/audio/fx_*.caf
    python3 tools/audio/make_sfx.py wow sleep    # only the named ones (the others stay byte-identical)
    python3 tools/audio/make_sfx.py purr meow    # the petting sounds
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

sys.path.insert(0, os.path.dirname(__file__))
from make_alarms import env, note_hz, tone  # noqa: E402

SR = 44100
OUT = "assets/audio"
KENNEY = "assets/Kenney Game Assets All-in-1 3/Audio"
FREESOUND = "assets/freesound"
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


def freesound_fx(name):
    """The CC0 Freesound recording listed in freesound.json as use = "fx", as = `name`, decoded to mono 44.1 kHz.
    (Looked up by `use` as well – the label "purr" also belongs to two story clips.)"""
    sounds = json.load(open("tools/audio/freesound.json"))["sounds"]
    sid = next(k for k, v in sounds.items() if v["use"] == "fx" and v["as"] == name)
    with tempfile.NamedTemporaryFile(suffix=".wav") as f:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(FREESOUND, f"{sid}.ogg"), "-ac", "1",
                        "-ar", str(SR), f.name], check=True)
        _, x = wavfile.read(f.name)
    return x.astype(np.float64) / 32768


def cut(x, start, length, fade_in, fade_out):
    """`length` seconds from `start`, with smooth (half-cosine) fades."""
    x = x[int(start * SR):int((start + length) * SR)].copy()
    fi, fo = int(fade_in * SR), int(fade_out * SR)
    x[:fi] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(fi) / fi)
    x[-fo:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(fo) / fo)
    return x


# Freesound 326295 "cat purring 2.wav" (blukotek, CC0): ZOOM H2, 14.7 s, a clean purr with a breath cycle of ≈ 2.6 s.
# Analysis: pulse train at 25.2 Hz (envelope autocorrelation 0.84), no clipping (peak 0.61), no events in the window
# (loudest 20 ms frame ≤ 4 dB above the median), gaps between the pulses 37 dB deep (low noise floor), nothing above
# 2 kHz. Most of the power is below 200 Hz (an iPhone speaker cannot play that), but the pulses are broadband: the
# part above 200 Hz alone is −21 dBFS RMS after the peak is normalised to −3 dB – the loudest of six CC0 candidates.
# 2.5 s … 4.5 s is one breath: the dip before the swell → the loud inhale → the softer tail (under the fade-out).
PURR_START, PURR_LENGTH = 2.5, 2.0


def purr():
    """Petting the cat: ≈ 2 s of a close, clean purr (CC0 recording), fade in 0.15 s, fade out 0.4 s."""
    x = freesound_fx("purr")
    x = signal.sosfiltfilt(signal.butter(2, 70, "high", fs=SR, output="sos"), x)   # rumble the speaker cannot play
    return cut(x, PURR_START, PURR_LENGTH, 0.15, 0.4)


# Freesound 262312 "Cat Meow1.wav" (steffcaffrey, CC0): a male cat's happy greeting, Zoom H4, mono 44.1 kHz.
# Analysis: ONE tonal event 0.035 … 0.505 s, fundamental 640–720 Hz (voicing 0.99), peak 0.44 (no clipping), the
# room before / after is ≈ 45 dB below the meow. The cut starts 15 ms before the onset (so the 20 ms fade-in keeps
# the attack) and ends just after the tail.
MEOW_START, MEOW_LENGTH = 0.015, 0.53


def meow():
    """A short, friendly "mrrp" (CC0 recording), ≈ 0.5 s, fade in 20 ms, fade out 80 ms."""
    return cut(freesound_fx("meow"), MEOW_START, MEOW_LENGTH, 0.02, 0.08)


ALL = {"sleep": sleep, "wow": wow, "sparkle": sparkle, "whoosh": whoosh, "pop": pop, "coins": coins,
       "purr": purr, "meow": meow}

if __name__ == "__main__":
    for name in sys.argv[1:] or ALL:
        write(name, ALL[name]())
