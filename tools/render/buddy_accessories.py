#!/usr/bin/env python3
"""Renders the sleep buddy's six cat accessories as TRANSPARENT LAYERS, one per accessory and pose, that the app
stacks over the shipped cat frame (assets/buddy/buddy-cat-<pose>.png). The owner may wear one item per group at the
same time (head + face + by the bed), so each item is its own layer.

    assets/buddy/accessories/buddy-acc-<id>-<pose>.png     6 ids x 8 poses = 48 PNGs, EXACTLY the size and crop of
                                                           the shipped buddy-cat-<pose>.png, transparent except for the
                                                           accessory's visible pixels
    ids:   nightcap, top-hat, builder-helmet (head) | sunglasses (face) | fish-bowl, rug (by the bed)
    poses: awake, blink, mid, asleep, happy, wink, arch-1, arch-2

How it works: the recipes are the shipped buddy recipes (make_recipes.buddy_recipes()) plus the accessory (the parts
come from accessory_proof.py). In a LAYER render the bed and every part of the cat are depth-only occluders
(`"occluder": true` in render_sprites.swift: depth written, no colour) and there is no shadow floor (`"floor": false`;
the shipped frame already holds the cat's floor shadow), so only the accessory's visible pixels get colour: the back of
a hat behind the head and the part of the rug under the bed are missing from the layer. Every worn item is a child of the
cat's `body` group, so it follows the pose (head up / down, arched back, ...).

The crop is derived, not hard-coded: the eight plain cat frames are rendered again and cropped exactly like
buddy_finish.py does (union of the alpha boxes + 8 px margin); that crop must reproduce the shipped frames
pixel for pixel, otherwise the script stops. Layers use the same rectangle.

Pixel check (the acceptance test): shipped cat frame + layer, composited, against a full render (cat + accessory
together, with the floor shadow) cropped the same way. Printed per accessory: the share of pixels that differ by more
than 8 levels in any channel and the maximum difference. What remains besides antialiasing: the accessory's shadow on the
cat and on the floor (a layer cannot darken the frame below it).

The rug colour: Kenney's rugRound is red; `RUG_COLOUR` below picks what ships (the night blue); a proof of all three
colours is written to build/11b5b/rug-colours.png. Change the one constant and rerun to re-render.

Outputs: assets/buddy/accessories/*.png, docs/previews/buddy_accessories.png (rows = accessories, columns = poses, then
combinations stacked the way the app does it), build/11b5b/real-size.png (the cat ~540 px wide, day and night),
build/11b5b/rug-colours.png; scratch renders in build/11b5b/renders/. Never touches assets/buddy/buddy-cat-*.png,
assets/sprites or SleepHole/.

usage (from the repo root; the render step needs the Bash sandbox OFF, ModelIO loads empty models inside it):
    python3 tools/render/buddy_accessories.py            # render everything, write the layers, check, previews
    python3 tools/render/buddy_accessories.py --no-render  # reuse build/11b5b/renders, redo crop / check / previews
    python3 tools/render/buddy_accessories.py --imagesets  # only copy the 48 layers into the asset catalog (no render)
Every run ends by copying the 48 layers into SleepHole/Resources/Assets.xcassets/buddy-acc-<id>-<pose>.imageset
(+ Contents.json: universal, 2x, like the cat frames); the imagesets are byte-identical copies of the PNGs.
Needs build/buddy/ (python3 tools/render/buddy_cat_obj.py writes it) and the raw Kenney bundle.
"""
import copy
import json
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import accessory_proof as ap  # noqa: E402
import make_recipes as mr  # noqa: E402

WORK = "build/11b5b"
RENDERS = WORK + "/renders"
OUT = "assets/buddy/accessories"
SHIPPED = "assets/buddy"
PREVIEW = "docs/previews/buddy_accessories.png"
POSES = ["awake", "blink", "mid", "asleep", "happy", "wink", "arch-1", "arch-2"]
MARGIN = 8                                  # buddy_finish.py
FONT = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"

# ---- the rug colour (the owner picks later): name -> (carpet, darker ring). "kenney" = the original red.
RUG_COLOURS = {"kenney": ("#f05e57", "#9b4c49"), "night-blue": ("#3c4c9e", "#2a3679"), "sage": ("#93b392", "#6e8f6f")}
RUG_COLOUR = "sage"

# id -> (group, builder). The accessory parts come from accessory_proof.py.
RUG_WIDTH, RUG_AT = 3.0, [0.6, 0.0, -0.3]
BOWL_AT = [1.6, 0.0, 0.3]
RUG_SRC = ap.obj(ap.FURN, "rugRound")


def bowl_parts():
    return [ap.fitted(ap.obj(ap.FOOD, "bowl"), 1.1, BOWL_AT),
            ap.fitted(ap.obj(ap.FOOD, "fish"), 0.75, [BOWL_AT[0], 0.22, BOWL_AT[2]], axis="z", rot=20)]


def rug_parts(colour):
    p = [ap.fitted(ap.obj(ap.FURN, "rugRound"), RUG_WIDTH, RUG_AT)]     # moved / shrunk to fit the shared crop
    if colour != "kenney":
        p[0]["src"] = make_rug_obj(colour)           # same geometry, other material colours
    return p


def make_rug_obj(colour):
    """Copy Kenney's rugRound.obj/.mtl into build/11b5b/rugs/ with the two material colours replaced."""
    d = WORK + "/rugs"
    os.makedirs(d, exist_ok=True)
    name = f"rug-{colour}"
    base = mr.ROOT + RUG_SRC
    shutil.copyfile(base + ".obj", f"{d}/{name}.obj")
    text = open(f"{d}/{name}.obj").read().replace("mtllib rugRound.mtl", f"mtllib {name}.mtl")
    open(f"{d}/{name}.obj", "w").write(text)
    carpet, dark = RUG_COLOURS[colour]
    rgb = lambda h: " ".join(f"{int(h[i:i + 2], 16) / 255:.6f}" for i in (1, 3, 5))
    with open(f"{d}/{name}.mtl", "w") as f:
        f.write(f"newmtl carpet\nKa 0 0 0\nKd {rgb(carpet)}\nKs 0.33 0.33 0.33\n\n"
                f"newmtl carpetDarker\nKa 0 0 0\nKd {rgb(dark)}\nKs 0.33 0.33 0.33\n")
    return f"@{d}/{name}"


ACCESSORIES = [("nightcap", "head", ap.a_nightcap), ("top-hat", "head", ap.a_top), ("builder-helmet", "head", ap.a_hard),
               ("sunglasses", "face", ap.a_sunglasses), ("fish-bowl", "bed", bowl_parts),
               ("rug", "bed", lambda: rug_parts(RUG_COLOUR))]
WORN = {"head", "face"}
COMBOS = [("nightcap + sunglasses + fish-bowl", ["fish-bowl", "sunglasses", "nightcap"]),
          ("top-hat + sunglasses + rug", ["rug", "sunglasses", "top-hat"]),
          ("builder-helmet + rug", ["rug", "builder-helmet"]),
          ("sunglasses alone", ["sunglasses"])]


# ---------------------------------------------------------------- recipes
def mark_occluders(part):
    part["occluder"] = True
    for c in part.get("children", []):
        mark_occluders(c)


def with_item(base, items, worn, layer, rid):
    r = copy.deepcopy(base)
    r["id"] = rid
    r["fixedBounds"] = True                      # the canvas = the plain frame's, whatever the item sticks out of
    if layer:
        for p in r["parts"]:
            mark_occluders(p)
        r["floor"] = False
    items = copy.deepcopy(items)
    if worn:
        cat = r["parts"][1]
        cat["children"] = cat.get("children", []) + items
    else:                                        # world items first; the cat stays in front by depth anyway
        r["parts"] = [r["parts"][0]] + items + r["parts"][1:]
    return r


def build_recipes():
    base = {r["id"]: r for r in mr.buddy_recipes()}
    out = [copy.deepcopy(base[f"buddy-cat-{p}"]) for p in POSES]
    for aid, grp, make in ACCESSORIES:
        for p in POSES:
            b = base[f"buddy-cat-{p}"]
            out.append(with_item(b, make(), grp in WORN, True, f"lay-{aid}-{p}"))
            out.append(with_item(b, make(), grp in WORN, False, f"full-{aid}-{p}"))
    for colour in RUG_COLOURS:                    # proof only: full renders of every rug colour
        for p in ("awake", "asleep"):
            out.append(with_item(base[f"buddy-cat-{p}"], rug_parts(colour), False, False, f"rugproof-{colour}-{p}"))
    return out


def render():
    shutil.rmtree(RENDERS, ignore_errors=True)
    os.makedirs(WORK, exist_ok=True)
    if not os.path.exists("build/buddy/animal-cat-closed.obj"):
        subprocess.check_call([sys.executable, "tools/render/buddy_cat_obj.py"])
    recs = build_recipes()
    with open(WORK + "/recipes.json", "w") as f:
        json.dump(recs, f, indent=1, ensure_ascii=False)
    subprocess.check_call(["swift", "tools/render/render_sprites.swift", WORK + "/recipes.json", RENDERS])


# ---------------------------------------------------------------- crop + pixel check
def raw(rid):
    return Image.open(f"{RENDERS}/L0/{rid}.png").convert("RGBA")


def derive_crop():
    """buddy_finish.py's rectangle, from the plain cat renders; verified against the shipped frames."""
    frames = {p: raw(f"buddy-cat-{p}") for p in POSES}
    W, H = frames["awake"].size
    assert all(im.size == (W, H) for im in frames.values())
    boxes = [im.getchannel("A").getbbox() for im in frames.values()]
    crop = (max(0, min(b[0] for b in boxes) - MARGIN), max(0, min(b[1] for b in boxes) - MARGIN),
            min(W, max(b[2] for b in boxes) + MARGIN), min(H, max(b[3] for b in boxes) + MARGIN))
    for p in POSES:
        mine = np.asarray(frames[p].crop(crop), dtype=np.int16)
        ship = np.asarray(Image.open(f"{SHIPPED}/buddy-cat-{p}.png").convert("RGBA"), dtype=np.int16)
        assert mine.shape == ship.shape, f"crop {crop} gives {mine.shape}, shipped {ship.shape}"
        d = np.abs(mine - ship).max()
        assert d == 0, f"the plain {p} render differs from the shipped frame (max {d}) - was the cat re-rendered?"
    print(f"crop {crop} of {W}x{H} -> {crop[2] - crop[0]}x{crop[3] - crop[1]}; the 8 plain renders equal the shipped frames")
    return crop, (W, H)


def over(bg_rgb, *layers):
    im = Image.new("RGBA", layers[0].size, bg_rgb + (255,))
    for l in layers:
        im.alpha_composite(l)
    return im


def make_layers(crop, size):
    os.makedirs(OUT, exist_ok=True)
    grey = (200, 200, 200)
    total, report = 0, {}
    for aid, _g, _m in ACCESSORIES:
        diffs, maxd, n_layer, n_all, n_bad_layer, clipped = [], 0, 0, 0, 0, []
        for p in POSES:
            full_raw = raw(f"lay-{aid}-{p}")
            assert full_raw.size == size, f"{aid}/{p}: canvas {full_raw.size} != {size}"
            a = full_raw.getchannel("A")
            # clipping: visible pixels of the layer outside the shared crop (or touching its edge)
            outside = int(np.asarray(a).astype(bool).sum() - np.asarray(a.crop(crop)).astype(bool).sum())
            layer = full_raw.crop(crop)
            bb = layer.getchannel("A").getbbox()
            if outside or (bb and (bb[0] == 0 or bb[1] == 0 or bb[2] == layer.width or bb[3] == layer.height)):
                clipped.append((p, outside, bb))
            path = f"{OUT}/buddy-acc-{aid}-{p}.png"
            layer.save(path, optimize=True)
            total += os.path.getsize(path)
            cat = Image.open(f"{SHIPPED}/buddy-cat-{p}.png").convert("RGBA")
            assert cat.size == layer.size
            comp = np.asarray(over(grey, cat, layer), dtype=np.int16)[..., :3]
            full = np.asarray(over(grey, raw(f"full-{aid}-{p}").crop(crop)), dtype=np.int16)[..., :3]
            d = np.abs(comp - full).max(axis=2)
            lay_mask = np.asarray(layer.getchannel("A")) > 0
            diffs.append(int((d > 8).sum())); maxd = max(maxd, int(d.max()))
            n_all += d.size; n_layer += int(lay_mask.sum()); n_bad_layer += int(((d > 8) & lay_mask).sum())
        report[aid] = (sum(diffs) / n_all, maxd, n_bad_layer / max(1, n_layer), diffs, clipped)
    print(f"\n48 layers -> {OUT}  ({total / 1024:.0f} KiB)")
    print("pixel check (shipped frame + layer vs full render; >8 levels in any channel):")
    for aid, (share, maxd, share_layer, diffs, clipped) in report.items():
        print(f"  {aid:15s} differing {share * 100:.4f} % of all pixels, {share_layer * 100:.2f} % of the layer's pixels, "
              f"max diff {maxd}; per pose {dict(zip(POSES, diffs))}")
        for p, outside, bb in clipped:
            print(f"      CLIPPED in {p}: {outside} visible px outside the crop, layer bbox {bb} in {layer.size}")
    return total


# ---------------------------------------------------------------- previews
def layer(aid, p):
    return Image.open(f"{OUT}/buddy-acc-{aid}-{p}.png").convert("RGBA")


def stacked(ids, p, scale=1.0):
    cat = Image.open(f"{SHIPPED}/buddy-cat-{p}.png").convert("RGBA")
    # the app's order: by the bed (under the cat's own hat), then face, then head - the layers cannot overlap otherwise
    for aid in ids:
        cat.alpha_composite(layer(aid, p))
    if scale != 1.0:
        cat = cat.resize((round(cat.width * scale), round(cat.height * scale)), Image.Resampling.LANCZOS)
    return cat


def build_preview():
    cw = 300
    ch = round(974 * cw / 860)
    label_w, pad, head = 360, 8, 40
    font, small = ImageFont.truetype(FONT, 26), ImageFont.truetype(FONT, 20)
    rows = [(aid, [aid]) for aid, _g, _m in ACCESSORIES] + COMBOS
    W = label_w + len(POSES) * (cw + pad) + pad
    H = head + len(rows) * (ch + pad) + pad
    img = Image.new("RGB", (W, H), (236, 242, 250))
    d = ImageDraw.Draw(img)
    for i, p in enumerate(POSES):
        d.text((label_w + i * (cw + pad) + pad + 6, 8), p, fill=(30, 30, 30), font=small)
    for r, (label, ids) in enumerate(rows):
        y = head + r * (ch + pad) + pad
        if r == len(ACCESSORIES):
            d.line([(0, y - pad // 2 - 2), (W, y - pad // 2 - 2)], fill=(120, 120, 140), width=3)
        d.text((10, y + 10), label, fill=(20, 20, 20), font=font if len(label) < 20 else small)
        for i, p in enumerate(POSES):
            tile = Image.new("RGBA", (cw, ch), (236, 242, 250, 255))
            tile.alpha_composite(stacked(ids, p, cw / 860))
            img.paste(tile.convert("RGB"), (label_w + i * (cw + pad) + pad, y))
    img.save(PREVIEW)
    print("wrote", PREVIEW, img.size)


def build_real_size(crop):
    """The cat ~540 px wide (the phone shows the 860 px frame at ~180 pt = 540 px @3x), day and night background."""
    k = 540 / 860
    ch = round(974 * k)
    sets = [("awake: nightcap + sunglasses + fish-bowl", "awake", ["fish-bowl", "sunglasses", "nightcap"]),
            ("asleep: top-hat + rug", "asleep", ["rug", "top-hat"]),
            ("arch-2: builder-helmet + rug", "arch-2", ["rug", "builder-helmet"]),
            ("wink: sunglasses", "wink", ["sunglasses"])]
    bgs = [("day", (170, 205, 240)), ("night", (28, 36, 78))]
    small = ImageFont.truetype(FONT, 20)
    img = Image.new("RGB", (len(sets) * 560 + 20, 2 * (ch + 40) + 20), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for r, (_n, bg) in enumerate(bgs):
        for c, (label, p, ids) in enumerate(sets):
            x, y = 10 + c * 560, 10 + r * (ch + 40)
            tile = Image.new("RGBA", (540, ch), bg + (255,))
            tile.alpha_composite(stacked(ids, p, k))
            img.paste(tile.convert("RGB"), (x, y + 30))
            d.text((x, y + 4), label, fill=(20, 20, 20), font=small)
    p = f"{WORK}/real-size.png"
    img.save(p)
    print("wrote", p, img.size)


def build_rug_proof(crop):
    cw = 560
    ch = round((crop[3] - crop[1]) * cw / (crop[2] - crop[0]))
    names = list(RUG_COLOURS)
    small = ImageFont.truetype(FONT, 22)
    bgs = [(236, 242, 250), (28, 36, 78)]
    img = Image.new("RGB", (len(names) * 2 * (cw + 8) + 8, 2 * (ch + 36) + 8))
    d = ImageDraw.Draw(img)
    for r, bg in enumerate(bgs):
        d.rectangle([0, r * (ch + 36), img.width, (r + 1) * (ch + 36)], fill=bg)
        fg = (20, 20, 20) if r == 0 else (235, 238, 255)
        for i, n in enumerate(names):
            for j, p in enumerate(("awake", "asleep")):
                im = raw(f"rugproof-{n}-{p}").crop(crop).resize((cw, ch), Image.Resampling.LANCZOS)
                x, y = 8 + (i * 2 + j) * (cw + 8), r * (ch + 36)
                img.paste(im, (x, y + 32), im)
                d.text((x + 4, y + 4), f"{n} ({p})" + ("  <- ships" if n == RUG_COLOUR else ""), fill=fg, font=small)
    p = f"{WORK}/rug-colours.png"
    img.save(p)
    print("wrote", p, img.size)


IMAGESETS = "SleepHole/Resources/Assets.xcassets"      # relative to the repo root


def install_imagesets():
    """Copies every layer into <IMAGESETS>/buddy-acc-<id>-<pose>.imageset (+ Contents.json, 2x, like the cat frames).
    Runs on EVERY run (also with --no-render); it only copies the PNGs in OUT, it never re-renders them."""
    if not os.path.isdir(IMAGESETS):
        print(f"{IMAGESETS} not found (run from the repo root) - app asset catalog not updated")
        return
    n = 0
    for aid, _slot, _fn in ACCESSORIES:
        for p in POSES:
            name = f"buddy-acc-{aid}-{p}"
            d = os.path.join(IMAGESETS, name + ".imageset")
            os.makedirs(d, exist_ok=True)
            shutil.copyfile(os.path.join(OUT, name + ".png"), os.path.join(d, name + ".png"))
            contents = {"images": [{"filename": name + ".png", "idiom": "universal", "scale": "2x"}],
                        "info": {"author": "xcode", "version": 1}}
            with open(os.path.join(d, "Contents.json"), "w") as f:
                json.dump(contents, f, indent=2, separators=(",", " : "), ensure_ascii=False)
                f.write("\n")
            n += 1
    print(f"{n} imagesets updated in {IMAGESETS}")


def main():
    if "--imagesets" in sys.argv:
        install_imagesets()
        return
    if "--no-render" not in sys.argv:
        render()
    crop, size = derive_crop()
    make_layers(crop, size)
    install_imagesets()
    build_preview()
    build_real_size(crop)
    build_rug_proof(crop)


if __name__ == "__main__":
    main()
