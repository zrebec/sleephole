#!/usr/bin/env python3
"""Synthesises SleepHole's alarm sounds (all original synthesis; melodies are public domain or our own), plus the
alarms made from CC0 Freesound recordings (tools/audio/freesound.json, use = "alarm"; fetch them first with
tools/audio/fetch_freesound.py – the raw files live in the git-ignored assets/freesound/).

    python3 tools/audio/make_alarms.py            # writes assets/audio/alarm_*.caf (via ffmpeg)

Every file is ≤ 29 s so it can also be used as a notification sound (iOS limit 30 s).
The app loops them for at most 2 minutes (rules.alarmDuration).
"""
import json
import os
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile

SR = 44100
OUT = "assets/audio"
MAX_LEN = 28.5


def note_hz(name):
    """'A4' / 'C#5' / 'Bb3' → Hz."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    n = names[name[0]]
    rest = name[1:]
    if rest[0] == "#":
        n += 1; rest = rest[1:]
    elif rest[0] == "b":
        n -= 1; rest = rest[1:]
    midi = 12 * (int(rest) + 1) + n
    return 440.0 * 2 ** ((midi - 69) / 12)


def env(n, attack=0.005, decay=None, release=0.03):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(attack, 1e-4))
    if decay:
        e *= np.exp(-t / decay)
    r = int(release * SR)
    if 0 < r < n:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def tone(freq, dur, kind):
    n = int(dur * SR)
    t = np.arange(n) / SR
    if kind == "marimba":                      # wooden bar: strong fundamental + inharmonic partials
        w = (np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 3.93 * t) * np.exp(-t / 0.08)
             + 0.12 * np.sin(2 * np.pi * freq * 9.2 * t) * np.exp(-t / 0.03))
        return w * env(n, 0.002, decay=0.45)
    if kind == "bell":                         # music box / chime
        w = (np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t / 0.4)
             + 0.25 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t / 0.15))
        return w * env(n, 0.001, decay=0.9)
    if kind == "flute":                        # soft sine with vibrato + breathy attack
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.minimum(1, t / 0.25)
        ph = 2 * np.pi * np.cumsum(freq * vib) / SR
        w = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
        w += 0.02 * np.random.default_rng(1).standard_normal(n) * np.exp(-t / 0.05)
        return w * env(n, 0.06, release=0.08)
    if kind == "brass":                        # bugle: bright harmonics, quick swell
        ph = 2 * np.pi * freq * t
        w = sum(np.sin(k * ph) / k ** 0.9 for k in range(1, 9))
        return w * env(n, 0.025, release=0.05) * (0.85 + 0.15 * np.minimum(1, t / 0.12))
    if kind == "beep":                         # digital piezo: square-ish
        ph = 2 * np.pi * freq * t
        w = np.sin(ph) + np.sin(3 * ph) / 3 + np.sin(5 * ph) / 5
        return w * env(n, 0.002, release=0.004)
    if kind == "harp":                         # plucked string: bright attack, long ringing decay
        w = sum(np.sin(2 * np.pi * freq * k * t) * np.exp(-t * (1.2 + 1.8 * k)) / k for k in range(1, 7))
        return w * env(n, 0.002, release=0.05)
    if kind == "pad":
        ph = 2 * np.pi * freq * t
        return (np.sin(ph) + 0.3 * np.sin(2 * ph)) * env(n, 0.4, release=0.6)
    raise ValueError(kind)


class Track:
    def __init__(self, seconds):
        self.buf = np.zeros(int(seconds * SR) + SR)

    def add(self, at, wave, gain=1.0):
        i = int(at * SR)
        j = min(len(self.buf), i + len(wave))
        if i < len(self.buf):
            self.buf[i:j] += wave[: j - i] * gain

    def seq(self, start, notes, beat, kind, gain=1.0, legato=1.0):
        """notes: [(name|None, beats)] → returns end time."""
        t = start
        for name, beats in notes:
            if name:
                self.add(t, tone(note_hz(name), beats * beat * legato + 0.05, kind), gain)
            t += beats * beat
        return t

    def save(self, name, peak_db=-1.0, fade_in=0.0):
        b = self.buf[: int(MAX_LEN * SR)]
        if fade_in:                                       # gentle start (the app ramps the volume too)
            n = int(fade_in * SR)
            b[:n] *= np.linspace(0.35, 1, n)
        b = b / (np.max(np.abs(b)) + 1e-9) * 10 ** (peak_db / 20)
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            wavfile.write(f.name, SR, (b * 32767).astype(np.int16))
        out = os.path.join(OUT, f"alarm_{name}.caf")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f.name, "-c:a", "pcm_s16le", out], check=True)
        os.unlink(f.name)
        print(out, f"{len(b) / SR:.1f}s")


# 1) Ranná nálada – Edvard Grieg, Peer Gynt Suite No. 1 (1875, public domain). Flute over a soft pad.
def morning_mood():
    tr = Track(MAX_LEN)
    beat = 0.36
    phrase = [("G#5", 1.5), ("E5", .5), ("D#5", .5), ("C#5", .5), ("D#5", .5), ("E5", 1.5)]
    phrase2 = [("G#5", 1.5), ("E5", .5), ("D#5", .5), ("C#5", .5), ("D#5", .5), ("E5", .5), ("D#5", .5),
               ("E5", .5), ("G#5", 1.0), ("E5", .5), ("G#5", .5), ("A#5", 1.0), ("E5", .5), ("A#5", .5),
               ("G#5", .5), ("E5", .5), ("D#5", .5), ("C#5", 1.5)]
    t, g = 0.3, 0.55
    for rep in range(3):
        start = t
        t = tr.seq(t, phrase, beat, "flute", g)
        t = tr.seq(t, phrase2, beat, "flute", g)
        for chord_t, notes in ((start, ["E3", "B3", "G#4"]), (start + 4 * beat, ["E3", "B3", "E4"]),
                               (start + 9 * beat, ["C#3", "G#3", "E4"]), (start + 14 * beat, ["B2", "F#3", "D#4"])):
            for n in notes:
                tr.add(chord_t, tone(note_hz(n), 5 * beat, "pad"), 0.12 * (1 + rep * 0.3))
        t += beat
        g *= 1.25
    tr.save("morning", fade_in=3)


# 2) Óda na radosť – Ludwig van Beethoven, Symphony No. 9 (1824, public domain), music box.
def ode_to_joy():
    tr = Track(MAX_LEN)
    beat = 0.34
    a = [("E5", 1), ("E5", 1), ("F5", 1), ("G5", 1), ("G5", 1), ("F5", 1), ("E5", 1), ("D5", 1),
         ("C5", 1), ("C5", 1), ("D5", 1), ("E5", 1)]
    end1 = [("E5", 1.5), ("D5", .5), ("D5", 2)]
    end2 = [("D5", 1.5), ("C5", .5), ("C5", 2)]
    t, g = 0.2, 0.6
    while t < MAX_LEN - 12 * beat:
        t = tr.seq(t, a + end1, beat, "bell", g)
        t = tr.seq(t, a + end2, beat, "bell", g)
        tr.seq(t - 16 * beat, [("C4", 4), ("G3", 4), ("C4", 4), ("G3", 2), ("C4", 2)], beat, "bell", g * 0.35)
        g *= 1.2
        beat *= 0.94                                      # gets a little livelier each round
    tr.save("ode", fade_in=2)


# 3) Budíček – our own bugle call, only natural bugle notes (C4 G4 C5 E5 G5).
def bugle():
    tr = Track(MAX_LEN)
    beat = 0.19
    call = [("G4", 1), ("C5", 1), ("E5", 2), ("C5", 1), ("E5", 1), ("G5", 3), (None, 1),
            ("E5", 1), ("E5", 1), ("C5", 1), ("E5", 1), ("G5", 2), ("E5", 1), ("C5", 1), ("G4", 3), (None, 1),
            ("G4", 1), ("C5", 1), ("E5", 1), ("G5", 1), ("E5", 1), ("C5", 1), ("E5", 1), ("G5", 1),
            ("C5", 4), (None, 4)]
    t, g = 0.1, 0.7
    while t < MAX_LEN - 8:
        t = tr.seq(t, call, beat, "brass", g, legato=0.85)
        g *= 1.15
    tr.save("bugle")


# 4) Poplach – aggressive radar-style pulses (original pattern, inspired by old phone alarms).
def alert():
    tr = Track(MAX_LEN)
    t = 0.0
    while t < MAX_LEN:
        for _ in range(2):
            for f in (2093, 2637, 2093, 2637):            # C7 / E7 chirps
                tr.add(t, tone(f, 0.055, "beep"), 1.0)
                t += 0.075
            t += 0.12
        t += 0.35
    tr.save("alert", peak_db=-0.5)


# 5) Digitálny budík – the classic bip-bip-bip-bip.
def digital():
    tr = Track(MAX_LEN)
    t = 0.0
    while t < MAX_LEN:
        for _ in range(4):
            tr.add(t, tone(3950, 0.07, "beep"), 1.0)
            t += 0.13
        t += 0.5
    tr.save("digital", peak_db=-0.5)


# 6) Zvonkohra – rising pentatonic chimes that speed up.
def chimes():
    tr = Track(MAX_LEN)
    scale = ["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6"]
    t, step, g = 0.2, 0.42, 0.5
    rng = np.random.default_rng(7)
    while t < MAX_LEN:
        for i in range(len(scale)):
            tr.add(t, tone(note_hz(scale[i]), 1.8, "bell"), g)
            if rng.random() < 0.3:
                tr.add(t, tone(note_hz(scale[max(0, i - 2)]) / 2, 1.8, "bell"), g * 0.4)
            t += step
        step = max(0.16, step * 0.85)
        g = min(1.0, g * 1.15)
    tr.save("chimes", fade_in=2)


# 7) Prelúdium – J. S. Bach, Prelude in C major BWV 846 (1722, public domain), harp. Each bar: the 5-note chord
#    broken as 1-2-3-4-5-3-4-5, twice.
def bach_prelude():
    tr = Track(MAX_LEN)
    bars = [["C4", "E4", "G4", "C5", "E5"], ["C4", "D4", "A4", "D5", "F5"], ["B3", "D4", "G4", "D5", "F5"],
            ["C4", "E4", "G4", "C5", "E5"], ["C4", "E4", "A4", "E5", "A5"], ["C4", "D4", "F#4", "A4", "D5"],
            ["B3", "D4", "G4", "D5", "G5"], ["B3", "C4", "E4", "G4", "C5"], ["A3", "C4", "E4", "G4", "C5"],
            ["D3", "A3", "D4", "F#4", "C5"], ["G3", "B3", "D4", "G4", "B4"], ["G3", "Bb3", "E4", "G4", "C#5"]]
    t, step, g = 0.3, 0.145, 0.45
    for bar in bars:
        for _ in range(2):
            for i in (0, 1, 2, 3, 4, 2, 3, 4):
                tr.add(t, tone(note_hz(bar[i]), 1.6, "harp"), g)
                t += step
        g = min(1.0, g * 1.08)
    tr.save("bach", fade_in=2)


# ───────────────────────── alarms from CC0 recordings (Freesound) ─────────────────────────

FREESOUND = "assets/freesound"


def recording(name):
    sid = next(k for k, v in json.load(open("tools/audio/freesound.json"))["sounds"].items() if v["as"] == name)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(FREESOUND, f"{sid}.ogg"), "-ac", "1",
                        "-ar", str(SR), f.name], check=True)
        _, x = wavfile.read(f.name)
    os.unlink(f.name)
    return x.astype(np.float64) / 32768.0


def from_recording(name, x, start=0.0, fade_in=3.0, rise_db=0.0, rms_db=None):
    """A ≤ 28.5 s excerpt; `rise_db` makes it slowly louder (the app ramps the volume as well); `rms_db` compresses
    peaky recordings (bird chirps) so they are as loud as the other alarms."""
    tr = Track(MAX_LEN)
    x = x[int(start * SR):][: int(MAX_LEN * SR)].copy()
    if rms_db is not None:
        x = x / (np.sqrt(np.mean(x ** 2)) + 1e-12) * 10 ** (rms_db / 20)
        x = 0.9 * np.tanh(x / 0.9)
    x *= 10 ** (np.linspace(-rise_db, 0, len(x)) / 20)
    fo = int(1.0 * SR)                                    # soft end: the file loops in the app
    x[-fo:] *= np.linspace(1, 0, fo)
    tr.add(0, x)
    tr.save(name, fade_in=fade_in)


# 8) Ranné vtáctvo – a dawn chorus (Synge101, CC0).
def birds():
    from_recording("birds", recording("birds"), start=20, fade_in=4, rise_db=6, rms_db=-17)


# 9) Spievajúca miska – singing-bowl strikes (s-light, mttvn, CC0) coming closer together and louder.
def bowl():
    tr = Track(MAX_LEN)
    low, high = recording("bowl"), recording("bowl-high")
    low = low[np.argmax(np.abs(low) > 0.05 * np.max(np.abs(low))):]      # start at the strike
    high = high[np.argmax(np.abs(high) > 0.05 * np.max(np.abs(high))):]
    t, gap, g, k = 0.2, 7.0, 0.45, 0
    while t < MAX_LEN - 1:
        src = low if k % 2 == 0 else high
        tr.add(t, src[: int(9 * SR)] * np.exp(-np.arange(min(len(src), int(9 * SR))) / SR / 4), g)
        t += gap
        gap = max(2.2, gap * 0.8)
        g = min(1.0, g * 1.15)
        k += 1
    tr.save("bowl", fade_in=0)


# 10) Hracia skrinka – a Symphonion music box playing "Klosterglocken" (Lefébure-Wély, public domain;
#     recording by thulitt, CC0).
def music_box():
    from_recording("musicbox", recording("musicbox"), start=0.5, fade_in=2, rise_db=3)


# 11) Kalimba – kalimba improvisation (SamuelGremaud, CC0).
def kalimba():
    from_recording("kalimba", recording("kalimba"), start=0, fade_in=2, rise_db=4, rms_db=-16)


if __name__ == "__main__":
    import sys
    only = sys.argv[1:]
    for fn in (morning_mood, ode_to_joy, bugle, alert, digital, chimes, bach_prelude, birds, bowl, music_box, kalimba):
        if not only or fn.__name__ in only:
            fn()
