#!/usr/bin/env python3
"""Renders a town exported by the SleepCore `dumpTown` test (real layout logic) with the real sprites.

    cd SleepCore && DUMP_TOWN=/tmp/town.json DUMP_NIGHTS=60 swift test --filter dumpTown
    python3 tools/render/layout_preview.py /tmp/town.json docs/previews/layout_60.png
"""
import json, os, sys
from PIL import Image

ROOT = "assets/sprites"
HALF_W, HALF_H = 0.70710678 * 181, 0.35355339 * 181
cat = {e["id"]: e for e in json.load(open(os.path.join(ROOT, "catalog.json")))}
items = json.load(open(sys.argv[1]))
out = sys.argv[2] if len(sys.argv) > 2 else "docs/previews/layout.png"

occ = {(i["col"] + a, i["row"] + b) for i in items for a in range(i["size"]) for b in range(i["size"])}
cs, rs = [c for c, _ in occ], [r for _, r in occ]
draw = []
for c in range(min(cs) - 1, max(cs) + 2):          # grass under everything
    for r in range(min(rs) - 1, max(rs) + 2):
        if (c, r) not in occ or any(i["col"] == c and i["row"] == r and cat[i["id"]]["kind"] != "road"
                                    and cat[i["id"]]["kind"] != "road-lit" for i in items):
            draw.append((-1, 0, "t-grass-a" if (c + r) % 2 else "t-grass-b", c, r))
for i in items:
    k = cat[i["id"]]["kind"]
    s = i["size"]
    x, z = i["col"] + (s - 1) / 2, i["row"] + (s - 1) / 2
    layer = 0 if k in ("road", "road-lit") else 1
    draw.append((i["col"] + s - 1 + i["row"] + s - 1 if layer else -1, layer, i["id"], x, z))
draw.sort(key=lambda t: (t[1] > 0, t[0], t[1]))

def pos(e, x, z):
    sx, sy = (x - z) * HALF_W, (x + z) * HALF_H
    return sx - e["anchor"][0] * e["size"][0], sy - (1 - e["anchor"][1]) * e["size"][1]

xs, ys = [], []
for _, _, sid, x, z in draw:
    e = cat[sid]; px, py = pos(e, x, z)
    xs += [px, px + e["size"][0]]; ys += [py, py + e["size"][1]]
img = Image.new("RGBA", (int(max(xs) - min(xs)) + 40, int(max(ys) - min(ys)) + 40), (182, 214, 232, 255))
for _, _, sid, x, z in draw:
    e = cat[sid]; px, py = pos(e, x, z)
    img.alpha_composite(Image.open(os.path.join(ROOT, e["file"])).convert("RGBA"),
                        (int(px - min(xs)) + 20, int(py - min(ys)) + 20))
img.thumbnail((2400, 2400))
img.convert("RGB").save(out)
print(out, img.size)
