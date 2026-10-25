#!/usr/bin/env python3
"""PROOF ONLY: renders candidate cat accessories (hats, glasses, nightcap, collar, things beside the bed) on the sleep
buddy so the owner can pick prizes for the mystery boxes. Touches nothing in the app: all output goes into
build/accessories-proof/ (recipes JSON, raw renders, sheet.png, sheet-real-size.png).

It imports make_recipes.py as a module (never runs it as a script) and appends each accessory to the buddy frames
awake / asleep / arch-2: worn items are children of the cat part attached to `body` (they follow every pose), world
items are extra parts of the recipe. Needs build/buddy/ (python3 tools/render/buddy_cat_obj.py writes it) and the
renderer's cone / sphere primitives.

usage (from the repo root; the render step needs the Bash sandbox OFF, ModelIO loads empty models inside it):
    python3 tools/render/accessory_proof.py          # writes recipes + calls the renderer + builds the sheets
    python3 tools/render/accessory_proof.py --sheets # only rebuild the sheets from the existing renders
"""
import copy
import json
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_recipes as mr  # noqa: E402  (module import only – no files are written)

OUT = "build/accessories-proof"
RENDERS = OUT + "/renders"
FRAMES = [("awake", "buddy-cat-awake"), ("asleep", "buddy-cat-asleep"), ("arch-2", "buddy-cat-arch-2")]
KENNEY = "assets/Kenney Game Assets All-in-1 3/3D assets/"
PROTO, HOLI, MINI, FURN, FOOD, PLAT = ("Prototype Kit", "Holiday Kit", "Mini Characters", "Furniture Kit", "Food Kit",
                                       "Platformer Kit")


def obj(kit, name):
    return f"{kit}/Models/OBJ format/{name}"


def fitted(src, width, at, rot=0, axis="x", front=None, **extra):
    """An OBJ part scaled so its `axis` extent is `width`, its bottom-centre (x, z of the bbox centre, y of the lowest
    vertex) put on `at` = [x, y, z] (in the parent's space)."""
    b = mr.bounds(src)
    ext = {"x": b[1] - b[0], "y": b[3] - b[2], "z": b[5] - b[4]}[axis]
    s = width / ext
    cx, cz = (b[0] + b[1]) / 2 * s, (b[4] + b[5]) / 2 * s
    import math
    a = math.radians(rot)
    cxr, czr = cx * math.cos(a) + cz * math.sin(a), -cx * math.sin(a) + cz * math.cos(a)    # yaw about +y
    if front is not None:        # put the model's +z-most plane (rot 0) exactly on z = front, ignoring at[2]
        czr, at = b[5] * s, [at[0], at[1], front]
    p = {"src": src, "pos": [round(at[0] - cxr, 4), round(at[1] - b[2] * s, 4), round(at[2] - czr, 4)],
         "rot": rot, "scale": round(s, 4)}
    p.update(extra)
    return p


def cone(r0, r1, h, color, pos, seg=8, **kw):
    p = {"cone": [r0, r1, h], "color": color, "pos": pos, "segments": seg}
    p.update(kw)
    return p


def sphere(r, color, pos, seg=8, **kw):
    p = {"sphere": r, "color": color, "pos": pos, "segments": seg, "center": True}
    p.update(kw)
    return p


def worn(parts):
    """Glue worn parts to the cat's `body` group (they follow its pose)."""
    return [{**p, "attach": "body"} for p in parts]


# ---------------------------------------------------------------- worn (cat model space; the head top is y ~1.31,
# the ears stand at x +-0.34, z 0.2..0.45 up to y 1.59; the face is at z ~0.64, eyes at y ~0.85, x +-0.27)
def a_cap():
    return worn([fitted(obj(PROTO, "hat-cap"), 0.8, [0, 1.27, 0.0], rot=90, axis="z")])


def a_hard():
    return worn([fitted(obj(PROTO, "hat-hard"), 0.9, [0, 1.27, 0.0], rot=90, axis="z")])


def a_top():
    """Holiday Kit's `snowman-hat` is a whole snowman wearing the hat (one group, cannot be split) -> a top hat made
    of renderer primitives instead: brim, crown, red band."""
    ink, red = "#2b2b36", "#c8344a"
    crown = cone(0.28, 0.26, 0.55, ink, [0, 1.42, 0.0], seg=12)
    brim = cone(0.42, 0.42, 0.06, ink, [0, 1.40, 0.0], seg=12)
    band = cone(0.285, 0.28, 0.10, red, [0, 1.46, 0.0], seg=12)
    return worn([brim, crown, band])


def a_glasses():
    return worn([fitted(obj(MINI, "aid-glasses"), 1.1, [0, 0.73, 0], front=0.665)])


def a_sunglasses():
    return worn([fitted(obj(MINI, "aid-sunglasses"), 1.1, [0, 0.73, 0], front=0.665)])


def nightcap_parts(tip_kind="pompom"):
    blue, white = "#4f6fc4", "#f4f4f8"
    if tip_kind == "star":
        tip = fitted(obj(PLAT, "star"), 0.5, [0, 0.38, 0.0], rot=0)
    else:
        tip = sphere(0.12, white, [0, 0.42, 0], seg=8)
    upper = cone(0.30, 0.06, 0.42, blue, [0, 0.34, 0], roll=-32)
    upper["children"] = [tip]
    base = cone(0.50, 0.30, 0.34, blue, [0, 1.27, -0.05])
    band = cone(0.50, 0.50, 0.09, white, [0, 1.25, -0.05])
    base["children"] = [upper]
    return [base, band]


def a_nightcap():
    return worn(nightcap_parts())


def a_nightcap_star():
    return worn(nightcap_parts("star"))


def a_collar():
    red, gold = "#d6455d", "#f2c23c"
    y, h = 0.46, 0.11
    boxes = []
    for sx in (-1, 1):                       # the sides
        b = mr.box(0.05, h, 1.34, red); b.update({"center": True, "chamfer": 0, "pos": [sx * 0.625, y, 0.03]}); boxes.append(b)
    for sz, zz in ((1, 0.705), (-1, -0.65)):  # front / back
        b = mr.box(1.3, h, 0.05, red); b.update({"center": True, "chamfer": 0, "pos": [0, y, zz]}); boxes.append(b)
    bell = sphere(0.1, gold, [0, y - 0.1, 0.73])
    return worn(boxes + [bell])


def a_star_head():
    return worn([fitted(obj(PLAT, "star"), 0.6, [0, 1.62, 0.28], rot=0)])


# ---------------------------------------------------------------- world items (world units; the bed is 1.6 wide
# (x) and 3.6 long (z), mattress top at y 1.14, the cat sits at z ~0.4, the camera looks from +x +z)
def w_pillow():
    return [fitted(obj(FURN, "pillow"), 1.3, [0.0, 1.12, -1.2], rot=0)]


def w_rug():
    return [fitted(obj(FURN, "rugRound"), 3.4, [0.0, 0.0, 0.25])]


def w_lamp():
    return [fitted(obj(FURN, "lampRoundFloor"), 2.0, [1.7, 0.0, 0.2], axis="y")]


def w_lantern():
    return [fitted(obj(HOLI, "lantern"), 1.3, [1.5, 0.0, 0.9], axis="y")]


def w_bowl():
    bowl = fitted(obj(FOOD, "bowl"), 1.1, [1.5, 0.0, 1.0])
    fish = fitted(obj(FOOD, "fish"), 0.75, [1.5, 0.22, 1.0], axis="z", rot=20)
    return [bowl, fish]


def w_present():
    return [fitted(obj(HOLI, "present-a-cube"), 1.0, [1.5, 0.0, 0.8])]


def w_sock():
    return [fitted(obj(HOLI, "sock-red"), 1.0, [0.0, 0.2, 1.95], axis="y")]


# id, EN, SK, builder, worn?
CANDIDATES = [
    ("plain", "Plain cat", "Obyčajná mačka", lambda: [], True),
    ("cap", "Cap", "Šiltovka", a_cap, True),
    ("hard", "Builder's helmet", "Prilba staviteľa", a_hard, True),
    ("top", "Top hat", "Cylinder", a_top, True),
    ("glasses", "Glasses", "Okuliare", a_glasses, True),
    ("sunglasses", "Sunglasses", "Slnečné okuliare", a_sunglasses, True),
    ("nightcap", "Nightcap", "Nočná čiapka", a_nightcap, True),
    ("collar", "Collar with a bell", "Obojok so zvončekom", a_collar, True),
    ("starhead", "Star above the head", "Hviezdička nad hlavou", a_star_head, True),
    ("nightcapstar", "Nightcap with a star", "Nočná čiapka s hviezdičkou", a_nightcap_star, True),
    ("pillow", "Pillow", "Vankúš", w_pillow, False),
    ("rug", "Rug", "Koberček", w_rug, False),
    ("lamp", "Lamp", "Lampa", w_lamp, False),
    ("lantern", "Lantern", "Lampáš", w_lantern, False),
    ("bowl", "Bowl with a fish", "Miska s rybou", w_bowl, False),
    ("present", "Present", "Darček", w_present, False),
    ("sock", "Stocking", "Ponožka", w_sock, False),
]


def build_recipes():
    base = {r["id"]: r for r in mr.buddy_recipes()}
    out = []
    for cid, _en, _sk, make, is_worn in CANDIDATES:
        for fname, fid in FRAMES:
            r = copy.deepcopy(base[fid])
            r["id"] = f"acc-{cid}-{fname}"
            items = make()
            if is_worn:
                cat = r["parts"][1]
                cat["children"] = cat.get("children", []) + items
            else:
                # world items are drawn before the cat so the cat stays in front
                r["parts"] = [r["parts"][0]] + items + r["parts"][1:]
            r["bounds"][4] = max(r["bounds"][4], 5.2)      # head-room for the floating star / tall hats
            out.append(r)
    return out


# ---------------------------------------------------------------- sheets
BG = {"day": (170, 205, 240), "night": (28, 36, 78)}
FONT = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"


def load_frame(cid, fname):
    """The raw render pasted onto a common canvas so the world origin (the catalog anchor) lands on the same pixel."""
    path = f"{RENDERS}/L0/acc-{cid}-{fname}.png"
    im = Image.open(path).convert("RGBA")
    cat = {e["id"]: e for e in json.load(open(f"{RENDERS}/catalog.json"))}[f"acc-{cid}-{fname}"]
    ax, ay = cat["anchor"][0] * im.width, (1 - cat["anchor"][1]) * im.height
    return im, ax, ay


def build_sheets():
    W, H, AX, AY = 1500, 1300, 750, 800                       # common canvas (px) and the anchor on it
    canon = {}
    for cid, *_ in CANDIDATES:
        for fname, _fid in FRAMES:
            im, ax, ay = load_frame(cid, fname)
            c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            c.paste(im, (round(AX - ax), round(AY - ay)), im)
            canon[(cid, fname)] = c
    # one common crop = the union of everything (so rows are comparable); real size scales the plain cat to 540 px
    box = None
    for c in canon.values():
        bb = c.getchannel("A").getbbox()
        box = bb if box is None else (min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]), max(box[3], bb[3]))
    plain = None
    for (cid, _f), c in canon.items():
        if cid == "plain":
            bb = c.getchannel("A").getbbox()
            plain = bb if plain is None else (min(plain[0], bb[0]), min(plain[1], bb[1]), max(plain[2], bb[2]), max(plain[3], bb[3]))
    cw, ch = box[2] - box[0], box[3] - box[1]
    print("common crop", cw, "x", ch, " plain cat+bed width", plain[2] - plain[0])
    make_sheet(canon, box, 1.0, "sheet.png", None)
    # real size: the app shows the 860 px wide buddy frame at 138-180 pt = ~540 px at @3x -> scale 540/860
    make_sheet(canon, box, 540 / 860, "sheet-real-size.png", 540)


def make_sheet(canon, box, k, name, cell_w):
    cw, ch = box[2] - box[0], box[3] - box[1]
    if cell_w is None:
        k = 520 / cw                                          # overview: every cell 520 px wide
    cell_w, cell_h = round(cw * k), round(ch * k)
    label_w, pad, head = 330, 10, 50
    cols = len(FRAMES) * 2                                    # per frame: day + night
    font = ImageFont.truetype(FONT, 28)
    small = ImageFont.truetype(FONT, 22)
    sheet_w = label_w + cols * (cell_w + pad) + pad
    sheet_h = head + len(CANDIDATES) * (cell_h + pad) + pad
    sheet = Image.new("RGB", (sheet_w, sheet_h), (245, 245, 245))
    d = ImageDraw.Draw(sheet)
    for i, (fname, _fid) in enumerate(FRAMES):
        for j, bgn in enumerate(("day", "night")):
            x = label_w + (i * 2 + j) * (cell_w + pad) + pad
            d.text((x + 6, 10), f"{fname} ({bgn})", fill=(30, 30, 30), font=small)
    for r, (cid, en, sk, _m, _w) in enumerate(CANDIDATES):
        y = head + r * (cell_h + pad) + pad
        d.text((10, y + 10), f"{r}. {en}", fill=(20, 20, 20), font=font)
        d.text((10, y + 48), sk, fill=(70, 70, 70), font=small)
        for i, (fname, _fid) in enumerate(FRAMES):
            c = canon[(cid, fname)].crop(box).resize((cell_w, cell_h), Image.Resampling.LANCZOS)
            for j, bgn in enumerate(("day", "night")):
                x = label_w + (i * 2 + j) * (cell_w + pad) + pad
                tile = Image.new("RGBA", (cell_w, cell_h), BG[bgn] + (255,))
                tile.alpha_composite(c)
                sheet.paste(tile.convert("RGB"), (x, y))
    sheet.save(f"{OUT}/{name}")
    print("wrote", f"{OUT}/{name}", sheet.size)


def main():
    os.makedirs(OUT, exist_ok=True)
    if "--sheets" not in sys.argv:
        if not os.path.exists("build/buddy/animal-cat-closed.obj"):
            subprocess.check_call([sys.executable, "tools/render/buddy_cat_obj.py"])
        recs = build_recipes()
        with open(f"{OUT}/accessory_recipes.json", "w") as f:
            json.dump(recs, f, indent=1, ensure_ascii=False)
        subprocess.check_call(["swift", "tools/render/render_sprites.swift", f"{OUT}/accessory_recipes.json", RENDERS])
    build_sheets()


if __name__ == "__main__":
    main()
