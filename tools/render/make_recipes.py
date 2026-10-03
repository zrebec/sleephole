#!/usr/bin/env python3
"""Generates tools/render/recipes.json – the list of every sprite SleepHole ships.

Run from the repo root:
    python3 tools/render/make_recipes.py
    swift tools/render/render_sprites.swift tools/render/recipes.json assets/sprites
    python3 tools/render/contact_sheet.py assets/sprites

The sleep buddy (cat on a camp bed, 4 frames) has its own recipe file – see `buddy_recipes()` below.

World conventions (must match render_sprites.swift and the app):
  * 1 world unit = 1 grid tile, y is up, the footprint is centred on the origin
  * a building's front faces +z (screen lower-left); +x is the screen lower-right side
  * level 0 = support sprites (terrain, roads, overlays, vehicles); 1…4 = unlock levels
"""
import json
import os

ROOT = "assets/Kenney Game Assets All-in-1 3/3D assets/"
COM = "City Kit - Commercial/Models/OBJ format/"
SUB = "City Kit - Suburban/Models/OBJ format/"
IND = "City Kit - Industrial/Models/OBJ format/"
RD = "City Kit - Roads/Models/OBJ format/"
CAR = "Car Kit/Models/OBJ format/"
NAT = "Nature Kit/Models/OBJ format/"
FAN = "Fantasy Town Kit/Models/OBJ format/"
HOL = "Holiday Kit/Models/OBJ format/"
MOD = "Modular Buildings/Models/OBJ format/"
BK = "Building Kit/Models/OBJ format/"
SUB_VAR = "City Kit - Suburban/Models/Textures/variation-%s.png"
COM_VAR = "City Kit - Commercial/Models/Textures/variation-%s.png"

GRASS = "#8fcf6f"
LAWN = "#7cc26a"
PLAZA = "#d8d5e3"
DIRT = "#b98a5e"
CAR_SCALE = 0.15

_bounds = {}


def bounds(src):
    """(minx, maxx, miny, maxy, minz, maxz) of an OBJ, cached."""
    if src not in _bounds:
        xs, ys, zs = [], [], []
        with open(ROOT + src + ".obj") as f:
            for line in f:
                if line.startswith("v "):
                    _, x, y, z = line.split()[:4]
                    xs.append(float(x)); ys.append(float(y)); zs.append(float(z))
        _bounds[src] = (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))
    return _bounds[src]


def part(src, x=0.0, z=0.0, y=0.0, rot=0, scale=1.0, texture=None, center=False):
    """A model part. center=True shifts the model so its (x,z) bbox centre lands on (x,z)."""
    if center:
        b = bounds(src)
        cx, cz = (b[0] + b[1]) / 2 * scale, (b[4] + b[5]) / 2 * scale
        if rot % 360 == 90:
            cx, cz = cz, -cx
        elif rot % 360 == 180:
            cx, cz = -cx, -cz
        elif rot % 360 == 270:
            cx, cz = -cz, cx
        x, z = x - cx, z - cz
    p = {"src": src, "pos": [round(x, 3), round(y, 3), round(z, 3)], "rot": rot, "scale": round(scale, 4)}
    if texture:
        p["texture"] = texture
    return p


def box(w, h, d, color, x=0.0, z=0.0, y=0.0):
    return {"box": [w, h, d], "color": color, "pos": [x, y, z]}


def plate(fp, color, h=0.03):
    """Ground plate covering the footprint (slightly inset so tiles read as separate)."""
    return box(fp * 0.98, h, fp * 0.98, color)


def fit_scale(src, fp, fill=0.94, rot=0):
    b = bounds(src)
    w, d = b[1] - b[0], b[5] - b[4]
    return min(1.0, fp * fill / max(w, d))


recipes = []

# English names (docs/IMPLEMENTATION_I18N.md §5.12). Every Slovak name needs one – add() checks it.
NAME_EN = {
    "Rodinný dom": "Family house", "Bytový dom": "Apartment block", "Veľký bytový dom": "Large apartment block",
    "Malý park": "Small park", "Park s fontánou": "Fountain park", "Záhrada so sochou": "Statue garden",
    "Park s jazierkom": "Pond park", "Osvetlená ulica": "Lit street", "Knižnica": "Library",
    "Mestská knižnica": "City library", "Múzeum": "Museum", "Múzeum umenia": "Art museum", "Radnica": "Town hall",
    "Škola": "School", "Hasičská stanica": "Fire station", "Polícia": "Police station", "Nemocnica": "Hospital",
    "Mrakodrap": "Skyscraper", "Výšková budova": "High-rise", "Auto": "Car", "Cesta": "Road", "Tráva": "Grass",
    "Dlažba": "Paving", "Stavebný pozemok": "Building plot", "Lešenie": "Scaffolding", "Stavenisko": "Building site",
    "Ruina": "Ruins", "Zarastená ruina": "Overgrown ruins", "Žeriav": "Crane",
}


def add(rid, level, kind, name, fp, parts, signs=None, shadow=True, connects=None):
    assert all(r["id"] != rid for r in recipes), rid
    r = {"id": rid, "level": level, "kind": kind, "nameSK": name, "nameEN": NAME_EN[name], "footprint": [fp, fp],
         "parts": parts}
    if connects:
        r["connects"] = "".join(d for d in "NESW" if d in connects)
    if signs:
        r["signs"] = signs
    if not shadow:
        r["shadow"] = False
    recipes.append(r)


def sign(text, color, height=0.72, text_color="#ffffff"):
    """`text` = {"sk": …, "en": …}: the Slovak sign is the normal sprite, the English one is rendered as
    `<id>.en.png` (catalog `fileEN`) with the same bounds/anchor."""
    return {"text": text["sk"], "textEN": text["en"], "color": color, "height": height, "textColor": text_color}


# ───────────────────────── LEVEL 1 – ordinary buildings ─────────────────────────
# 21 suburban houses × 3 colour variants, all 1×1 (scaled to fit the tile).
for c in "abcdefghijklmnopqrstu":
    src = SUB + "building-type-" + c
    s = fit_scale(src, 1)
    for v, tex in (("0", None), ("a", SUB_VAR % "a"), ("b", SUB_VAR % "b")):
        add(f"l1-house-{c}-{v}", 1, "building", "Rodinný dom", 1, [part(src, scale=s, texture=tex, center=True)])

# small apartment / shop blocks (1×1) – base + one colour variant
for c in "abcdfgh":
    src = COM + "building-" + c
    s = fit_scale(src, 1)
    for v, tex in (("0", None), ("a", COM_VAR % "a")):
        add(f"l1-block-{c}-{v}", 1, "building", "Bytový dom", 1, [part(src, scale=s, texture=tex, center=True)])

# wider blocks on 2×2 lots with a little greenery
for c in "eijkln":
    src = COM + "building-" + c
    s = fit_scale(src, 2, 0.8)
    add(f"l1-bigblock-{c}", 1, "building", "Veľký bytový dom", 2, [
        part(src, z=-0.15, scale=s, center=True),
        part(SUB + "tree-large", x=0.78, z=0.72),
        part(SUB + "planter", x=-0.6, z=0.78),
    ])

# ───────────────────────── LEVEL 2 – parks, lit streets, museums, libraries ─────────────────────────
add("l2-park-small", 2, "park", "Malý park", 1, [
    plate(1, LAWN),
    part(SUB + "tree-large", x=-0.25, z=-0.25),
    part(SUB + "tree-small", x=0.3, z=-0.3),
    part(HOL + "bench", x=0.05, z=0.28, scale=0.3),
    part(NAT + "flower_redA", x=0.35, z=0.3), part(NAT + "flower_yellowA", x=-0.35, z=0.25),
    part(NAT + "flower_purpleA", x=0.38, z=0.05),
])
add("l2-park-fountain", 2, "park", "Park s fontánou", 2, [
    plate(2, LAWN),
    part(FAN + "fountain-round-detail", scale=0.5),
    part(SUB + "tree-large", x=-0.72, z=-0.72), part(SUB + "tree-large", x=0.72, z=-0.72),
    part(SUB + "tree-large", x=-0.72, z=0.72), part(SUB + "tree-small", x=0.75, z=0.75),
    part(HOL + "bench", x=0, z=0.72, scale=0.3), part(HOL + "bench", x=0.72, z=0, rot=90, scale=0.3),
    part(HOL + "lantern", x=-0.45, z=0.45, scale=0.33), part(HOL + "lantern", x=0.45, z=-0.45, scale=0.33),
])
add("l2-park-garden", 2, "park", "Záhrada so sochou", 2, [
    plate(2, LAWN),
    part(NAT + "statue_obelisk", scale=0.9),
    part(FAN + "hedge", x=-0.55, z=0, scale=0.9), part(FAN + "hedge", x=0.55, z=0, rot=180, scale=0.9),
    part(SUB + "tree-large", x=-0.75, z=-0.75), part(SUB + "tree-large", x=0.75, z=-0.75),
    part(NAT + "flower_redA", x=-0.3, z=0.6), part(NAT + "flower_yellowB", x=0.3, z=0.65),
    part(NAT + "flower_purpleB", x=0.6, z=0.35), part(NAT + "flower_redB", x=-0.6, z=0.4),
    part(HOL + "bench", x=0, z=0.75, scale=0.3),
])
add("l2-park-pond", 2, "park", "Park s jazierkom", 2, [
    plate(2, LAWN),
    box(0.9, 0.035, 0.7, "#6cc3e8", x=0.1, z=0.1),
    part(NAT + "lily_large", x=0.05, z=0.05, y=0.035), part(NAT + "lily_small", x=0.3, z=0.25, y=0.035),
    part(NAT + "rock_smallA", x=-0.4, z=0.4), part(NAT + "rock_smallC", x=0.6, z=-0.2),
    part(SUB + "tree-large", x=-0.72, z=-0.7), part(SUB + "tree-small", x=-0.4, z=-0.78),
    part(SUB + "tree-large", x=0.72, z=-0.72),
    part(HOL + "bench", x=-0.6, z=0.1, rot=90, scale=0.3),
    part(NAT + "flower_yellowA", x=0.7, z=0.7), part(NAT + "flower_redA", x=-0.2, z=0.75),
])

# lit streets: a straight road with two street lamps (the app makes them glow at night).
# light-square's arm points to -z at rot 0.
add("l2-road-lit-we", 2, "road-lit", "Osvetlená ulica", 1, [
    part(RD + "road-straight", rot=0),
    part(RD + "light-square", x=0.25, z=0.45, rot=0),
    part(RD + "light-square", x=-0.25, z=-0.45, rot=180),
], connects="EW")
add("l2-road-lit-ns", 2, "road-lit", "Osvetlená ulica", 1, [
    part(RD + "road-straight", rot=90),
    part(RD + "light-square", x=0.45, z=-0.25, rot=90),
    part(RD + "light-square", x=-0.45, z=0.25, rot=270),
], connects="NS")

add("l2-museum-a", 2, "building", "Múzeum", 2, [
    part(MOD + "building-sample-house-c", z=-0.25, scale=0.75, center=True),
    box(1.5, 0.05, 0.32, PLAZA, z=0.72),
    *[part(BK + "column", x=x, z=0.74, y=0.05, scale=0.24) for x in (-0.6, -0.2, 0.2, 0.6)],
    part(NAT + "statue_column", x=0.85, z=0.85, scale=0.5),
], signs=[sign({"sk": "MÚZEUM", "en": "MUSEUM"}, "#7b4a2a", height=0.4)])
add("l2-museum-b", 2, "building", "Múzeum umenia", 2, [
    part(COM + "building-e", z=-0.3, scale=1.0, texture=COM_VAR % "b", center=True),
    *[part(BK + "column-wide", x=x, z=0.35, scale=0.3) for x in (-0.55, 0, 0.55)],
    part(NAT + "statue_obelisk", x=-0.7, z=0.75, scale=0.7),
    part(SUB + "tree-small", x=0.75, z=0.75),
], signs=[sign({"sk": "GALÉRIA", "en": "GALLERY"}, "#6b3f8f", height=0.8)])
add("l2-library-a", 2, "building", "Knižnica", 2, [
    part(MOD + "building-sample-house-a", x=-0.2, z=-0.1, scale=0.85, center=True),
    part(HOL + "bench", x=0.35, z=0.7, scale=0.3),
    part(SUB + "tree-large", x=-0.75, z=0.7), part(SUB + "planter", x=0.75, z=0.35),
], signs=[sign({"sk": "KNIŽNICA", "en": "LIBRARY"}, "#2f7a55", height=0.5)])
add("l2-library-b", 2, "building", "Mestská knižnica", 2, [
    part(COM + "building-k", z=-0.3, scale=0.9, texture=COM_VAR % "a", center=True),
    part(HOL + "bench", x=-0.3, z=0.72, scale=0.3),
    part(SUB + "tree-large", x=0.75, z=0.72), part(SUB + "tree-small", x=-0.8, z=0.75),
], signs=[sign({"sk": "KNIŽNICA", "en": "LIBRARY"}, "#2f7a55", height=0.55)])

# ───────────────────────── LEVEL 3 – civic buildings ─────────────────────────
add("l3-townhall", 3, "building", "Radnica", 2, [
    plate(2, PLAZA),
    part(MOD + "building-sample-tower-c", z=-0.35, scale=0.75, center=True),
    part(MOD + "building-sample-house-b", x=-0.55, z=-0.35, scale=0.7, center=True),
    part(MOD + "building-sample-house-b", x=0.55, z=-0.35, scale=0.7, center=True),
    part(FAN + "fountain-round", x=0, z=0.62, scale=0.3),
    box(0.03, 1.1, 0.03, "#9a9aa8", x=0.75, z=0.75),
    # town flag: gold with a green stripe (deliberately not a national flag)
    box(0.02, 0.2, 0.32, "#f2c14e", x=0.75, z=0.59, y=0.82),
    box(0.024, 0.06, 0.32, "#3a9a5b", x=0.75, z=0.59, y=0.89),
    box(0.03, 0.2, 0.03, "#8a6a3a", x=-0.62, z=0.78), box(0.03, 0.2, 0.03, "#8a6a3a", x=-0.08, z=0.78),
], signs=[{**sign({"sk": "RADNICA", "en": "TOWN HALL"}, "#b8862b"), "pos": [-0.35, 0.24, 0.8]}])
add("l3-school", 3, "building", "Škola", 2, [
    part(COM + "building-k", z=-0.35, scale=0.9, texture=COM_VAR % "b", center=True),
    box(0.5, 0.05, 0.4, "#e8d28a", x=0.55, z=0.55),
    part(SUB + "tree-large", x=-0.75, z=0.65), part(SUB + "tree-small", x=-0.45, z=0.8),
    part(SUB + "tree-small", x=0.8, z=0.3),
], signs=[sign({"sk": "ŠKOLA", "en": "SCHOOL"}, "#e07b24", height=0.6)])
add("l3-firestation", 3, "building", "Hasičská stanica", 2, [
    plate(2, PLAZA),
    part(IND + "building-g", z=-0.3, scale=0.95, center=True),
    part(CAR + "firetruck", x=0.45, z=0.55, rot=0, scale=CAR_SCALE),
], signs=[sign({"sk": "HASIČI", "en": "FIRE STATION"}, "#c8342b", height=0.8)])
add("l3-police", 3, "building", "Polícia", 2, [
    plate(2, PLAZA),
    part(COM + "building-c", x=-0.2, z=-0.3, scale=1.0, center=True),
    part(COM + "building-a", x=0.6, z=-0.45, scale=0.8, center=True),
    part(CAR + "police", x=0.45, z=0.6, rot=90, scale=CAR_SCALE),
], signs=[sign({"sk": "POLÍCIA", "en": "POLICE"}, "#1f4fa3", height=0.7)])
add("l3-hospital", 3, "building", "Nemocnica", 2, [
    plate(2, PLAZA),
    part(COM + "building-j", z=-0.3, scale=0.85, center=True),
    part(CAR + "ambulance", x=0.55, z=0.65, rot=90, scale=CAR_SCALE),
], signs=[sign({"sk": "NEMOCNICA", "en": "HOSPITAL"}, "#ffffff", height=0.82, text_color="#d8342b")])

# ───────────────────────── LEVEL 4 – skyscrapers ─────────────────────────
for c in "abcde":
    src = COM + "building-skyscraper-" + c
    for v, tex in (("0", None), ("a", COM_VAR % "a")):
        add(f"l4-sky-{c}-{v}", 4, "building", "Mrakodrap", 2, [
            plate(2, PLAZA),
            part(src, z=-0.1, x=-0.1, scale=1.0, texture=tex, center=True),
            part(SUB + "tree-large", x=0.75, z=0.75), part(SUB + "planter", x=-0.7, z=0.8),
        ])
add("l4-tower-m", 4, "building", "Výšková budova", 2, [
    plate(2, PLAZA),
    part(COM + "building-m", z=-0.1, x=-0.1, center=True),
    part(SUB + "tree-large", x=0.75, z=0.75),
])

# ───────────────────────── LEVEL 0 – terrain, roads, overlays, vehicles ─────────────────────────
add("t-grass-a", 0, "terrain", "Tráva", 1, [box(1, 0.04, 1, GRASS)], shadow=False)
add("t-grass-b", 0, "terrain", "Tráva", 1, [box(1, 0.04, 1, "#86c768")], shadow=False)
add("t-plaza", 0, "terrain", "Dlažba", 1, [box(1, 0.04, 1, PLAZA)], shadow=False)
add("t-lot", 0, "terrain", "Stavebný pozemok", 1, [box(1, 0.04, 1, DIRT)], shadow=False)
# Road pieces, named by the edges they connect (grid: E = +x = screen down-right,
# S = +z = screen down-left, W = -x, N = -z). Verified visually with a labelled debug sheet.
# Rotation by +90° maps E→N, S→E, W→S, N→W.
ROADS = [  # (kenney model, rot, connects)
    ("straight", 0, "EW"), ("straight", 90, "NS"),
    ("crossing", 0, "EW"), ("crossing", 90, "NS"),
    ("crossroad", 0, "NESW"),
    ("intersection", 0, "ESW"), ("intersection", 90, "NES"),
    ("intersection", 180, "NEW"), ("intersection", 270, "NSW"),
    ("bend", 0, "SW"), ("bend", 90, "ES"), ("bend", 180, "NE"), ("bend", 270, "NW"),
    ("end", 0, "E"), ("end", 90, "N"), ("end", 180, "W"), ("end", 270, "S"),
]
for model, rot, conn in ROADS:
    rid = f"t-road-{model}-{conn.lower()}"
    add(rid, 0, "road", "Cesta", 1, [part(RD + "road-" + model, rot=rot)], shadow=False, connects=conn)


def scaffold(fp, h):
    """Wooden scaffolding frame drawn over a growing building."""
    e = fp * 0.47
    parts = []
    for x in (-e, e):
        for z in (-e, e):
            parts.append(box(0.035, h, 0.035, "#c8914f", x=x, z=z))
    y = 0.3
    while y < h:
        parts += [box(fp * 0.94, 0.03, 0.04, "#d9a15e", z=e, y=y), box(0.04, 0.03, fp * 0.94, "#d9a15e", x=e, y=y),
                  box(fp * 0.94, 0.03, 0.04, "#d9a15e", z=-e, y=y), box(0.04, 0.03, fp * 0.94, "#d9a15e", x=-e, y=y)]
        y += 0.32
    return parts


add("o-scaffold-1", 0, "overlay", "Lešenie", 1, scaffold(1, 1.25), shadow=False)
add("o-scaffold-2", 0, "overlay", "Lešenie", 2, scaffold(2, 1.9), shadow=False)
add("o-site-1", 0, "overlay", "Stavenisko", 1, [
    plate(1, DIRT),
    part(RD + "construction-cone", x=0.4, z=0.4), part(RD + "construction-cone", x=-0.4, z=0.42),
    part(RD + "construction-barrier", x=0, z=0.44),
    part(RD + "construction-light", x=0.42, z=-0.4),
])
add("o-site-2", 0, "overlay", "Stavenisko", 2, [
    plate(2, DIRT),
    part(RD + "construction-cone", x=0.9, z=0.9), part(RD + "construction-cone", x=-0.9, z=0.92),
    part(RD + "construction-barrier", x=-0.3, z=0.92), part(RD + "construction-barrier", x=0.3, z=0.92),
    part(RD + "construction-light", x=0.92, z=-0.9), part(RD + "construction-light", x=-0.92, z=-0.9),
])


def ruin(fp, flowers):
    e = fp * 0.35
    parts = [plate(fp, "#a99a86"),
             box(fp * 0.7, 0.22, 0.08, "#b7b3c4", x=-0.05 * fp, z=-e),
             box(0.08, 0.34, fp * 0.55, "#a9a5b8", x=-e, z=-0.1 * fp),
             box(0.18, 0.1, 0.14, "#9d98ab", x=0.1 * fp, z=0.1 * fp),
             box(0.12, 0.07, 0.1, "#b7b3c4", x=0.25 * fp, z=-0.05 * fp),
             part(NAT + "rock_smallA", x=0.2 * fp, z=0.25 * fp), part(NAT + "rock_smallC", x=-0.2 * fp, z=0.2 * fp),
             part(RD + "construction-barrier", x=0.3 * fp, z=0.42 * fp)]
    if flowers:
        parts += [part(NAT + "flower_redA", x=-0.1 * fp, z=0.3 * fp), part(NAT + "flower_yellowA", x=0.3 * fp, z=0.0),
                  part(NAT + "flower_purpleA", x=-0.3 * fp, z=0.35 * fp), part(NAT + "plant_bushLarge", x=0.05, z=-0.2 * fp),
                  part(NAT + "grass_large", x=-0.35 * fp, z=-0.3 * fp)]
    return parts


add("o-ruin-1", 0, "overlay", "Ruina", 1, ruin(1, False))
add("o-ruin-2", 0, "overlay", "Ruina", 2, ruin(2, False))
add("o-ruin-flowers-1", 0, "overlay", "Zarastená ruina", 1, ruin(1, True))
add("o-ruin-flowers-2", 0, "overlay", "Zarastená ruina", 2, ruin(2, True))

# ── Animated tower crane (night screen "stavba prebieha"), 16 frames: the jib slews, the trolley
#    travels, the load bobs, the tip light blinks. Built from primitive boxes (Kenney has no tower crane).
import math

CRANE_FRAMES = 16
YELLOW, YELLOW_DARK, STEEL = "#f2b632", "#c98f1c", "#8d8fa3"


def rot_box(w, h, d, color, dist, y, theta, side=0.0, yaw=None):
    """A box centred `dist` along the jib direction theta (deg); its long side (w) points along
    theta, or along `yaw` when given."""
    t = math.radians(theta)
    x, z = dist * math.cos(t) + side * math.sin(t), -dist * math.sin(t) + side * math.cos(t)
    b = box(w, h, d, color, x=round(x, 4), z=round(z, 4), y=y)
    b["rot"] = theta if yaw is None else yaw
    return b


def crane_frame(i):
    ph = 2 * math.pi * i / CRANE_FRAMES
    theta = 45 + 55 * math.sin(ph)                  # slewing jib
    trolley = 0.95 + 0.35 * math.sin(ph + 1.2)       # trolley travels along the jib
    top = 2.05
    hook_y = 0.95 + 0.25 * math.sin(2 * ph)          # load goes up and down
    parts = [box(0.42, 0.12, 0.42, "#9a98a8"),       # concrete base
             box(0.13, top, 0.13, YELLOW, y=0.12)]    # mast
    y = 0.3
    while y < top:                                   # lattice rings
        parts.append(box(0.145, 0.025, 0.145, YELLOW_DARK, y=y))
        y += 0.22
    jy = top + 0.12
    parts += [
        box(0.16, 0.08, 0.16, YELLOW_DARK, y=top + 0.12),                    # slewing ring
        rot_box(0.2, 0.15, 0.17, "#eef0f6", -0.02, jy - 0.02, theta, side=0.13),  # cab
        rot_box(1.6, 0.07, 0.08, YELLOW, 0.8, jy + 0.08, theta),             # jib
        rot_box(0.6, 0.07, 0.08, YELLOW, -0.3, jy + 0.08, theta),            # counter-jib
        rot_box(0.18, 0.16, 0.16, STEEL, -0.52, jy + 0.02, theta),           # counterweight
        box(0.06, 0.34, 0.06, YELLOW_DARK, y=jy + 0.15),                     # top tower
        rot_box(0.1, 0.04, 0.1, "#55576a", trolley, jy + 0.04, theta),       # trolley
        rot_box(0.022, round(jy + 0.04 - hook_y, 3), 0.022, "#3a3b48", trolley, hook_y, theta),  # cable
        rot_box(0.34, 0.06, 0.09, "#c8914f", trolley, hook_y - 0.06, theta, yaw=theta + 90),  # load: a beam
        rot_box(0.05, 0.05, 0.05, "#ff3b30" if i % 4 < 2 else "#6b1d19", 1.6, jy + 0.12, theta),  # tip light
    ]
    return parts


for i in range(CRANE_FRAMES):
    add(f"o-crane-{i:02d}", 0, "overlay", "Žeriav", 1, crane_frame(i), shadow=False)

for car in ("sedan", "taxi", "van", "suv", "police", "ambulance", "firetruck", "garbage-truck", "delivery"):
    # rot 0 = car front towards +z (screen SW), 90 = +x (SE), 180 = -z (NE), 270 = -x (NW)
    for rot, d in ((0, "sw"), (90, "se"), (180, "ne"), (270, "nw")):
        add(f"v-{car}-{d}", 0, "vehicle", "Auto", 1, [part(CAR + car, rot=rot, scale=CAR_SCALE)])


# ───────────────────────── SLEEP BUDDY (own recipe file, never part of the town catalog) ─────────────────────────
CAT = "Cube Pets/Models/OBJ format/animal-cat"
CAT_CLOSED = "@build/buddy/animal-cat-closed"    # generated by buddy_cat_obj.py: the eyes turned into plain fur
BED = NAT + "bed"
LASH = "#3d3f4b"

# Tunables of the buddy scene (world units; the cat's model units are scaled by `cat`).
BUDDY = {
    "cat": 1.1, "bed": 3.7,           # model scales
    "cat_yaw": 45, "bed_yaw": 0,      # 45 = the cat's face squarely towards the camera (the +x,+z corner)
    "awake_pitch": -14, "asleep_pitch": 14,   # degrees: negative = tilted back (face up), positive = head down
    "bed_pos": [0.0, 0.0],
    "along": 0.08,                   # the cat sits this far along the bed's long (z) axis, bed model units
    "mattress": 0.237,                # mattress top height in the bed's model units
}


def buddy_recipes(P=None):
    """The four sleep-buddy frames (a cat on a camp bed), kind "buddy", level 0. They are NOT written into
    recipes.json – the town catalog never sees them – but into buddy_recipes.json:

        python3 tools/render/make_recipes.py          # also writes tools/render/buddy_recipes.json + build/buddy/
        swift tools/render/render_sprites.swift tools/render/buddy_recipes.json assets/buddy   # sandbox OFF
        python3 tools/render/buddy_finish.py assets/buddy      # flatten, one common crop, docs/previews/buddy_poses.png

    (delete assets/buddy first when re-rendering from scratch: `rm -rf assets/buddy`)

    The cat OBJ has no separate head: head up / down is a pose of the whole cube (pitch of the `body` group about
    its bottom edge), the eyes are flat polygons on the face, so "closed" = the OBJ variant whose eye polygons
    carry the fur shading (buddy_cat_obj.py) + thin dark lash boxes. All four frames share `bounds`, so the
    renderer gives them the identical canvas and anchor.
    """
    P = {**BUDDY, **(P or {})}
    sc, sb = P["cat"], P["bed"]
    y_bed = P["mattress"] * sb                       # mattress top in world units
    yaw = math.radians(P["bed_yaw"])
    cat_xz = [P["bed_pos"][0] + P["along"] * sb * math.sin(yaw), P["bed_pos"][1] + P["along"] * sb * math.cos(yaw)]
    FRONT = [0, 0.18, 0.62]                          # front bottom edge of the cube (model units)
    REAR = [0, 0.18, -0.62]                          # rear bottom edge
    TAIL = [0, 0.7, -0.6]                            # where the tail grows out of the back

    def lashes(y=0.86, dx=0.27, z=0.645):
        """A drooping "︶" on each eye: two thin dark boxes per eye, tilted so the outer ends are higher.
        Model units, glued to the `body` group (they follow its pose)."""
        out = []
        for sx in (-1, 1):                                # left / right eye
            for half in (-1, 1):                          # outer / inner half of the lash
                b = box(0.17, 0.045, 0.012, LASH)
                b.update({"center": True, "chamfer": 0, "attach": "body", "roll": half * 13,
                          "pos": [round(sx * dx + half * 0.082, 3), round(y - 0.012, 3), z]})
                out.append(b)
        return out

    def frame(name, closed, body, drop, legs, tail, label):
        pose = {"body": body}
        pose.update(legs)
        pose["tail"] = {"rot": tail[:3], "pivot": TAIL, "move": tail[3] if len(tail) > 3 else [0, 0, 0]}
        cat = {"src": CAT_CLOSED if closed else CAT, "pos": [round(cat_xz[0], 4), round(y_bed - drop * sc, 4), round(cat_xz[1], 4)],
               "rot": P["cat_yaw"], "scale": sc, "pose": pose}
        if closed:
            cat["children"] = lashes()
        return {"id": name, "level": 0, "kind": "buddy", "nameSK": "Spací kamarát", "nameEN": label, "footprint": [1, 1],
                "parts": [part(BED, x=P["bed_pos"][0], z=P["bed_pos"][1], rot=P["bed_yaw"], scale=sb), cat],
                "bounds": [-3.0, 0, -3.0, 3.0, 3.0, 3.0]}

    stretch = {"leg-front-*": {"scale": [1, 1.5, 1], "pivot": [0, 0, 0]}}
    hide = {"leg-*": {"hidden": True}}
    # drowsy: the cat is 0.09 lower, so the half-height front legs are lifted by the same amount (no stub
    # sunk into the mattress, which would poke out of its sloped edge); the back legs are hidden
    half = {"leg-front-*": {"scale": [1, 0.5, 1], "pivot": [0, 0, 0], "move": [0, 0.09, 0]}, "leg-back-*": {"hidden": True}}
    up = {"rot": [P["awake_pitch"], 0, 0], "pivot": REAR}                                   # sat up, face looks up
    mid = {"rot": [0, 0, 0], "pivot": REAR}
    down = {"rot": [P["asleep_pitch"], 0, 0], "pivot": FRONT, "scale": [1.04, 0.93, 1.04]}  # head down, a bit flatter
    return [
        frame("buddy-cat-awake", False, up, 0.0, stretch, [0, 0, -8], "Sleep buddy – awake"),
        frame("buddy-cat-blink", True, up, 0.0, stretch, [0, 0, -8], "Sleep buddy – blink"),
        frame("buddy-cat-mid", True, mid, 0.09, half, [0, 20, 55], "Sleep buddy – drowsy"),
        # tail: euler degrees about the root (z swings it sideways, then y forward) + an optional offset;
        # asleep it lies on the mattress beside the body
        frame("buddy-cat-asleep", True, down, 0.18, hide, [0, 45, -90, [0.0, -0.5, 0.0]], "Sleep buddy – asleep"),
    ]


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "recipes.json")
    with open(out, "w") as f:
        json.dump(recipes, f, indent=1, ensure_ascii=False)
    by = {}
    for r in recipes:
        by[r["level"]] = by.get(r["level"], 0) + 1
    print(out, len(recipes), "recipes", dict(sorted(by.items())))
    import buddy_cat_obj
    buddy_cat_obj.main()
    bout = os.path.join(os.path.dirname(__file__), "buddy_recipes.json")
    with open(bout, "w") as f:
        json.dump(buddy_recipes(), f, indent=1, ensure_ascii=False)
    print(bout, 4, "buddy frames")
