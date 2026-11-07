#!/usr/bin/env python3
"""SleepHole promo video: deterministic motion-graphics renderer (Pillow + numpy + ffmpeg).

usage: python3 tools/promo/make_promo.py --format landscape|vertical --lang en \
           --shots build/store/raw-2026-11/en/large --out build/promo [--thumb] [--stills-only]

Frames are drawn in worker processes, streamed to ffmpeg as raw RGB; the music bed and the sound effects are
synthesised / mixed with numpy and normalised with ffmpeg loudnorm (two passes).  Needs the macOS font Avenir Next.
Reuses the phone frame and fonts of tools/store/compose.py (imported, not modified).
"""
import argparse
import json
import math
import multiprocessing as mp
import os
import random
import re
import subprocess
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "store"))
import compose as C  # noqa: E402  (phone frame, fonts)
import panorama as pano  # noqa: E402  (glow, paste_clip)

FFMPEG = "/opt/homebrew/bin/ffmpeg" if os.path.exists("/opt/homebrew/bin/ffmpeg") else "ffmpeg"
FPS = 30
SPRITES = os.path.join(ROOT, "assets", "sprites")
AUDIO = os.path.join(ROOT, "assets", "audio")
ICON = os.path.join(ROOT, "SleepHole", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")
HEAVY, BOLD, MEDIUM = C.HEAVY, C.BOLD, C.MEDIUM

CREAM = (244, 233, 193)
PERI = (143, 184, 255)
SUBC = (178, 204, 252)
WHITE = (236, 242, 255)
NAVY = (6, 11, 30)

# ------------------------------------------------------------------ timeline (seconds)
TL = dict(S1=(0.0, 4.2), S2=(4.0, 8.8), S3=(8.6, 13.4), S4=(13.2, 18.0), S5=(17.8, 27.8),
          S6a=(27.6, 33.0), S6b=(32.8, 35.6), S7=(35.4, 44.0))
TOTAL = 44.0
FADE_OUT_FROM = 41.9
POP_T0 = TL["S5"][0] + 1.2          # first building pops
POP_DT = 0.165
N_NIGHTS = 30
S5_PHASE2 = TL["S5"][0] + 7.0       # town gone, phone with the town screenshot in


def pop_time(i):
    return POP_T0 + i * POP_DT


def sfx_events():
    """(time, file, gain) – shared by the audio mix; picture is synced to the same numbers."""
    ev = [(1.0, "fx_sparkle.caf", 0.5), (TL["S2"][0] + 0.15, "fx_whoosh.caf", 0.32),
          (TL["S3"][0] + 0.15, "fx_whoosh.caf", 0.32), (TL["S3"][0] + 0.5, "fx_sleep.caf", 0.30),
          (TL["S4"][0] + 0.15, "fx_whoosh.caf", 0.32), (TL["S4"][0] + 0.55, "building_done.caf", 0.55),
          (S5_PHASE2 - 0.1, "fx_whoosh.caf", 0.32),
          (TL["S6a"][0] + 0.05, "fx_whoosh.caf", 0.3), (TL["S6a"][0] + 0.30, "fx_whoosh.caf", 0.3),
          (TL["S6a"][0] + 0.55, "fx_whoosh.caf", 0.3), (TL["S7"][0] + 0.6, "fx_sparkle.caf", 0.45)]
    for i in range(N_NIGHTS):
        ev.append((pop_time(i), "fx_pop.caf", 0.5))
        if (i + 1) % 5 == 0:
            ev.append((pop_time(i) + 0.04, "fx_sparkle.caf", 0.28 if i < N_NIGHTS - 1 else 0.5))
    return ev


# ------------------------------------------------------------------ easing
def clamp01(x):
    return max(0.0, min(1.0, x))


def ease_io(x):
    x = clamp01(x)
    return x * x * (3 - 2 * x)


def ease_out(x):
    x = clamp01(x)
    return 1 - (1 - x) ** 3


def ease_back(x):
    x = clamp01(x)
    c1 = 1.5
    return 1 + (c1 + 1) * (x - 1) ** 3 + c1 * (x - 1) ** 2


def vis(t, a, b, fin=0.6, fout=0.6):
    return ease_io((t - a) / fin) * (1 - ease_io((t - (b - fout)) / fout))


# ------------------------------------------------------------------ formats
class Fmt:
    def __init__(self, name):
        self.name = name
        self.vertical = name == "vertical"
        if self.vertical:
            self.W, self.H = 1080, 1920
            self.hs, self.ss, self.label = 88, 46, 44
            self.phone_h = 1000
            self.phone_cy = 1070
            self.text_top = 205
            self.town_k = 0.33
            self.town_cy = 1060
            self.icon = 300
        else:
            self.W, self.H = 1920, 1080
            self.hs, self.ss, self.label = 96, 46, 44
            self.phone_h = 900
            self.phone_cy = 540
            self.text_top = None
            self.town_k = 0.46
            self.town_cy = 700
            self.icon = 260


def fnt(idx, size):
    return C.font(idx, size)


# ------------------------------------------------------------------ text tiles
TP = 44   # tile padding (glow room)


def text_tile(items, align="c", glow=PERI, glow_a=0.55):
    """items: [(text, font, fill, gap_before)] -> RGBA tile (padding TP).  Returns (tile, textw, texth)."""
    d = ImageDraw.Draw(Image.new("RGB", (4, 4)))
    lines = []
    y = 0
    for text, fo, fill, gap in items:
        y += gap
        w = d.textlength(text, font=fo)
        asc, desc = fo.getmetrics()
        lines.append((text, fo, fill, y, w))
        y += int((asc + desc) * 1.0)
    tw = int(max(l[4] for l in lines)) + 1
    th = y
    tile = Image.new("RGBA", (tw + 2 * TP, th + 2 * TP), (0, 0, 0, 0))
    mask = Image.new("L", tile.size, 0)
    layer = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    dm, dl = ImageDraw.Draw(mask), ImageDraw.Draw(layer)
    for text, fo, fill, ly, w in lines:
        x = TP + (tw - w) / 2 if align == "c" else TP
        dm.text((x, TP + ly), text, font=fo, fill=255)
        dl.text((x, TP + ly), text, font=fo, fill=fill + (255,))
    g = mask.filter(ImageFilter.GaussianBlur(16)).point(lambda v: int(min(255, v * 1.6 * glow_a)))
    glow_l = Image.new("RGBA", tile.size, glow + (0,))
    glow_l.putalpha(g)
    sh = mask.filter(ImageFilter.GaussianBlur(5)).point(lambda v: int(v * 0.5))
    sh_l = Image.new("RGBA", tile.size, (0, 0, 10, 0))
    sh_l.putalpha(sh)
    tile.alpha_composite(sh_l, (0, 5))
    tile.alpha_composite(glow_l)
    tile.alpha_composite(layer)
    return tile, tw, th


def fit_size(idx, lines, size, maxw, minsize=40):
    d = ImageDraw.Draw(Image.new("RGB", (4, 4)))
    while size > minsize and max(d.textlength(l, font=fnt(idx, size)) for l in lines) > maxw:
        size -= 2
    return size


def headline_tile(fm, text, sub=None, maxw=None, align="c", hs=None, ss=None):
    lines = text.split("\n")
    maxw = maxw or fm.W * 0.90
    hs = fit_size(HEAVY, lines, hs or fm.hs, maxw)
    items = [(l, fnt(HEAVY, hs), CREAM, 0 if i == 0 else int(hs * 0.10)) for i, l in enumerate(lines)]
    if sub:
        sl = sub.split("\n")
        s = fit_size(MEDIUM, sl, ss or fm.ss, maxw, 36)
        for i, l in enumerate(sl):
            items.append((l, fnt(MEDIUM, s), SUBC, int(hs * 0.30) if i == 0 else int(s * 0.12)))
    return text_tile(items, align)


# ------------------------------------------------------------------ blit
def blit(dst, tile, cx, cy, alpha=1.0, scale=1.0, angle=0.0):
    if alpha <= 0.004:
        return
    t = tile
    if abs(scale - 1) > 1e-3:
        t = t.resize((max(1, int(t.width * scale)), max(1, int(t.height * scale))), Image.Resampling.BICUBIC)
    if abs(angle) > 1e-3:
        t = t.convert("RGBa").rotate(angle, resample=Image.Resampling.BICUBIC, expand=True).convert("RGBA")
    if alpha < 0.999:
        a = t.getchannel("A").point(lambda v: int(v * alpha))
        t = t.copy()
        t.putalpha(a)
    pano.paste_clip(dst, t, int(round(cx - t.width / 2)), int(round(cy - t.height / 2)))


# ------------------------------------------------------------------ assets
def make_moon(r):
    S = 3
    m = Image.new("RGBA", (2 * r * S, 2 * r * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(m)
    d.ellipse((0, 0, 2 * r * S - 1, 2 * r * S - 1), fill=(246, 240, 214, 255))
    for (px, py, pr, shade) in [(-0.35, -0.25, 0.22, 20), (0.30, 0.15, 0.30, 16), (-0.10, 0.45, 0.17, 18),
                                (0.45, -0.40, 0.12, 14), (-0.50, 0.20, 0.10, 14), (0.05, -0.55, 0.09, 12)]:
        c = (int(r * S * (1 + px)), int(r * S * (1 + py)))
        rr = int(r * S * pr)
        d.ellipse((c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr), fill=(246 - shade, 238 - shade, 212 - shade, 255))
    mask = Image.new("L", m.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, 2 * r * S - 1, 2 * r * S - 1), fill=255)
    m = m.resize((2 * r, 2 * r), Image.Resampling.LANCZOS)
    m.putalpha(mask.resize((2 * r, 2 * r), Image.Resampling.LANCZOS))
    g = pano.glow(r * 9, (150, 172, 255), 0.55)
    g.alpha_composite(m, (g.width // 2 - r, g.height // 2 - r))
    return g


def make_icon(size):
    im = Image.open(ICON).convert("RGB").resize((size, size), Image.Resampling.LANCZOS)
    mask = C.rounded_mask((size, size), int(size * 0.2237))
    out = im.convert("RGBA")
    out.putalpha(mask)
    pad = int(size * 0.5)
    tile = Image.new("RGBA", (size + 2 * pad, size + 2 * pad), (0, 0, 0, 0))
    g = pano.glow(int(size * 2.1), (130, 160, 255), 0.55)
    tile.alpha_composite(g, ((tile.width - g.width) // 2, (tile.height - g.height) // 2))
    tile.alpha_composite(out, (pad, pad))
    return tile


def phone_tile(shot_path, height):
    shot = Image.open(shot_path)
    pw = int(height / 2.2)
    for _ in range(40):
        bz = max(2, int(round(pw * C.BEZEL / (1 + 2 * C.BEZEL))))
        sw = pw - 2 * bz
        oh = int(round(sw * shot.height / shot.width)) + 2 * bz
        if abs(oh - height) <= 1:
            break
        pw += 1 if oh < height else -1
    tile, (ow, oh, pad) = C.phone(shot, pw, pw / 924.0, 0)
    return tile


def load_sprite(cat, sid, tint, k):
    path = os.path.join(SPRITES, cat[sid]["file"])
    var = path[:-4] + ".en.png"
    if os.path.exists(var):
        path = var
    im = Image.open(path).convert("RGBA")
    arr = np.asarray(im).astype(np.float32)
    for i in range(3):
        arr[..., i] *= tint[i]
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    w, h = int(round(im.width * k)), int(round(im.height * k))
    return im.convert("RGBa").resize((w, h), Image.Resampling.LANCZOS).convert("RGBA")


class Town:
    """11x11 isometric ground with a crossroad, 30 buildings (one per night) drawn depth-sorted."""
    G = 11
    ROAD = 5

    def __init__(self, k, seed=47):    # seed chosen so no small building hides behind a big one
        cat = {e["id"]: e for e in json.load(open(os.path.join(SPRITES, "catalog.json")))}
        self.cat = cat
        self.k = k
        self.hw, self.hh = pano.HW * k, pano.HH * k
        tint = (0.86, 0.91, 1.0)
        g = self.G
        self.cw = int((2 * (g - 1) * pano.HW + 700) * k)
        self.head = int(760 * k)
        self.ch = int(self.head + (2 * (g - 1) * pano.HH) * k + 260 * k)
        self.ox = self.cw / 2
        self.oy = self.head + (g - 1) * self.hh   # canvas y of the ground centre (= tile centre c+r = g-1)
        rnd = random.Random(seed)

        def scr(c, r):
            return self.ox + (c - r) * self.hw, self.head + (c + r) * self.hh

        self.scr = scr
        ground = Image.new("RGBA", (self.cw, self.ch), (0, 0, 0, 0))
        tiles = sorted(((c, r) for c in range(g) for r in range(g)), key=lambda p: (p[0] + p[1], p[0]))
        for c, r in tiles:
            if c == self.ROAD and r == self.ROAD:
                sid = "t-road-crossroad-nesw"
            elif r == self.ROAD:
                sid = "t-road-straight-ew"
            elif c == self.ROAD:
                sid = "t-road-straight-ns"
            else:
                sid = "t-grass-a" if (c + r) % 2 == 0 else "t-grass-b"
            self.paste(ground, sid, tint, scr(c, r))
        self.ground = ground
        # ---- buildings
        houses = [i for i in sorted(cat) if i.startswith("l1-house") and i.endswith("-0")][:11]
        smalls = houses + ["d-pines", "d-bench-lamp", "d-well", "d-flower-bed", "l2-park-small"]
        cross = []
        for qc in (0, 6):
            for qr in (0, 6):
                for l in range(5):
                    cross.append((qc + 2, qr + l))
                    if l != 2:
                        cross.append((qc + l, qr + 2))
        rnd.shuffle(cross)
        small_slots = cross[:len(smalls)]
        big = {"l2": ["l2-library-a", "l2-museum-a", "l2-park-fountain", "l2-library-b", "l2-museum-b", "l2-park-pond"],
               "l3": ["l3-school", "l3-hospital", "l3-police", "l3-firestation", "l3-townhall"],
               "l4": ["l4-sky-a-0", "l4-tower-m", "l4-sky-c-0"]}
        # 2x2 slots (footprint origin) by quarter corners
        slots = {"l4": [(9, 0), (0, 9), (6, 3)],
                 "l3": [(9, 6), (6, 9), (3, 0), (0, 3), (9, 9)],
                 "l2": [(6, 0), (3, 6), (0, 6), (3, 3)]}
        # (3,3) lies on the road ring? ROAD=5, so (3,3) covers 3..4 -> fine; the remaining l2 slots:
        slots["l2"] += [(3, 9), (6, 6)]
        order = []
        for sid, (c, r) in zip(smalls, small_slots):
            order.append((sid, c, r, 1))
        for lv in ("l2", "l3", "l4"):
            for sid, (c, r) in zip(big[lv], slots[lv]):
                order.append((sid, c, r, 2))
        self.items = []
        for n, (sid, c, r, fp) in enumerate(order):
            sp = load_sprite(cat, sid, tint, k)
            e = cat[sid]
            cx, cy = scr(c + (fp - 1) / 2, r + (fp - 1) / 2)
            self.items.append(dict(n=n, sid=sid, sp=sp, cx=cx, cy=cy, e=e, depth=c + r + 2 * (fp - 1)))
        self.draw_order = sorted(self.items, key=lambda it: (it["depth"], it["n"]))

    def paste(self, img, sid, tint, centre):
        sp = load_sprite(self.cat, sid, tint, self.k)
        e = self.cat[sid]
        cx, cy = centre
        pano.paste_clip(img, sp, int(round(cx - e["anchor"][0] * sp.width)),
                        int(round(cy - (1 - e["anchor"][1]) * sp.height)))

    def frame(self, t, ground_a=1.0):
        """RGBA canvas with the ground and all buildings popped at time t."""
        canvas = self.ground.copy()
        if ground_a < 0.999:
            canvas.putalpha(canvas.getchannel("A").point(lambda v: int(v * ground_a)))
        spark = []
        popped = 0
        for it in self.draw_order:
            u = (t - pop_time(it["n"])) / 0.55
            if u < 0:
                continue
            e, sp = it["e"], it["sp"]
            s = max(0.02, ease_back(u)) if u < 1 else 1.0
            if s != 1.0:
                sp = sp.resize((max(1, int(sp.width * s)), max(1, int(sp.height * s))), Image.Resampling.BICUBIC)
            if u < 0.25:
                a = sp.getchannel("A").point(lambda v, f=u / 0.25: int(v * f))
                sp = sp.copy()
                sp.putalpha(a)
            ax, ay = e["anchor"][0] * sp.width, (1 - e["anchor"][1]) * sp.height
            pano.paste_clip(canvas, sp, int(round(it["cx"] - ax)), int(round(it["cy"] - ay)))
            if 0 <= u < 1.4:
                spark.append((it, u))
        for it, u in spark:
            # tiny sparkles around the base
            rnd = random.Random(it["n"] * 31 + 5)
            for _ in range(4):
                ang = rnd.uniform(0, 2 * math.pi)
                dist = rnd.uniform(0.3, 0.9) * (0.5 + u) * 60 * self.k / 0.4
                x = it["cx"] + math.cos(ang) * dist
                y = it["cy"] - it["sp"].height * 0.25 + math.sin(ang) * dist * 0.6 - u * 20
                a = int(255 * clamp01(1 - u / 1.4) * clamp01(u / 0.12))
                Ls = rnd.uniform(5, 9) * self.k / 0.4
                ov = Image.new("RGBA", (int(Ls * 4), int(Ls * 4)), (0, 0, 0, 0))
                d = ImageDraw.Draw(ov)
                c0 = Ls * 2
                d.line((c0 - Ls, c0, c0 + Ls, c0), fill=(255, 245, 210, a // 2), width=2)
                d.line((c0, c0 - Ls, c0, c0 + Ls), fill=(255, 245, 210, a // 2), width=2)
                d.ellipse((c0 - 2, c0 - 2, c0 + 2, c0 + 2), fill=(255, 255, 255, a))
                pano.paste_clip(canvas, ov, int(x - c0), int(y - c0))
        return canvas


# ------------------------------------------------------------------ context
CTX = {}


def build_ctx(fm, lang, shots, copy):
    cx = dict(fm=fm, lang=lang, copy=copy)
    W, H = fm.W, fm.H
    rnd = random.Random(3)
    # stars: x, y, size, phase, speed, parallax px/s
    stars = []
    for _ in range(260 if not fm.vertical else 300):
        stars.append((rnd.random() * W, (rnd.random() ** 1.15) * H * 0.92, rnd.choice([1.1, 1.3, 1.6, 2.0, 2.4]),
                      rnd.random() * 6.28, rnd.uniform(0.4, 1.4), rnd.uniform(1.5, 7.0)))
    cx["stars"] = stars
    cx["big_stars"] = [(rnd.uniform(0.05, 0.95) * W, rnd.uniform(0.06, 0.55) * H, rnd.uniform(9, 18), rnd.random() * 6.28)
                       for _ in range(14)]
    cx["moon"] = make_moon(70 if not fm.vertical else 54)
    cx["dawn_glow"] = pano.glow(int(W * 1.7), (255, 176, 130), 0.55)
    cx["phone_glow"] = pano.glow(int(fm.phone_h * 1.55), (110, 134, 255), 0.40)
    cx["icon_big"] = make_icon(fm.icon)
    cx["icon_small"] = make_icon(150 if not fm.vertical else 190)
    shot = lambda n: os.path.join(shots, n)
    cx["ph"] = {k: phone_tile(shot(f), fm.phone_h) for k, f in
                dict(today="07-today-evening.png", night="03-night.png", morning="04-morning.png",
                     town="01-town.png").items()}
    sh = int(fm.phone_h * 0.76)
    heights = dict(stats=sh, postcards=sh, sounds=sh)
    if fm.vertical:       # a fan: the postcard phone in front and big, the others smaller and behind
        heights = dict(stats=800, postcards=1010, sounds=800)
    cx["ph_s"] = {k: phone_tile(shot(f), heights[k]) for k, f in
                  dict(stats="05-stats.png", postcards="12-postcard.png", sounds="08-sounds.png").items()}
    cx["sh"] = sh
    cx["shs"] = heights
    cx["town"] = Town(fm.town_k)
    cx["zs"] = [(fnt(HEAVY, s), s) for s in (60, 80, 100)]
    return cx


def gradient(fm, d, dim):
    """Background colours: midnight navy -> a little dawn (d) ; dim darkens."""
    top_n, bot_n = np.array([10, 20, 48.]), np.array([19, 40, 90.])
    top_d, bot_d = np.array([26, 48, 104.]), np.array([98, 104, 156.])
    top = top_n * (1 - d) + top_d * d
    bot = bot_n * (1 - d) + bot_d * d
    f = (np.linspace(0, 1, fm.H) ** 1.35)[:, None]
    col = (top * (1 - f) + bot * f) * (1 - 0.3 * dim)
    return col


def dawn_amount(t):
    return 0.85 * (ease_io((t - 13.4) / 2.2) * (1 - ease_io((t - 18.6) / 2.4)))


def dim_amount(t):
    return ease_io((t - 8.6) / 1.0) * (1 - ease_io((t - 13.4) / 1.0))


# ------------------------------------------------------------------ frame
def phone_pose(t, t0, fm, side, rest=-2.5, dur=1.3, ph=0.0):
    """position offsets + angle for an entering floating phone."""
    u = ease_out((t - t0) / dur)
    if fm.vertical:
        dx, dy = 0, (1 - u) * 340
    else:
        dx, dy = (1 - u) * (300 if side == "R" else -300), (1 - u) * 60
    ang = rest + (1 - u) * (6 if side == "R" else -6)
    fl = math.sin(2 * math.pi * t / 5.8 + ph)
    return dx, dy + fl * 9, ang + math.sin(2 * math.pi * t / 7.3 + ph) * 0.7


def draw_phone(img, cx, tile_key, group, t, a, b, side, fm, rest=-2.5):
    al = vis(t, a, b, 0.7, 0.55)
    if al <= 0:
        return
    pcx = (1400 if side == "R" else 520) if not fm.vertical else fm.W / 2
    pcy = fm.phone_cy
    dx, dy, ang = phone_pose(t, a + 0.05, fm, side, rest)
    glow = cx["phone_glow"]
    blit(img, glow, pcx + dx * 0.6, pcy + dy * 0.6, al)
    blit(img, cx[group][tile_key], pcx + dx, pcy + dy, al, angle=ang)


def text_pos(fm, side, tile, tw):
    """centre of a headline tile for the layout."""
    if fm.vertical:
        return fm.W / 2, fm.text_top - TP + tile.height / 2
    x = 140 if side == "R" else 1010          # phone on the right -> text left, and vice versa
    return x - TP + tile.width / 2, fm.H / 2


def draw_text(img, fm, tile, tw, side, t, a, b, rise=26):
    al = vis(t, a + 0.3, b, 0.7, 0.5)
    if al <= 0:
        return
    cx_, cy_ = text_pos(fm, side, tile, tw)
    off = (1 - ease_out((t - a - 0.3) / 0.9)) * rise
    blit(img, tile, cx_, cy_ + off, al)


def render_frame(fi):
    return render_t(fi / FPS)


def render_t(t, raw=True):
    cx = CTX
    fm, copy = cx["fm"], cx["copy"]
    W, H = fm.W, fm.H
    d, dim = dawn_amount(t), dim_amount(t)
    col = gradient(fm, d, dim).astype(np.uint8)
    arr = np.ascontiguousarray(np.broadcast_to(col[:, None, :], (H, W, 3)))
    img = Image.fromarray(arr, "RGB")
    # ---- stars (parallax drift, twinkle)
    star_a = ease_io(t / 2.2) * (1 - 0.75 * d) * (1 - 0.25 * dim * 0)
    sl = Image.new("RGB", (W, H), (0, 0, 0))
    ds = ImageDraw.Draw(sl)
    for x0, y0, s, ph, sp, par in cx["stars"]:
        x = (x0 + t * par) % W
        tw = 0.55 + 0.45 * math.sin(t * sp * 1.6 + ph)
        v = int(255 * star_a * tw * (0.55 if s < 1.5 else 0.9))
        if v < 6:
            continue
        ds.ellipse((x - s, y0 - s, x + s, y0 + s), fill=(v, v, int(v * 0.96)))
    for x0, y0, L, ph in cx["big_stars"]:
        x = (x0 + t * 3.0) % W
        tw = clamp01(0.5 + 0.5 * math.sin(t * 0.9 + ph))
        v = int(215 * star_a * tw)
        if v < 10:
            continue
        L2 = L * (0.5 + 0.5 * tw)
        ds.line((x - L2, y0, x + L2, y0), fill=(v // 2, v // 2, v // 2), width=2)
        ds.line((x, y0 - L2, x, y0 + L2), fill=(v // 2, v // 2, v // 2), width=2)
        ds.ellipse((x - 3, y0 - 3, x + 3, y0 + 3), fill=(v, v, v))
    img = ImageChops.add(img, sl.filter(ImageFilter.GaussianBlur(0.6)))
    img = img.convert("RGBA")
    # ---- warm dawn glow at the horizon
    if d > 0.02:
        blit(img, cx["dawn_glow"], W / 2, H * 1.02, d * 0.42)
    # ---- the moon drifts along an arc over the whole video
    mu = t / TOTAL
    mx = W * (0.10 + 0.80 * mu)
    top_y = H * (0.07 if not fm.vertical else 0.040)
    base_y = H * (0.20 if not fm.vertical else 0.062)
    my = base_y - (base_y - top_y) * math.sin(math.pi * mu)
    ma = ease_io(t / 1.4) * (1 - ease_io((t - 14.2) / 1.6) * (1 - ease_io((t - 18.4) / 1.8)))
    mdim = 0.75 * ease_io((t - 18.6) / 0.8) * (1 - ease_io((t - 25.2) / 0.8)) if not fm.vertical else 0.0
    blit(img, cx["moon"], mx, my, ma * (1 - 0.25 * dim) * (1 - mdim))

    # ---- S1 intro
    a, b = TL["S1"]
    if t < b + 0.2:
        al = vis(t, a + 0.2, b, 1.0, 0.7)
        u = ease_out((t - 0.8) / 1.4)
        ic_y = H * (0.37 if not fm.vertical else 0.40)
        blit(img, cx["icon_big"], W / 2, ic_y + (1 - u) * 24, ease_io((t - 0.8) / 1.0) * (1 - ease_io((t - 3.6) / 0.6)),
             scale=0.86 + 0.14 * u)
        ti, tw, th = CTX_TXT["intro"]
        ty = H * (0.62 if not fm.vertical else 0.585)
        blit(img, ti, W / 2, ty + (1 - ease_out((t - 1.5) / 1.1)) * 20,
             ease_io((t - 1.5) / 1.0) * (1 - ease_io((t - 3.6) / 0.6)))

    # ---- S2 start / S3 night / S4 morning (phone + headline)
    for key, grp, side, scene, rest in (("today", "ph", "R", "S2", -2.5), ("night", "ph", "L", "S3", 2.5),
                                        ("morning", "ph", "R", "S4", -2.5)):
        a, b = TL[scene]
        if a - 0.1 <= t <= b + 0.1:
            tx = {"S2": "start", "S3": "night", "S4": "morning"}[scene]
            ti, tw, th = CTX_TXT[tx]
            draw_phone(img, cx, key, grp, t, a, b, side, fm, rest)
            draw_text(img, fm, ti, tw, "R" if side == "R" else "L", t, a, b)
    # sleepy z's and floating stars in S3
    a, b = TL["S3"]
    if a <= t <= b + 0.3:
        al = vis(t, a + 0.6, b, 0.8, 0.6)
        for i in range(5):
            ph = (t * 0.2 + i / 5.0) % 1.0
            zt = CTX_Z[i % 3]
            if fm.vertical:       # empty sky beside the phone, well below the text
                side = -1 if i % 2 == 0 else 1
                zx = fm.W / 2 + side * (370 + (i // 2) * 55) + math.sin(ph * 6.28 + i) * 16
                zy = 930 - ph * 260
            else:                 # left of the phone, the text is on the right
                zx = 150 + (i % 3) * 62 + math.sin(ph * 6.28 + i) * 16
                zy = 640 - ph * 330 - (i % 2) * 40
            blit(img, zt, zx, zy, al * math.sin(ph * math.pi) ** 1.5 * 0.85)

    # ---- S5 town grows
    a, b = TL["S5"]
    if a - 0.1 <= t <= b + 0.1:
        tn = cx["town"]
        # phase 1: headline + counter + town
        p1 = vis(t, a + 0.2, S5_PHASE2 + 0.3, 0.7, 0.8)
        town_al = vis(t, a + 0.3, S5_PHASE2 + 0.4, 0.9, 0.9)
        if town_al > 0.01:
            canvas = tn.frame(t, ease_io((t - a - 0.4) / 0.9))
            rise = (1 - ease_out((t - a - 0.3) / 1.0)) * 40 + ease_io((t - S5_PHASE2 + 0.4) / 1.0) * 40
            tcx = W / 2
            blit(img, canvas, tcx - tn.ox + canvas.width / 2 + 0, fm.town_cy - tn.oy + canvas.height / 2 + rise, town_al)
        if p1 > 0.01:
            ti, tw, th = CTX_TXT["grow"]
            if fm.vertical:
                px, py = W / 2, fm.text_top - TP + ti.height / 2
            else:
                px, py = W / 2, 54 - TP + ti.height / 2 + 36
            blit(img, ti, px, py + (1 - ease_out((t - a - 0.2) / 0.9)) * 24, p1)
            n = sum(1 for i in range(N_NIGHTS) if t >= pop_time(i) + 0.12)
            if n > 0:
                ct = counter_tile(fm, copy["grow"]["counter"].format(n=n))
                if fm.vertical:
                    cxp, cyp = W / 2, fm.text_top + 360
                else:
                    cxp, cyp = 360, fm.H - 150
                al2 = ease_io((t - pop_time(0) - 0.12) / 0.5) * p1
                blit(img, ct, cxp, cyp, al2)
        # phase 2: phone with the town + text
        p2a = S5_PHASE2 - 0.2
        if t >= p2a:
            ti, tw, th = CTX_TXT["grow2"]
            draw_phone(img, cx, "town", "ph", t, p2a, b, "R", fm, -2.5)
            draw_text(img, fm, ti, tw, "R", t, p2a, b)

    # ---- S6 feature montage + promise
    a, b = TL["S6a"]
    if a - 0.1 <= t <= b + 0.1:
        labels = CTX_LABELS
        keys = ["stats", "postcards", "sounds"]
        if fm.vertical:
            order = [0, 2, 1]                      # sides first, the middle phone on top
            xs = [250, fm.W / 2, 830]
            ys = [770, 880, 770]
            angs = [-5.0, 0.0, 5.0]
            starts = [a + 0.35, a, a + 0.55]
            # labels: the side ones above their phones, the middle one below the front phone
            lab_xy = [(250, 345 - CTX_LABELS[0].height / 2 + TP), (fm.W / 2, 880 + 505 + 14 + CTX_LABELS[1].height / 2 - TP),
                      (830, 345 - CTX_LABELS[2].height / 2 + TP)]
        else:
            order = [0, 1, 2]
            xs = [520, 960, 1400]
            ys = [fm.H * 0.5 - 125 + 30, fm.H * 0.5 - 125 - 10, fm.H * 0.5 - 125 + 30]
            angs = [3.5, 0.0, -3.5]
            starts = [a + 0.25 * i for i in range(3)]
            lab_xy = [(xs[i], ys[i] + cx["shs"][k] / 2 + 26 + labels[i].height / 2 - TP)
                      for i, k in enumerate(keys)]
        for i in order:
            k = keys[i]
            t0 = starts[i]
            al = vis(t, t0, b, 0.7, 0.6)
            if al <= 0.01:
                continue
            u = ease_out((t - t0 - 0.05) / 1.2)
            dy = (1 - u) * 300
            dx = (1 - u) * (0 if not fm.vertical or i == 1 else (-260 if i == 0 else 260))
            fl = math.sin(2 * math.pi * t / 5.8 + i * 1.7) * 8
            tile = cx["ph_s"][k]
            gh = cx["shs"][k]
            blit(img, pano.glow(int(gh * 1.45), (110, 134, 255), 0.36), xs[i] + dx, ys[i] + dy * 0.6, al)
            blit(img, tile, xs[i] + dx, ys[i] + dy + fl, al, angle=angs[i] + (1 - u) * (-4 if i == 0 else 4))
        for i in range(3):
            lx, ly = lab_xy[i]
            t0 = starts[i]
            ly_off = (1 - ease_out((t - t0 - 0.5) / 0.9)) * 18
            blit(img, labels[i], lx, ly + ly_off, vis(t, t0 + 0.5, b, 0.8, 0.6))
    a, b = TL["S6b"]
    if a - 0.1 <= t <= b + 0.1:
        ti, tw, th = CTX_TXT["promise"]
        al = vis(t, a, b, 0.8, 0.6)
        if fm.vertical:
            px, py = W / 2, H * 0.47
        else:
            px, py = W / 2, H / 2
        blit(img, ti, px, py + (1 - ease_out((t - a) / 1.0)) * 24, al)

    # ---- S7 call to action
    a, b = TL["S7"]
    if t >= a - 0.1:
        al_icon = vis(t, a, b + 1, 0.8, 0.1)
        ic_y = 170 if not fm.vertical else 420
        blit(img, cx["icon_small"], W / 2, ic_y + (1 - ease_out((t - a) / 1.0)) * 20, al_icon)
        ti, tw, th = CTX_TXT["cta_h"]
        hy = 300 + ti.height / 2 - TP if not fm.vertical else 580 + ti.height / 2 - TP
        blit(img, ti, W / 2, hy + (1 - ease_out((t - a - 0.4) / 0.9)) * 20, vis(t, a + 0.4, b + 1, 0.8, 0.1))
        lk, lw, lh = CTX_TXT["cta_link"]
        ly = (700 if not fm.vertical else 1010)
        pulse = 0.88 + 0.12 * math.sin(2 * math.pi * (t - a) / 3.2)
        blit(img, cx["link_glow"], W / 2, ly, vis(t, a + 1.0, b + 1, 0.9, 0.1) * pulse)
        blit(img, lk, W / 2, ly + (1 - ease_out((t - a - 1.0) / 0.9)) * 20, vis(t, a + 1.0, b + 1, 0.9, 0.1))
        lg, _, _ = CTX_TXT["cta_langs"]
        gy = (905 if not fm.vertical else 1280)
        blit(img, lg, W / 2, gy, vis(t, a + 1.8, b + 1, 0.9, 0.1))

    out = img.convert("RGB")
    if t > FADE_OUT_FROM:
        k = clamp01((t - FADE_OUT_FROM) / (TOTAL - FADE_OUT_FROM))
        out = Image.blend(out, Image.new("RGB", out.size, NAVY), ease_io(k))
    return out.tobytes() if raw else out


def counter_tile(fm, text):
    fo = fnt(HEAVY, 54 if not fm.vertical else 60)
    d = ImageDraw.Draw(Image.new("RGB", (4, 4)))
    w = int(d.textlength(text, font=fo)) + 90
    h = int(fo.size * 1.5)
    tile = Image.new("RGBA", (max(w, 300) + 2 * TP, h + 2 * TP), (0, 0, 0, 0))
    W_, H_ = tile.size
    pill = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    dp = ImageDraw.Draw(pill)
    dp.rounded_rectangle((TP, TP, W_ - TP, H_ - TP), radius=h // 2, fill=(20, 36, 84, 180),
                         outline=PERI + (200,), width=3)
    gl = pill.filter(ImageFilter.GaussianBlur(14))
    tile.alpha_composite(gl)
    tile.alpha_composite(pill)
    ImageDraw.Draw(tile).text((W_ / 2, H_ / 2 + 2), text, font=fo, fill=CREAM + (255,), anchor="mm")
    return tile


CTX_TXT = {}
CTX_Z = []
CTX_LABELS = []


def build_text(fm, copy):
    c = copy
    CTX_TXT["intro"] = headline_tile(fm, c["intro"]["title"], c["intro"]["sub"], hs=150 if not fm.vertical else 150,
                                     ss=50 if not fm.vertical else 52)
    left_w = 880 if not fm.vertical else fm.W * 0.9
    CTX_TXT["start"] = headline_tile(fm, c["start"]["headline"], None, left_w, "l" if not fm.vertical else "c")
    CTX_TXT["night"] = headline_tile(fm, c["night"]["headline"], c["night"]["sub"], 780 if not fm.vertical else fm.W * 0.9,
                                     "l" if not fm.vertical else "c")
    CTX_TXT["morning"] = headline_tile(fm, c["morning"]["headline"], None, left_w, "l" if not fm.vertical else "c")
    CTX_TXT["grow"] = headline_tile(fm, c["grow"]["headline"], None, fm.W * 0.9, "c", hs=fm.hs if fm.vertical else 84)
    CTX_TXT["grow2"] = headline_tile(fm, c["grow"]["headline2"], c["grow"]["sub2"], 880 if not fm.vertical else fm.W * 0.9,
                                     "l" if not fm.vertical else "c")
    CTX_TXT["promise"] = headline_tile(fm, c["promise"]["headline"], None, fm.W * 0.9, "c", hs=fm.hs + 24)
    CTX_TXT["cta_h"] = headline_tile(fm, c["cta"]["headline"], None, fm.W * 0.9, "c", hs=fm.hs)
    # the link: as big as fits
    link = c["cta"]["link"]
    maxw = fm.W * 0.86 - 2 * 60
    ls = fit_size(HEAVY, [link], 132 if not fm.vertical else 120, maxw, 60)
    ti, tw, th = text_tile([(link, fnt(HEAVY, ls), CREAM, 0)], "c", glow=PERI, glow_a=0.9)
    CTX_TXT["cta_link"] = (ti, tw, th)
    pad = 56
    pw_, ph_ = tw + 2 * pad, th + 40
    g = Image.new("RGBA", (pw_ + 2 * TP + 80, ph_ + 2 * TP + 80), (0, 0, 0, 0))
    dg = ImageDraw.Draw(g)
    box = (g.width // 2 - pw_ // 2, g.height // 2 - ph_ // 2, g.width // 2 + pw_ // 2, g.height // 2 + ph_ // 2)
    dg.rounded_rectangle(box, radius=ph_ // 2, fill=(16, 32, 80, 200), outline=PERI + (230,), width=4)
    glow = g.filter(ImageFilter.GaussianBlur(26))
    g2 = Image.new("RGBA", g.size, (0, 0, 0, 0))
    g2.alpha_composite(glow)
    g2.alpha_composite(glow)
    g2.alpha_composite(g)
    CTX["link_glow"] = g2
    CTX_TXT["cta_langs"] = text_tile([(c["cta"]["langs"], fnt(MEDIUM, 40), SUBC, 0)], "c", glow=PERI, glow_a=0.4)
    CTX_Z[:] = [text_tile([("z", fnt(HEAVY, s), (190, 212, 255), 0)], "c", glow=PERI, glow_a=0.8)[0] for s in (60, 80, 100)]
    labels = [c["features"]["stats"], c["features"]["postcards"], c["features"]["sounds"]]
    spacing = 440 if not fm.vertical else 336
    out = []
    d = ImageDraw.Draw(Image.new("RGB", (4, 4)))
    fo = fnt(BOLD, fm.label)
    for li, lab in enumerate(labels):
        maxlw = spacing - 36 if not fm.vertical else (640 if li == 1 else 440)
        words, lines, cur = lab.split(" "), [], ""
        for w in words:
            tt = (cur + " " + w).strip()
            if d.textlength(tt, font=fo) <= maxlw or not cur:
                cur = tt
            else:
                lines.append(cur)
                cur = w
        lines.append(cur)
        if lab == labels[0]:
            col = CREAM
        else:
            col = WHITE
        items = [(l, fo, col, 0 if i == 0 else 6) for i, l in enumerate(lines)]
        out.append(text_tile(items, "c")[0])
    CTX_LABELS[:] = out


# ------------------------------------------------------------------ audio
SR = 48000


def read_caf(name):
    p = subprocess.run([FFMPEG, "-v", "error", "-i", os.path.join(AUDIO, name), "-f", "f32le", "-ar", str(SR),
                        "-ac", "2", "-"], capture_output=True, check=True)
    return np.frombuffer(p.stdout, np.float32).reshape(-1, 2).copy()


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def synth_music(total):
    n = int(total * SR)
    tt = np.arange(n) / SR
    out = np.zeros((n, 2), np.float64)
    bpm = 64.0
    bar = 4 * 60.0 / bpm
    chords = [[38, 50, 57, 64, 66, 69], [35, 47, 54, 62, 64, 66], [43, 50, 59, 62, 66, 69], [45, 52, 59, 61, 64, 69]]
    nb = int(total / bar) + 2
    for b in range(nb):
        t0 = b * bar
        i0 = int(t0 * SR)
        L = int((bar + 2.2) * SR)
        i1 = min(n, i0 + L)
        if i0 >= n:
            break
        m = i1 - i0
        tl = np.arange(m) / SR
        env = np.minimum(1, tl / 1.4) ** 2 * np.minimum(1, (m / SR - tl) / 1.8)
        env = env * env * (3 - 2 * env) if False else env
        env = np.clip(env, 0, 1)
        env = env * env * (3 - 2 * env)
        for k, note in enumerate(chords[b % 4]):
            f = midi(note)
            amp = 0.55 / (1 + 0.12 * k) * (1.25 if k == 0 else 1.0)
            for ch, det in ((0, -2.5), (1, 2.5)):
                fd = f * 2 ** (det / 1200.0)
                ph0 = k * 1.3 + ch * 0.7
                sig = np.sin(2 * np.pi * fd * (tl + t0) + ph0)
                sig += 0.30 * np.sin(2 * np.pi * 2 * fd * (tl + t0) + ph0 * 1.7)
                sig += 0.12 * np.sin(2 * np.pi * 3 * fd * (tl + t0) + ph0 * 0.4)
                sig *= amp
                out[i0:i1, ch] += sig * env
    # slow swell + gentle low-pass (FFT)
    out *= (0.86 + 0.14 * np.sin(2 * np.pi * tt / 11.0))[:, None]
    freqs = np.fft.rfftfreq(n, 1 / SR)
    lp = 1.0 / (1.0 + (freqs / 1400.0) ** 4)
    for ch in range(2):
        out[:, ch] = np.fft.irfft(np.fft.rfft(out[:, ch]) * lp, n)
    out *= 0.16 / max(1e-6, np.abs(out).max()) * 1.0 * 1.0
    pad = out.copy()
    # bells / kalimba plucks
    rnd = random.Random(11)
    scale = [74, 76, 78, 81, 83, 86]      # D5 E5 F#5 A5 B5 D6
    bells = np.zeros((n, 2), np.float64)
    beat = 60.0 / bpm
    idx = 2
    for b in range(nb):
        for off in (0.0, 1.5, 2.5 if b % 2 else 3.0):
            if rnd.random() < 0.18:
                continue
            tstart = b * bar + off * beat + 0.4
            if tstart + 0.2 > total:
                continue
            idx = max(0, min(len(scale) - 1, idx + rnd.choice([-2, -1, 1, 2, 0, 3, -3])))
            f = midi(scale[idx])
            m = int(2.6 * SR)
            i0 = int(tstart * SR)
            i1 = min(n, i0 + m)
            tl = np.arange(i1 - i0) / SR
            s = np.sin(2 * np.pi * f * tl) * np.exp(-tl / 0.9)
            s += 0.30 * np.sin(2 * np.pi * f * 2.76 * tl) * np.exp(-tl / 0.18)
            s += 0.10 * np.sin(2 * np.pi * f * 5.4 * tl) * np.exp(-tl / 0.08)
            s *= np.minimum(1, tl / 0.004) * 0.06
            pan = rnd.uniform(0.25, 0.75)
            bells[i0:i1, 0] += s * (1 - pan) * 1.4
            bells[i0:i1, 1] += s * pan * 1.4
    # ping-pong echo
    dl = int(0.46 * SR)
    echo = bells.copy()
    for rep, g in ((1, 0.38), (2, 0.2), (3, 0.1)):
        sh = rep * dl
        if sh >= n:
            break
        echo[sh:, 0] += bells[:-sh, 1 if rep % 2 else 0] * g
        echo[sh:, 1] += bells[:-sh, 0 if rep % 2 else 1] * g
    out = pad + echo
    # quiet rain
    rain = read_caf("rain_window.caf").astype(np.float64)
    xf = int(2.0 * SR)
    w = np.linspace(0, 1, xf)[:, None]
    loop = np.concatenate([rain[xf:-xf], rain[-xf:] * (1 - w) + rain[:xf] * w])
    rl = np.tile(loop, (int(np.ceil(n / len(loop))) + 1, 1))
    rl = rl[:n]
    rl = rl / max(1e-6, np.abs(rl).max()) * 0.03
    out += rl
    return out


def mix_audio(total, wav_path):
    music = synth_music(total + 2.0)
    n = int(total * SR)
    mix = np.zeros((n, 2), np.float64)
    mix += music[:n]
    cache = {}
    for t, name, g in sfx_events():
        if name not in cache:
            cache[name] = read_caf(name).astype(np.float64)
        s = cache[name]
        i0 = int(t * SR)
        i1 = min(n, i0 + len(s))
        if i0 < n:
            mix[i0:i1] += s[:i1 - i0] * g * 0.5
    data = mix.astype(np.float32)
    raw = wav_path + ".raw.wav"
    write_wav(raw, data)
    # two-pass loudnorm
    base = "loudnorm=I=-16:TP=-1.5:LRA=11"
    p = subprocess.run([FFMPEG, "-hide_banner", "-i", raw, "-af", base + ":print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True)
    js = json.loads(re.findall(r"\{[^{}]*\}", p.stderr)[-1])
    af = (f"{base}:measured_I={js['input_i']}:measured_TP={js['input_tp']}:measured_LRA={js['input_lra']}:"
          f"measured_thresh={js['input_thresh']}:offset={js['target_offset']}:linear=true")
    norm = wav_path + ".norm.wav"
    subprocess.run([FFMPEG, "-y", "-hide_banner", "-loglevel", "error", "-i", raw, "-af", af, "-ar", str(SR), norm],
                   check=True)
    d = read_wav(norm)[:n].astype(np.float64)
    tt = np.arange(len(d)) / SR
    fade_in = np.clip(tt / 2.0, 0, 1)
    fade_in = fade_in * fade_in * (3 - 2 * fade_in)
    fade_out = np.clip((total - tt) / 1.6, 0, 1)
    fade_out = fade_out * fade_out * (3 - 2 * fade_out)
    d *= (fade_in * fade_out)[:, None]
    write_wav(wav_path, d.astype(np.float32))
    for f in (raw, norm):
        os.remove(f)


def write_wav(path, data):
    import wave
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    import wave
    with wave.open(path, "rb") as w:
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, "<i2").reshape(-1, 2).astype(np.float32) / 32767


# ------------------------------------------------------------------ thumbnail
def thumbnail(fm, copy, out_path):
    """1280x720 YouTube thumbnail composed with the same pieces (landscape context required)."""
    cx = CTX
    W, H = fm.W, fm.H
    col = gradient(fm, 0.18, 0.0).astype(np.uint8)
    img = Image.fromarray(np.ascontiguousarray(np.broadcast_to(col[:, None, :], (H, W, 3))), "RGB").convert("RGBA")
    rnd = random.Random(5)
    sl = Image.new("RGB", (W, H), (0, 0, 0))
    ds = ImageDraw.Draw(sl)
    for _ in range(260):
        x, y, s = rnd.random() * W, rnd.random() * H * 0.9, rnd.choice([1.2, 1.6, 2.2])
        v = rnd.randint(110, 255)
        ds.ellipse((x - s, y - s, x + s, y + s), fill=(v, v, v))
    img = ImageChops.add(img.convert("RGB"), sl.filter(ImageFilter.GaussianBlur(0.6))).convert("RGBA")
    blit(img, make_moon(95), 1180, 170, 0.95)
    blit(img, pano.glow(1500, (110, 134, 255), 0.4), 1450, 560, 1.0)
    blit(img, cx["ph"]["night"], 1360, 585, 1.0, angle=6)
    blit(img, cx["ph"]["town"], 1665, 520, 1.0, angle=-3)
    ic = make_icon(190)
    blit(img, ic, 200, 150, 1.0)
    items = [("SleepHole", fnt(HEAVY, 150), CREAM, 0), ("Sleep on time.", fnt(HEAVY, 78), SUBC, 10),
             ("Grow a town.", fnt(HEAVY, 78), SUBC, 4)]
    ti, tw, th = text_tile(items, "l")
    blit(img, ti, 90 - TP + ti.width / 2 + 40, 520 - 40 + ti.height / 2 - 120, 1.0)
    fo = fnt(HEAVY, 48)
    pill = copy["thumb"]["pill"]
    d = ImageDraw.Draw(Image.new("RGB", (4, 4)))
    w = int(d.textlength(pill, font=fo)) + 80
    pt = Image.new("RGBA", (w + 2 * TP, 100 + 2 * TP), (0, 0, 0, 0))
    dp = ImageDraw.Draw(pt)
    dp.rounded_rectangle((TP, TP, TP + w, TP + 100), radius=50, fill=(143, 184, 255, 255))
    dp.text((TP + w / 2, TP + 52), pill, font=fo, fill=(10, 20, 48, 255), anchor="mm")
    blit(img, pt, 90 - TP + pt.width / 2 + 40, 930, 1.0)
    img.convert("RGB").resize((1280, 720), Image.Resampling.LANCZOS).save(out_path, quality=92)


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--format", choices=["landscape", "vertical"], required=True)
    ap.add_argument("--lang", default="en")
    ap.add_argument("--shots", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--thumb", action="store_true", help="also write the 1280x720 thumbnail (landscape only)")
    ap.add_argument("--stills-only", action="store_true", help="write the stills, skip the video")
    ap.add_argument("--skip-audio", action="store_true", help="reuse build/promo/_audio.wav")
    ap.add_argument("--workers", type=int, default=7)
    a = ap.parse_args()
    shots = os.path.abspath(a.shots)
    out = os.path.abspath(a.out)
    os.makedirs(os.path.join(out, "frames"), exist_ok=True)
    fm = Fmt(a.format)
    copy = json.load(open(os.path.join(HERE, "copy.json"), encoding="utf-8"))[a.lang]
    CTX.update(build_ctx(fm, a.lang, shots, copy))
    build_text(fm, copy)
    tag = "16x9" if not fm.vertical else "9x16"

    stills = [("1-intro", 2.8), ("2-start", 6.4), ("3-night", 11.0), ("4-morning", 15.8), ("5a-town-grows", 23.0),
              ("5b-town-phone", 26.9), ("6a-features", 30.6), ("6b-promise", 34.4), ("7-cta", 39.0)]
    for name, t in stills:
        render_t(t, raw=False).save(os.path.join(out, "frames", f"{name}-{tag}.png"))
    if a.thumb and not fm.vertical:
        thumbnail(fm, copy, os.path.join(out, f"sleephole-thumb-{a.lang}.jpg"))
    if a.stills_only:
        return
    wav = os.path.join(out, "_audio.wav")
    if not (a.skip_audio and os.path.exists(wav)):
        print("audio ...", flush=True)
        mix_audio(TOTAL, wav)
    mp4 = os.path.join(out, f"sleephole-promo-{a.lang}-{tag}.mp4")
    nfr = int(round(TOTAL * FPS))
    cmd = [FFMPEG, "-y", "-hide_banner", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", f"{fm.W}x{fm.H}", "-r", str(FPS), "-i", "-", "-i", wav,
           "-c:v", "libx264", "-profile:v", "high", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart", "-r", str(FPS),
           "-shortest", mp4]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    ctx = mp.get_context("fork")
    with ctx.Pool(a.workers) as pool:
        for i, fr in enumerate(pool.imap(render_frame, range(nfr), chunksize=3)):
            proc.stdin.write(fr)
            if i % 150 == 0:
                print(f"frame {i}/{nfr}", flush=True)
    proc.stdin.close()
    proc.wait()
    print("wrote", mp4)


if __name__ == "__main__":
    main()
