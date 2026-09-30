#!/usr/bin/env python3
"""Rain loops for the night sound (owner request 2026-09-30: "like rain on a tent, not noise").

    python3 tools/audio/make_rain.py           # writes assets/audio/rain_tent.caf + rain_window.caf

rain_tent   – physical-ish model: every drop is a short impulse exciting the taut tent fabric (a damped
              resonator 170–420 Hz, slight pitch drop) + a tiny bright "tick"; dozens of drops per second
              with slowly changing intensity (gusts), occasional heavy drips from a tree, soft distant rain
              bed, random stereo positions. 60 s seamless loop.
rain_window – "Rain on Windows, Interior, A" by InspectorJ (www.jshaw.co.uk) from Freesound.org,
              CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) – trimmed, crossfaded into a
              seamless loop, resampled to mono 24 kHz. Attribution is shown in the app's credits.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 24000
OUT = "assets/audio"
SRC_WINDOW = "sounds/346642__inspectorj__rain-on-windows-interior-a.wav"
rng = np.random.default_rng(2026)


def seamless(x, fade_s=3.0):
    """Crossfade the last `fade_s` seconds into the start (equal power) → loops without a seam."""
    n = int(fade_s * SR)
    t = np.linspace(0, np.pi / 2, n)
    head, tail = x[:n], x[-n:]
    mixed = tail * np.cos(t)[:, None] + head * np.sin(t)[:, None] if x.ndim > 1 else tail * np.cos(t) + head * np.sin(t)
    return np.concatenate([mixed, x[n:-n]])


def save(name, x, peak_db=-3.0):
    x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wavfile.write(f.name, SR, (x * 32767).astype(np.int16))
    out = os.path.join(OUT, f"{name}.caf")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f.name, "-c:a", "pcm_s16le", out], check=True)
    os.unlink(f.name)
    print(out, f"{len(x) / SR:.1f}s", "stereo" if x.ndim > 1 else "mono", f"{os.path.getsize(out) / 1e6:.1f} MB")
    return x


def tent(seconds=63.0):
    n = int(seconds * SR)
    out = np.zeros((n, 2))
    t_axis = np.arange(n) / SR

    # 1) distant rain bed: pink-ish noise, low-passed, slowly breathing
    w = rng.standard_normal(n)
    b, a = signal.butter(2, 1300, "lp", fs=SR)
    bed = signal.lfilter(b, a, np.cumsum(w) * 0.02 - signal.lfilter([1], [1, -0.995], w * 0.02) + w * 0.3)
    bed = bed / np.max(np.abs(bed)) * 0.06 * (0.85 + 0.15 * np.sin(2 * np.pi * t_axis / 17))
    out += np.stack([bed, np.roll(bed, 37)], axis=1)

    # 2) drops on the fabric: Poisson process with gusty intensity
    def drop(freq, tau, amp, bright):
        L = int(tau * 7 * SR)
        tt = np.arange(L) / SR
        f = freq * (1 - 0.1 * np.minimum(1, tt / (tau * 3)))            # slight pitch drop of the membrane
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / tau)
        click_n = int(0.003 * SR)
        click = np.diff(rng.standard_normal(click_n + 1)) * np.exp(-np.arange(click_n) / (0.0008 * SR))
        body[:click_n] += click * bright
        attack = np.minimum(1, tt / 0.0015)                              # no digital clicks
        return body * attack * amp

    t = 0.0
    while t < seconds - 0.3:
        intensity = 55 + 30 * np.sin(2 * np.pi * t / 23) + 15 * np.sin(2 * np.pi * t / 7.3)
        t += rng.exponential(1 / max(15, intensity))
        size = rng.lognormal(0, 0.45)                                    # bigger drop = louder + lower
        d = drop(freq=rng.uniform(170, 420) / size ** 0.3, tau=rng.uniform(0.012, 0.03), amp=0.18 * size,
                 bright=0.35)
        pan = rng.uniform(0.15, 0.85)
        i = int(t * SR)
        j = min(n, i + len(d))
        out[i:j, 0] += d[: j - i] * np.sqrt(1 - pan)
        out[i:j, 1] += d[: j - i] * np.sqrt(pan)

    # 3) heavy drips from a tree now and then (low, longer "tup")
    t = 1.0
    while t < seconds - 0.5:
        d = drop(freq=rng.uniform(110, 170), tau=0.05, amp=0.55, bright=0.2)
        pan = rng.uniform(0.3, 0.7)
        i = int(t * SR)
        j = min(n, i + len(d))
        out[i:j, 0] += d[: j - i] * np.sqrt(1 - pan)
        out[i:j, 1] += d[: j - i] * np.sqrt(pan)
        t += rng.uniform(1.4, 4.5)

    # gentle warmth: tame the very top
    b, a = signal.butter(2, 6000, "lp", fs=SR)
    out = signal.lfilter(b, a, out, axis=0)
    return save("rain_tent", seamless(out))


def window():
    sr, x = wavfile.read(SRC_WINDOW)
    x = x.astype(np.float64)
    if x.ndim > 1:
        x = x.mean(axis=1)
    x = signal.resample_poly(x, SR, sr)
    x = x[int(0.3 * SR):-int(0.3 * SR)]                                   # drop edge artefacts
    return save("rain_window", seamless(x))


def analyse(name, x):
    x = x.mean(axis=1) if x.ndim > 1 else x
    f, P = signal.welch(x, SR, nperseg=4096)
    hp = signal.sosfilt(signal.butter(4, 1500, "hp", fs=SR, output="sos"), x)
    env = signal.sosfilt(signal.butter(2, 200, "lp", fs=SR, output="sos"), np.abs(signal.hilbert(hp)))
    peaks, _ = signal.find_peaks(env, height=np.median(env) * 4, distance=int(0.01 * SR))
    print(f"  {name}: centroid {(f * P).sum() / P.sum():.0f} Hz, audible drops {len(peaks) / (len(x) / SR):.1f}/s")


if __name__ == "__main__":
    analyse("rain_tent", tent())
    analyse("rain_window", window())
