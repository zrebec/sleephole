#!/usr/bin/env python3
"""Sound stories for falling asleep (owner 2026-09-30: "like listening to someone play a survival game – you hear
the axe, the pickaxe, the first cave and imagine what happens; random, surprising").

    python3 tools/audio/make_stories.py        # needs the raw Kenney bundle (git-ignored) + ffmpeg

Writes into assets/audio (bundled at the app root):
  st_<group>_<n>.caf  one-shot samples from Kenney's CC0 packs (Impact Sounds, RPG Audio, Foley Sounds):
                      mono 44.1 kHz, trimmed, peak -3 dB. The app arranges them into random "scenes" at runtime
                      (SleepHole/Night/Stories.swift), so every night sounds different.
  bed_forest.caf      60 s seamless bed: a crackling camp fire + soft gusts of wind
  bed_cave.caf        60 s seamless bed: deep cave room tone + distant echoing drips
  bed_workshop.caf    60 s seamless bed: a small stove fire + gentle rain on the roof
The beds are synthesised here (Kenney has no ambient loops).
"""
import glob
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

KENNEY = "assets/Kenney Game Assets All-in-1 3/Audio"
OUT = "assets/audio"
SR = 44100
rng = np.random.default_rng(1409)

# group → glob patterns inside the Kenney audio packs (order = sample index)
SAMPLES = {
    "mine": ["Impact Sounds/Audio/impactMining_*.ogg"],
    "chop": ["RPG Audio/Audio/chop.ogg", "Impact Sounds/Audio/impactWood_heavy_*.ogg"],
    "log": ["Impact Sounds/Audio/impactWood_medium_*.ogg", "Impact Sounds/Audio/impactWood_light_*.ogg"],
    "plank": ["Impact Sounds/Audio/impactPlank_medium_*.ogg"],
    "anvil": ["Impact Sounds/Audio/impactMetal_light_*.ogg"],
    "grass": ["Impact Sounds/Audio/footstep_grass_*.ogg"],
    "wood": ["Impact Sounds/Audio/footstep_wood_*.ogg"],
    "stone": ["Impact Sounds/Audio/footstep_concrete_*.ogg"],
    "snow": ["Impact Sounds/Audio/footstep_snow_*.ogg"],
    "drip": ["Foley Sounds/Audio/Water/drip*.ogg"],
    "rock": ["Foley Sounds/Audio/Rocks/stoneHit*.ogg", "Foley Sounds/Audio/Rocks/rockHit*.ogg",
             "Foley Sounds/Audio/Rocks/stonesHit*.ogg"],
    "drag": ["Foley Sounds/Audio/Rocks/stoneDrag*.ogg"],
    "pickup": ["Foley Sounds/Audio/Helmet/pickup*.ogg", "Foley Sounds/Audio/Helmet/setDown*.ogg"],
    "creak": ["RPG Audio/Audio/creak*.ogg"],
    "door": ["RPG Audio/Audio/doorOpen_*.ogg", "RPG Audio/Audio/doorClose_*.ogg"],
    "page": ["RPG Audio/Audio/bookFlip*.ogg"],
    "cloth": ["RPG Audio/Audio/cloth*.ogg"],
    "pot": ["RPG Audio/Audio/metalPot*.ogg"],
    "tool": ["RPG Audio/Audio/metalClick.ogg", "RPG Audio/Audio/metalLatch.ogg", "RPG Audio/Audio/dropLeather.ogg"],
    "carve": ["RPG Audio/Audio/drawKnife*.ogg", "RPG Audio/Audio/knifeSlice.ogg"],
}


def decode(path):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ac", "1", "-ar", str(SR), f.name], check=True)
        sr, x = wavfile.read(f.name)
    os.unlink(f.name)
    return x.astype(np.float64) / 32768.0


def write(name, x, peak_db=-3.0, sr=SR, aac=False, rms_db=None):
    """PCM for the short samples; AAC (in CAF, gapless thanks to its packet table) for the 60 s beds.
    `rms_db`: level the average loudness instead of the peak (beds), with a soft limiter for the crackles."""
    if rms_db is not None:
        x = x / (np.sqrt(np.mean(x ** 2)) + 1e-12) * 10 ** (rms_db / 20)
        x = np.tanh(x * 1.5) / 1.5
    else:
        x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wavfile.write(f.name, sr, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    out = os.path.join(OUT, name)
    if aac:                        # macOS afconvert: AAC in CAF with the priming/padding info → loops cleanly
        subprocess.run(["afconvert", "-f", "caff", "-d", "aac", "-b", "128000", f.name, out], check=True)
    else:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f.name, "-c:a", "pcm_s16le", out], check=True)
    os.unlink(f.name)
    return out


def trim(x, threshold_db=-50):
    """Cut leading/trailing silence, 3 ms fade-in, 20 ms fade-out."""
    thr = 10 ** (threshold_db / 20) * np.max(np.abs(x))
    idx = np.nonzero(np.abs(x) > thr)[0]
    x = x[max(0, idx[0] - 30): idx[-1] + int(0.02 * SR)] if len(idx) else x
    fi, fo = int(0.003 * SR), min(len(x) // 2, int(0.02 * SR))
    x[:fi] *= np.linspace(0, 1, fi)
    x[-fo:] *= np.linspace(1, 0, fo)
    return x


def samples():
    for old in glob.glob(os.path.join(OUT, "st_*.caf")):
        os.unlink(old)
    counts = {}
    for group, patterns in SAMPLES.items():
        files = [f for p in patterns for f in sorted(glob.glob(os.path.join(KENNEY, p)))]
        assert files, group
        for i, f in enumerate(files):
            write(f"st_{group}_{i}.caf", trim(decode(f)))
        counts[group] = len(files)
    return counts


# ───────────────────────── beds ─────────────────────────

def seamless(x, fade_s=3.0, sr=SR):
    n = int(fade_s * sr)
    t = np.linspace(0, np.pi / 2, n)[:, None]
    return np.concatenate([x[-n:] * np.cos(t) + x[:n] * np.sin(t), x[n:-n]])


def lowpass(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, "low", fs=SR, output="sos"), x, axis=0)


def bandpass(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, hi], "band", fs=SR, output="sos"), x, axis=0)


def slow_lfo(n, hz_range=(0.03, 0.12), depth=0.6):
    t = np.arange(n) / SR
    f = rng.uniform(*hz_range)
    return 1 - depth / 2 + depth / 2 * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28))


def crackle(n, rate, pop_rate, gain=1.0):
    """Camp-fire crackle: sparse bright clicks + a few deeper pops + a low burning rumble. Stereo."""
    out = np.zeros((n, 2))
    for count, (lo, hi), (dmin, dmax), (amin, amax) in (
            (int(rate * n / SR), (1500, 7000), (0.002, 0.012), (0.05, 0.4)),
            (int(pop_rate * n / SR), (400, 1600), (0.01, 0.04), (0.2, 0.8))):
        for _ in range(count):
            d = int(rng.uniform(dmin, dmax) * SR)
            click = rng.standard_normal(d) * np.exp(-np.linspace(0, 6, d))
            click = bandpass(click, lo, hi) * rng.uniform(amin, amax)
            at = rng.integers(0, n - d)
            pan = rng.uniform(0.3, 0.7)
            out[at:at + d, 0] += click * (1 - pan)
            out[at:at + d, 1] += click * pan
    rumble = lowpass(np.cumsum(rng.standard_normal((n, 2)), axis=0) * 0.002, 180)
    rumble -= lowpass(rumble, 20)                                   # no DC drift
    out += rumble * slow_lfo(n, (0.1, 0.3), 0.5)[:, None] * 0.6
    return out * gain


def wind(n, gain=1.0):
    w = bandpass(rng.standard_normal((n, 2)), 180, 900) * 0.25
    return w * slow_lfo(n, (0.04, 0.09), 0.9)[:, None] * gain


def reverb_ir(seconds, decay):
    m = int(seconds * SR)
    return rng.standard_normal((m, 2)) * np.exp(-np.linspace(0, decay, m))[:, None] * 0.02


def bed_forest(seconds=63.0):
    n = int(seconds * SR)
    x = crackle(n, rate=6, pop_rate=0.6) + wind(n, 0.45)
    return seamless(x)


def bed_cave(seconds=63.0):
    n = int(seconds * SR)
    tone = lowpass(np.cumsum(rng.standard_normal((n, 2)), axis=0) * 0.003, 110)
    tone -= lowpass(tone, 15)
    air = bandpass(rng.standard_normal((n, 2)), 300, 700) * 0.01 * slow_lfo(n)[:, None]
    drips = np.zeros((n, 2))
    t = 1.0
    while t < seconds - 3:
        f0 = rng.uniform(1100, 2300)
        d = int(0.09 * SR)
        tt = np.arange(d) / SR
        drop = np.sin(2 * np.pi * (f0 * tt - 2500 * tt ** 2)) * np.exp(-tt * 45) * rng.uniform(0.15, 0.4)
        at, pan = int(t * SR), rng.uniform(0.1, 0.9)
        drips[at:at + d, 0] += drop * (1 - pan)
        drips[at:at + d, 1] += drop * pan
        t += rng.uniform(3.5, 9.0)
    ir = reverb_ir(2.8, 7)
    echoed = np.stack([signal.fftconvolve(drips[:, c], ir[:, c])[:n] for c in range(2)], axis=1)
    return seamless(tone * 0.8 + air + drips * 0.35 + echoed * 1.2)


def bed_workshop(seconds=63.0):
    n = int(seconds * SR)
    rain = bandpass(rng.standard_normal((n, 2)), 900, 6000) * 0.05 * slow_lfo(n, (0.02, 0.06), 0.4)[:, None]
    taps = np.zeros((n, 2))                                         # individual drops on the roof
    for _ in range(int(9 * seconds)):
        d = int(0.004 * SR)
        at, pan = rng.integers(0, n - d), rng.uniform(0, 1)
        tap = rng.standard_normal(d) * np.exp(-np.linspace(0, 5, d)) * rng.uniform(0.02, 0.08)
        taps[at:at + d, 0] += tap * (1 - pan)
        taps[at:at + d, 1] += tap * pan
    room = lowpass(rng.standard_normal((n, 2)), 250) * 0.02
    return seamless(crackle(n, rate=3, pop_rate=0.3, gain=0.7) + rain + lowpass(taps, 5000) + room)


if __name__ == "__main__":
    counts = samples()
    print("samples:", counts, "total", sum(counts.values()))
    for name, fn in (("bed_forest.caf", bed_forest), ("bed_cave.caf", bed_cave), ("bed_workshop.caf", bed_workshop)):
        x = fn()
        print(write(name, x, aac=True, rms_db=-24.0), f"{len(x) / SR:.1f} s")
