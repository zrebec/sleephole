#!/usr/bin/env python3
"""Composes the App Store marketing screenshots: panorama background + headline + phone frame.

usage: python3 tools/store/compose.py --lang en --size large --shots <raw screenshots dir> --out <dir>
Writes 01.png … 08.png and panorama-preview.png (RGB, no alpha).
"""
import argparse
import json
import os
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import panorama as pano  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SIZES = {"large": (1320, 2868), "medium": (1206, 2622)}   # 6.9" and 6.3"
FONT_PATH = "/System/Library/Fonts/Avenir Next.ttc"
HEAVY, BOLD, MEDIUM = 8, 0, 5                               # face indices in the .ttc

# slot -> raw screenshot file name (the final run points --shots at a folder with the same names)
SLOTS = [
    "02-today.png",          # 1 hero: Today
    "07-today-evening.png",  # 2 "Go to sleep"
    "03-night.png",          # 3 night screen
    "04-morning.png",        # 4 morning result
    "01-town.png",           # 5 a big town
    "05-stats.png",          # 6 stats + calendar
    "12-postcard.png",       # 7 parcel / postcard (placeholder while the file is missing)
    "08-sounds.png",         # 8 sleep sounds
]
TILT = {2: 3.5, 4: -3.5, 6: 3.5}                            # slot -> degrees (counter-clockwise)

PHONE_W = 0.70          # outer phone width / image width
PHONE_BOTTOM_OFF = 0.07   # this share of the phone height runs off the bottom edge
BEZEL = 0.022           # of the screen width
CORNER = 0.137          # display corner radius / screen width
HEADLINE_BASE = 112     # px at 1320 wide
SUB_SIZE = 50
TEXT_TOP = 0.070        # of the image height


def font(idx, size):
    return ImageFont.truetype(FONT_PATH, int(round(size)), index=idx)


def panorama_for(size, cache_dir, lang):
    os.makedirs(cache_dir, exist_ok=True)
    path = os.path.join(cache_dir, f"panorama-large-{lang}.png")
    if os.path.exists(path) and os.path.getmtime(path) > os.path.getmtime(pano.__file__):
        big = Image.open(path).convert("RGB")
    else:
        big = pano.render(lang=lang)
        big.save(path)
    w, h = SIZES[size]
    if (w, h) == SIZES["large"]:
        return big
    return big.resize((8 * w, h), Image.Resampling.LANCZOS)


def rounded_mask(size, radius, scale=4):
    w, h = size
    m = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), radius * scale, fill=255)
    return m.resize((w, h), Image.Resampling.LANCZOS)


def placeholder(size, word):
    w, h = size
    arr = np.zeros((h, w, 3), np.float32)
    top, bot = np.array([12, 14, 44]), np.array([22, 24, 70])
    f = np.linspace(0, 1, h)[:, None, None]
    arr[:] = top * (1 - f) + bot * f
    im = Image.fromarray(arr.astype(np.uint8), "RGB")
    d = ImageDraw.Draw(im)
    fo = font(HEAVY, w * 0.11)
    d.text((w / 2, h / 2), word, font=fo, fill=(150, 160, 220), anchor="mm")
    return im


def phone(shot, pw, f, angle):
    """RGBA tile: screenshot in a dark bezel with a soft shadow, rotated by `angle` degrees."""
    bz = max(2, int(round(pw * BEZEL / (1 + 2 * BEZEL))))
    sw = pw - 2 * bz
    sh = int(round(sw * shot.height / shot.width))
    scr = shot.convert("RGB").resize((sw, sh), Image.Resampling.LANCZOS)
    pad = int(160 * f)
    ow, oh = pw, sh + 2 * bz
    tile = Image.new("RGBA", (ow + 2 * pad, oh + 2 * pad), (0, 0, 0, 0))
    # shadow
    sm = Image.new("L", tile.size, 0)
    strong = 1.0 if angle else 0.0                      # tilted phones: shadow falls further away, to the side
    dx = int((-1 if angle > 0 else 1) * 34 * f * strong)
    dy = int((46 + 34 * strong) * f)
    sm.paste(rounded_mask((ow, oh), int(sw * CORNER) + bz), (pad + dx, pad + dy))
    sm = sm.filter(ImageFilter.GaussianBlur(52 * f)).point(lambda v: int(v * (0.62 + 0.1 * strong)))
    tile.alpha_composite(Image.merge("RGBA", (Image.new("L", tile.size, 0),) * 3 + (sm,)))
    # bezel
    outer = rounded_mask((ow, oh), int(sw * CORNER) + bz)
    body = Image.new("RGBA", (ow, oh), (16, 16, 20, 255))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, ow - 1, oh - 1), int(sw * CORNER) + bz, outline=(74, 76, 90, 255),
                                           width=max(2, int(3 * f)))
    body.putalpha(outer)
    tile.alpha_composite(body, (pad, pad))
    # screen
    sc = scr.convert("RGBA")
    sc.putalpha(rounded_mask((sw, sh), int(sw * CORNER)))
    tile.alpha_composite(sc, (pad + bz, pad + bz))
    if angle:
        tile = tile.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    return tile, (ow, oh, pad)


def wrap(text, fo, maxw, draw):
    words, lines, cur = text.split(" "), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=fo) <= maxw or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    if len(lines) == 2:        # balance the two lines (no orphan word)
        best = min(range(1, len(words)), key=lambda k: max(draw.textlength(" ".join(words[:k]), font=fo),
                                                          draw.textlength(" ".join(words[k:]), font=fo)))
        lines = [" ".join(words[:best]), " ".join(words[best:])]
    return lines


def headline_size(copy, W):
    """One headline size per language: the biggest at which every headline line fits."""
    d = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    size = HEADLINE_BASE * W / 1320
    maxw = W * 0.88
    for c in copy:
        for line in c["headline"].split("\n"):
            wd = d.textlength(line, font=font(HEAVY, size))
            if wd > maxw:
                size = size * maxw / wd
    return size


def draw_text(img, c, hsize, f, W, H):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d, ds = ImageDraw.Draw(layer), ImageDraw.Draw(shadow)
    fh, fs = font(HEAVY, hsize), font(MEDIUM, SUB_SIZE * f)
    y = H * TEXT_TOP
    for line in c["headline"].split("\n"):
        ds.text((W / 2, y + 5 * f), line, font=fh, fill=(0, 0, 20, 110), anchor="mt")
        d.text((W / 2, y), line, font=fh, fill=(255, 255, 255, 255), anchor="mt")
        y += hsize * 1.13
    y += 22 * f
    for line in wrap(c["sub"], fs, W * 0.80, d):
        ds.text((W / 2, y + 3 * f), line, font=fs, fill=(0, 0, 20, 90), anchor="mt")
        d.text((W / 2, y), line, font=fs, fill=(255, 255, 255, 204), anchor="mt")
        y += SUB_SIZE * f * 1.25
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(7 * f)))
    img.alpha_composite(layer)
    return y


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", required=True, choices=["en", "sk", "cs"])
    ap.add_argument("--size", required=True, choices=list(SIZES))
    ap.add_argument("--shots", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cache-dir", default=os.path.join(tempfile.gettempdir(), "sleephole-store"))
    a = ap.parse_args()
    W, H = SIZES[a.size]
    f = W / 1320
    copy = json.load(open(os.path.join(HERE, "copy.json"), encoding="utf-8"))[a.lang]
    os.makedirs(a.out, exist_ok=True)
    big = panorama_for(a.size, a.cache_dir, a.lang)
    hsize = headline_size(copy, W)
    print(f"headline size {hsize:.1f}px (base {HEADLINE_BASE * f:.1f})")
    slices = []
    for i in range(8):
        img = big.crop((i * W, 0, (i + 1) * W, H)).convert("RGBA")
        n = i + 1
        path = os.path.join(a.shots, SLOTS[i])
        shot = Image.open(path) if os.path.exists(path) else placeholder(SIZES[a.size], "postcard")
        if not os.path.exists(path):
            print(f"  slot {n}: {SLOTS[i]} missing -> placeholder")
        pw = int(round(PHONE_W * W))
        tile, (ow, oh, pad) = phone(shot, pw, f, TILT.get(n, 0))
        cx = W / 2
        cy = H - oh * (1 - PHONE_BOTTOM_OFF) + oh / 2
        # a soft glow behind the phone in the night images
        nf = float(pano.night_factor((i + 0.5) / 8))
        if nf > 0.05:
            g = pano.glow(int(pw * 1.7), (110, 130, 255), 0.42 * nf)
            pano.paste_clip(img, g, int(cx - g.width / 2), int(cy - g.height / 2))
        pano.paste_clip(img, tile, int(round(cx - tile.width / 2)), int(round(cy - tile.height / 2)))
        text_bottom = draw_text(img, copy[i], hsize, f, W, H)
        top_of_phone = cy - oh / 2
        if text_bottom > top_of_phone - 10 * f:
            print(f"  WARNING slot {n}: text bottom {text_bottom:.0f} touches phone top {top_of_phone:.0f}")
        rgb = img.convert("RGB")
        rgb.save(os.path.join(a.out, f"{n:02d}.png"))
        slices.append(rgb)
    # review strip: all 8 side by side, thin gaps, ~3000 px wide
    gap = 6
    pw_ = (3000 - 7 * gap) // 8
    ph_ = int(round(pw_ * H / W))
    prev = Image.new("RGB", (8 * pw_ + 7 * gap, ph_), (255, 255, 255))
    for i, s in enumerate(slices):
        prev.paste(s.resize((pw_, ph_), Image.Resampling.LANCZOS), (i * (pw_ + gap), 0))
    prev.save(os.path.join(a.out, "panorama-preview.png"))
    # contact sheet for a review page: the 8 images in one row at 25 %, JPEG q85
    cw, ch = W // 4, H // 4
    con = Image.new("RGB", (8 * cw, ch))
    for i, s_ in enumerate(slices):
        con.paste(s_.resize((cw, ch), Image.Resampling.LANCZOS), (i * cw, 0))
    con.save(os.path.join(a.out, "contact.jpg"), quality=85)


if __name__ == "__main__":
    main()
