#!/usr/bin/env python3
"""Step 11b5c, part 1 – candidates for the town decorations the mystery boxes will give (no app change).

Builds ~24 candidate 1x1 props in exactly the town's sprite style (same renderer, camera, light, shadow and pixel scale as
the shipped 1x1 sprites), renders them and composes three preview images for the owner's pick:

    build/11b5c/recipes.json     the candidate recipes (tools/render/recipes.json is NOT touched)
    build/11b5c/renders/         rendered sprites + catalog.json (level 0, kind "decoration", ids d-<name>)
    build/11b5c/candidates.png   contact sheet: every candidate on a grass tile, light and night background
    build/11b5c/in-town.png      12 candidates on the grass in front of a demo town (painter's order)
    build/11b5c/real-size.png    6 candidates at the size one tile has on the phone's town screen (~130 px @3x)

Usage (repo root; the renderer needs the Bash sandbox DISABLED – inside it ModelIO silently loads empty models):

    python3 tools/render/decorations.py            # recipes + render + previews
    python3 tools/render/decorations.py --no-render   # recipes + previews from existing renders
    python3 tools/render/decorations.py --only d-fountain   # render just one id (previews need all)
    python3 tools/render/decorations.py --install     # ship: copy the 12 PNGs into assets/sprites/L0/ and add their 12
                                                      # entries to assets/sprites/catalog.json (text insert, sorted by
                                                      # file like the rest, nothing else touched; idempotent)

Needs the raw Kenney bundle (git-ignored) and Pillow. Models are placed with the helpers of make_recipes.py (imported,
never modified). Decorations have no ground plate: they stand on the town's grass tile (t-grass-a / t-grass-b).
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_recipes as mr                      # noqa: E402  (only its helpers; its recipes are not written)
from make_recipes import part, box, NAT, FAN, HOL, SUB, RD  # noqa: E402
from PIL import Image, ImageDraw, ImageFont    # noqa: E402

OUT = "build/11b5c"
SPR = "assets/sprites"
SURV = "Survival Kit/Models/OBJ format/"
MG = "Minigolf Kit/Models/OBJ format/"
SPACE = "Space Kit/Models/OBJ format/"
PETS = "Cube Pets/Models/OBJ format/"
STONE, STONE_D, WOOD, WOOD_D = "#bdb9c9", "#8f8ba0", "#a8794a", "#7a5535"
RED, WHITE, WATER, SNOW = "#c9534b", "#f3f0e8", "#6cc3e8", "#f4f8fb"


def cone(r0, r1, h, color, x=0.0, z=0.0, y=0.0, seg=8, rot=0):
    return {"cone": [r0, r1, h], "color": color, "pos": [x, y, z], "segments": seg, "rot": rot}


def ball(r, color, x=0.0, z=0.0, y=0.0, seg=8):
    return {"sphere": r, "color": color, "pos": [x, y, z], "segments": seg}


def tilted(b, pitch=0, roll=0, pivot=None):
    b = dict(b)
    b["pitch"], b["roll"] = pitch, roll
    if pivot:
        b["pivot"] = pivot
    return b


C = []     # (id, nameEN, nameSK, parts, signs)


def cand(rid, en, sk, parts, signs=None):
    C.append((rid, en, sk, parts, signs))


# 1 fountain
cand("d-fountain", "Fountain", "Fontána", [part(FAN + "fountain-round-detail", scale=0.46)])

# 2 the sleep cat on a plinth
cand("d-cat-statue", "Sleeping cat statue", "Socha spiacej mačky", [
    cone(0.36, 0.3, 0.05, STONE_D, seg=8), box(0.42, 0.26, 0.42, STONE, y=0.05),
    box(0.5, 0.04, 0.5, STONE_D, y=0.31),
    {**part(PETS + "animal-cat", y=0.35, scale=0.3, rot=45),
     "pose": {"leg-*": {"hidden": True},                       # the tail lies down like the buddy's asleep frame
              "tail": {"rot": [0, 45, -90], "pivot": [0, 0.7, -0.6], "move": [0.0, -0.5, 0.0]}}},
])

# 3 windmill (slim landmark)
cand("d-windmill", "Windmill", "Veterný mlyn", [part(MG + "windmill", scale=0.55, center=True)])

# 4 gazebo / bandstand
cand("d-gazebo", "Gazebo", "Altánok", [
    cone(0.5, 0.5, 0.05, STONE, seg=8),
    *[part(FAN + "pillar-stone", x=sx * 0.3, z=sz * 0.3, y=0.05, scale=0.5) for sx in (-1, 1) for sz in (-1, 1)],
    cone(0.52, 0.0, 0.26, RED, y=0.55, seg=8, rot=22),
    ball(0.045, "#f2c94c", y=0.8),
])

# 5 bench with a street lamp
cand("d-bench-lamp", "Bench and lamp", "Lavička s lampou", [
    part(HOL + "bench", z=0.1, scale=0.55), part(HOL + "lantern", x=0.36, z=-0.1, scale=0.36),
    part(NAT + "flower_yellowA", x=-0.38, z=-0.25), part(NAT + "flower_purpleA", x=-0.3, z=-0.33),
])

# 6 flower bed
_fl = ["flower_redA", "flower_yellowA", "flower_purpleA", "flower_redB", "flower_yellowB", "flower_purpleB",
       "flower_purpleC", "flower_redC", "flower_yellowC"]
cand("d-flower-bed", "Flower bed", "Kvetinový záhon", [
    box(0.74, 0.08, 0.06, WOOD, z=0.31), box(0.74, 0.08, 0.06, WOOD, z=-0.31),
    box(0.06, 0.08, 0.68, WOOD, x=0.34), box(0.06, 0.08, 0.68, WOOD, x=-0.34),
    box(0.64, 0.06, 0.58, "#6b4a35"),
    *[part(NAT + _fl[i], x=-0.2 + 0.2 * (i % 3), z=-0.2 + 0.2 * (i // 3), y=0.06, scale=1.0) for i in range(9)],
])

# 7 well
cand("d-well", "Wishing well", "Studňa prianí", [
    cone(0.27, 0.25, 0.22, STONE), cone(0.2, 0.2, 0.01, "#4aa3d8", y=0.22),
    box(0.04, 0.42, 0.04, WOOD_D, x=-0.22, y=0.22), box(0.04, 0.42, 0.04, WOOD_D, x=0.22, y=0.22),
    box(0.5, 0.03, 0.03, WOOD_D, y=0.62),
    cone(0.36, 0.0, 0.17, RED, y=0.64, seg=4, rot=0),
])

# 8 oak
cand("d-oak", "Old oak", "Starý dub", [
    part(NAT + "tree_oak", scale=0.78), part(NAT + "flower_yellowA", x=0.3, z=0.3),
    part(NAT + "rock_smallA", x=-0.3, z=0.28, scale=0.8),
])

# 9 pine group
cand("d-pines", "Pine grove", "Smrekový hájik", [
    part(NAT + "tree_pineTallA", x=-0.12, z=-0.12, scale=0.75), part(NAT + "tree_pineDefaultA", x=0.25, z=-0.1, scale=0.8),
    part(NAT + "tree_pineSmallA", x=0.02, z=0.28, scale=0.9), part(NAT + "mushroom_redGroup", x=-0.35, z=0.3),
])

# 10 telescope (night theme)
cand("d-telescope", "Telescope", "Ďalekohľad", [
    cone(0.4, 0.4, 0.04, STONE_D, seg=8),
    box(0.03, 0.3, 0.03, "#6d6a80", x=-0.07, z=0.07, y=0.04), box(0.03, 0.3, 0.03, "#6d6a80", x=0.08, z=0.06, y=0.04),
    box(0.03, 0.3, 0.03, "#6d6a80", z=-0.09, y=0.04),
    tilted(box(0.1, 0.1, 0.5, "#3b4a7a", y=0.34, z=0.08, x=0.0), pitch=-28),
    tilted(box(0.12, 0.12, 0.05, "#e3b04b", y=0.34, z=0.08), pitch=-28),
    ball(0.03, "#f2c94c", x=0.28, z=-0.2, y=0.0),
])

# 11 campfire with a tent
cand("d-campfire", "Campfire and tent", "Ohnisko so stanom", [
    part(NAT + "tent_detailedOpen", x=-0.14, z=-0.14, scale=0.82, rot=20), part(NAT + "campfire_stones", x=0.28, z=0.2, scale=1.1),
    part(NAT + "log", x=0.3, z=-0.05, scale=0.9, rot=90), part(NAT + "stump_round", x=0.0, z=0.33, scale=0.9),
    ball(0.05, "#ff9a3c", x=0.28, z=0.2, y=0.05, seg=6),
])

# 12 moored hot-air balloon
cand("d-balloon", "Hot-air balloon", "Teplovzdušný balón", [
    box(0.16, 0.1, 0.16, WOOD, y=0.02),
    *[box(0.012, 0.3, 0.012, "#6d5a45", x=sx * 0.06, z=sz * 0.06, y=0.12) for sx in (-1, 1) for sz in (-1, 1)],
    cone(0.07, 0.2, 0.14, "#e8706a", y=0.4, seg=8), ball(0.26, "#e8706a", y=0.52),
    ball(0.045, "#f6f0e0", x=0.0, z=0.22, y=0.64, seg=6),
    box(0.04, 0.03, 0.04, "#7a5535", x=0.34, z=0.3, y=0.0),
])

# 13 lighthouse
cand("d-lighthouse", "Lighthouse", "Maják", [
    part(NAT + "rock_smallA", x=-0.28, z=0.25, scale=1.0), part(NAT + "rock_smallC", x=0.3, z=0.22, scale=0.9),
    cone(0.24, 0.18, 0.3, WHITE), cone(0.18, 0.15, 0.22, RED, y=0.3), cone(0.15, 0.13, 0.2, WHITE, y=0.52),
    cone(0.2, 0.2, 0.03, "#5a5670", y=0.72), ball(0.07, "#ffe27a", y=0.75, seg=6), cone(0.14, 0.0, 0.14, RED, y=0.82),
])

# 14 market stall
cand("d-stall", "Market stall", "Trhový stánok", [
    part(FAN + "stall-red", scale=0.72, center=True), part(SURV + "barrel", x=0.36, z=0.3, scale=0.8),
    part(SURV + "box", x=-0.34, z=0.3, scale=0.9),
])

# 15 pond with a duckling
cand("d-pond", "Pond", "Jazierko", [
    cone(0.46, 0.46, 0.035, "#8fcf6f", seg=10, rot=10), cone(0.4, 0.4, 0.045, WATER, seg=10, rot=10),
    part(NAT + "lily_large", x=-0.08, z=0.0, y=0.045, scale=0.9), part(NAT + "lily_small", x=0.18, z=-0.12, y=0.045),
    {**part(PETS + "animal-chick", x=0.1, z=0.14, y=0.04, scale=0.17, rot=30), "pose": {"leg-*": {"hidden": True}}},
    part(NAT + "rock_smallB", x=-0.38, z=0.28, scale=0.9), part(NAT + "rock_smallA", x=0.38, z=-0.28),
])

# 16 flag pole
cand("d-flagpole", "Flag pole", "Vlajkový stĺp", [
    cone(0.18, 0.15, 0.05, STONE_D), box(0.025, 0.92, 0.025, "#d9d6e2", y=0.05),
    ball(0.035, "#f2c94c", y=0.97, seg=6),
    box(0.34, 0.2, 0.012, "#5b7fd8", x=0.18, y=0.7), box(0.34, 0.07, 0.014, "#f3f0e8", x=0.18, y=0.77),
])

# 17 Christmas tree
cand("d-xmas-tree", "Christmas tree", "Vianočný stromček", [
    part(HOL + "tree-decorated", scale=0.5), part(HOL + "present-a-cube", x=0.3, z=0.22, scale=0.5),
    part(HOL + "present-b-round", x=-0.28, z=0.28, scale=0.5),
])

# 18 snowman
cand("d-snowman", "Snowman", "Snehuliak", [
    cone(0.46, 0.42, 0.035, SNOW, seg=10), part(HOL + "snowman", y=0.03, scale=0.62),
])

# 19 bus stop with a mailbox
cand("d-bus-stop", "Bus stop", "Autobusová zastávka", [
    box(0.74, 0.03, 0.4, "#9a96ab", z=0.02),
    box(0.04, 0.46, 0.04, "#6d6a80", x=-0.34, z=0.17, y=0.03), box(0.04, 0.46, 0.04, "#6d6a80", x=0.34, z=0.17, y=0.03),
    box(0.04, 0.46, 0.04, "#6d6a80", x=-0.34, z=-0.13, y=0.03), box(0.04, 0.46, 0.04, "#6d6a80", x=0.34, z=-0.13, y=0.03),
    box(0.8, 0.04, 0.46, "#4a90c9", y=0.49, z=0.02), box(0.7, 0.34, 0.02, "#b5dcee", z=-0.13, y=0.13),
    part(HOL + "bench-short", z=-0.02, y=0.03, scale=0.4),
    box(0.03, 0.2, 0.03, "#6d6a80", x=0.44, z=0.35), box(0.1, 0.07, 0.07, "#d8504a", x=0.44, z=0.35, y=0.2),
])

# 20 swing
cand("d-swing", "Playground swing", "Detská hojdačka", [
    *[box(0.035, 0.52, 0.035, "#d9703b", x=sx * 0.3, z=sz * 0.14) for sx in (-1, 1) for sz in (-1, 1)],
    box(0.7, 0.04, 0.04, "#d9703b", y=0.5),
    box(0.012, 0.3, 0.012, "#555", x=-0.1, y=0.22), box(0.012, 0.3, 0.012, "#555", x=0.1, y=0.22),
    box(0.26, 0.025, 0.1, "#5b7fd8", y=0.2), cone(0.4, 0.4, 0.015, "#e8d9a8", seg=10, z=0.05),
])

# 21 little bridge over a stream
cand("d-bridge", "Stone bridge", "Kamenný mostík", [
    box(0.42, 0.03, 1.0, WATER), box(0.1, 0.03, 1.0, "#d9c79a", x=-0.26), box(0.1, 0.03, 1.0, "#d9c79a", x=0.26),
    part(NAT + "bridge_stoneRound", scale=0.92, y=0.02, center=True), part(NAT + "flower_redA", x=0.32, z=0.34),
])

# 22 clock tower
cand("d-clock-tower", "Clock tower", "Hodinová veža", [
    box(0.46, 0.08, 0.46, STONE_D), box(0.34, 0.62, 0.34, "#e2d3b2", y=0.08),
    box(0.2, 0.2, 0.02, WHITE, z=0.18, y=0.45), box(0.02, 0.07, 0.025, "#333", z=0.19, y=0.52),
    box(0.06, 0.02, 0.025, "#333", x=0.025, z=0.19, y=0.52),
    box(0.4, 0.04, 0.4, STONE_D, y=0.7), cone(0.3, 0.0, 0.26, RED, y=0.74, seg=4, rot=45),
])

# 23 hedge maze piece
cand("d-hedge", "Hedge maze", "Živý plot", [
    part(FAN + "hedge", x=-0.38, z=0, scale=0.9, center=True), part(FAN + "hedge", x=0.38, z=0, scale=0.9, center=True),
    part(FAN + "hedge", x=0, z=-0.38, rot=90, scale=0.9, center=True),
    part(FAN + "hedge", x=-0.28, z=0.38, rot=90, scale=0.4, center=True),
    part(FAN + "hedge", x=0.28, z=0.38, rot=90, scale=0.4, center=True),
    ball(0.1, "#4f9a4d", y=0.0),
    part(NAT + "flower_redA", x=0.0, z=0.3),
])

# 24 welcome sign
cand("d-sign", "SleepHole sign", "Tabuľa SleepHole", [
    box(0.05, 0.4, 0.05, WOOD_D, x=-0.36, y=0), box(0.05, 0.4, 0.05, WOOD_D, x=0.36, y=0),
    box(0.86, 0.34, 0.05, "#2b3563", y=0.28),
    part(NAT + "flower_yellowB", x=-0.38, z=0.15), part(NAT + "flower_purpleA", x=0.38, z=0.15),
    
], signs=[{"text": "SleepHole", "pos": [0, 0.45, 0.03], "width": 0.8, "color": "#2b3563",
           "textColor": "#f6e7a6"}])

# 25 night crystals
cand("d-crystals", "Moon crystals", "Mesačné kryštály", [
    part(SPACE + "rock_crystalsLargeA", scale=0.45, center=True), part(SPACE + "rock_crystals", x=0.3, z=0.25, scale=0.5),
    part(NAT + "rock_smallA", x=-0.32, z=0.28, scale=0.8),
])

# 26 lantern path
cand("d-lantern-walk", "Lantern walk", "Lampiónová cestička", [
    part(NAT + "path_stoneCircle", scale=0.9), part(HOL + "lantern", x=-0.34, z=-0.2, scale=0.34),
    part(HOL + "lantern", x=0.34, z=0.2, scale=0.34), part(NAT + "flower_purpleB", x=0.3, z=-0.3),
])


def recipes():
    out = []
    for rid, en, sk, parts, signs in C:
        r = {"id": rid, "level": 0, "kind": "decoration", "nameSK": sk, "nameEN": en, "footprint": [1, 1], "parts": parts}
        if signs:
            r["signs"] = signs
        out.append(r)
    return out


# ───────────────────────── previews ─────────────────────────
HALF_W, HALF_H = 0.70710678 * 181.0, 0.35355339 * 181.0


def font(size):
    for p in ("/System/Library/Fonts/Helvetica.ttc", "/System/Library/Fonts/SFNS.ttf", "/Library/Fonts/Arial.ttf"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()


def load_cat(root):
    return {e["id"]: e for e in json.load(open(os.path.join(root, "catalog.json")))}


def paste(img, root, e, sx, sy, scale=1.0):
    """Paste sprite `e` so that its anchor (the world origin on the ground) lands on screen point (sx, sy)."""
    sp = Image.open(os.path.join(root, e["file"])).convert("RGBA")
    if scale != 1.0:
        sp = sp.resize((max(1, round(sp.width * scale)), max(1, round(sp.height * scale))), Image.Resampling.LANCZOS)
    img.alpha_composite(sp, (round(sx - e["anchor"][0] * sp.width), round(sy - (1 - e["anchor"][1]) * sp.height)))


def contact_sheet(rend, ids, cat, grass):
    cols, cw, ch = 3, 760, 400
    rows = (len(ids) + cols - 1) // cols
    img = Image.new("RGBA", (cols * cw, rows * ch), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    f1, f2 = font(24), font(19)
    for i, rid in enumerate(ids):
        x0, y0 = (i % cols) * cw, (i // cols) * ch
        for k, bg in enumerate(((236, 242, 248, 255), (24, 30, 58, 255))):
            cell = Image.new("RGBA", (cw // 2, ch), bg)
            paste(cell, SPR, grass, cell.width / 2, ch * 0.7)
            paste(cell, rend, cat[rid], cell.width / 2, ch * 0.7)
            img.alpha_composite(cell, (x0 + k * cw // 2, y0))
        e = cat[rid]
        d.text((x0 + 10, y0 + 6), f"{i + 1:02d}  {rid}", fill=(20, 20, 30), font=f1)
        d.text((x0 + 10, y0 + 36), f"{e['nameEN']} / {e['nameSK']}", fill=(60, 60, 80), font=f2)
        d.rectangle([x0, y0, x0 + cw - 1, y0 + ch - 1], outline=(150, 150, 160))
    img.convert("RGB").save(f"{OUT}/candidates.png")


def in_town(rend, cat, scat, picks):
    """A small demo town (roads + L1/L2 buildings from assets/sprites) with a grass margin in front; the picks stand on
    the margin cells (largest col + row), one empty cell between two decorations."""
    import random
    rnd = random.Random(7)
    N, M = 10, 13
    road = {(i, 4) for i in range(N)} | {(4, i) for i in range(N)} | {(i, 8) for i in range(1, 8)}
    items = []

    def put(e, c, r, base):
        fw, fd = e["footprint"]
        items.append(((c + fw - 1) + (r + fd - 1), 0 if e["kind"] in ("terrain", "road") else 1, e, c + (fw - 1) / 2,
                      r + (fd - 1) / 2, base))

    def road_id(c, r):
        conn = "".join(dd for dd, (dc, dr) in {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}.items()
                       if (c + dc, r + dr) in road)
        for e in scat.values():
            if e["kind"] == "road" and e.get("connects") == conn and e["level"] == 0:
                return e
        return scat["t-road-crossroad-nesw"]

    used = set(road)
    houses = [e for e in scat.values() if e["level"] == 1 and e["kind"] == "building" and e["footprint"] == [1, 1]]
    parks = [e for e in scat.values() if e["kind"] == "park" and e["footprint"] == [2, 2]]
    for c in range(M):
        for r in range(M):
            if (c, r) in road:
                put(road_id(c, r), c, r, None)
            else:
                put(scat[rnd.choice(["t-grass-a", "t-grass-b"])], c, r, None)
    for c, r in ((0, 0), (5, 0), (0, 5), (5, 5), (6, 2)):
        cells = [(c + a, r + b) for a in (0, 1) for b in (0, 1)]
        if all(x not in used and x[0] < N and x[1] < N for x in cells) and parks:
            used.update(cells)
            put(parks[len(used) % len(parks)], c, r, None)
    for c in range(N):
        for r in range(N):
            if (c, r) not in used:
                used.add((c, r))
                put(rnd.choice(houses), c, r, None)
    slots = [(c, 10) for c in (0, 2, 4, 6, 8)] + [(10, r) for r in (0, 2, 4, 6, 8)] + [(10, 10), (12, 10)]
    for rid, (c, r) in zip(picks, slots):
        put(cat[rid], c, r, rend)
    items.sort(key=lambda t: (t[0], t[1]))
    pos = [((x - z) * HALF_W, (x + z) * HALF_H) for _, _, _, x, z, _ in items]
    xs, ys = [], []
    for (_, _, e, _, _, _), (sx, sy) in zip(items, pos):
        w, h = e["size"]
        xs += [sx - e["anchor"][0] * w, sx + (1 - e["anchor"][0]) * w]
        ys += [sy - (1 - e["anchor"][1]) * h, sy + e["anchor"][1] * h]
    ox, oy = -min(xs) + 20, -min(ys) + 20
    img = Image.new("RGBA", (int(max(xs) - min(xs) + 40), int(max(ys) - min(ys) + 40)), (182, 214, 232, 255))
    for (_, _, e, _, _, base), (sx, sy) in zip(items, pos):
        paste(img, base or SPR, e, ox + sx, oy + sy)
    # crop to the front part of the town (decorations + two rows of buildings behind them)
    left, top = 0, int(img.height * 0.28)
    img = img.crop((left, top, img.width, img.height))
    img.convert("RGB").save(f"{OUT}/in-town.png")


def real_size(rend, cat, grass, picks):
    tile = 130.0
    k = tile / grass["size"][0] * 1.0          # the grass sprite is the 1x1 diamond (+margin): scale to ~130 px
    k = tile / 256.0
    img = Image.new("RGBA", (len(picks) * 190 + 20, 260), (182, 214, 232, 255))
    for i, rid in enumerate(picks):
        cx, cy = 105 + i * 190, 190
        paste(img, SPR, grass, cx, cy, k)
        paste(img, rend, cat[rid], cx, cy, k)
    img.convert("RGB").save(f"{OUT}/real-size.png")


TOP12 = ["d-fountain", "d-cat-statue", "d-windmill", "d-gazebo", "d-bench-lamp", "d-flower-bed", "d-well", "d-sign",
         "d-clock-tower", "d-campfire", "d-pines", "d-stall"]
_OLD = ["d-fountain", "d-cat-statue", "d-windmill", "d-gazebo", "d-bench-lamp", "d-flower-bed", "d-well", "d-oak",
         "d-telescope", "d-campfire", "d-lighthouse", "d-pond"]
REAL6 = ["d-cat-statue", "d-sign", "d-campfire", "d-stall", "d-flower-bed", "d-bench-lamp"]
_OLD6 = ["d-cat-statue", "d-bench-lamp", "d-flower-bed", "d-telescope", "d-well", "d-pond"]


def install():
    """Copy the rendered PNGs into assets/sprites/L0 and insert their catalog entries as TEXT (Apple's JSON style of the
    existing file stays byte-identical). Entries are kept sorted by `file`, like the whole catalog."""
    import shutil
    names = {r["id"]: (r["nameEN"], r["nameSK"]) for r in recipes()}
    rend = json.load(open(f"{OUT}/renders/catalog.json"))
    have = {e["id"] for e in json.load(open(f"{SPR}/catalog.json"))}
    blocks = []
    for e in sorted((e for e in rend if e["id"] in TOP12 and e["id"] not in have), key=lambda e: e["file"]):
        e["nameEN"], e["nameSK"] = names[e["id"]]
        shutil.copyfile(f"{OUT}/renders/{e['file']}", f"{SPR}/{e['file']}")
        text = json.dumps(e, indent=2, sort_keys=True, ensure_ascii=False, separators=(",", " : ")).replace("/", "\\/")
        # json.dumps puts lists on several lines already; add the 2-space array indent
        blocks.append("\n".join("  " + ln for ln in text.split("\n")))
    if not blocks:
        print("nothing to install")
        return
    path = f"{SPR}/catalog.json"
    old = open(path, encoding="utf-8").read()
    assert old.startswith("[\n  {")
    new = "[\n" + ",\n".join(blocks) + ",\n" + old[2:]       # all new files (L0/d-…) sort before L0/o-crane-00
    open(path, "w", encoding="utf-8").write(new)
    print("installed", len(blocks), "sprites")


def main():
    args = sys.argv[1:]
    if "--install" in args:
        return install()
    os.makedirs(OUT + "/renders", exist_ok=True)
    rc = [r for r in recipes() if r["id"] in TOP12]
    rc.sort(key=lambda r: TOP12.index(r["id"]))
    json.dump(rc, open(f"{OUT}/recipes.json", "w"), indent=1, ensure_ascii=False)
    print(f"{OUT}/recipes.json", len(rc), "candidates")
    only = args[args.index("--only") + 1] if "--only" in args else None
    if "--no-render" not in args:
        cmd = ["swift", "tools/render/render_sprites.swift", f"{OUT}/recipes.json", f"{OUT}/renders"] + ([only] if only else [])
        print(" ".join(cmd))
        subprocess.run(cmd, check=True)
    if only:
        return
    rend = f"{OUT}/renders"
    cat, scat = load_cat(rend), load_cat(SPR)
    ids = [r["id"] for r in rc]
    grass = scat["t-grass-a"]
    contact_sheet(rend, ids, cat, grass)
    in_town(rend, cat, scat, [p for p in TOP12 if p in cat])
    real_size(rend, cat, grass, [p for p in REAL6 if p in cat])
    print("previews written to", OUT)


if __name__ == "__main__":
    main()
