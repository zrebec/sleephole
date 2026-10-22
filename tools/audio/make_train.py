#!/usr/bin/env python3
"""Night train ride, 20 min stereo, heard from inside a carriage (prototype - synthesized only).

    python3 make_train.py   ->  train-20min.wav (temporary), timeline.json, overview.png

Model
 * v(t): smooth speed profile (keyframes + smoothstep), +-5 % slow drift while cruising. Position s(t)=integral v.
 * Rail joints every RAIL_LEN m of travel. Each joint is hit by every wheelset: near bogie (2 axles, AXLE_SPACING
   apart, loudest, panned left), far bogie of the same car (~17.5 m behind, quieter, panned right), faintly the
   neighbouring car's bogie. Hit = low resonant thump + damped metallic ring + noise; amplitude ~ v^1.5, brightness
   ~ v^2, +-20 % level, random timbre (pre-rendered variants) and a few ms of timing jitter. No hits under 2 m/s.
 * Switch clusters: short soft irregular bursts of hits every 3-5 min.
 * Rolling rumble: brown noise LP ~300 Hz + pink-ish LP ~1.5 kHz layer, level/brightness rise with speed,
   slow modulation, decorrelated L/R. Sway: 0.2-0.4 Hz swells (+-1.5 dB) plus deeper longer sways.
 * Bridge: rumble gets a hollow resonance. Whistles: distant two-tone horn through a reverb tail.
 * Braking: only a soft air hiss; stop: one soft 'pssh'; ~2.5 min near silence on a faint room tone; air sound
   before departure. Master: soft limiter, peak <= -3 dBFS, level like the project's sleep beds (RMS ~ -21 dBFS).
"""
import json, os, sys
import numpy as np
from scipy import signal
from scipy.io import wavfile

# ---------------- parameters ----------------
HIT_MODEL = os.environ.get("HIT_MODEL", "v2")   # "v2" = steel on steel (double impact, modal), "v1" = old wooden thump
OUT_WAV = {"v2": "train-20min.wav", "v1": "train-v1.wav", "v2b": "train-v2b.wav"}[HIT_MODEL]
B = HIT_MODEL == "v2b"                          # v2b: same impacts, much shorter / quieter ring, stronger contact "tk"
SR = 44100
DUR = 1200.0
SEED = 20261018
CRUISE = 22.0                    # m/s (~80 km/h)
RAIL_LEN = 25.0                  # m
AXLE_SPACING = 2.5
FAR_BOGIE = 17.5                 # m behind the near bogie
# speed keyframes (t seconds, v m/s)
KEYS = [(0, 0), (60, CRUISE), (420, CRUISE), (480, 0), (630, 0), (690, CRUISE), (1200, CRUISE)]
BRIDGE = (780.0, 805.0)
WHISTLES = [330.0, 960.0]
TARGET_RMS_DB = -21.5            # cruise RMS (project beds: about -21 dBFS)
PEAK_DB = -3.0
HIT_LEVEL = 0.6                  # hits relative to the rumble (tuned by measurement)
RUMBLE_LO, RUMBLE_MID = 1.0, 0.45
ROOM_LEVEL = 0.045               # room tone rel. to cruise rumble (near silence at the stop)
HISS_LEVEL = 0.02
rng = np.random.default_rng(SEED)
hr = np.random.default_rng(SEED + 7)      # hit randomness only, so both models share the same timeline / sway / rumble
N = int(DUR * SR)
CR = 200                         # control rate

def smooth(x): return x * x * (3 - 2 * x)

def lp(x, fc, order=2): return signal.sosfilt(signal.butter(order, fc, "lp", fs=SR, output="sos"), x)
def bp(x, lo, hi): return signal.sosfilt(signal.butter(2, [lo, hi], "bp", fs=SR, output="sos"), x)
def hp(x, fc): return signal.sosfilt(signal.butter(2, fc, "hp", fs=SR, output="sos"), x)
def norm(x): return x / (np.std(x) + 1e-12)
def up(c): return np.interp(np.arange(N) / SR, np.arange(len(c)) / CR, c).astype(np.float32)
def bump(t, a, b):               # smooth 0..1..0 over [a,b]
    u = np.clip((t - a) / (b - a), 0, 1); return np.sin(np.pi * u) ** 2
def ramp(t, a, b): return smooth(np.clip((t - a) / (b - a), 0, 1))

tc = np.arange(int(DUR * CR) + 1) / CR
# ---------------- speed ----------------
v = np.zeros_like(tc)
for (t0, v0), (t1, v1) in zip(KEYS[:-1], KEYS[1:]):
    m = (tc >= t0) & (tc <= t1)
    v[m] = v0 + (v1 - v0) * smooth((tc[m] - t0) / (t1 - t0))
drift = lp(rng.standard_normal(len(tc) * 20)[::20] if False else np.cumsum(rng.standard_normal(len(tc))), 1.0) if False else None
d = signal.sosfilt(signal.butter(2, 0.02, "lp", fs=CR, output="sos"), rng.standard_normal(len(tc)))
d = d / np.max(np.abs(d))
v = v * (1 + 0.05 * d * np.clip(v / CRUISE, 0, 1))
s = np.cumsum(v) / CR + rng.uniform(0, RAIL_LEN)       # position along the track [m]
vN = up(v) / CRUISE                                     # speed / cruise at audio rate

# ---------------- events ----------------
events = []
def ev(t, label, kind, dur=0.0): events.append({"t": round(float(t), 1), "kind": kind, "label": label, "duration": round(float(dur), 1)})
ev(0, "Departure: train pulls away from standstill", "departure", 60)
ev(60, "Cruise at ~80 km/h (first section)", "cruise", 360)
ev(420, "Braking: soft air hiss, gentle slowdown", "braking", 60)
ev(480, "Stop: one soft pssh of released air", "stop")
ev(484, "Standstill: near-silence on a faint room tone", "silence", 140)
ev(615, "Soft air sound before departure", "air", 10)
ev(630, "Departure: starts again", "departure", 60)
ev(690, "Cruise to the end (second section)", "cruise", 490)
ev(BRIDGE[0], "Bridge: hollower rumble", "bridge", BRIDGE[1] - BRIDGE[0])
for w in WHISTLES: ev(w, "Distant two-tone whistle", "whistle", 2.2)
ev(DUR - 20, "Fade-out", "fade", 20)

# ---------------- wheels on joints ----------------
def make_variants(n=14):
    out = []
    if HIT_MODEL != "v1": return out
    t = np.arange(int(0.4 * SR)) / SR
    for _ in range(n):
        f0 = hr.uniform(60, 120); tau = hr.uniform(0.022, 0.032)
        thump = np.sin(2 * np.pi * f0 * t * (1 - 0.15 * t / 0.1 * (t < 0.1))) * np.exp(-t / tau)
        thump += 0.5 * np.sin(2 * np.pi * 2.1 * f0 * t) * np.exp(-t / (tau * 0.5))
        fr = hr.uniform(1000, 3000); tr = hr.uniform(0.004, 0.012)
        ring = np.sin(2 * np.pi * fr * t + hr.uniform(0, 6)) * np.exp(-t / tr)
        ring += 0.6 * np.sin(2 * np.pi * fr * hr.uniform(1.4, 1.9) * t) * np.exp(-t / (tr * 0.6))
        nz = lp(hr.standard_normal(len(t)), 900) * np.exp(-t / 0.015)
        body = thump + 0.35 * norm(nz)
        body[0:3] *= np.array([0.3, 0.7, 1])[:len(body[0:3])]
        out.append((body.astype(np.float32), ring.astype(np.float32)))
    return out
variants = make_variants()
L_HIT = len(variants[0][0]) if HIT_MODEL == "v1" else int(0.62 * SR)

# ---- v2: steel on steel. Each axle at a joint = two impacts (wheel drops into the gap, strikes the next rail end).
# Impact = 1-3 ms broadband contact "tk" (high-passed) + inharmonic modal ring (free-bar ratios + a few high partials)
# + a small short carriage-floor thump.
BAR_RATIOS = [1.0, 2.756, 5.404, 8.933, 13.34]
BAR_AMP = [0.55, 0.9, 0.8, 0.55, 0.35]
_HP1K = signal.butter(2, 1000, "hp", fs=SR, output="sos")
def impact_v2(bright, g):
    n = int(0.6 * SR); t = np.arange(n) / SR
    f0 = g.uniform(350, 700)
    hf = 0.2 + 0.8 * min(bright, 1.3)                      # high modes grow with speed
    y = np.zeros(n)
    modes = []
    for k, (rt, am) in enumerate(zip(BAR_RATIOS, BAR_AMP)):
        f = f0 * rt * (1 + g.normal(0, 0.004))
        if f > 9000: continue
        tau = g.uniform(0.08, 0.18) if k < 3 else g.uniform(0.02, 0.06)
        a = am * g.uniform(0.3, 1.0) * (hf ** 0.6 if k == 2 else hf if k > 2 else 1.0)
        if B:
            tau = g.uniform(0.020, 0.050) if k < 3 else g.uniform(0.010, 0.030)
            if k < 2: a *= 0.5
            if k > 2: a *= 0.5
        modes.append((f, tau, a))
    for _ in range(g.integers(2, 4)):                      # extra partials 2.5-6 kHz
        modes.append((g.uniform(2500, 6000), g.uniform(0.010, 0.030) if B else g.uniform(0.02, 0.06), g.uniform(0.25, 0.5) * hf * g.uniform(0.3, 1.0) * (0.5 if B else 1)))
    for f, tau, a in modes:
        m = int(min(n, 8 * tau * SR))
        y[:m] += a * np.real(np.exp((-1 / tau + 2j * np.pi * f) * t[:m] + 1j * g.uniform(0, 6.28)))
    nc = int(g.uniform(0.001, 0.003) * SR)
    c = signal.sosfilt(_HP1K, g.standard_normal(nc + 64))[64:] * np.exp(-np.arange(nc) / (0.0007 * SR))
    y[:nc] += c * (0.9 + 1.2 * bright) * 0.9 * (1.5 if B else 1)
    fb = g.uniform(70, 110)
    y += 0.22 * np.sin(2 * np.pi * fb * t) * np.exp(-t / g.uniform(0.010, 0.014))
    y[:2] *= 0.5
    y[-int(0.1 * SR):] *= np.linspace(1, 0, int(0.1 * SR))
    return y

def axle_v2(r, bright, g):
    base = 0.0155 - 0.0085 * min(r, 1.0)                   # 7 ms at cruise, ~15 ms when slow
    dt = base * g.uniform(0.55, 1.0)
    i2 = int(round(dt * SR))
    k2 = g.uniform(1.1, 1.7) if g.random() < 0.75 else g.uniform(0.6, 0.95)
    out = np.zeros(L_HIT)
    a = impact_v2(bright * g.uniform(0.85, 1.0), g); b = impact_v2(bright, g)
    out[:len(a)] += 0.7 * a
    out[i2:i2 + len(b)] += (k2 * 0.7) * b[:L_HIT - i2]
    return out.astype(np.float32)

if "--analyze" in sys.argv:
    HIT_MODEL_SAVE = HIT_MODEL
    def one_hit(model, r):
        if model == "v1":
            t = np.arange(int(0.4 * SR)) / SR
            f0 = hr.uniform(60, 120); tau = hr.uniform(0.022, 0.032)
            thump = np.sin(2 * np.pi * f0 * t * (1 - 0.15 * t / 0.1 * (t < 0.1))) * np.exp(-t / tau)
            thump += 0.5 * np.sin(2 * np.pi * 2.1 * f0 * t) * np.exp(-t / (tau * 0.5))
            fr = hr.uniform(1000, 3000); tr = hr.uniform(0.004, 0.012)
            ring = np.sin(2 * np.pi * fr * t + hr.uniform(0, 6)) * np.exp(-t / tr)
            ring += 0.6 * np.sin(2 * np.pi * fr * hr.uniform(1.4, 1.9) * t) * np.exp(-t / (tr * 0.6))
            nz = lp(hr.standard_normal(len(t)), 900) * np.exp(-t / 0.015)
            body = thump + 0.35 * norm(nz); body[0:3] *= np.array([0.3, 0.7, 1])
            w = body + ring * r ** 2 * 0.8; fc = 2200
        else:
            w = axle_v2(r, r ** 2, hr); fc = None
        w = np.concatenate([w, np.zeros(SR)])
        return lp(w, 2200) if model == "v1" else lp(w, 7000)
    for model in ("v1", "v2", "v2b"):
        B = model == "v2b"
        cs, t20, t40, t60 = [], [], [], []
        for _ in range(60):
            w = one_hit(model, 1.0)
            ip = np.argmax(np.abs(w)); seg = w[max(0, ip - int(0.015 * SR)):][:int(0.2 * SR)]
            P = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), 1 << 16)) ** 2; fr_ = np.fft.rfftfreq(1 << 16, 1 / SR)
            cs.append(np.sum(fr_ * P) / np.sum(P))
            env = np.sqrt(np.convolve(w ** 2, np.ones(int(0.004 * SR)) / int(0.004 * SR), "same")); env_db = 20 * np.log10(env / env.max() + 1e-12)
            pk = np.argmax(env_db)
            for lst, th in ((t20, -20), (t40, -40), (t60, -60)):
                idx = np.where(env_db[pk:] < th)[0]; lst.append(idx[0] / SR if len(idx) else np.nan)
        print(f"{model}: centroid mean {np.mean(cs):.0f} Hz (sd {np.std(cs):.0f}, min {min(cs):.0f}, max {max(cs):.0f}); "
              f"envelope decay after peak: -20 dB {np.nanmean(t20)*1000:.0f} ms, -40 dB {np.nanmean(t40)*1000:.0f} ms, -60 dB {np.nanmean(t60)*1000:.0f} ms")
    sys.exit(0)

def vel_at(tt): return np.interp(tt, tc, v)
def tpos(sp): # time when position reaches sp
    return np.interp(sp, s, tc)

wheelL = np.zeros(N, np.float32); wheelR = np.zeros(N, np.float32)
# (distance behind reference, amplitude, panL, panR)
WHEELS = [(0.0, 1.0, 0.85, 0.40), (AXLE_SPACING, 0.85, 0.85, 0.40),
          (FAR_BOGIE, 0.45, 0.35, 0.80), (FAR_BOGIE + AXLE_SPACING, 0.38, 0.35, 0.80),
          (-6.0, 0.16, 0.6, 0.6), (-8.5, 0.13, 0.6, 0.6)]

def put(tt, amp, bright, pl, pr):
    i = int(round(tt * SR))
    if i < 0 or i + L_HIT + 40 >= N: return
    if HIT_MODEL == "v1":
        body, ring = variants[hr.integers(len(variants))]
        w = body + ring * bright * 0.8
        wheelL[i:i + L_HIT] += w * amp * pl; wheelR[i:i + L_HIT] += w * amp * pr
        return
    w = axle_v2(min(1.0, np.sqrt(max(bright, 0.01))), bright, hr)
    d = int(round(hr.uniform(0.3, 0.6) * 1e-3 * SR))        # inter-channel delay: the far side is later
    dl, dr = (0, d) if pl > pr + 0.1 else ((d, 0) if pr > pl + 0.1 else (0, 0))
    wheelL[i + dl:i + dl + L_HIT] += w * amp * pl; wheelR[i + dr:i + dr + L_HIT] += w * amp * pr

k0 = int(np.floor((s[0] - 30) / RAIL_LEN))
for k in range(k0, int(s[-1] / RAIL_LEN) + 2):
    for dist, a, pl, pr in WHEELS:
        sp = k * RAIL_LEN + dist
        if sp <= s[0] or sp >= s[-1]: continue
        tt = tpos(sp)
        vv = vel_at(tt)
        if vv < 2.0: continue
        fade = ramp(vv, 2.0, 5.0)
        r = vv / CRUISE
        amp = fade * r ** 1.5 * a * hr.uniform(0.8, 1.2)
        tt += hr.normal(0, 0.0025)
        put(tt, amp, r ** 2 * hr.uniform(0.7, 1.3), pl * hr.uniform(0.92, 1.08), pr * hr.uniform(0.92, 1.08))

# switch / crossing clusters every 3-5 min over cruise
t = 150.0
while t < DUR - 60:
    t += rng.uniform(180, 300)
    if 400 < t < 700 or t > DUR - 60 or vel_at(t) < 18: continue
    dur = rng.uniform(2.5, 4.0); tt = t; nh = 0
    ev(t, "Switch / crossing: soft irregular cluster", "switch", dur)
    while tt < t + dur:
        pan = hr.uniform(0.3, 0.9)
        for off, a in ((0, 0.9), (0.11, 0.7)):
            put(tt + off + hr.normal(0, .004), a * hr.uniform(0.35, 0.7), hr.uniform(0.3, 0.9), pan, 1.2 - pan)
        tt += rng.uniform(0.18, 0.5)
# inside a carriage: muffled
FC = 2200 if HIT_MODEL == "v1" else 7000      # v2: gentle dulling, steel stays steel
wheelL = lp(wheelL, FC); wheelR = lp(wheelR, FC)
# thump emphasis during the bridge
# (the bridge acts on the rumble below)

# ---------------- sway / modulation ----------------
ph = np.cumsum(0.3 + 0.1 * lp(rng.standard_normal(len(tc)), 0.02) / 3 * 0 + 0.08 * np.sin(2 * np.pi * tc / 47)) / CR * 2 * np.pi
sway = 1 + 0.17 * np.sin(ph) * (0.6 + 0.4 * np.sin(2 * np.pi * tc / 31 + 1))        # about +-1.5 dB
deep = np.zeros_like(tc); ts = 40.0; deep_list = []
while ts < DUR - 30:
    ts += rng.uniform(40, 90)
    L = rng.uniform(5, 9); deep += 0.30 * bump(tc, ts, ts + L) * rng.choice([-1, 1]) * rng.uniform(0.6, 1.0)
    if vel_at(ts) > 15 and ts < DUR - 40: deep_list.append((ts, L))
for ts, L in deep_list: ev(ts, "Deeper, longer sway", "sway", L)
swayc = np.clip(sway + deep, 0.6, 1.5)
bridgeEnv = ramp(tc, BRIDGE[0], BRIDGE[0] + 3) * (1 - ramp(tc, BRIDGE[1] - 4, BRIDGE[1]))
slow = 1 + 0.05 * lp(rng.standard_normal(len(tc)), 0.4) * 6

def rumble(seed_off):
    r = np.random.default_rng(SEED + seed_off)
    w = r.standard_normal(N).astype(np.float32)
    brown = lp(signal.lfilter([1], [1, -0.997], w), 320); brown = norm(brown)
    pink = lp(w[::-1].copy() * 0 + r.standard_normal(N), 1500)
    pink = norm(pink + 0.6 * lp(signal.lfilter([1], [1, -0.95], r.standard_normal(N)), 600) )
    # bridge: hollow resonances (band-passed noise added in)
    w3 = r.standard_normal(N)
    hol = norm(bp(w3, 140, 190)) * 0.9 + norm(bp(r.standard_normal(N), 320, 420)) * 0.6
    sw = up(swayc * slow)
    lo = brown * (vN ** 0.8) * (sw ** 1.5) * RUMBLE_LO          # sway emphasises the lows more
    mid = pink * (vN ** 2.0) * sw * RUMBLE_MID
    br = up(bridgeEnv)
    lo = lo * (1 + 0.25 * br)
    out = lo + mid + hol * br * (vN ** 0.8) * 0.5
    del brown, pink, hol
    return out

def room(seed_off):
    r = np.random.default_rng(SEED + 100 + seed_off)
    x = lp(signal.lfilter([1], [1, -0.995], r.standard_normal(N)), 140); x = norm(x)
    hum = np.sin(2 * np.pi * 100 * np.arange(N) / SR + seed_off) * (0.5 + 0.2 * np.sin(2 * np.pi * np.arange(N) / SR / 37))
    air = norm(lp(r.standard_normal(N), 900)) * 0.25
    amb = 1 + 0.4 * np.sin(2 * np.pi * np.arange(N) / SR / 23 + seed_off)
    return (x + 0.35 * hum + air) * amb * ROOM_LEVEL

def air_hiss(seed_off):
    r = np.random.default_rng(SEED + 200 + seed_off)
    n = bp(r.standard_normal(N), 1800, 6500); n = norm(n)
    n = lp(n, 5000)
    brk = bump(tc, 422, 486) * (0.4 + 0.6 * ramp(tc, 425, 470))
    pssh = np.zeros_like(tc)
    u = np.clip((tc - 481.5) / 3.5, 0, 1); pssh = (1 - np.exp(-u * 30)) * np.exp(-u * 5) * (u > 0) * (u < 1)
    pre = bump(tc, 612, 626) ** 2 * 0.6
    env = (brk * 0.5 + pssh * 1.8 + pre) * HISS_LEVEL * 2
    return n * up(env)

# whistle
def whistle(f1, f2):
    t = np.arange(int(2.2 * SR)) / SR
    env = np.minimum(1, t / 0.35) * np.exp(-np.maximum(0, t - 1.7) * 6) * (1 + 0.03 * np.sin(2 * np.pi * 5 * t))
    x = np.zeros_like(t)
    for f in (f1, f2):
        for h, a in ((1, 1), (2, .5), (3, .3), (4, .15)): x += a * np.sin(2 * np.pi * f * h * t * (1 - 0.01 * (t < .3) * (1 - t / .3)))
    x = lp(x * env, 1300)
    return x / np.max(np.abs(x))
def ir(seed):
    r = np.random.default_rng(seed); t = np.arange(int(2.8 * SR)) / SR
    return lp(r.standard_normal(len(t)), 1800) * np.exp(-t / 0.7) * (1 - np.exp(-t / 0.05))
whist = np.zeros((N, 2), np.float32)
for wi, wt in enumerate(WHISTLES):
    h = whistle(392 * (1 if wi == 0 else 0.94), 494 * (1 if wi == 0 else 0.94))
    for c in range(2):
        y = signal.fftconvolve(h, ir(wi * 2 + c))[: int(5 * SR)]; y = y / np.max(np.abs(y))
        i = int(wt * SR); whist[i:i + len(y), c] += y[: N - i].astype(np.float32) * 0.45

# ---------------- mix ----------------
mix = np.zeros((N, 2), np.float32)
for c in range(2):
    rb = rumble(c)
    mix[:, c] = rb
    del rb
rum_rms_ref = None
# reference rumble RMS in the first cruise to set relative levels
seg = slice(int(100 * SR), int(400 * SR))
ref = np.sqrt(np.mean(mix[seg] ** 2))
mix[:, 0] += wheelL / np.max(np.abs(wheelL)) * 0 + wheelL * ref * HIT_LEVEL / (np.sqrt(np.mean(wheelL[seg] ** 2)) + 1e-9) * 0.9
mix[:, 1] += wheelR * ref * HIT_LEVEL / (np.sqrt(np.mean(wheelR[seg] ** 2)) + 1e-9) * 0.9
del wheelL, wheelR
for c in range(2):
    mix[:, c] += room(c) * ref + air_hiss(c) * ref
mix += whist * ref * 1.0
del whist
# start / end fades
tt = np.arange(N) / SR
g = np.minimum(1, tt / 2.0) * np.clip((DUR - tt) / 20.0, 0, 1) ** 1.5
mix *= g[:, None].astype(np.float32)
# scale to target cruise RMS, then soft limiter, peak <= -3 dBFS
seg2 = slice(int(100 * SR), int(400 * SR))
mix *= 10 ** (TARGET_RMS_DB / 20) / np.sqrt(np.mean(mix[seg2] ** 2))
pk = 10 ** (PEAK_DB / 20)
thr = 0.5
a = np.abs(mix)
over = a > thr
mix = np.where(over, np.sign(mix) * (thr + (pk * 1.0 - thr) * np.tanh((a - thr) / (pk - thr))), mix)
mix = np.clip(mix, -pk, pk).astype(np.float32)
wavfile.write(OUT_WAV, SR, (mix * 32767).astype(np.int16))
if HIT_MODEL == "v2": json.dump(sorted(events, key=lambda e: e["t"]), open("timeline.json", "w"), indent=1)

# ---------------- report ----------------
def db(x): return 20 * np.log10(x + 1e-12)
secs = [("departure 0-60", 0, 60), ("cruise 1 (90-400)", 90, 400), ("braking 425-480", 425, 480), ("standstill 490-610", 490, 610),
        ("departure 630-690", 630, 690), ("cruise 2 (700-1170)", 700, 1170), ("bridge", *BRIDGE), ("whistle 1 (330-335)", 330, 335),
        ("last 20 s", 1180, 1200)]
for n, a0, b0 in secs:
    x = mix[int(a0 * SR):int(b0 * SR)]
    print(f"{n:24s} RMS {db(np.sqrt(np.mean(x**2))):6.1f} dBFS   peak {db(np.abs(x).max()):6.1f}")
print("overall peak", db(np.abs(mix).max()), "duration", len(mix) / SR)

try:
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    mono = mix.mean(1)
    win = SR // 2
    rms = np.sqrt(np.mean(mono[: len(mono) // win * win].reshape(-1, win) ** 2, 1))
    fig, ax = plt.subplots(2, 1, figsize=(15, 8), sharex=True)
    ax[0].plot(np.arange(len(rms)) * 0.5, db(rms), lw=0.8); ax[0].set_ylabel("RMS dBFS (0.5 s)"); ax[0].set_ylim(-70, -10)
    f, tt2, S = signal.spectrogram(mono[::4], SR / 4, nperseg=2048, noverlap=1024)
    ax[1].pcolormesh(tt2, f, 10 * np.log10(S + 1e-14), vmin=-120, vmax=-60, shading="auto"); ax[1].set_ylabel("Hz (0-5.5k)"); ax[1].set_xlabel("s")
    col = {"whistle": "r", "bridge": "m", "switch": "orange", "stop": "k", "braking": "g", "departure": "c", "silence": "b", "air": "y", "fade": "gray"}
    for e in events:
        if e["kind"] in col:
            for a_ in ax: a_.axvline(e["t"], color=col[e["kind"]], lw=0.8, alpha=0.8)
            ax[0].text(e["t"], -12 - (hash(e["kind"]) % 5) * 4, e["kind"], rotation=90, fontsize=7, va="top", color=col[e["kind"]])
    plt.tight_layout(); plt.savefig("overview.png", dpi=90)
except ImportError:
    pass
