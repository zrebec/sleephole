#!/usr/bin/env python3
"""Renders the App Store panorama: one continuous background for 8 screenshots side by side.

evening -> deep night -> dawn, a big moon on the border of image 3 and 4, a low sun at the far right,
and a growing isometric town (the app's own sprites) along the bottom.

The panorama is always rendered at the LARGE size (8 x 1320 wide, 2868 high) and scaled for the
other sizes, so slices line up exactly.   usage: python3 tools/store/panorama.py out.png
"""
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPRITES = os.environ.get("STORE_SPRITES") or os.path.join(ROOT, "assets", "sprites")
LANG = "sk"                    # sprite sign language: "sk" = the default files, "en" / "cs" = <id>.<lang>.png when present
N = 8
SLICE_W, H = 1320, 2868
W = N * SLICE_W
K = 0.9                        # sprite scale in the final panorama
HW, HH = 127.98, 63.99         # half tile (same as tools/render/demo_town.py)
ROWS = 14                      # depth of the town band in tiles (rows)


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def night_factor(t):
    """0 at dusk / dawn, 1 in the deep night (t = 0..1 along the panorama)."""
    t = np.asarray(t, dtype=np.float64)
    return smooth((t - 0.10) / 0.25) * (1 - smooth((t - 0.66) / 0.22))


# (t, top colour, horizon colour)
SKY = [
    (0.00, (34, 30, 92), (236, 122, 104)),
    (0.14, (24, 26, 82), (170, 96, 130)),
    (0.30, (14, 18, 62), (62, 56, 120)),
    (0.50, (10, 13, 46), (22, 30, 82)),
    (0.68, (14, 20, 66), (56, 66, 124)),
    (0.84, (60, 92, 160), (248, 160, 124)),
    (1.00, (96, 150, 214), (255, 206, 142)),
]


def sky_colors(t):
    ts = [k[0] for k in SKY]
    top = np.stack([np.interp(t, ts, [k[1][i] for k in SKY]) for i in range(3)], -1)
    hor = np.stack([np.interp(t, ts, [k[2][i] for k in SKY]) for i in range(3)], -1)
    return top, hor


def sky():
    t = np.linspace(0, 1, W)
    top, hor = sky_colors(t)                                   # (W, 3)
    f = np.linspace(0, 1, H)[:, None]                          # (H, 1)
    m = np.clip((f - 0.30) / 0.62, 0, 1) ** 1.7                # warm low band
    arr = top[None, :, :] * (1 - m[..., None]) + hor[None, :, :] * m[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def glow(size, color, strength=1.0):
    """A soft radial glow tile: RGBA, alpha falls off smoothly."""
    size = size // 2 * 2
    r = size // 2
    y, x = np.mgrid[-r:r, -r:r]
    d = np.sqrt(x * x + y * y) / r
    a = (np.clip(1 - d, 0, 1) ** 2.2) * 255 * strength
    arr = np.zeros((size, size, 4), np.uint8)
    arr[..., 0], arr[..., 1], arr[..., 2] = color
    arr[..., 3] = a.astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def paste_clip(img, tile, x0, y0):
    sx0, sy0 = max(0, -x0), max(0, -y0)
    sx1, sy1 = min(tile.width, img.width - x0), min(tile.height, img.height - y0)
    if sx1 > sx0 and sy1 > sy0:
        img.alpha_composite(tile.crop((sx0, sy0, sx1, sy1)), (x0 + sx0, y0 + sy0))


def stars(img, rnd):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(3200):
        x = rnd.random() * W
        y = (rnd.random() ** 1.25) * H * 0.78
        nf = float(night_factor(x / W))
        if rnd.random() > nf:
            continue
        fade = 1 - float(smooth((y / H - 0.45) / 0.30))
        a = int(255 * (0.35 + 0.65 * rnd.random()) * fade * min(1, nf * 1.4 + 0.2))
        s = rnd.choice([1, 1, 1.5, 2, 2, 3])
        col = rnd.choice([(255, 255, 255), (255, 244, 214), (205, 222, 255)])
        d.ellipse((x - s, y - s, x + s, y + s), fill=col + (a,))
    for _ in range(60):                       # a few big four-point twinkles
        x = rnd.uniform(0.12, 0.72) * W
        y = rnd.uniform(0.19, 0.50) * H
        nf = float(night_factor(x / W))
        if nf < 0.5:
            continue
        L = rnd.uniform(14, 30)
        a = int(235 * nf)
        d.line((x - L, y, x + L, y), fill=(255, 255, 255, a // 2), width=2)
        d.line((x, y - L, x, y + L), fill=(255, 255, 255, a // 2), width=2)
        d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=(255, 255, 255, a))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(3)))
    img.alpha_composite(layer)


def moon(img):
    cx, cy, r = 3 * SLICE_W, 1010, 255            # straddles the border of image 3 and 4
    img.alpha_composite(glow(1900, (150, 170, 255), 0.55), (cx - 950, cy - 950))
    img.alpha_composite(glow(1000, (225, 232, 255), 0.55), (cx - 500, cy - 500))
    S = 4
    m = Image.new("RGBA", (2 * r * S, 2 * r * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(m)
    d.ellipse((0, 0, 2 * r * S - 1, 2 * r * S - 1), fill=(246, 242, 222, 255))
    for (px, py, pr, shade) in [(-0.35, -0.25, 0.22, 20), (0.30, 0.15, 0.30, 16), (-0.10, 0.45, 0.17, 18),
                                (0.45, -0.40, 0.12, 14), (-0.50, 0.20, 0.10, 14), (0.05, -0.55, 0.09, 12),
                                (0.12, 0.62, 0.08, 12), (-0.28, 0.02, 0.07, 10)]:
        c = (int(r * S * (1 + px)), int(r * S * (1 + py)))
        rr = int(r * S * pr)
        d.ellipse((c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr), fill=(246 - shade, 240 - shade, 218 - shade, 255))
    mask = Image.new("L", m.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, 2 * r * S - 1, 2 * r * S - 1), fill=255)
    m = m.resize((2 * r, 2 * r), Image.Resampling.LANCZOS)
    m.putalpha(mask.resize((2 * r, 2 * r), Image.Resampling.LANCZOS))
    img.alpha_composite(m, (cx - r, cy - r))


def sun(img):
    cx, cy, r = W - 150, 2050, 215
    paste_clip(img, glow(2000, (255, 190, 120), 0.7), cx - 1000, cy - 1000)
    paste_clip(img, glow(900, (255, 225, 160), 0.8), cx - 450, cy - 450)
    S = 3
    s = Image.new("RGBA", (2 * r * S, 2 * r * S), (0, 0, 0, 0))
    ImageDraw.Draw(s).ellipse((0, 0, 2 * r * S - 1, 2 * r * S - 1), fill=(255, 226, 150, 255))
    paste_clip(img, s.resize((2 * r, 2 * r), Image.Resampling.LANCZOS), cx - r, cy - r)


def hills(img):
    """Two soft distant ridges behind the town (they hide the zigzag back edge of the grass)."""
    base = H - ROWS * HH * K + 40
    x = np.arange(W)
    t = x / W
    nf = night_factor(t)
    for amp, off, lift, col_night, col_day in [
            (60, 0.0, 150, (26, 36, 86), (118, 150, 150)),
            (45, 1.7, 70, (22, 40, 76), (96, 160, 120))]:
        y = base - lift + amp * (np.sin(x / 520.0 + off) * 0.6 + np.sin(x / 190.0 + off * 2) * 0.25
                                 + np.sin(x / 1300.0 + off) * 0.5)
        col = np.array(col_day)[None, :] * (1 - nf[:, None]) + np.array(col_night)[None, :] * nf[:, None]
        arr = np.zeros((H, W, 4), np.uint8)
        arr[..., :3] = col[None, :, :].astype(np.uint8)
        arr[..., 3] = ((np.arange(H)[:, None] >= y[None, :]) * 255).astype(np.uint8)
        img.alpha_composite(Image.fromarray(arr, "RGBA"))


# ---------------------------------------------------------------- the town
_cat = {e["id"]: e for e in json.load(open(os.path.join(SPRITES, "catalog.json")))}
_cache = {}


def sprite(sid):
    key = ("sprite", sid, LANG)
    if key not in _cache:
        path = os.path.join(SPRITES, _cat[sid]["file"])
        variant = path[:-4] + "." + LANG + ".png"
        if LANG != "sk" and os.path.exists(variant):
            path = variant
        _cache[key] = Image.open(path).convert("RGBA")
    return _cache[key]


def tint_for(t):
    """Multiply colour along the story: dusk warm-dim, night blue, dawn natural."""
    keys = [(0.0, (1.00, 0.84, 0.86)), (0.16, (0.74, 0.74, 0.96)), (0.50, (0.52, 0.60, 0.92)),
            (0.68, (0.62, 0.68, 0.96)), (0.84, (0.98, 0.90, 0.90)), (1.0, (1.0, 0.97, 0.92))]
    ts = [k[0] for k in keys]
    return tuple(float(np.interp(t, ts, [k[1][i] for k in keys])) for i in range(3))


def tinted(sid, tint):
    key = (sid, LANG, tuple(round(c, 2) for c in tint))
    if key not in _cache:
        arr = np.asarray(sprite(sid)).astype(np.float32)
        for i in range(3):
            arr[..., i] *= tint[i]
        _cache[key] = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    return _cache[key]


def town(rnd):
    Wc, Hc = int(math.ceil(W / K)), int(math.ceil(H / K))
    layer = Image.new("RGBA", (Wc, Hc), (0, 0, 0, 0))
    oy = Hc - (ROWS - 1) * HH + 30        # screen y of band row 0 (the last row sits below the bottom edge)

    def screen(c, r):
        return (c - r) * HW, oy + (c + r) * HH

    occ = set()
    items = []    # (sort key, kind order, sid, c, r, fw, fd)

    def free(c, r, fw, fd):
        return all((c + a, r + b) not in occ for a in range(fw) for b in range(fd))

    def inband(c, r, fw, fd):
        return all(0 <= (c + a + r + b) < ROWS for a in range(fw) for b in range(fd))

    def put(sid, c, r):
        fw, fd = _cat[sid]["footprint"]
        for a in range(fw):
            for b in range(fd):
                occ.add((c + a, r + b))
        items.append((c + fw - 1 + r + fd - 1, 1, sid, c, r, fw, fd))

    def place_at(sid, x_final, s):
        fw, fd = _cat[sid]["footprint"]
        u = int(round(x_final / K / HW))
        s0 = s - (fw - 1)
        if (s0 - u) % 2:
            s0 += 1
        c, r = (u + s0) // 2, (s0 - u) // 2
        if inband(c, r, fw, fd) and free(c, r, fw, fd):
            put(sid, c, r)
            return True
        return False

    umin, umax = -3, int(Wc / HW) + 3
    for s in range(ROWS):                  # grass everywhere in the band
        for u in range(umin, umax):
            if (s - u) % 2:
                continue
            items.append((s, 0, rnd.choice(["t-grass-a", "t-grass-b"]), (u + s) // 2, (s - u) // 2, 1, 1))

    # landmarks at the gaps between the screenshots (the visible part of the panorama), growing to the right
    g = lambda k, dx=0: k * SLICE_W + dx
    feats = [
        (g(0, 40), "l1-house-a-0", 5), (g(0, 40), "l1-house-m-0", 8),
        (g(1, -110), "l1-house-e-0", 6), (g(1, 110), "o-site-2", 7), (g(1, 130), "o-crane-08", 4),
        (g(1, 10), "l1-house-k-0", 10),
        (g(2, -110), "l1-bigblock-e", 6), (g(2, 100), "l1-house-r-0", 5), (g(2, 0), "d-pines", 9),
        (g(3, -140), "l2-museum-a", 6), (g(3, 130), "l2-park-fountain", 8), (g(3, 0), "l1-house-t-0", 11),
        (g(4, -120), "l3-school", 6), (g(4, 140), "l2-library-b", 8), (g(4, 0), "d-clock-tower", 11),
        (g(5, -130), "l3-hospital", 5), (g(5, 120), "l3-townhall", 7), (g(5, 0), "l1-bigblock-j", 10),
        (g(6, -130), "l4-sky-b-0", 4), (g(6, 140), "l4-tower-m", 6), (g(6, 0), "l3-police", 10),
        (g(7, -130), "l4-sky-d-0", 4), (g(7, 150), "l4-sky-c-0", 6), (g(7, 0), "l3-firestation", 10),
        (g(8, -150), "l4-sky-a-0", 5), (g(8, -330), "l4-sky-e-0", 8),
    ]
    for x, sid, s in feats:
        place_at(sid, x, s)

    # fill the rest, denser and bigger towards the right
    houses = [i for i, e in _cat.items() if i.startswith("l1-house") and i.endswith("-0")]
    lvl = lambda l: [i for i, e in _cat.items() if e["level"] == l and e["kind"] in ("building", "park")]
    l2, l3 = lvl(2), lvl(3)
    cands = [(u, s) for s in range(1, ROWS) for u in range(umin, umax) if (s - u) % 2 == 0]
    rnd.shuffle(cands)
    for u, s in cands:
        c, r = (u + s) // 2, (s - u) // 2
        if (c, r) in occ:
            continue
        t = min(max(u * HW * K / W, 0), 1)
        density = 0.10 + 0.50 * t if t < 0.5 else 0.55
        if s < 3:
            density *= 0.5
        if rnd.random() > density:
            continue
        roll = rnd.random()
        if t < 0.2:
            sid = rnd.choice(houses) if roll < 0.7 else rnd.choice(["o-ruin-flowers-1", "o-site-1", "d-flower-bed"])
        elif t < 0.5:
            sid = rnd.choice(houses) if roll < 0.75 else rnd.choice(["d-pines", "d-bench-lamp", "d-well", "d-stall", "l2-park-small"])
        elif t < 0.75:
            sid = rnd.choice(houses) if roll < 0.45 else rnd.choice(l2 + l3 + ["d-pines", "d-bench-lamp"])
        else:
            sid = rnd.choice(houses) if roll < 0.35 else rnd.choice(l3 + ["d-pines", "d-bench-lamp", "d-windmill"])
        fw, fd = _cat[sid]["footprint"]
        if inband(c, r, fw, fd) and free(c, r, fw, fd):
            put(sid, c, r)

    items.sort(key=lambda it: (it[0], it[1], it[2]))
    for _, _, sid, c, r, fw, fd in items:
        e = _cat[sid]
        cx, cy = screen(c + (fw - 1) / 2, r + (fd - 1) / 2)
        tt = min(max(cx * K / W, 0), 1)
        tint = tint_for(tt)
        if e["kind"] == "terrain":       # the grass sinks deeper into the night
            tint = tuple(c * (1 - 0.28 * float(night_factor(tt))) for c in tint)
        sp = tinted(sid, tint)
        paste_clip(layer, sp, int(round(cx - e["anchor"][0] * sp.width)),
                   int(round(cy - (1 - e["anchor"][1]) * sp.height)))
    # scale to the final panorama size (premultiplied, so edges stay clean)
    return layer.convert("RGBa").resize((W, H), Image.Resampling.LANCZOS).convert("RGBA")


def render(seed=11, lang="sk"):
    global LANG
    LANG = lang
    rnd = random.Random(seed)
    img = sky()
    stars(img, rnd)
    moon(img)
    sun(img)
    hills(img)
    img.alpha_composite(town(rnd))
    return img.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "panorama.png"
    im = render(lang=sys.argv[2] if len(sys.argv) > 2 else "sk")
    im.save(out)
    print(out, im.size, im.mode)
