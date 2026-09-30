# SleepHole 🌙🏗️

🇬🇧 English · 🇸🇰 [Slovensky](README.sk.md)

A personal iPhone app for a **regular sleep schedule**, in the spirit of SleepTown. In the evening you start a building, at night you leave your phone alone, and in the morning you get up with the alarm. Every night adds one building to your town: complete, unfinished or ruins. The town grows night by night. The tone is warm and never cruel 💙

<p align="center">
  <img src="docs/previews/app-guide.png" width="240" alt="Guide">
  <img src="docs/previews/app-night.png" width="240" alt="Building at night">
  <img src="docs/previews/app-town.png" width="240" alt="Town">
</p>

> A native Swift app (SwiftUI, SpriteKit, SwiftData) for iPhone only. **It never blocks anything** – it only notices when you leave it at night.
> The app speaks **English** (default) and **Slovak**; switch it in Settings.

---

## How a night works

| | Rule |
|---|---|
| 🔔 **Reminder** | a notification before bedtime (30 min by default) |
| 🏗️ **Start building** | only from **bedtime − 10 min** to **bedtime + 5 min**, otherwise the night is missed |
| 🎧 **Setup** | after starting you have until bedtime **+ 5 minutes** in other apps (podcast, bedtime story), then come back to SleepHole |
| 📱 **Night** | the screen may be off, but SleepHole must stay in the foreground. When you leave, **“⚠️ Come back!”** arrives and you have **10 s** to return, otherwise the building collapses |
| 📞 **Exceptions** | phone calls don't count. If iOS kills the app at night, it counts in your favour |
| ⏰ **Alarm** | rings for at most **2 minutes** (even in silent mode) and lights up the screen. Confirm you're up by **shaking** or with a **code** (at the earliest 30 min before wake-up) |
| 🏢 **Complete** | confirmed while the alarm rings (+100 🪙, every 7th complete night in a row +200 🪙) |
| 🚧 **Unfinished** | confirmed after the alarm stopped, at the latest within 60 min (+50 🪙). Your next good night finishes it |
| 🧱 **Ruins** | the building collapsed, the night was cancelled, or you didn't confirm getting up. Your next complete night repairs it 🛠️ (unless an unfinished building is waiting), otherwise flowers grow over it after a week 🌸 |
| 😴 **Nap** | in the afternoon, **30 or 60 min**, only in its window (**13:00–15:00** by default), **once a day**. Same rules as at night, 2 min setup, an alarm at the end. **It doesn't build**; complete **+50 🪙**, cut short **+25 🪙** |

**Levels** by the number of building nights (complete or unfinished):

| Nights | Unlocked | Buildings |
|---|---|---|
| 1–5 | L1 | family houses, apartment blocks |
| 6–15 | L1–L2 | + parks, lit streets, museums, libraries |
| 16–30 | L1–L3 | + town hall, school, fire station, police, hospital |
| 31+ | L1–L4 | + skyscrapers |

Every night one of the unlocked levels is picked at random, then a building from it. Buildings you don't have yet come first. The last 3 buildings never repeat.

---

## What already exists

- **The whole night:** start window, setup time, lock / app-switch detection, the “Come back” warning, call tolerance, alarm, confirmation by shaking or code, a result with sound.
- **Night screen:** a night sky with twinkling stars, the building rising from the bottom on its building site, an animated tower crane and a “breathing” *Building in progress* label.
- **Town (SpriteKit):** a borderless isometric map that grows from the centre in 4×4 blocks and fills in its own roads. Panning with inertia and pinch zoom like SimCity. Tap a building to see which night it's from and its state. The header shows buildings and population.
- **190 isometric sprites** rendered from Kenney 3D City Kits (CC0) by our own SceneKit renderer. Buildings L1–L4 with signs in Slovak and English (9 buildings have an EN variant), roads, scaffolding, ruins, cars and a 16-frame crane.
- **8 alarms:** Gentle pizzicato (default), Morning Mood (Grieg), Ode to Joy (music box), Chimes, Retro, Reveille (trumpet), Digital, Alarm! (aggressive). Gentle ones get louder slowly, aggressive ones play at full volume at once.
- **Today:** always two buttons, **🌙 Go to sleep** and **😴 Nap**. Outside their windows they're disabled and explain why.
- **🔥 Streak** of complete nights and **🪙 coins** (nights, streak bonus, naps).
- **Stats:** streak, night calendar with the story of each night, average start and wake-up, regularity, chart, naps, levels.
- **Level-up celebration** with confetti, **ruin repair** by a good night.
- **Achievements:** 12 of them (first building, 3/7/30 nights in a row, 10/50/100 nights built, first level 2/3 building, first skyscraper, first nap, ruin repaired), each pays +50 🪙 (big ones +200).
- **Town name** (tap it in the Town header) and a **weekly town journal** in Stats; on Monday morning the result screen shows how the finished week went.
- **Vibrations** when a night starts, when the phone locks, before the setup ends, with the “Come back!” warning and when you're back in time.
- **Sleep sounds:** brown, pink and white noise, rain on a tent and rain on a window, and four **sound stories** (cabin in the woods, a cave, a carpenter's workshop and the whole-night **journey** through six chapters – cabin, workshop, rising wind, a storm and a cave for shelter, an underground lake, quiet after the rain): a quiet bed with random scenes on top – footsteps, an axe, a saw, a pickaxe, a dog, an owl, distant thunder – different every night. They play exactly for the timer (1–60 min or all night), also during a night and with the screen off.
- **Backup:** export / import to a file and an automatic backup after every night (Files → On My iPhone → SleepHole).
- **First-run guide** (6 pages, language picker on the first one). The numbers in it come straight from the rules in the code. Before the first night a “Your first night” checklist appears too. Both are stored in the database.
- **Two languages:** English (default) and Slovak. The switch is at the top of Settings; the choice is stored in the database and applies immediately, without a restart. Everything is translated, including notifications, building names and the signs painted on buildings.
- **Settings:** language, bedtime, wake-up, reminder, wake code, night sound and alarm with preview, notification permission status.
- **Developer tools:** quick night (4 min) and test night (15 min), counting one test night for the town, night journal, detection test, launch arguments for agents.

**Data:** nights, guide progress and the chosen language live in SwiftData (SQLite) in the app's folder, settings in UserDefaults. The town is not stored – it's replayed from the saved nights every time.

---

## Project

```
SleepCore/        Swift package: night rules, schedule, levels, building picker, town layout, projection (no UI)
SleepHole/        iOS app: SwiftUI screens, AppModel, SpriteKit town, audio, detection, notifications
SleepHole/Resources/Localizable.xcstrings   every UI text (key = English text, Slovak translation)
SleepHoleTests/   app tests (hosted, Swift Testing)
assets/sprites/   190 PNG sprites (+ 9 English sign variants) + catalog.json      assets/audio/  alarms and sounds (CAF)
tools/render/     Kenney OBJ → isometric sprites (SceneKit), previews, town layout
tools/audio/      alarm synthesis, rain loops, sound-story samples + beds (numpy)
tools/i18n/       translation key check (keys.py), adding translations (add.py)
docs/             PLAN.md (decisions, SK) · IMPLEMENTATION_PLAN.md (for agents, EN) · IMPLEMENTATION_I18N.md · RUN_ON_IPHONE.md
project.yml       XcodeGen (.xcodeproj is generated, not in git)
```

### Run

```bash
brew install xcodegen
xcodegen generate && open SleepHole.xcodeproj     # then ▶ Run on the iPhone (guide: docs/RUN_ON_IPHONE.md)
```

### Tests

```bash
tools/coverage.sh            # SleepCore: 95 tests, ~97 % lines
tools/test_app.sh            # the app on the iPhone 16 Pro simulator: 81 tests, ~93 % lines
python3 tools/i18n/keys.py   # after a build: missing / untranslated keys in the catalog
```

More tools:
- `tools/sim_shot.sh`: a simulator screenshot (e.g. `-seedNights 60 -openTab town -lang sk`); always shuts the simulator down.
- `python3 tools/render/make_recipes.py` and `render_sprites.swift`: new sprites.
- `python3 tools/audio/make_alarms.py`: new alarms.

**For AI agents:** start in [`AGENTS.md`](AGENTS.md). Phase status and all findings are in [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).

---

## Status

| Phase | | Status |
|---|---|---|
| A | assets (sprites, sounds, pipeline) | ✅ |
| F0 | tooling, app on the iPhone | ✅ |
| F1 | SleepCore and tests | ✅ |
| F2 | the night without town graphics | ✅ |
| F3 | town (SpriteKit) | ✅ built, ⏳ waiting for real nights |
| F4 | levels, stats, backup, coins, nap | ✅ mostly, ⏳ building shop |
| I18N | English + Slovak | ✅ |
| F5 | living town | ⬜ |
| F6 | paid Apple account | ⬜ next |
| F7 | new buildings | ⬜ |

## What's next

**Soon**
- **First nights with the town (F3):** how the town grows from real nights.
- **Apple Developer Program (F6):**
  - the app won't expire after 7 days,
  - *time-sensitive* notifications break through Focus,
  - **AlarmKit** (a system alarm that rings even after an iOS restart),
  - later HealthKit and Apple Watch (sleep verification, a vibrating alarm on the wrist),
  - TestFlight.

**Building shop for 🪙**
- Prices: house 100, L2 200, L3 400, L4 1000. You stay “in the village” longer; the police arrive only after weeks.
- Still to decide: when a building is chosen, when coins are charged, and what happens if there aren't enough.

**F5: living town**
- Day and night by the real time, glowing lamps and windows.
- Little cars driving on the roads, a growing population.

**F7: more buildings**
- Mainly L3: post office, church, hotel, stadium, railway station, cinema, swimming pool.
- More L2 and L4 variants, later own models from Blender.

**Ideas (XS → XXL)**
| | |
|---|---|
| ~~XS~~ | ✅ vibrations when a night starts and when the phone locks |
| ~~S~~ | ✅ achievements, your own town name |
| M | a home-screen widget with the streak and a bedtime countdown (✅ the weekly “town journal” is done) |
| L | seasons: snow and Christmas trees in winter, autumn colours |
| XL | a Live Activity with the growing building on the lock screen, an Apple Watch app |
| XXL | a shared town with a partner or friends (iCloud), an App Store release |

---

## Licences and thanks

- **Graphics and some sounds:** [Kenney](https://kenney.nl) (CC0). Rendered and assembled by our own scripts in `tools/`.
- **Alarm melodies:** E. Grieg (*Peer Gynt*, 1875) and L. van Beethoven (*Symphony No. 9*, 1824), both public domain. Reveille and Alarm! are original. Everything is synthesised in `tools/audio/make_alarms.py`.
- **Sound stories:** Kenney's CC0 Impact Sounds, RPG Audio and Foley Sounds plus 50 CC0 field recordings from [Freesound](https://freesound.org) (authors in [`assets/audio/CREDITS-freesound.txt`](assets/audio/CREDITS-freesound.txt); fetched with `tools/audio/fetch_freesound.py`, cut and mixed by `tools/audio/make_stories.py`), arranged at random by the app (`SleepHole/Night/Stories.swift`).
- **Rain on a window:** “Rain on Windows, Interior, A” by [InspectorJ](https://freesound.org/s/346642/) (www.jshaw.co.uk), Freesound, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), made into a loop. Rain on a tent and the noises are synthesised (`tools/audio/make_rain.py`, `AudioKeeper`).
- **Inspiration:** [SleepTown](https://apps.apple.com/app/sleeptown/id1210251567) by Seekrtech.
