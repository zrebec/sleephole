#!/usr/bin/env python3
"""Contact sheet of rendered sprites grouped by level (for human review).
usage: python3 tools/render/contact_sheet.py assets/sprites [out.png] [cell_px]"""
import json, sys, os
from PIL import Image, ImageDraw, ImageFont
root = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "docs/previews/contact_sheet.png"
cell = int(sys.argv[3]) if len(sys.argv) > 3 else 220
cat = json.load(open(os.path.join(root, "catalog.json")))
cols = 8
try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 13)
    big = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 22)
except OSError:
    font = big = ImageFont.load_default()
rows = []
for lvl in sorted({e["level"] for e in cat}):
    items = [e for e in cat if e["level"] == lvl]
    rows.append(("header", lvl, len(items)))
    for i in range(0, len(items), cols):
        rows.append(("items", items[i:i + cols]))
H = sum(40 if r[0] == "header" else cell + 20 for r in rows)
sheet = Image.new("RGBA", (cols * cell, H), (236, 240, 232, 255))
d = ImageDraw.Draw(sheet)
y = 0
for r in rows:
    if r[0] == "header":
        d.text((10, y + 8), f"Level {r[1]}  ({r[2]} sprites)", fill=(30, 30, 30), font=big)
        y += 40
        continue
    for i, e in enumerate(r[1]):
        im = Image.open(os.path.join(root, e["file"])).convert("RGBA")
        im.thumbnail((cell - 10, cell - 10))
        x0 = i * cell + (cell - im.width) // 2
        sheet.alpha_composite(im, (x0, y + (cell - im.height) // 2))
        d.text((i * cell + 6, y + cell), f'{e["id"]} · {e["nameSK"]}', fill=(40, 40, 40), font=font)
    y += cell + 20
sheet.convert("RGB").save(out)
print(out, sheet.size)
