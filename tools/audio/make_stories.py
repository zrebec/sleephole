#!/usr/bin/env python3
"""Sound stories for falling asleep (owner 2026-09-30: "like listening to someone play a survival game – you hear
the axe, the pickaxe, the first cave and imagine what happens; random, surprising").

    python3 tools/audio/make_stories.py        # needs the raw Kenney bundle (git-ignored) + ffmpeg

Also needs the CC0 Freesound recordings (python3 tools/audio/fetch_freesound.py → assets/freesound/, git-ignored).

Writes into assets/audio (bundled at the app root):
  st_<group>_<n>.caf  event clips, all mono 44.1 kHz (the app's players need one format):
                      - one-shots from Kenney's CC0 packs (Impact Sounds, RPG Audio, Foley Sounds), PCM
                      - clips cut from the Freesound CC0 recordings (saw, plane, owl, dog, thunder …), AAC
                      The app arranges them into random scenes at runtime (SleepHole/Night/Stories.swift).
  bed_<chapter>.caf   75 s seamless stereo beds (AAC in CAF) mixed from the Freesound ambiences + a little
                      synthesis: forest (camp fire, crickets, a brook), workshop (stove, crickets outside),
                      cave (drips), wind (trees in the wind), storm (rain + distant thunder), lake (cave lake),
                      after (the rain fades, frogs, crickets).
"""
import json
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


def write(name, x, peak_db=-3.0, sr=SR, aac=False, rms_db=None, channels=2):
    """PCM for the short samples; AAC (in CAF, gapless thanks to its packet table) for the 60 s beds.
    `rms_db`: level the average loudness instead of the peak (beds), with a soft limiter for the crackles."""
    if rms_db is not None:
        x = x / (np.sqrt(np.mean(x ** 2)) + 1e-12) * 10 ** (rms_db / 20)
        x = np.tanh(x * 1.5) / 1.5                          # safety only – sources are tamed before
        if aac:
            x *= 0.7                                        # AAC overshoots on sharp clicks → 3 dB headroom
    else:
        x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wavfile.write(f.name, sr, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    out = os.path.join(OUT, name)
    if aac:                        # macOS afconvert: AAC in CAF with the priming/padding info → loops cleanly
        rate = "64000" if channels == 1 else "96000"
        subprocess.run(["afconvert", "-f", "caff", "-d", "aac", "-b", rate, f.name, out], check=True)
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


# ───────────────────────── Freesound clips ─────────────────────────

FREESOUND = "assets/freesound"
# group → (mode, length range s, clips per recording). "window" = continuous activity cut into pieces,
# "split" = separate sounds divided by silence.
CLIPS = {
    "saw": ("window", (3, 7), 3), "plane": ("window", (2, 5), 3), "sand": ("window", (3, 6), 3),
    "nail": ("split", (0.4, 4), 4), "sweep": ("window", (2, 5), 3), "floor": ("split", (0.5, 5), 1),
    "owl": ("split", (0.4, 5), 3), "dog": ("window", (3, 7), 2), "bark": ("split", (0.2, 2.5), 2),
    "chicken": ("window", (3, 6), 3), "purr": ("window", (6, 10), 2), "horse": ("split", (1, 6), 2),
    "wolf": ("window", (5, 12), 1), "wade": ("window", (3, 7), 2), "bucket": ("split", (0.5, 4), 1),
    "leaves": ("window", (3, 7), 3), "thunder": ("window", (6, 15), 2),
}


def envelope(x, win=0.02):
    n = int(win * SR)
    e = np.sqrt(np.convolve(x ** 2, np.ones(n) / n, mode="same"))
    return e


def fade(x, fin, fout):
    fi, fo = min(len(x) // 3, int(fin * SR)), min(len(x) // 3, int(fout * SR))
    if fi: x[:fi] *= np.linspace(0, 1, fi)
    if fo: x[-fo:] *= np.linspace(1, 0, fo)
    return x


def cut(x, mode, lengths, count):
    env = envelope(x)
    loud = np.percentile(env, 95)
    if mode == "split":
        active = env > loud * 10 ** (-32 / 20)
        regions, start, gap = [], None, int(0.3 * SR)
        idx = np.flatnonzero(active)
        if len(idx) == 0:
            return []
        start, last = idx[0], idx[0]
        for i in idx[1:]:
            if i - last > gap:
                regions.append((start, last)); start = i
            last = i
        regions.append((start, last))
        regions = [(a, min(b, a + int(lengths[1] * SR))) for a, b in regions if (b - a) >= lengths[0] * SR]
        regions.sort(key=lambda r: -np.mean(env[r[0]:r[1]]))
        return [fade(x[max(0, a - 200):b + int(0.05 * SR)].copy(), 0.005, 0.08) for a, b in regions[:count]]
    # window: consecutive pieces of random length; keep the lively ones, evenly spread over the recording
    pieces, t = [], 0
    while t < len(x) - lengths[0] * SR:
        n = int(rng.uniform(*lengths) * SR)
        seg = x[t:t + n]
        if np.sqrt(np.mean(seg ** 2)) > 0.35 * np.median(env[env > loud * 0.1]):
            pieces.append(seg)
        t += n
    if len(pieces) > count:
        pieces = [pieces[int(i)] for i in np.linspace(0, len(pieces) - 1, count)]
    return [fade(p.copy(), 0.03, 0.3) for p in pieces]


def freesound_clips():
    sounds = json.load(open("tools/audio/freesound.json"))["sounds"]
    counts = {}
    for sid, info in sounds.items():
        if info["use"] != "clip":
            continue
        group = info["as"]
        mode, lengths, count = CLIPS[group]
        for clip in cut(decode(os.path.join(FREESOUND, f"{sid}.ogg")), mode, lengths, count):
            n = counts.get(group, 0)
            write(f"st_{group}_{n}.caf", tame(clip, 18), aac=True, rms_db=-22.0, channels=1)
            counts[group] = n + 1
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


def wind(n, gain=1.0):
    w = bandpass(rng.standard_normal((n, 2)), 180, 900) * 0.25
    return w * slow_lfo(n, (0.04, 0.09), 0.9)[:, None] * gain


def cave_tone(n):
    tone = lowpass(np.cumsum(rng.standard_normal((n, 2)), axis=0) * 0.003, 110)
    return tone - lowpass(tone, 15)


BED_SECONDS = 78.0          # 75 s after the seamless crossfade


def tame(x, crest_db=15.0):
    """Soft-limit the peaks to `crest_db` above the RMS (camp-fire pops, owl hoots) – no hard clipping later."""
    limit = np.sqrt(np.mean(x ** 2)) * 10 ** (crest_db / 20) + 1e-12
    return limit * np.tanh(x / limit)


def ambience(name, rms_db):
    """A Freesound ambience (stereo), looped with crossfades to BED_SECONDS, at `rms_db`."""
    sid = next(k for k, v in json.load(open("tools/audio/freesound.json"))["sounds"].items() if v["as"] == name)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(FREESOUND, f"{sid}.ogg"), "-ac", "2",
                        "-ar", str(SR), f.name], check=True)
        _, x = wavfile.read(f.name)
    os.unlink(f.name)
    x = x.astype(np.float64) / 32768.0
    n, xf = int(BED_SECONDS * SR), int(2.0 * SR)
    x = x[int(0.5 * SR):-int(0.5 * SR)]                       # no handling noise at the edges
    out = x
    while len(out) < n:                                      # crossfade copies until long enough
        t = np.linspace(0, np.pi / 2, xf)[:, None]
        out = np.concatenate([out[:-xf], out[-xf:] * np.cos(t) + x[:xf] * np.sin(t), x[xf:]])
    out = tame(tame(out[:n], 12), 12)                       # twice: the RMS drops after the first pass
    return out / (np.sqrt(np.mean(out ** 2)) + 1e-12) * 10 ** (rms_db / 20)


def beds():
    n = int(BED_SECONDS * SR)
    fire = ambience("fire", -24)
    crickets = ambience("crickets", -30)
    return {
        "forest": fire + crickets + ambience("stream", -40) + wind(n, 0.15),
        "workshop": lowpass(fire, 2500) * 0.7 + lowpass(crickets, 2500) * 0.35 + cave_tone(n) * 0.3,
        "cave": ambience("cavedrips", -26) + cave_tone(n) * 0.8,
        "wind": ambience("treewind", -25) + wind(n, 0.6) + crickets * 0.3 + ambience("stream", -40),
        "storm": ambience("thunderrain", -26) + ambience("rainforest", -28),
        "lake": ambience("cavelake", -25) + ambience("cavedrips", -34) + cave_tone(n) * 0.5,
        "after": lowpass(ambience("rainforest", -32), 4000) + ambience("frogs", -34) + crickets * 0.5,
    }


if __name__ == "__main__":
    counts = samples()
    counts.update(freesound_clips())
    print("clips:", counts, "total", sum(counts.values()))
    for old in glob.glob(os.path.join(OUT, "bed_*.caf")):
        os.unlink(old)
    for name, x in beds().items():
        print(write(f"bed_{name}.caf", seamless(x), aac=True, rms_db=-24.0), f"{len(x) / SR:.1f} s")
