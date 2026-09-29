#!/usr/bin/env python3
"""Composes a demo town from rendered sprites – validates anchors/projection and previews the look.
This is also the reference implementation of the app's IsoProjection + draw order.

usage: python3 tools/render/demo_town.py assets/sprites [out.png]
"""
import json
import os
import random
import sys

from PIL import Image

PPU = 181.0                 # must match render_sprites.swift
HALF_W = 0.70710678 * PPU   # = TILE_W / 2 ≈ 128 px
HALF_H = 0.35355339 * PPU   # = TILE_H / 2 ≈ 64 px

root = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "docs/previews/demo_town.png"
cat = {e["id"]: e for e in json.load(open(os.path.join(root, "catalog.json")))}
rnd = random.Random(7)
N = 10


def screen(x, z):
    """World (x, z) in tile units -> screen px (y down), before the global offset."""
    return (x - z) * HALF_W, (x + z) * HALF_H


items = []  # (sortKey, id, originX, originZ)


def put(sid, c, r):
    e = cat[sid]
    fw, fd = e["footprint"]
    ox, oz = c + (fw - 1) / 2, r + (fd - 1) / 2       # footprint centre
    items.append(((c + fw - 1) + (r + fd - 1), 0 if e["kind"] in ("terrain", "road") else 1, sid, ox, oz))


# roads: a cross through the middle + a ring road
road = {}
for i in range(N):
    road[(i, 4)] = True
    road[(4, i)] = True
for i in range(1, 8):
    road[(i, 8)] = True
road[(8, 8)] = True
for i in range(5, 8):
    road[(8, i)] = True


def road_sprite(c, r):
    conn = "".join(d for d, (dc, dr) in {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}.items()
                   if road.get((c + dc, r + dr)))
    for e in cat.values():
        if e["kind"] == "road" and e.get("connects") == conn:
            return e["id"]
    return "t-road-crossroad-nesw"


used = set(road)
for c in range(N):
    for r in range(N):
        if (c, r) in road:
            sid = road_sprite(c, r)
            if sid == "t-road-straight-ew" and c in (2, 6):
                sid = "l2-road-lit-we"
            if sid == "t-road-straight-ns" and r in (2, 6):
                sid = "l2-road-lit-ns"
            put(sid, c, r)
        else:
            put(rnd.choice(["t-grass-a", "t-grass-b"]), c, r)

# buildings: pick from levels, 2×2 first where they fit
by_level = {l: [e["id"] for e in cat.values() if e["level"] == l and e["kind"] in ("building", "park")] for l in (1, 2, 3, 4)}
plan = [(0, 0, 3), (5, 0, 4), (0, 5, 2), (5, 5, 3), (2, 0, 4), (7, 2, 3), (0, 2, 2), (2, 6, 1), (6, 6, 1)]
for c, r, lvl in plan:
    choices = [i for i in by_level[lvl] if cat[i]["footprint"][0] == 2]
    if not choices:
        continue
    cells = [(c + a, r + b) for a in (0, 1) for b in (0, 1)]
    if any(x in used or x[0] >= N or x[1] >= N for x in cells):
        continue
    sid = rnd.choice(choices)
    by_level[lvl].remove(sid)
    used.update(cells)
    put(sid, c, r)
for c in range(N):
    for r in range(N):
        if (c, r) not in used:
            if rnd.random() < 0.08:
                put(rnd.choice(["o-ruin-flowers-1", "o-site-1"]), c, r)
            else:
                put(rnd.choice([i for i in by_level[1] if cat[i]["footprint"][0] == 1]), c, r)
            used.add((c, r))

# cars on roads
for (c, r), d in [((1, 4), "se"), ((4, 2), "sw"), ((4, 7), "ne"), ((6, 4), "nw"), ((3, 8), "se")]:
    items.append((c + r + 0.5, 2, f"v-sedan-{d}" if c % 2 else f"v-taxi-{d}", c, r))

items.sort(key=lambda t: (t[0], t[1]))
xs, ys = [], []
for _, _, sid, x, z in items:
    e = cat[sid]
    sx, sy = screen(x, z)
    w, h = e["size"]
    xs += [sx - e["anchor"][0] * w, sx + (1 - e["anchor"][0]) * w]
    ys += [sy - (1 - e["anchor"][1]) * h, sy + e["anchor"][1] * h]
ox, oy = -min(xs) + 20, -min(ys) + 20
img = Image.new("RGBA", (int(max(xs) - min(xs) + 40), int(max(ys) - min(ys) + 40)), (182, 214, 232, 255))
for _, _, sid, x, z in items:
    e = cat[sid]
    sp = Image.open(os.path.join(root, e["file"])).convert("RGBA")
    sx, sy = screen(x, z)
    img.alpha_composite(sp, (int(round(ox + sx - e["anchor"][0] * sp.width)),
                             int(round(oy + sy - (1 - e["anchor"][1]) * sp.height))))
img.thumbnail((2000, 2000))
img.convert("RGB").save(out)
print(out, img.size)
