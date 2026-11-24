# tools/store – App Store marketing screenshots with a panorama

Turns plain simulator screenshots into 8 marketing images whose background is ONE continuous panorama
(evening -> night -> dawn, moon on the border of image 3 / 4, a growing isometric town from the app's own sprites
along the bottom, a low sun at the right end), with a headline + sub-line and the app screen in a drawn phone frame.
Languages en / sk / cs, sizes `large` 1320x2868 (6.9") and `medium` 1206x2622 (6.3"); output is RGB PNG, no alpha.

* `panorama.py` – renders the background at the large size (10560x2868); the medium size is a scaled copy,
  so slices always line up. Deterministic (fixed seed). Cached in `$TMPDIR/sleephole-store/panorama-large.png`
  and re-rendered when `panorama.py` changes.
* `compose.py` – the slices, headlines, phones. The `SLOTS` table at its top maps slot -> raw screenshot file name
  (slot 7 = `12-postcard.png`; a placeholder screen is drawn while that file is missing).
* `copy.json` – the texts (en / sk / cs); `\n` is a line break in the headline.

```
python3 tools/store/compose.py --lang en --size large --shots <raw screenshots dir> --out <out dir>
```

Writes `01.png … 08.png` and `panorama-preview.png` (all 8 side by side) into `--out`.
Needs Pillow + numpy and the macOS font Avenir Next.

Raw screenshots: plain simulator screenshots of the app (`build/store/<locale>/<large|medium>/`, git-ignored),
named `01-town`, `02-today`, `03-night`, `04-morning`, `05-stats`, `07-today-evening`, `08-sounds`, `12-postcard` (.png).
