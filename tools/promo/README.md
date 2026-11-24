# tools/promo – SleepHole promo video (X / YouTube)

Deterministic motion-graphics renderer: dark-blue sleepy look, real build-13 screenshots in the drawn phone frame of
`tools/store/compose.py` (imported, not modified), the app's own isometric sprites, a synthesised ambient bed
(numpy) plus the app's `fx_*.caf` sounds, two-pass `loudnorm` (about -16 LUFS, TP below -1.5 dB). Everything on screen is
text, so it works muted. Texts: `copy.json`, keyed by language (add `sk` / `cs` blocks, no code change).

```
python3 tools/promo/make_promo.py --format landscape --lang en --shots build/store/raw-2026-11/en/large --out build/promo --thumb
python3 tools/promo/make_promo.py --format vertical  --lang en --shots build/store/raw-2026-11/en/large --out build/promo --skip-audio
```
`--music <audio file>` (mp3 / wav / m4a / caf, read by ffmpeg) replaces the synthesised pad, plucks and rain with that
track; `--music-start <seconds>` (default 0) is the offset into it. The track is looped if too short, trimmed to the video,
levelled, faded in 1.5 s / out 2 s with the picture, ducked about 3 dB under the sound effects, then the same two-pass
loudnorm (about -16 LUFS) is applied. Without `--music` the synth is the default. `--mp4-name` sets another output file name.
Sound effects: `fx_wow` + `fx_coins` (1.1 s later) when the morning phone lands, like the app's complete-night sounds; never
`building_done`, `building_unfinished` or `building_ruin`.
`--stills-only` writes only `build/promo/frames/*.png`; `--skip-audio` reuses `build/promo/_audio.wav` (the audio is the same
for both formats). Output (git-ignored): `sleephole-promo-<lang>-16x9.mp4` (1920x1080) / `-9x16.mp4` (1080x1920), 30 fps,
H.264 High yuv420p crf 18, AAC 48 kHz stereo 192 kb/s, 44.0 s; `sleephole-thumb-<lang>.jpg` (1280x720, landscape run with `--thumb`).
Inputs: screenshots `01-town 03-night 04-morning 05-stats 07-today-evening 08-sounds 12-postcard` (.png, 1320x2868),
`assets/sprites`, `assets/audio`, the app icon. Needs Pillow, numpy, ffmpeg, Avenir Next. About 1 min per format.

| Time (s) | Scene | On-screen text |
|---|---|---|
| 0.0-4.2 | Stars, moon on an arc, icon + glow | SleepHole / Sleep on time. Grow a town. |
| 4.0-8.8 | Phone: 07-today-evening | Start a building at bedtime. |
| 8.6-13.4 | Phone: 03-night, dimmed sky, floating z | Put the phone away. / It builds while you sleep. |
| 13.2-18.0 | Phone: 04-morning, sky warms to dawn | Wake up to a finished building. |
| 17.8-24.8 | Isometric town, 30 buildings pop in (synced pops; `Town(seed=47)` keeps small houses from hiding behind big buildings; the counter rises 0.12 s after each pop starts) | Night by night, a town grows. / Night 1 ... Night 30 |
| 24.6-27.8 | Phone: 01-town | Your nights become a town. / Every finished night adds a building. |
| 27.6-33.0 | Three phones (vertical: a fan, postcard phone big in front): 05-stats, 12-postcard, 08-sounds | Streaks & stats / 30 postcards – almost all backed by a real study / Rain, noise or a sound story |
| 32.8-35.6 | Promise | No account. No ads. No tracking. |
| 35.4-44.0 | Call to action, fade out 43.1-44.0 | Join the free beta on TestFlight / departures.to/apps/23674 / English · Slovenčina · Čeština |
