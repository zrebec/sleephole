#!/usr/bin/env python3
"""Pads animation frames (ids with a common prefix) to one canvas with a shared anchor, so the app can
flip frames without jitter. Updates size/anchor in catalog.json.

usage: python3 tools/render/align_frames.py assets/sprites o-crane-
"""
import json, os, sys
from PIL import Image

root, prefix = sys.argv[1], sys.argv[2]
path = os.path.join(root, "catalog.json")
cat = json.load(open(path))
frames = [e for e in cat if e["id"].startswith(prefix)]
# anchor point in pixels from the top-left of each frame
left = max(e["anchor"][0] * e["size"][0] for e in frames)
right = max((1 - e["anchor"][0]) * e["size"][0] for e in frames)
top = max((1 - e["anchor"][1]) * e["size"][1] for e in frames)
bottom = max(e["anchor"][1] * e["size"][1] for e in frames)
W, H = int(round(left + right)), int(round(top + bottom))
for e in frames:
    im = Image.open(os.path.join(root, e["file"])).convert("RGBA")
    canvas = Image.new("RGBA", (W, H))
    canvas.alpha_composite(im, (int(round(left - e["anchor"][0] * e["size"][0])),
                                int(round(top - (1 - e["anchor"][1]) * e["size"][1]))))
    canvas.save(os.path.join(root, e["file"]))
    e["size"] = [W, H]
    e["anchor"] = [round(left / W, 3), round(bottom / H, 3)]
json.dump(cat, open(path, "w"), indent=2, sort_keys=True, ensure_ascii=False)
print(f"{len(frames)} frames → {W}x{H}")
