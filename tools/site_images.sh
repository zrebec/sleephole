#!/bin/sh
# Usage: tools/site_images.sh SRC_DIR
# Turns the six store screenshots (SRC_DIR/NN-name.png) into site/img/NN-name.jpg, 660 px wide, JPEG ~80.
set -u
SRC="${1:?usage: site_images.sh SRC_DIR}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/site/img"
mkdir -p "$OUT"
for n in 01-town 02-today 03-night 04-morning 05-stats 06-town-night; do
  f="$SRC/$n.png"
  if [ ! -f "$f" ]; then echo "missing: $f (skipped)"; continue; fi
  sips -s format jpeg -s formatOptions 80 --resampleWidth 660 "$f" --out "$OUT/$n.jpg" >/dev/null \
    && echo "$n.jpg  $(wc -c < "$OUT/$n.jpg" | tr -d ' ') bytes"
done
