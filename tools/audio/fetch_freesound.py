#!/usr/bin/env python3
"""Downloads the CC0 Freesound recordings listed in tools/audio/freesound.json into assets/freesound/ (git-ignored,
like the Kenney bundle) and writes assets/audio/CREDITS-freesound.txt (committed, attribution).

    python3 tools/audio/fetch_freesound.py

Needs a free Freesound API key in ~/.freesound_key (never commit it – the repo is public). Uses the official API:
sound metadata + the high-quality preview (OGG); every sound must be licensed CC0, otherwise the script stops.
"""
import json
import os
import sys
import urllib.parse
import urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
MANIFEST = os.path.join(ROOT, "tools/audio/freesound.json")
RAW = os.path.join(ROOT, "assets/freesound")
CREDITS = os.path.join(ROOT, "assets/audio/CREDITS-freesound.txt")
API = "https://freesound.org/apiv2/sounds/{}/?"


def main():
    key = open(os.path.expanduser("~/.freesound_key")).read().strip()
    sounds = json.load(open(MANIFEST))["sounds"]
    os.makedirs(RAW, exist_ok=True)
    lines = []
    for sid, info in sounds.items():
        q = urllib.parse.urlencode({"fields": "id,name,username,license,url,previews", "token": key})
        meta = json.load(urllib.request.urlopen(API.format(sid) + q, timeout=30))
        if "publicdomain/zero" not in meta["license"]:
            sys.exit(f"{sid} {meta['name']} is not CC0: {meta['license']}")
        out = os.path.join(RAW, f"{sid}.ogg")
        if not os.path.exists(out):
            urllib.request.urlretrieve(meta["previews"]["preview-hq-ogg"], out)
        lines.append(f"{info['as']:<12} {sid:>7}  \"{meta['name']}\" by {meta['username']}  {meta['url']}")
        print(lines[-1])
    with open(CREDITS, "w") as f:
        f.write("Sound stories – CC0 recordings from Freesound.org (public domain, credited with thanks).\n"
                "Downloaded as high-quality previews via the Freesound API, then cut / mixed by "
                "tools/audio/make_stories.py.\n\n")
        f.write("\n".join(sorted(lines)) + "\n")
    print(len(lines), "sounds →", RAW)


if __name__ == "__main__":
    main()
