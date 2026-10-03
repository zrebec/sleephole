#!/usr/bin/env python3
"""Finishes the sleep buddy sprites after render_sprites.swift: flattens <dir>/L0/*.png into <dir>/, crops ALL
frames with ONE common rectangle (the union of their non-transparent pixels + a small margin), so every frame keeps
the identical pixel size and the bed sits at exactly the same pixel in every frame (the renderer already gave all
frames the same canvas through `bounds`), rewrites <dir>/catalog.json (file, size, anchor) and builds the preview
sheet docs/previews/buddy_poses.png.

Last step: copies the four frames into the app's asset catalog (SleepHole/Resources/Assets.xcassets/<id>.imageset,
scale 2x), so a re-render updates the app.

usage (from the repo root):
    python3 tools/render/buddy_finish.py assets/buddy [docs/previews/buddy_poses.png]
"""
import json
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

ORDER = ["buddy-cat-awake", "buddy-cat-blink", "buddy-cat-mid", "buddy-cat-asleep"]
MARGIN = 8
IMAGESETS = "SleepHole/Resources/Assets.xcassets"      # relative to the repo root (the script runs from there)


def main():
    root = sys.argv[1]
    sheet = sys.argv[2] if len(sys.argv) > 2 else "docs/previews/buddy_poses.png"
    cat_path = os.path.join(root, "catalog.json")
    cat = {e["id"]: e for e in json.load(open(cat_path))}
    assert set(ORDER) <= set(cat), "run the renderer first"
    frames = {i: Image.open(os.path.join(root, cat[i]["file"])).convert("RGBA") for i in ORDER}
    sizes = {im.size for im in frames.values()}
    assert len(sizes) == 1, f"frames differ in size {sizes} - give every recipe the same `bounds`"
    W, H = sizes.pop()

    # one common crop = union of the alpha bounding boxes
    boxes = [im.getchannel("A").getbbox() for im in frames.values()]
    left = max(0, min(b[0] for b in boxes) - MARGIN)
    top = max(0, min(b[1] for b in boxes) - MARGIN)
    right = min(W, max(b[2] for b in boxes) + MARGIN)
    bottom = min(H, max(b[3] for b in boxes) + MARGIN)
    nw, nh = right - left, bottom - top

    out = []
    for i in ORDER:
        e = cat[i]
        frames[i].crop((left, top, right, bottom)).save(os.path.join(root, i + ".png"))
        ax, ay = e["anchor"]                        # normalized, y from the bottom (SpriteKit convention)
        e["file"] = i + ".png"
        e["size"] = [nw, nh]
        e["anchor"] = [round((ax * W - left) / nw, 4), round((ay * H - (H - bottom)) / nh, 4)]
        out.append(e)
    shutil.rmtree(os.path.join(root, "L0"), ignore_errors=True)
    json.dump(out, open(cat_path, "w"), indent=2, sort_keys=True, ensure_ascii=False)
    print(f"{len(ORDER)} frames -> {nw}x{nh} (crop {left},{top},{right},{bottom} of {W}x{H}); anchor {out[0]['anchor']}")

    # preview sheet: every frame on a night and a day background, with the frame names as labels
    cell_w = 400
    cell_h = round(nh * cell_w / nw)
    pad, label_h = 20, 36
    band_h = label_h + cell_h + pad
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
    except OSError:
        font = ImageFont.load_default()
    resample = getattr(Image, "Resampling", Image).LANCZOS
    img = Image.new("RGB", (pad + len(ORDER) * (cell_w + pad), 2 * band_h), "#0b1030")
    d = ImageDraw.Draw(img)
    for row, (bg, fg) in enumerate((("#0b1030", "#e8ecff"), ("#bfe3ff", "#0b1030"))):
        y = row * band_h
        d.rectangle([0, y, img.width, y + band_h], fill=bg)
        for c, i in enumerate(ORDER):
            x = pad + c * (cell_w + pad)
            small = Image.open(os.path.join(root, i + ".png")).resize((cell_w, cell_h), resample)
            img.paste(small, (x, y + label_h), small)
            d.text((x + 4, y + 8), i, fill=fg, font=font)
    img.save(sheet)
    print(sheet, img.size)

    install_imagesets(root)


def install_imagesets(root):
    """Copies <root>/<id>.png into <IMAGESETS>/<id>.imageset (+ Contents.json, 2x) for every frame."""
    if not os.path.isdir(IMAGESETS):
        print(f"{IMAGESETS} not found (run from the repo root) - app asset catalog not updated")
        return
    for i in ORDER:
        d = os.path.join(IMAGESETS, i + ".imageset")
        os.makedirs(d, exist_ok=True)
        shutil.copyfile(os.path.join(root, i + ".png"), os.path.join(d, i + ".png"))
        contents = {"images": [{"filename": i + ".png", "idiom": "universal", "scale": "2x"}],
                    "info": {"author": "xcode", "version": 1}}
        with open(os.path.join(d, "Contents.json"), "w") as f:
            json.dump(contents, f, indent=2, separators=(",", " : "), ensure_ascii=False)
            f.write("\n")
    print(f"{len(ORDER)} imagesets updated in {IMAGESETS}")


if __name__ == "__main__":
    main()
