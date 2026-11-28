#!/usr/bin/env python3
"""Comparison sheet of the build 14 shop candidates (step 14c1), at the same pixel scale as existing sprites.
usage: python3 tools/render/shop_sheet.py [candidates_dir=build/shop-candidates] [out=docs/previews/shop-candidates.png]
Rows: shopping centre candidates, retail park candidates, and a SCALE row of existing buildings (no thumbnailing)."""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

cdir = sys.argv[1] if len(sys.argv) > 1 else "build/shop-candidates"
out = sys.argv[2] if len(sys.argv) > 2 else "docs/previews/shop-candidates.png"
cat = json.load(open(os.path.join(cdir, "catalog.json")))
try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 16)
    big = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 26)
except OSError:
    font = big = ImageFont.load_default()
LABELS = {"cand-sc1": "SC1 Hala (a)", "cand-sc1-b": "SC1 Hala (b)", "cand-sc2": "SC2 Pasaz s trhom",
          "cand-sc3": "SC3 Obchodny dom", "cand-sc4": "SC4 Sklenene centrum", "cand-rp1": "RP1 Dlha hala (a)",
          "cand-rp1-b": "RP1 Dlha hala (b)", "cand-rp2": "RP2 Dve predajne", "cand-rp3": "RP3 Rad s markizami", "cand-sc5": "SC5 Velke sklenene centrum (4x4)",
          "cand-sc5-name": "SC5 with a cat name (4x4)", "cand-sc6": "SC6 Centrum do L (4x4)"}
SCALE = [("assets/sprites/L1/l1-house-a-0.png", "house (L1, 1x1)"), ("assets/sprites/L3/l3-police.png", "police (L3)"), ("assets/sprites/L3/l3-hospital.png", "hospital (L3)"),
         ("assets/sprites/L2/l2-library-b.png", "library (L2)"), ("assets/sprites/L4/l4-sky-a-0.png", "skyscraper (L4)")]

def row(title, items):
    ims = [(Image.open(p).convert("RGBA"), t) for p, t in items]
    h = max(i.height for i, _ in ims)
    w = sum(i.width + 30 for i, _ in ims) + 30
    return title, ims, h, w

BIG = ("cand-sc5", "cand-sc5-name", "cand-sc6")
rows = [
    row("Nakupne centrum (shopping centre, proposed L3)",
        [(os.path.join(cdir, e["file"]), LABELS[e["id"]]) for e in cat if e["id"].startswith("cand-sc") and e["id"] not in BIG]),
    row("Obchodny park (retail park, proposed L2)",
        [(os.path.join(cdir, e["file"]), LABELS[e["id"]]) for e in cat if e["id"].startswith("cand-rp")]),
    row("4x4 - a whole block (shopping centre, proposed L3)",
        [(os.path.join(cdir, e["file"]), LABELS[e["id"]]) for e in cat if e["id"] in BIG]),
    row("SCALE - existing buildings at the same pixel scale", SCALE),
]
W = max(r[3] for r in rows)
H = sum(r[2] + 90 for r in rows) + 20
sheet = Image.new("RGBA", (W, H), (236, 240, 232, 255))
d = ImageDraw.Draw(sheet)
y = 10
for title, ims, h, _ in rows:
    d.text((20, y), title, fill=(30, 30, 30), font=big)
    y += 45
    x = 30
    for im, t in ims:
        sheet.alpha_composite(im, (x, y + h - im.height))
        d.text((x, y + h + 6), t, fill=(40, 40, 40), font=font)
        x += im.width + 30
    y += h + 45
sheet.convert("RGB").save(out)
print(out, sheet.size)
