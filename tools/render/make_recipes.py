#!/usr/bin/env python3
"""Generates tools/render/recipes.json – the list of every sprite SleepHole ships.

Run from the repo root:
    python3 tools/render/make_recipes.py
    swift tools/render/render_sprites.swift tools/render/recipes.json assets/sprites
    python3 tools/render/contact_sheet.py assets/sprites

The sleep buddy (cat on a camp bed, 8 frames) has its own recipe file – see `buddy_recipes()` below.

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
IND_VAR = "City Kit - Industrial/Models/Textures/variation-%s.png"
MM = "Mini Market/Models/OBJ format/"
RAC = "Racing Kit/Models/OBJ format/"

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
    "Nákupné centrum": "Shopping centre", "Obchodný park": "Retail park",
}

# Czech names (build 13b), keyed like NAME_EN by the Slovak name; the app falls back to the Slovak name without one.
NAME_CS = {
    "Rodinný dom": "Rodinný dům", "Bytový dom": "Bytový dům", "Veľký bytový dom": "Velký bytový dům",
    "Malý park": "Malý park", "Park s fontánou": "Park s fontánou", "Záhrada so sochou": "Zahrada se sochou",
    "Park s jazierkom": "Park s jezírkem", "Osvetlená ulica": "Osvětlená ulice", "Knižnica": "Knihovna",
    "Mestská knižnica": "Městská knihovna", "Múzeum": "Muzeum", "Múzeum umenia": "Muzeum umění", "Radnica": "Radnice",
    "Škola": "Škola", "Hasičská stanica": "Hasičská stanice", "Polícia": "Policie", "Nemocnica": "Nemocnice",
    "Mrakodrap": "Mrakodrap", "Výšková budova": "Výšková budova", "Auto": "Auto", "Cesta": "Silnice", "Tráva": "Tráva",
    "Dlažba": "Dlažba", "Stavebný pozemok": "Stavební pozemek", "Lešenie": "Lešení", "Stavenisko": "Staveniště",
    "Ruina": "Ruina", "Zarastená ruina": "Zarostlá ruina", "Žeriav": "Jeřáb",
    "Nákupné centrum": "Nákupní centrum", "Obchodný park": "Obchodní park",
}


def add(rid, level, kind, name, fp, parts, signs=None, shadow=True, connects=None):
    assert all(r["id"] != rid for r in recipes), rid
    r = {"id": rid, "level": level, "kind": kind, "nameSK": name, "nameEN": NAME_EN[name], "nameCS": NAME_CS[name],
         "footprint": [fp, fp],
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
    `<id>.en.png` (catalog `fileEN`) with the same bounds/anchor; optional "cs" likewise → `.cs.png`."""
    r = {"text": text["sk"], "textEN": text["en"], "color": color, "height": height, "textColor": text_color}
    if text.get("cs") and text["cs"] != text["sk"]:
        r["textCS"] = text["cs"]   # Czech variant `<id>.cs.png` (catalog `fileCS`); omitted when equal to Slovak
    return r


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
], signs=[sign({"sk": "MÚZEUM", "en": "MUSEUM", "cs": "MUZEUM"}, "#7b4a2a", height=0.4)])
add("l2-museum-b", 2, "building", "Múzeum umenia", 2, [
    part(COM + "building-e", z=-0.3, scale=1.0, texture=COM_VAR % "b", center=True),
    *[part(BK + "column-wide", x=x, z=0.35, scale=0.3) for x in (-0.55, 0, 0.55)],
    part(NAT + "statue_obelisk", x=-0.7, z=0.75, scale=0.7),
    part(SUB + "tree-small", x=0.75, z=0.75),
], signs=[sign({"sk": "GALÉRIA", "en": "GALLERY", "cs": "GALERIE"}, "#6b3f8f", height=0.8)])
add("l2-library-a", 2, "building", "Knižnica", 2, [
    part(MOD + "building-sample-house-a", x=-0.2, z=-0.1, scale=0.85, center=True),
    part(HOL + "bench", x=0.35, z=0.7, scale=0.3),
    part(SUB + "tree-large", x=-0.75, z=0.7), part(SUB + "planter", x=0.75, z=0.35),
], signs=[sign({"sk": "KNIŽNICA", "en": "LIBRARY", "cs": "KNIHOVNA"}, "#2f7a55", height=0.5)])
add("l2-library-b", 2, "building", "Mestská knižnica", 2, [
    part(COM + "building-k", z=-0.3, scale=0.9, texture=COM_VAR % "a", center=True),
    part(HOL + "bench", x=-0.3, z=0.72, scale=0.3),
    part(SUB + "tree-large", x=0.75, z=0.72), part(SUB + "tree-small", x=-0.8, z=0.75),
], signs=[sign({"sk": "KNIŽNICA", "en": "LIBRARY", "cs": "KNIHOVNA"}, "#2f7a55", height=0.55)])

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
], signs=[{**sign({"sk": "RADNICA", "en": "TOWN HALL", "cs": "RADNICE"}, "#b8862b"), "pos": [-0.35, 0.24, 0.8]}])
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
], signs=[sign({"sk": "POLÍCIA", "en": "POLICE", "cs": "POLICIE"}, "#1f4fa3", height=0.7)])
add("l3-hospital", 3, "building", "Nemocnica", 2, [
    plate(2, PLAZA),
    part(COM + "building-j", z=-0.3, scale=0.85, center=True),
    part(CAR + "ambulance", x=0.55, z=0.65, rot=90, scale=CAR_SCALE),
], signs=[sign({"sk": "NEMOCNICA", "en": "HOSPITAL", "cs": "NEMOCNICE"}, "#ffffff", height=0.82, text_color="#d8342b")])

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
CAT_WINK = "@build/buddy/animal-cat-wink"        # same, but only the cat's left eye (+x); the right one stays open
BED = NAT + "bed"
LASH = "#3d3f4b"
LEG_H = 0.306                                    # height of the cat's leg stubs (model units)

# Tunables of the buddy scene (world units; the cat's model units are scaled by `cat`).
BUDDY = {
    "size": 1.3,                      # one factor for the whole scene: cat, bed, positions and `bounds` (final canvas 860 px wide)
    "cat": 1.1, "bed": 3.7,           # model scales (before `size`)
    "cat_yaw": 45, "bed_yaw": 0,      # 45 = the cat's face squarely towards the camera (the +x,+z corner)
    "awake_pitch": -14, "asleep_pitch": 14,   # degrees: negative = tilted back (face up), positive = head down
    "bed_pos": [0.0, 0.0],
    "along": 0.08,                   # the cat sits this far along the bed's long (z) axis, bed model units
    "mattress": 0.237,                # mattress top height in the bed's model units
    "top": 3.9,                       # top of the shared `bounds` (before `size`): the arched cat is tall
    # "arched back": factor of the legs' height, pitch (positive = rear up), body scale, tail scale
    "arch1": {"legs": 2.4, "pitch": 5, "scale": [0.975, 1.035, 0.975], "tail": [1.2, 1.05, 1.2]},
    "arch2": {"legs": 2.9, "pitch": 9, "scale": [0.95, 1.07, 0.95], "tail": [1.4, 1.0, 1.4]},
    "happy_scale": [1.03, 0.97, 1.03],  # the purring cat is a touch squashed
    "wink_roll": -7,                  # degrees about z: negative = the top leans towards +x (the closed left eye)
}


def buddy_recipes(P=None):
    """The eight sleep-buddy frames (a cat on a camp bed), kind "buddy", level 0. They are NOT written into
    recipes.json – the town catalog never sees them – but into buddy_recipes.json:

        python3 tools/render/make_recipes.py          # also writes tools/render/buddy_recipes.json + build/buddy/
        swift tools/render/render_sprites.swift tools/render/buddy_recipes.json assets/buddy   # sandbox OFF
        python3 tools/render/buddy_finish.py assets/buddy      # flatten, one common crop, docs/previews/buddy_poses.png

    (delete assets/buddy first when re-rendering from scratch: `rm -rf assets/buddy`)

    Frames: awake, blink, happy ("^ ^" eyes, purring), wink (one eye), arch-1 / arch-2 (the cat arches its back),
    mid (drowsy), asleep.

    The cat OBJ has no separate head: head up / down is a pose of the whole cube (pitch of the `body` group about
    its bottom edge), the eyes are flat polygons on the face. Eye modes (see `frame`): "open" = the plain cat;
    "closed" / "happy" = the OBJ variant whose eye polygons carry the fur shading (buddy_cat_obj.py) + thin dark
    lash boxes (drooping "︶" = sleepy, tilted the other way "^" = happy); "wink" = the variant with only the
    left eye (+x) turned into fur + one happy lash. The `Group` (a flat mouth detail on the face) and the `tail`
    follow the body's pose. All frames share `bounds`, so the renderer gives them the identical canvas and anchor.
    """
    P = {**BUDDY, **(P or {})}
    k = P["size"]
    sc, sb = P["cat"] * k, P["bed"] * k
    y_bed = P["mattress"] * sb                       # mattress top in world units
    yaw = math.radians(P["bed_yaw"])
    bed_pos = [P["bed_pos"][0] * k, P["bed_pos"][1] * k]
    cat_xz = [bed_pos[0] + P["along"] * sb * math.sin(yaw), bed_pos[1] + P["along"] * sb * math.cos(yaw)]
    FRONT = [0, 0.18, 0.62]                          # front bottom edge of the cube (model units)
    REAR = [0, 0.18, -0.62]                          # rear bottom edge
    CENTER = [0, 0.18, 0]                            # bottom centre (arched back: the pivot of the pitch / scale)
    TAIL = [0, 0.7, -0.6]                            # where the tail grows out of the back

    def lashes(eyes="both", style="sleepy", y=None, dx=0.27, z=0.645):
        """The closed-eye lines, glued to the `body` group (they follow its pose). Two thin dark boxes per eye,
        model units. eyes: "both" or "left" (the cat's left = +x only). style: "sleepy" = drooping "︶" (outer ends
        up, 13°); "happy" = the halves tilted the other way, an arc "^" (24°)."""
        happy = style == "happy"
        angle, gap, thick = (24, 0.076, 0.052) if happy else (13, 0.082, 0.045)
        y = (0.85 if happy else 0.86) if y is None else y
        out = []
        for sx in ((-1, 1) if eyes == "both" else (1,)):      # right (-x) / left (+x) eye
            for half in (-1, 1):                              # the two halves of the lash
                b = box(0.17, thick, 0.012, LASH)
                b.update({"center": True, "chamfer": 0, "attach": "body", "roll": -half * angle if happy else half * angle,
                          "pos": [round(sx * dx + half * gap, 3), round(y - 0.012, 3), z]})
                out.append(b)
        return out

    def through(pt, pose):
        """Where a model-space point lands after a group pose of the form {rot:[rx,0,0], pivot, scale, move}
        (the renderer: translate(pivot + move) · rotate · scale · translate(-pivot))."""
        piv, mv, sc3 = pose.get("pivot", [0, 0, 0]), pose.get("move", [0, 0, 0]), pose.get("scale", [1, 1, 1])
        x, y, z = (pt[i] - piv[i] for i in range(3))
        x, y, z = x * sc3[0], y * sc3[1], z * sc3[2]
        a = math.radians(pose.get("rot", [0, 0, 0])[0])
        y, z = y * math.cos(a) - z * math.sin(a), y * math.sin(a) + z * math.cos(a)
        return [piv[0] + mv[0] + x, piv[1] + mv[1] + y, piv[2] + mv[2] + z]

    EYES = {"open": (CAT, lambda: []), "closed": (CAT_CLOSED, lambda: lashes()),
            "happy": (CAT_CLOSED, lambda: lashes(style="happy")),
            "wink": (CAT_WINK, lambda: lashes(eyes="left", style="happy"))}

    def frame(name, eyes, body, drop, legs, tail, label, mouth=True):
        """eyes: "open" (plain cat) | "closed" (closed OBJ + sleepy lashes) | "happy" (closed OBJ + happy lashes) |
        "wink" (wink OBJ + one happy lash on the left eye). mouth: the `Group` follows the body's pose."""
        src, make_children = EYES[eyes]
        pose = {"body": body}
        if mouth:
            pose["Group"] = dict(body)
        pose.update(legs)
        if isinstance(tail, dict):
            pose["tail"] = tail
        else:
            pose["tail"] = {"rot": tail[:3], "pivot": TAIL, "move": tail[3] if len(tail) > 3 else [0, 0, 0]}
        cat = {"src": src, "pos": [round(cat_xz[0], 4), round(y_bed - drop * sc, 4), round(cat_xz[1], 4)],
               "rot": P["cat_yaw"], "scale": sc, "pose": pose}
        if eyes != "open":
            cat["children"] = make_children()
        return {"id": name, "level": 0, "kind": "buddy", "nameSK": "Spací kamarát", "nameEN": label, "footprint": [1, 1],
                "parts": [part(BED, x=bed_pos[0], z=bed_pos[1], rot=P["bed_yaw"], scale=sb), cat],
                "bounds": [-3.0 * k, 0, -3.0 * k, 3.0 * k, P["top"] * k, 3.0 * k]}

    stretch = {"leg-front-*": {"scale": [1, 1.5, 1], "pivot": [0, 0, 0]}}
    hide = {"leg-*": {"hidden": True}}
    # drowsy: the cat is 0.09 lower, so the half-height front legs are lifted by the same amount (no stub
    # sunk into the mattress, which would poke out of its sloped edge); the back legs are hidden
    half = {"leg-front-*": {"scale": [1, 0.5, 1], "pivot": [0, 0, 0], "move": [0, 0.09, 0]}, "leg-back-*": {"hidden": True}}
    up = {"rot": [P["awake_pitch"], 0, 0], "pivot": REAR}                                   # sat up, face looks up
    mid = {"rot": [0, 0, 0], "pivot": REAR}
    down = {"rot": [P["asleep_pitch"], 0, 0], "pivot": FRONT, "scale": [1.04, 0.93, 1.04]}  # head down, a bit flatter
    awake_tail = [0, 0, -8]

    # happy: the awake pose, a touch squashed (about the same rear-bottom pivot, so it stays seated)
    happy = {**up, "scale": P["happy_scale"]}
    # wink: the awake pose rolled towards the closed eye; the tail root follows the roll (about the bottom centre)
    roll = P["wink_roll"]
    wink = {**up, "rot": [P["awake_pitch"], 0, roll]}
    r = math.radians(roll)
    dy = TAIL[1] - CENTER[1]
    wink_tail = {"rot": awake_tail, "pivot": TAIL, "move": [round(-dy * math.sin(r), 4), round(dy * (math.cos(r) - 1), 4), 0]}

    def arch(a):
        """The cat arches its back: all four legs stretched about their feet, the cube (and its mouth / lashes) lifted
        by what the legs gained and pitched forward about its bottom centre (rear up), a bit taller and narrower; the
        tail root rides along, the tail stands up and puffs."""
        lift = LEG_H * (a["legs"] - 1)
        body = {"rot": [a["pitch"], 0, 0], "pivot": CENTER, "scale": a["scale"], "move": [0, round(lift, 4), 0]}
        root = through(TAIL, body)
        tail = {"rot": [a["pitch"] + 10, 0, 0], "pivot": TAIL, "scale": a["tail"],
                "move": [round(root[i] - TAIL[i], 4) for i in range(3)]}
        return body, {"leg-*": {"scale": [1, a["legs"], 1], "pivot": [0, 0, 0]}}, tail

    b1, l1, t1 = arch(P["arch1"])
    b2, l2, t2 = arch(P["arch2"])
    return [
        frame("buddy-cat-awake", "open", up, 0.0, stretch, awake_tail, "Sleep buddy – awake"),
        frame("buddy-cat-blink", "closed", up, 0.0, stretch, awake_tail, "Sleep buddy – blink"),
        frame("buddy-cat-happy", "happy", happy, 0.0, stretch, awake_tail, "Sleep buddy – happy"),
        frame("buddy-cat-wink", "wink", wink, 0.0, stretch, wink_tail, "Sleep buddy – wink"),
        frame("buddy-cat-arch-1", "open", b1, 0.0, l1, t1, "Sleep buddy – arching"),
        frame("buddy-cat-arch-2", "open", b2, 0.0, l2, t2, "Sleep buddy – arched"),
        frame("buddy-cat-mid", "closed", mid, 0.09, half, [0, 20, 55], "Sleep buddy – drowsy"),
        # tail: euler degrees about the root (z swings it sideways, then y forward) + an optional offset;
        # asleep it lies on the mattress beside the body (and the mouth detail stays inside the cube, as before)
        frame("buddy-cat-asleep", "closed", down, 0.18, hide, [0, 45, -90, [0.0, -0.5, 0.0]], "Sleep buddy – asleep",
              mouth=False),
    ]


def shop_candidates():
    """Candidate recipes for the build 14 shops (step 14c1): shopping centre SC1-SC4, retail park RP1-RP3.
    NOT part of recipes.json – written to shop_candidates.json and rendered into build/shop-candidates/ only,
    so the owner can pick. Footprint 2x2 (front = +z)."""
    out = []

    def cand(rid, level, name, parts, label, text, color, sign_pos=None, fp=2, sign_h=0.7):
        out.append({"id": rid, "level": level, "kind": "building", "nameSK": name, "nameEN": NAME_EN[name],
                    "nameCS": NAME_CS[name], "footprint": [fp, fp], "parts": parts,
                    "signs": [{**sign(text, color, height=sign_h), **({"pos": sign_pos} if sign_pos else {})}], "label": label})

    SHOP = {"sk": "NÁKUPY", "en": "SHOPPING"}
    SHOPS = {"sk": "OBCHODY", "en": "SHOPS"}
    SC, RP = "#c2410c", "#0f766e"
    cars = lambda name, x, z, rot=180: part(CAR + name, x=x, z=z, rot=rot, scale=CAR_SCALE)

    def carpark(zc=0.62, lamps=True, stalls=5):
        ps = [box(1.96, 0.02, 0.84, "#5b5e70", z=0.5)]
        for i in range(stalls):
            ps.append(box(0.02, 0.012, 0.34, "#f5f5f5", x=round(-0.8 + i * 1.6 / (stalls - 1), 3), z=zc, y=0.03))
        if lamps:
            ps += [part(RAC + "lightPostModern", x=-0.92, z=0.3, scale=0.8), part(RAC + "lightPostModern", x=0.92, z=0.3, scale=0.8)]
        return ps

    # SC1 – an industrial hall turned into a mall, with a plaza and parasols
    for v in ("a", "b"):
        cand("cand-sc1" + ("" if v == "a" else "-b"), 3, "Nákupné centrum", [
            plate(2, PLAZA),
            part(IND + "building-q", z=-0.15, scale=0.88, texture=IND_VAR % ("a" if v == "a" else "c"), center=True),
            part(COM + "detail-parasol-a", x=-0.6, z=0.83), part(COM + "detail-parasol-b", x=-0.1, z=0.83),
            part(SUB + "tree-large", x=0.8, z=0.8), part(SUB + "planter", x=0.45, z=0.85),
            cars("sedan", 0.45, 0.35),
        ], "SC1 Hala", SHOP, SC)
    # SC2 – a shop-front building with awnings and market stalls
    cand("cand-sc2", 3, "Nákupné centrum", [
        plate(2, PLAZA),
        part(COM + "building-e", z=-0.5, scale=1.1, center=True),
        part(COM + "detail-awning-wide", x=-0.42, z=0.0, y=0.0, scale=1.1),
        part(COM + "detail-awning-wide", x=0.42, z=0.0, y=0.0, scale=1.1),
        part(MM + "display-fruit", x=-0.55, z=0.75, scale=0.45), part(MM + "display-bread", x=0.0, z=0.75, scale=0.45),
        part(MM + "shopping-cart", x=0.4, z=0.8, rot=30, scale=0.6),
        part(SUB + "tree-large", x=0.8, z=0.8), cars("sedan", 0.75, 0.3),
    ], "SC2 Pasáž s trhom", SHOP, SC)
    # SC3 – a department store: a tall commercial block with an entrance canopy
    cand("cand-sc3", 3, "Nákupné centrum", [
        plate(2, PLAZA),
        part(COM + "building-n", z=-0.25, scale=0.78, center=True),
        part(COM + "detail-overhang-wide", x=0, z=0.3, scale=0.9),
        part(SUB + "tree-large", x=-0.8, z=0.75), part(SUB + "planter", x=0.78, z=0.8),
        cars("van", -0.4, 0.75), cars("hatchback-sports", 0.4, 0.75),
    ], "SC3 Obchodný dom", SHOP, SC)
    # SC4 – our own mall from plain boxes + Kenney details
    GL = "#7fa7d6"
    cand("cand-sc4", 3, "Nákupné centrum", [
        plate(2, PLAZA),
        box(1.74, 0.14, 1.04, "#8d89a6", z=-0.35),                       # darker plinth / ground-floor band
        box(1.7, 0.6, 1.0, "#e9e6f2", z=-0.35, y=0.14),                  # the two-storey body
        box(1.76, 0.05, 1.06, "#4a4a5e", z=-0.35, y=0.74),               # dark roof edge
        box(1.5, 0.12, 0.01, GL, z=0.155, y=0.2), box(1.5, 0.12, 0.01, GL, z=0.155, y=0.5),   # front glass bands
        box(0.01, 0.12, 0.8, GL, x=0.855, z=-0.35, y=0.2), box(0.01, 0.12, 0.8, GL, x=0.855, z=-0.35, y=0.5),  # side bands
        box(0.5, 0.95, 0.5, "#9fc3e8", x=0.42, z=0.1),                    # glass atrium
        box(0.52, 0.04, 0.52, "#4a4a5e", x=0.42, z=0.1, y=0.95),
        part(COM + "detail-overhang-wide", x=0.42, z=0.3, scale=0.9),
        part(RAC + "lightPostModern", x=-0.9, z=0.55, scale=0.8), part(RAC + "lightPostModern", x=0.9, z=0.55, scale=0.8),
        part(COM + "detail-parasol-a", x=-0.75, z=0.8), part(SUB + "tree-large", x=0.88, z=0.88),
        cars("sedan", -0.2, 0.8),
    ], "SC4 Sklenené centrum", SHOP, SC, sign_pos=[-0.62, 0.2, 0.18])
    # RP1 – one long shed with shop doors and a car park
    for v in ("a", "b"):
        cand("cand-rp1" + ("" if v == "a" else "-b"), 2, "Obchodný park", [
            part(IND + "building-s", z=-0.58, scale=0.9, texture=IND_VAR % ("a" if v == "a" else "b"), center=True),
            *carpark(),
            cars("sedan", -0.4, 0.62), cars("hatchback-sports", 0.0, 0.62), cars("suv", 0.4, 0.62),
            part(MM + "shopping-cart", x=0.8, z=0.55, scale=0.6), part(SUB + "tree-small", x=0.88, z=-0.1),
        ], "RP1 Dlhá hala", SHOPS, RP)
    # RP2 – two separate big-box units
    cand("cand-rp2", 2, "Obchodný park", [
        part(IND + "building-p", x=-0.55, z=-0.6, scale=0.72, texture=IND_VAR % "a", center=True),
        part(IND + "building-h", x=0.55, z=-0.6, scale=0.7, texture=IND_VAR % "c", center=True),
        *carpark(stalls=4),
        cars("sedan", -0.3, 0.62), cars("van", 0.3, 0.62),
        part(MM + "display-fruit", x=-0.55, z=-0.02, scale=0.4),
    ], "RP2 Dve predajne", SHOPS, RP)
    # RP3 – a row of shops with awnings
    cand("cand-rp3", 2, "Obchodný park", [
        part(IND + "building-t", x=-0.5, z=-0.6, scale=0.72, center=True),
        part(IND + "building-p", x=0.55, z=-0.6, scale=0.6, center=True),
        part(COM + "detail-awning-wide", x=-0.5, z=-0.2, scale=0.9), part(COM + "detail-awning-wide", x=0.55, z=-0.39, scale=0.8),
        *carpark(),
        cars("sedan", -0.4, 0.62), cars("suv", 0.4, 0.62),
    ], "RP3 Rad s markízami", SHOPS, RP)
    # ---- 4x4 alternatives: a whole block, SC4's glass language scaled up -------------------------------
    GLASS, FAC, PLINTH, ROOF = "#7fa7d6", "#e9e6f2", "#8d89a6", "#4a4a5e"
    lamp = lambda x, z: part(RAC + "lightPostModern", x=x, z=z, scale=0.9)

    def wing(x0, x1, z0, z1, front=True, side=True, h=0.9):
        """A two-storey glass-banded wing: plinth, body, roof edge, bands on the +z (front) and / or +x (side) face."""
        cx, cz, w, d = (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0
        ps = [box(w + 0.04, 0.2, d + 0.04, PLINTH, x=cx, z=cz), box(w, h, d, FAC, x=cx, z=cz, y=0.2),
              box(w + 0.06, 0.06, d + 0.06, ROOF, x=cx, z=cz, y=0.2 + h)]
        for y in (0.3, 0.3 + h / 2):
            if front:
                ps.append(box(w - 0.4, 0.2, 0.01, GLASS, x=cx, z=z1 + 0.005, y=y))
            if side:
                ps.append(box(0.01, 0.2, d - 0.4, GLASS, x=x1 + 0.005, z=cz, y=y))
        return ps

    def roof_units(pts, y=1.16):
        return [box(0.34, 0.16, 0.26, "#9a9aa8", x=x, z=z, y=y) for x, z in pts] + \
               [box(0.18, 0.1, 0.18, "#b8b8c4", x=x + 0.05, z=z - 0.03, y=y + 0.16) for x, z in pts[::2]]

    def atrium(x, z, w, d, h, canopy_scale=1.5):
        return [box(w, h, d, "#9fc3e8", x=x, z=z), box(w + 0.04, 0.06, d + 0.04, ROOF, x=x, z=z, y=h),
                box(w * 0.6, 0.5, 0.01, "#5d86b8", x=x, z=z + d / 2 + 0.006, y=0.22),   # dark glass doors
                part(COM + "detail-overhang-wide", x=x, z=z + d / 2 - 0.15, scale=canopy_scale)]

    def stalls(x0, x1, zc, n_step=0.4, length=0.55):
        n = int(round((x1 - x0) / n_step))
        return [box(0.02, 0.012, length, "#f5f5f5", x=round(x0 + i * n_step, 3), z=zc, y=0.05) for i in range(n + 1)]

    MIX = ["sedan", "hatchback-sports", "suv", "van", "taxi", "sedan-sports", "suv-luxury", "delivery"]

    def parked(x0, zc, n, skip=(), step=0.4):
        return [cars(MIX[i % len(MIX)], round(x0 + step / 2 + i * step, 3), zc) for i in range(n) if i not in skip]

    def sc5(rid, text):
        cand(rid, 3, "Nákupné centrum", [
            plate(4, PLAZA),
            *wing(-1.7, 1.7, -1.9, -0.1),
            *atrium(0.0, -0.2, 1.1, 0.9, 1.8),
            part(COM + "detail-overhang-wide", x=-1.25, z=0.05, scale=1.0), box(0.5, 0.45, 0.02, "#5d86b8", x=-1.25, z=-0.09, y=0.2),
            part(COM + "detail-overhang-wide", x=1.2, z=0.05, scale=1.0), box(0.5, 0.45, 0.02, "#5d86b8", x=1.2, z=-0.09, y=0.2),
            *roof_units([(-1.2, -1.5), (-0.6, -1.0), (0.9, -1.4), (1.3, -0.8), (-1.3, -0.7)]),
            # plaza strip with parasols / planters / trees, then the car park
            part(COM + "detail-parasol-a", x=-0.9, z=0.75), part(COM + "detail-parasol-b", x=0.9, z=0.75),
            part(SUB + "planter", x=-1.5, z=0.75), part(SUB + "planter", x=1.5, z=0.75),
            part(SUB + "tree-large", x=-1.85, z=0.5), part(SUB + "tree-large", x=1.85, z=0.5),
            part(MM + "shopping-cart", x=0.35, z=0.8, rot=20, scale=0.6), part(MM + "shopping-cart", x=-0.3, z=0.85, rot=-15, scale=0.6),
            box(3.9, 0.02, 1.0, "#5b5e70", z=1.45, y=0.03),
            *stalls(-1.8, 1.8, 1.45, length=0.6), *parked(-1.8, 1.45, 9, skip=(2, 6)),
            lamp(-1.9, 0.95), lamp(1.9, 0.95), lamp(-0.6, 0.95), lamp(0.6, 0.95),
        ], "SC5 " + text["en"], text, SC, sign_pos=[-1.3, 0.6, -0.07], fp=4, sign_h=0.95)

    sc5("cand-sc5", SHOP)
    sc5("cand-sc5-name", {"sk": "FELIX", "en": "PEPPER"})

    # SC6 – an L of two wings (along the back and along the +x side) around a car park, a tall corner atrium at the inner corner
    cand("cand-sc6", 3, "Nákupné centrum", [
        plate(4, PLAZA),
        *wing(-1.9, 1.95, -1.95, -0.95, front=True, side=True),
        *wing(0.95, 1.95, -0.95, 1.9, front=True, side=True),
        *atrium(0.55, -0.7, 1.0, 1.0, 1.8),
        *roof_units([(-1.3, -1.5), (-0.5, -1.4), (0.4, -1.6), (1.5, -1.2), (1.45, 0.0), (1.45, 1.0)]),
        part(COM + "detail-overhang-wide", x=1.45, z=1.9, scale=1.0),
        box(2.7, 0.02, 1.35, "#5b5e70", x=-0.62, z=1.2, y=0.03),
        *stalls(-1.9, 0.6, 1.2, length=0.6), *parked(-1.9, 1.2, 6, skip=(2,)),
        part(COM + "detail-parasol-a", x=-0.9, z=0.15), part(COM + "detail-parasol-b", x=-0.1, z=0.2),
        part(SUB + "planter", x=-1.7, z=0.2), part(SUB + "tree-large", x=-1.85, z=1.85), part(SUB + "tree-large", x=0.65, z=1.85),
        part(MM + "shopping-cart", x=0.2, z=0.5, rot=20, scale=0.6), part(MM + "shopping-cart", x=-0.5, z=0.45, rot=-15, scale=0.6),
        lamp(-1.9, 0.5), lamp(0.7, 0.5), lamp(-0.6, 1.9),
    ], "SC6 Centrum do L", SHOP, SC, sign_pos=[-1.4, 0.45, -0.92], fp=4, sign_h=0.95)
    return out


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
    print(bout, 8, "buddy frames")
    cout = os.path.join(os.path.dirname(__file__), "shop_candidates.json")
    with open(cout, "w") as f:
        json.dump(shop_candidates(), f, indent=1, ensure_ascii=False)
    print(cout, len(shop_candidates()), "shop candidates")
