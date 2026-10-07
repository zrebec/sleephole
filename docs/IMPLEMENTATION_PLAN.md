# SleepHole — Implementation Plan

> **Audience:** a coding agent (Claude Code, Codex, …) starting with **zero memory** of earlier sessions.
> This file and [`AGENTS.md`](../AGENTS.md) are the single source of truth. Product background and the owner's
> decisions (in Slovak) are in [`docs/PLAN.md`](PLAN.md); if the two disagree, **this file wins** for
> implementation details, and PLAN.md wins for product intent.
>
> Written 2026-09-29. Status of every phase is tracked in §0 — keep it up to date.

---

## 0. Status board (update after every checkpoint)

| Phase | Title | Status | Owner checkpoint |
|---|---|---|---|
| A | Assets: sprites + audio + render pipeline | ✅ done (2026-09-29) | reviewed `docs/previews/demo_town.png` |
| F0 | Tooling + empty app on the iPhone | ✅ done (2026-09-29) | app icon launches on owner's iPhone |
| F1 | `SleepCore` domain package + tests | ✅ done (2026-09-29), rules revised by owner → R2 | `swift test` green, owner reads rules summary |
| F2 | Night loop without town graphics | ✅ done (2026-09-30, first real night complete) | 2–3 real nights, detection verified |
| F3 | Town rendering (SpriteKit) | ✅ accepted by the owner 2026-10-03 (pan, two zoom levels, tap-to-inspect: "works first time"); the growth animation is still open, not blocking | town shows all past nights |
| F4 | Progression, level-ups, statistics, backup | 🟡 stats/backup/level-up/ruin repair done 2026-09-30; vibrations, achievements, town name, weekly journal done; shop next | one week of use |
| I18N | English (default) + Slovak, in-app switch stored in SQLite | ✅ done (2026-09-30), **confirmed by the owner 2026-10-03** ("works great", survives an app and a phone restart) | owner switches the language in Settings and checks both |
| LIM | Limits: town rename 1×/year (else 5 000 🪙), schedule change free on days 1–3 / first week (else streak reset) | ✅ done (2026-09-30), installed | owner tests rename + schedule change |
| UI | Look & feel: living sky, Today island, glass cards, micro-animations; UI-2: theme, splash/WOW, sounds, voice | 🟡 built + installed 2026-10-02; theme switch and voice confirmed 2026-10-03 (the owner keeps the voice off – he does not like it); the overall look still awaits his verdict | owner: "it looks nice now" |
| P1 | Night pause (D17) + away budget 30 s/night + alarm safety + expiry warning (B1–B6, B9) | 🟡 built + installed 2026-10-03; the alarm in silent mode confirmed; the pause itself not used yet – the owner tries it in the night 2026-10-04 → 05 | owner uses a pause in a real night |
| P2 | Sleep buddy: awake / asleep cat that faces the owner (plan A step 2, spec in §10 P2) + bug B19 | ✅ accepted by the owner 2026-10-04 ("the cat behaves as expected"; a real night with it) | owner sleeps with the buddy |
| P2b | The buddy is the hero of Today (no town there any more) + three tap reactions: purr, arched back, wink (spec in §10 P2b) | ✅ accepted by the owner 2026-10-04; his remark: the arched back has too few poses – left as it is until we render our own models (F7) | owner pets the cat on Today |
| SKY | City in Settings + real sun/moon on a semicircle (spec in §10 SKY) | 🟡 built, committed and installed 2026-10-04 17:29 (final build). City search, night sky, sun and moon confirmed by the owner on the interim build; only the final semicircle position (right of the title) still waits for his look | owner picks his city, sees the true sun/moon |
| F5 | Living town (day/night, lamps, cars) + Cube Pets residents (plan A/B/C) | ⬜ todo – its first part runs as phase TOWN-W (next row) | "I like looking at it" |
| TOWN-W | The town grows and has weather (owner 2026-10-07, spec in §10 TOWN-W): 0b warning when Time Sensitive Notifications are off, 1 roads first, 2 weather on Today (WeatherKit) → checkpoint A; 3 rain and snow in the town → B; 4 day and night in the town → C | 🟡 steps 1 (roads first) and 2 (weather badge on Today) built, reviewed, merged and committed 2026-10-07; the owner ran them from Xcode the same day (15:03): no weather badge – Apple refuses the WeatherKit token (B23, owner checks the App Services tab); roads not judged yet; step 0b (the warning for the Time Sensitive switch) built and reviewed 2026-10-07 afternoon, not committed; the tree with steps 0b + 1 + 2 was installed on the phone by Opus 2026-10-07 16:37 (the owner asked). **Checkpoint A passed the same evening** (roads ✓, the warning ✓, the Focus test with the switch on ✓; the weather still refused). Three follow-ups he approved before step 3: A1 the card on Today becomes a tappable triangle, A2 a second weather source (MET Norway), A3 the TestFlight preparation – see §10 TOWN-W | the owner sees the outlined empty block, the temperature on Today, rain / snow and the dark town at night |
| R4 | Closing the app during a night counts as leaving it (the owner's loophole finding 2026-10-04, spec in §10 R4) | 🟡 committed and installed by the owner 2026-10-07 07:44; his quick nights the same morning (journal pulled): closed + reopened in time → the building stands ✅, a phone restart → the building stands ✅, the notices arrive with the app closed ✅. Still to prove: closed and STAYED away → collapse; only one alarm when the app is reopened while the system alarm rings | swiping the app away and using the phone collapses the building |
| F6 | Paid Apple Developer Program: F6a Time Sensitive notifications, F6b AlarmKit backup + safety alarm (spec in §10 F6); later HealthKit, iCloud, TestFlight | 🟡 F6a on the phone since 2026-10-04 19:11 – the owner's Focus test of 2026-10-07 brought no warning because Time Sensitive Notifications were switched off in iOS (his finding the same day) → B21 closed, the app gets a warning for it (TOWN-W step 0b); **re-tested with the switch on 2026-10-07 evening: the warning arrives in a Focus (owner: "confirmed")**; F6b (AlarmKit) built and reviewed 2026-10-04 evening, installed by the owner himself ≈ 20:00 – it rang with the app swiped away; committed 2026-10-07; his remaining checks are listed in §10 F6 | the system alarm wakes the owner with the app swiped away |
| F7 | *(optional)* own / extended assets | ⬜ later | — |

**Rule:** work on the first phase that is not ✅, do only that phase, then stop and hand over to the
owner (see AGENTS.md "Checkpoint protocol"). Tick sub-tasks (`- [x]`) in this file as you finish them.
F4 and UI stay 🟡 only because they wait for the owner's time with the app (a week of use / his verdict on the look) –
they do not block P2. **What is really verified, feature by feature, is in §0a.**

## 0a. Verification board (owner request 2026-10-03 – keep it current)

"Built" is not "confirmed". Three levels, per feature:

* 🟢 **confirmed by the owner** on the iPhone (his words or his test result are on record – date in brackets)
* 📱 **ran on the iPhone** (seen in the app data pulled from the phone for the audit of 2026-10-03, or in the findings log), but
  the owner's explicit OK is not on record
* 🖥 **tests / simulator only** – installed on the phone, never exercised there
* ❌ **failed on the phone** – a bug is open (§11a)

When the owner confirms or rejects something, move the row the same day. Automated state on 2026-10-03 (evening):
SleepCore 220 tests green; app 250 tests, 91.96 % line coverage (2026-10-07, roads first + weather + step 0b).

### Night and nap
| | Feature | Evidence |
|---|---|---|
| 🟢 | Lock vs. leaving the app (detection) | device log #2, all scenarios (2026-09-29) |
| 🟢 | App survives a whole night, podcast during the setup | podcast test (2026-09-29) + the real nights since |
| 🟢 | Whole night: start → setup → alarm → confirm → building | F2 ✅; real nights since 2026-09-30 |
| 🟢 | Collapse after leaving the app once the setup is over | owner's quick nights (2026-09-29) |
| 🟢 | "Come back!" warning (two notifications) | owner (2026-10-03) |
| 🟢 | Phone call is excused | device log #2 (2026-09-29) |
| 🟢 | In-app alarm, also with the ringer switched off (silent mode) | owner (2026-10-03): "the alarm works with the ringer off"; again after a real night (2026-10-04) |
| 📱 | Confirm by wake code and by shake | both used on the phone |
| 📱 | Longer setup after an early start | owner's request 2026-09-30, in use since |
| 📱 | Nap 30 / 60 min | used on the phone |
| 📱 | Guide + first-night checklist | done on the phone |
| 📱 | Vibration at the start and on a return in time | owner's test 2026-09-30 (nothing vibrates in the background – iOS) |
| 🖥 | Outcome "unfinished" (confirm after the alarm stopped) | not happened on the phone since rules R3 |
| 🟢 | Closing the app and reopening it in time keeps the building (R4) | owner's quick night 2026-10-07; the journal shows the closure and the relaunch a few seconds later |
| 🟢 | A phone restart during a night keeps the building (R4) | owner's quick night 2026-10-07 (the journal: see §12, 2026-10-07) |
| 🟢 | Notices arrive with the app closed: "15 s of setup left", "SleepHole was closed" (no Focus) | owner 2026-10-07 |
| 🟢 | Warnings during a Focus (F6a, time sensitive) | owner 2026-10-07 (checkpoint A, the new build): with Time Sensitive Notifications switched on the "Come back" warning arrives during a Focus – "confirmed". In the morning nothing had arrived only because the switch was off (B21 closed) |
| 🟢 | Warning while Time Sensitive Notifications are off: a card on Today + a row in Settings (TOWN-W step 0b) | owner 2026-10-07 on the phone: switching the iOS switch off shows both, switching it on hides both – "works excellently". His wish: on Today a tappable triangle instead of the tall card (follow-up A1, §10 TOWN-W) |
| 🖥 | Closing the app and staying away collapses the building (R4) | not tried on the phone yet |
| 🖥 | Night pause (D17) | not used in any night up to 2026-10-06 → 07 (journal pulled 2026-10-07) |
| 🖥 | Away budget 30 s per night + its counter | installed 2026-10-03 |
| 🖥 | Safer alarm (B1 retry, B3 five backup notifications) | installed 2026-10-03 |
| 🖥 | Screen checks ignore the unlock after the alarm (B9) | installed 2026-10-03 |

### Town
| | Feature | Evidence |
|---|---|---|
| 🟢 | A good night adds its building to the town | owner's test (2026-09-29) |
| 🟢 | Town map: pan, two zoom levels, tap shows the building's details | owner (2026-10-03): "works first time" |
| 📱 | Town as a floating island over the sky, header card | on the phone since 2026-10-02, part of the UI verdict |
| 📱 | Today island | seen by the owner (he reported the 4th-house bug) |
| 📱 | Fix: the sleeping cat no longer stays over the Town tab | owner (2026-10-03): "not any more, hopefully OK" |
| 🖥 | Fix: island keeps its road and size after the 4th house | installed 2026-10-03, not checked by the owner yet |
| 🖥 | Scaffold, ruins, flowers after 7 days, ruin repair, finishing an unfinished building | never happened on the phone |
| 📱 | L2 buildings | two stand in the owner's town (journal pulled 2026-10-07) |
| 🖥 | Lit streets, L3–L4 buildings | not reached yet |
| 🖥 | English signs on buildings | the owner uses Slovak |
| 🟢 | Roads first: the street ring of every started block + one empty block ahead (TOWN-W step 1) | owner 2026-10-07 (checkpoint A): he sees the outlined empty block; that both blocks do not fit the screen without panning does not bother him – the camera stays as it is |
| ❌ | Weather badge on Today (TOWN-W step 2) | owner 2026-10-07 (his own Xcode build of 15:03): no badge – Apple refuses the WeatherKit token (`WDSJWTAuthenticatorServiceListener.Errors Code=2`), bug B23; the badge itself is checked only in the simulator with a simulated value. Still Code=2 after the install of 16:37 ("Refresh now"); the owner agreed to a second source, MET Norway (follow-up A2, §10 TOWN-W) |
| 📱 | Settings → Developer → Weather test (TOWN-W step 2) | owner 2026-10-07: he read "Last error" from it on the phone; the simulation there not tried on the phone yet |

### Coins, progress, statistics
| | Feature | Evidence |
|---|---|---|
| 🟢 | Coins 🪙 and streak 🔥 | owner (2026-10-03): streaks work, coins add up correctly |
| 📱 | Statistics: calendar, night story, averages, chart | run on his nights since 2026-09-30 |
| 📱 | Achievements + town name | in use on the phone |
| 📱 | Free schedule change + the monthly card (days 1–3) | both used on the phone |
| 🖥 | Rename dialog (free / typo fix / 5 000 🪙) | never used on the phone – a phone test would spend the yearly free rename |
| 🖥 | Paid schedule change (streak starts again) | never used on the phone |
| 🖥 | Jokers 🛡️ + fix B6 | never used on the phone – a phone test would spend the month's joker |
| 🖥 | Coin spending (`CoinSpend`) | never used on the phone |
| 🖥 | +30 🪙 for a night without a pause | first possible in the night 2026-10-03 → 04 |
| 🖥 | Coins 120 / 150 / 200 for L2–L4, +200 for every 7th night in a row | not reached yet |
| 🖥 | Level unlocks + the level-up celebration | first at building night 6 |
| 🖥 | Finished-week card of the weekly journal | first after the night 2026-10-04 → 05 |
| 🖥 | Regularity = start − bedtime (B5) | installed 2026-10-03 |

### Sound
| | Feature | Evidence |
|---|---|---|
| 🟢 | Voice (works) | owner (2026-10-03): works, he does not like it and keeps it switched off |
| 📱 | Sleep sounds + exact timer | owner (2026-10-03): works, but a stop was not remembered (B19) |
| 🟢 | B19 fix: a stop is remembered, switch "Play when the night starts" | owner (2026-10-04): the nap after a stop started silent – "hopefully OK" |
| 📱 | Sound stories | in use on the phone |
| 📱 | Sound effects, good-night splash, WOW of a finished building | quick nights on 2026-10-02 |
| 🖥 | The 5 newer alarms (birds, bowl, music box, kalimba, Bach) | no record of a phone test |
| 🖥 | The "journey" story (chapters through the night) | no record of a phone test |

### Look, texts, language
| | Feature | Evidence |
|---|---|---|
| 🟢 | English + Slovak with the in-app switch | owner (2026-10-03): works great, survives an app and a phone restart |
| 🟢 | Theme System / Light / Dark | owner (2026-10-03): accepted, switching works perfectly |
| 🟢 | Contrast (B7): solid card backing, readable disabled buttons and captions, calendar numbers in dark mode | owner (2026-10-04): "very good, even the statistics are well visible" |
| 🟢 | Full-width semicircle restored | installed 2026-10-04 17:37 after the owner rejected the small one |
| 🟢 | City in Settings: Apple Maps search, ✕ → ✓ (SKY) | owner (2026-10-03, interim build): "it works, Bratislava OK" |
| 🟢 | Real sky: night after the real sunset (SKY) | owner (2026-10-03, interim build): the night background shows |
| 🟢 | Sun / moon on the semicircle, the moon's real phase (SKY) | owner (2026-10-04, interim build): "exactly as expected, very satisfied"; the final geometry (right of the title, above the badges) is not installed yet |
| 📱 | Living sky, glass cards, micro-animations | awaiting "it looks nice now" |
| 📱 | Slower animations (`Motion.pace`) | built after his remark of 2026-10-02 |
| 🟢 | Sleep buddy (P2): asleep / awake cat on the night, nap and alarm screens | owner (2026-10-04): behaves as expected |
| 🟢 | Today = only the cat (no town there), three tap reactions: purr, arched back, wink (P2b) | owner (2026-10-04): behaves as expected; the arched back has too few poses – revisit with our own renders |
| 🖥 | "The app stops launching soon" card + the date in Settings (B2) | the profile now runs until 2027-10-03, so the card will not show by itself – Settings → About must show the new date; the card can be checked with `-expiresIn HOURS` in the simulator |

### Data, backup, tooling
| | Feature | Evidence |
|---|---|---|
| 🟢 | The app runs on the owner's iPhone | F0 ✅ |
| 📱 | Automatic backup after a real night | the backup file was on the phone at the audit |
| 📱 | Install over the cable + pulling the app's data | used for the audit |
| 🖥 | Manual backup export / import | no record of use on the phone |
| 🖥 | Store migration to the version with pauses | checked on a copy of the owner's store in the simulator |

---

---

## 1. Product in one paragraph

A personal, native **iPhone** app that builds the habit of a **fixed bedtime and wake time**. In the
evening the owner taps **"Začať stavbu"** (start building); the phone is then locked and left alone. In the
morning the app's own **alarm** rings and the owner confirms **"Vstal som"** (I'm up) in a short window.
Each night produces a building (or an unfinished building, or ruins) that is placed into a growing
isometric **low-poly town** (Kenney CC0 assets). Nothing is ever blocked — the app only **detects**
leaving the app. Tone: cute, warm, **never cruel**.

### Owner decisions that constrain the implementation (do not re-litigate)
| # | Decision |
|---|---|
| D1 | iPhone only, **native Swift / SwiftUI**. No Android, no PWA. |
| D2 | Free **Personal Team** signing for now (7-day provisioning). No paid-only APIs until F6. |
| D3 | **No blocking.** Do **not** use Screen Time APIs (FamilyControls / ManagedSettings / DeviceActivity). Only lifecycle detection. Any app switch counts; the app does not know/care which app. |
| D4 | **Graded outcome:** complete / unfinished / ruins (§5.4). |
| D5 | Classic **low-poly isometric city** look. |
| D6 | Before sleep: **only a reminder notification**. |
| D7 | Morning: **own alarm + wake-up confirmation** within a window. |
| D8 | **One fixed schedule**, the same every day. |
| D9 | Owner has an **Apple Watch** — relevant only in F6 (HealthKit). |
| D10 | Kenney CC0 assets first (done — rendered from the 3D kits), own assets later. |
| D11 | Motivation = **level unlocks + streaks/stats + living town**. Placement is automatic. |
| D12 | Work in **checkpointed phases**; the owner tests on the phone; **the owner commits** (agents never commit). |
| D13 | **Level unlocks** (owner, 2026-09-29): first 5 building nights only L1; next 10 → L1+L2; next 15 → L1–L3; from then on (the "next 20" and beyond) → L1–L4, i.e. everything. One random building per night. |
| D14 | UI language **Slovak** (with correct diacritics). Code, comments, docs for agents: English. **Superseded 2026-09-30:** English (default) + Slovak, see `docs/IMPLEMENTATION_I18N.md`; every UI string via `L("English key")`. |
| D16 | **Nap ("Odpočinok", owner 2026-09-30):** 30 or 60 min only; start only inside the nap window (default 13:00–15:00, inclusive – starting at 15:00 with 60 min lasts until 16:00); once per day; same detection rules as a night with a 2-min setup (`NapPlan.rules`); alarm at the end, confirm only when it is over (`earlyConfirmOverride = 0`); complete +50 🪙, cut short +25 🪙; never builds, never changes streaks/levels/stats of nights; stored as `NightRecord(isNap: true, id "nap-<date>")`. The home screen always shows BOTH buttons ("🌙 Ísť spať", "😴 Odpočinok"), disabled outside their windows with a reason. |
| D17 | **Night pause (owner 2026-10-02, built 2026-10-03):** intentional "🌙 Pause" button, 10 min per pause; 1st per night free, 2nd 50 🪙, 3rd 100, 4th 150 (+50 each); no pause in a night → +30 🪙; the building stays complete. Never turn a pause into a habit. |
| D18 | **Jokers 🛡️ (owner 2026-10-02, built):** one per calendar month: bronze 1 night (free, also automatic like Duolingo's streak freeze), silver 3 nights 1 000 🪙, gold 7 nights 5 000 🪙; a switched-on joker starts tonight, or last night if it went wrong ("repair"). Protected nights → `Outcome.excused` (streak waits, nothing built, no coins). Coins per complete night by level: 100 / 120 / 150 / 200, unfinished half. |
| D15 | **Night rules R2** (owner, 2026-09-29, supersedes the graded away-time of D4): start possible **only from bedtime − 10 min until bedtime + 5 min** (owner: critical; later = missed night); after starting, **5 min setup grace** in which the app may be in the background (podcast, bedtime story); after that **any user-initiated background collapses the building** like SleepTown (10 s accidental tolerance – agent's choice); screen off / locked is fine but the app must stay in the foreground; **phone calls are system-forced → excused**; killed by the system → owner's favour, but avoid it (background audio). Finish ("Vstal som") earliest **wake − 30 min**, by **shaking or typing a wake code** (code visible in Settings). The **alarm rings at most 2 min**. Confirm ≤ wake+15 → complete, ≤ wake+60 → unfinished, later → ruins. |

---

## 2. Environment & hard constraints

* **Mac:** macOS 26, Apple Silicon. **Xcode 27.0** (iOS 27 SDK, simulators "iPhone 17", "iPhone 18 Pro", …),
  XcodeGen 2.46, `ffmpeg`, ImageMagick, Python 3 + Pillow. Blender.app is installed too (not needed so far).
  ⚠️ Until the owner runs `sudo xcode-select -s /Applications/Xcode.app`, prefix Xcode commands with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (xcode-select still points to the CLT).
* **iPhone:** owner's own device, iOS 26 expected. Deployment target: **iOS 18.0** (SwiftData, Swift Charts,
  `SpriteView` all available; keeps options open).
* **Personal Team limits** (free Apple ID): app expires **7 days** after install → reinstall with Xcode
  "Run" (data survives because the bundle id stays the same). **Not available:** HealthKit, AlarmKit,
  FamilyControls, iCloud, push. **Available:** local notifications, Background Modes → *Audio*, SwiftData,
  CoreMotion (shake), SpriteKit.
* **Project generation:** use **XcodeGen** (`brew install xcodegen`) with a checked-in `project.yml`;
  the `.xcodeproj` is generated and git-ignored. Agents can edit YAML reliably; they cannot edit pbxproj reliably.
* **Git:** own repo (`main`, created in F0, owner commits). Tracked: code, docs, tools, **rendered**
  `assets/sprites` + `assets/audio` (CC0 derivatives, ~15 MB). **Not tracked:** the raw Kenney bundle
  (bought on itch.io; CC0 but 1.4 GB and it's Kenney's paid convenience bundle — never commit/redistribute it).
* **Sandbox note for agents:** the sprite renderer (SceneKit/ModelIO) cannot read model files inside the
  Claude Code sandbox; run it with the sandbox disabled (see §3.4).

---

## 3. Assets (phase A — DONE)

### 3.1 What exists
```
assets/
├── sprites/                     # ← ships in the app bundle as folder "sprites/"
│   ├── catalog.json             # manifest, see §3.2
│   ├── L0/ …                    # terrain, roads, overlays (scaffold/site/ruins), vehicles
│   ├── L1/ … L4/                # buildings by unlock level
│   └── LICENSE-Kenney.txt       # CC0
│   (human previews live in docs/previews/: contact_sheet.png, demo_town.png — NOT in the bundle)
├── audio/                       # ← ships in the bundle; CAF (linear PCM), notification-safe (≤30 s)
│   ├── alarm_gentle.caf         # 27 s pizzicato loop (Kenney)          (DEFAULT alarm, ramp 60 s)
│   ├── alarm_retro.caf          # 22 s retro loop (Kenney)              (ramp 60 s)
│   ├── alarm_morning.caf        # Grieg "Morning Mood" (PD), synthesised flute + pad (ramp 45 s)
│   ├── alarm_ode.caf            # Beethoven "Ode to Joy" (PD), music box (ramp 45 s)
│   ├── alarm_chimes.caf         # rising pentatonic chimes (ramp 30 s)
│   ├── alarm_bugle.caf          # own bugle call, natural bugle notes (ramp 10 s)
│   ├── alarm_digital.caf        # classic bip-bip-bip-bip (full volume)
│   ├── alarm_alert.caf          # aggressive radar-style chirps (full volume)
│   │   (all alarm_*.caf except gentle/retro are generated by tools/audio/make_alarms.py, 28.5 s, mono)
│   ├── night_start.caf  ui_confirm.caf  level_up.caf
│   ├── building_done.caf  building_unfinished.caf  building_ruin.caf
│   └── LICENSE-Kenney.txt
└── Kenney Game Assets All-in-1 3/   # raw 1.4 GB source bundle — git-ignored, only for re-rendering
```
Sprite counts: **L1 83** (63 family houses = 21 models × 3 colour variants, 14 small blocks, 6 big blocks on
2×2), **L2 10** (4 parks, 2 lit-street tiles, 2 museums, 2 libraries), **L3 5** (town hall, school, fire
station, police, hospital), **L4 11** (10 skyscrapers + 1 high-rise), **L0 65** (4 terrain, 17 road pieces,
8 overlays, 36 vehicle sprites = 9 vehicles × 4 directions).

### 3.2 `catalog.json` schema (the app loads only this + the PNGs)
```jsonc
{
  "id": "l3-police",           // unique, stable – persisted in the database, never rename shipped ids
  "level": 3,                  // 0 = support sprite, 1…4 = unlock level
  "kind": "building",          // building | park | road-lit | road | terrain | overlay | vehicle
  "nameSK": "Polícia",         // display name (Slovak)
  "footprint": [2, 2],         // tiles (only 1×1 and 2×2 exist)
  "file": "L3/l3-police.png",  // relative to the sprites folder
  "size": [644, 425],          // PNG pixel size
  "anchor": [0.46, 0.21],      // SpriteKit anchorPoint (y from bottom) = footprint centre on the ground
  "connects": "EW"             // roads / road-lit only: open edges ⊂ "NESW"
}
```
Id prefixes: `l1-…`–`l4-…` buildings, `t-…` terrain/roads, `o-…` overlays, `v-<vehicle>-<dir>` vehicles
(`dir` ∈ `sw se ne nw` = direction the car's front points on screen).

Overlays: `o-scaffold-1|2` (drawn over a growing building), `o-site-1|2` (building site shown at night
start), `o-ruin-1|2`, `o-ruin-flowers-1|2` (a ruin older than 7 days — "never cruel").

### 3.3 Projection contract (renderer ⇄ app, must match exactly)
* Grid: `col` grows along world **+x** (= **E**, screen down-right), `row` grows along **+z** (= **S**,
  screen down-left). N = −z (screen up-right), W = −x (screen up-left).
* Dimetric 2:1, one tile diamond = **TILE_W = 256**, **TILE_H = 128** scene points (1 sprite pixel = 1 point
  at camera scale 1).
* Tile/footprint centre `(x, z)` in tile units → scene position (SpriteKit, y up):
  ```
  func scenePoint(x: Double, z: Double) -> CGPoint {
      CGPoint(x: (x - z) * TILE_W / 2,
              y: -(x + z) * TILE_H / 2)
  }
  // 1×1 at (c, r): centre = (c, r);  2×2 with top-left cell (c, r): centre = (c + 0.5, r + 0.5)
  ```
* Every `SKSpriteNode` uses `anchorPoint = catalog.anchor` and `size = catalog.size` (points), and is
  positioned at `scenePoint(centre)`.
* **Draw order** (painter's algorithm): terrain & roads in a flat bottom layer; everything else sorted by
  `depth = (c + fw − 1) + (r + fd − 1)` (front-most covered tile), then by layer (building < vehicle <
  effect). Use `zPosition = depth * 10 + layerOffset`. `tools/render/demo_town.py` is a working reference
  implementation of projection + ordering — port it, don't re-invent it.

### 3.4 Re-rendering (only if assets change — F7 or bug fixes)
```bash
python3 tools/render/make_recipes.py                         # writes tools/render/recipes.json
swift tools/render/render_sprites.swift tools/render/recipes.json assets/sprites        # all
swift tools/render/render_sprites.swift tools/render/recipes.json assets/sprites <id>   # one sprite
python3 tools/render/contact_sheet.py assets/sprites        # docs/previews/contact_sheet.png
python3 tools/render/demo_town.py assets/sprites            # docs/previews/demo_town.png
```
* Needs the raw Kenney bundle under `assets/Kenney Game Assets All-in-1 3/`.
* **Must run outside the Claude Code sandbox** (`dangerouslyDisableSandbox: true`); inside it ModelIO
  silently loads empty scenes.
* Recipes are code (`make_recipes.py`): parts = Kenney OBJ + position/rotation/scale/texture variant,
  primitive boxes (plates, flags, scaffolds), and optional 3D sign boards with Slovak text.
* Never change an existing id; add new ids instead (ids are stored in users' databases).

---

## 4. Target repository layout

```
sleephole/
├── AGENTS.md  CLAUDE.md  .gitignore
├── project.yml                      # XcodeGen spec (F0)
├── SleepCore/                       # Swift package – pure logic, NO UIKit/SwiftUI/SpriteKit imports
│   ├── Package.swift
│   ├── Sources/SleepCore/
│   │   ├── Clock.swift              # injectable time source
│   │   ├── Schedule.swift           # fixed bedtime/wake → concrete night windows
│   │   ├── NightModels.swift        # NightEvent, NightLog, Outcome, NightResult
│   │   ├── NightEvaluator.swift     # graded outcome (§5.4)
│   │   ├── Progression.swift        # built-night count, unlocked levels, streaks (§5.5)
│   │   ├── BuildingPicker.swift     # random pick with levels + anti-repeat (§5.6)
│   │   ├── Catalog.swift            # Codable catalog entries (§3.2)
│   │   ├── TownLayout.swift         # lots, roads, placement (§7.1)
│   │   └── RoadTiles.swift          # neighbour mask → road sprite id
│   └── Tests/SleepCoreTests/        # Swift Testing (`import Testing`), XCTest fallback
├── SleepHole/                       # iOS app target
│   ├── App/SleepHoleApp.swift       # @main, ModelContainer, AppModel injection
│   ├── App/AppModel.swift           # @Observable app state machine (§6)
│   ├── Night/LifecycleMonitor.swift # lock vs leave detection (§5.3)
│   ├── Night/AudioKeeper.swift      # background audio: ambience + alarm (§6.3)
│   ├── Night/Notifications.swift    # reminder, nudge, backup alarm (§6.4)
│   ├── Night/ShakeDetector.swift
│   ├── Persistence/Models.swift     # SwiftData @Model types (§8)
│   ├── Persistence/Backup.swift     # JSON export/import
│   ├── UI/…                         # SwiftUI screens (§9)
│   ├── Town/TownScene.swift         # SpriteKit scene (§7)
│   ├── Town/IsoProjection.swift
│   ├── Resources/Localizable.xcstrings   # Slovak strings
│   ├── Resources/Assets.xcassets         # app icon, colours
│   └── Info.plist                   # UIBackgroundModes = [audio]
├── SleepHoleTests/                  # app-level tests (optional)
├── assets/ (see §3)   tools/render/ (see §3.4)   docs/
```
Bundle id: `sk.zrebec.sleephole` (must be unique for Personal Team; change the prefix if taken).

---

## 5. Domain logic — `SleepCore` (pure, fully unit-tested)

### 5.1 Time & schedule
```swift
public protocol Clock: Sendable { var now: Date { get } }
public struct SystemClock: Clock { public var now: Date { Date() } }
public final class FakeClock: Clock { public var now: Date; public func advance(_ s: TimeInterval) }

public struct TimeOfDay: Codable, Hashable { var hour: Int; var minute: Int }   // local wall-clock

public struct Schedule: Codable, Equatable {
    var bedtime: TimeOfDay          // default 22:30
    var wake: TimeOfDay             // default 06:30
    var reminderOffsets: [Int]      // minutes before bedtime, default [30]
}

/// A concrete night. The night's identity ("nightKey") is the calendar DATE OF THE MORNING,
/// e.g. the night 28→29 Sep has nightKey 2026-09-29. Stable across DST.
public struct NightWindow: Equatable {
    let key: NightKey               // y-m-d of the wake date (struct NightKey, "2026-09-29")
    let bedtime: Date               // scheduled
    let wake: Date                  // scheduled
    var startOpens: Date   { bedtime - 3h }            // earliest "Začať stavbu"
    var confirmOpens: Date { wake - 30min }            // early "Vstal som" allowed
    var confirmOnTimeUntil: Date { wake + 15min }      // on-time window end
    var confirmLateUntil: Date   { wake + 60min }      // after this the night is over (ruins)
}

extension Schedule {
    /// The night the user is "in" or "heading into" at `t`.
    func window(containing t: Date, calendar: Calendar) -> NightWindow {
        // candidate = the next wake occurrence strictly after (t - 60min)   (so the late-confirm
        //             window still belongs to this morning)
        // bedtime   = the latest bedtime occurrence before that wake
        //             (handles 22:30→06:30 and 00:30→08:00 alike)
        // return NightWindow(nightKey: ymd(wake), bedtime, wake)
    }
}
```
Tests: normal night, bedtime after midnight, DST forward/backward (Europe/Bratislava, 29 Mar / 25 Oct),
calling at 12:00, 21:00, 02:00, 06:50, 07:31.

### 5.2 Night log
Everything that happens during a night is an append-only event list (persisted immediately — the app may be
killed at any moment):
```swift
public enum NightEventKind: String, Codable {
    case started            // "Začať stavbu" tapped
    case locked             // phone locked (protected data became unavailable)
    case unlocked           // phone unlocked
    case leftApp            // app went to background while the phone was unlocked
    case returned           // app became active again
    case alarmFired
    case confirmed          // "Vstal som" / shake
    case appLaunched        // cold launch while a night was active (after a kill)
    case abandoned          // user explicitly cancelled the night
}
public struct NightEvent: Codable, Equatable { let kind: NightEventKind; let at: Date }
public struct NightLog: Codable, Equatable {
    let nightKey: DateComponents; let window: NightWindow
    var buildingId: String          // chosen at start (§5.6)
    var events: [NightEvent]
}
```

### 5.3 Away time (implemented: `NightEvaluator.awayIntervals / awaySeconds`)
Away intervals = `.leftApp` → first of `.returned` / `.locked` / `.confirmed` (or wake if never back),
clipped to [start, wake], **minus phone-call intervals** (`.callStarted` → `.callEnded`, excused as
system-forced). `.appLaunched` (the app had been killed) drops an open interval → owner's favour.
* After an unlock the phone returns to our app (it was foreground) → `.unlocked` then `.returned` within
  ~1 s. If `.returned` does not follow within **3 s**, the monitor appends `.leftApp` stamped with the
  unlock time (camera / notification opened from the lock screen).

### 5.4 Outcome — rules R2 (D15). Implemented: `SleepRules`, `NightEvaluator.evaluate / collapsedAt`
```swift
struct SleepRules { startDeadline = 5 min; setupGrace = 5 min; accidentalTolerance = 10 s; alarmDuration = 2 min }

collapsedAt(log):   graceEnd = start + setupGrace
                    for each away interval (a, b): from = max(a, graceEnd)
                        if b - from > accidentalTolerance → collapsed at from + tolerance
evaluate(log):
    not started, or started after bedtime + 5 min         → .missed   (UI disables the button anyway)
    abandoned or collapsedAt != nil                        → .ruins
    not confirmed, or confirmed after wake + 60 min        → .ruins
    confirmed after wake + 15 min                          → .unfinished
    else                                                   → .complete
windows: canStart = [bedtime − 10 min, bedtime + 5 min]; canConfirm = [wake − 30 min, wake + 60 min]
```
Tests: `EvaluatorTests` (22-row outcome table incl. podcast setup, accidental swipe, calls, camera from lock
screen, kill while locked, confirm edges).
The night screen shows a collapse **live** ("Stavba sa zrútila 🧱") when the owner returns; the night
still runs to the morning and the alarm still rings (the habit of getting up matters too).

### 5.5 Progression — levels (D13) and streaks
```swift
public struct Progression {
    /// "Building nights" = nights whose outcome produced a building.
    static func builtNights(_ results: [NightResult]) -> Int {
        results.filter { $0.outcome == .complete || $0.outcome == .unfinished }.count
    }
    /// Owner rule: nights 1–5 → L1; 6–15 → L1–2; 16–30 → L1–3; 31+ → L1–4 (everything).
    static let thresholds: [(minBuilt: Int, maxLevel: Int)] = [(0, 1), (5, 2), (15, 3), (30, 4)]
    static func unlockedMaxLevel(builtBefore n: Int) -> Int {   // n = built nights BEFORE tonight
        thresholds.last { n >= $0.minBuilt }!.maxLevel
    }
    /// Streak: consecutive nights (by nightKey) ending .complete. .unfinished neither extends nor breaks
    /// it (gentle); .ruins and .missed break it.
    static func currentStreak(_ results: [NightResult]) -> Int
    static func bestStreak(_ results: [NightResult]) -> Int
}
```
Level-up events (for F4 toast): when tonight's result moves `builtNights` across 5, 15 or 30.

### 5.6 Choosing tonight's building (at "Začať stavbu")
```swift
public struct BuildingPicker {
    /// 1. pick a LEVEL uniformly among 1…maxLevel  (so rare L2/L3 items actually appear;
    ///    picking uniformly over all sprites would drown L2–L4 in 83 L1 sprites)
    /// 2. inside the level pick uniformly among candidates, preferring ids not yet in the town,
    ///    then least-recently used; never the same id as the last 3 nights
    /// 3. kind "road-lit" is a valid pick (it upgrades streets, §7.3) – only if an unlit
    ///    straight road exists, otherwise re-pick
    func pick(maxLevel: Int, catalog: Catalog, town: [PlacedBuilding], recent: [String],
              rng: inout some RandomNumberGenerator) -> CatalogEntry
}
```
Seeded RNG in tests. The pick is stored in the `NightLog` at start so the night screen can show what is
being built.

---

## 6. App state machine & night services

### 6.1 `AppModel` (single `@Observable`, owned by the App)
```
enum Phase {
  case idle(next: NightWindow)                // daytime; shows town + "Dnes o 22:30"
  case canStart(window: NightWindow)          // now ≥ startOpens and no log yet
  case building(log: NightLog)                // started, before wake
  case alarm(log: NightLog)                   // wake reached, alarm ringing, waiting for confirm
  case result(NightResult)                    // outcome screen, then → idle
}

func refresh(now):                            // on launch, on foreground, every minute via timer
    window = schedule.window(containing: now)
    log = store.log(for: window.nightKey)
    switch:
      log == nil && now < window.startOpens                 → idle
      log == nil && now < window.confirmLateUntil           → canStart   (late start still allowed)
      log == nil                                            → finalize(missed) → idle(next)
      log.confirmed or now > window.confirmLateUntil        → finalize(log) → result
      now >= window.wake                                    → alarm
      else                                                  → building
```
`finalize` evaluates (§5.4), persists `NightResult`, places the building into the town (§7), plays the
matching sound, and is **idempotent** (keyed by nightKey).

### 6.2 `LifecycleMonitor` (UIKit notifications → NightEvents)
```swift
final class LifecycleMonitor {
    private var lockedAt: Date?
    private var pendingUnlockCheck: Task<Void, Never>?

    func start(appending: @escaping (NightEventKind) -> Void) {
        observe(UIApplication.protectedDataWillBecomeUnavailableNotification) {   // lock
            lockedAt = now; appending(.locked)
        }
        observe(UIApplication.protectedDataDidBecomeAvailableNotification) {      // unlock
            lockedAt = nil; appending(.unlocked)
            pendingUnlockCheck = Task { try? await Task.sleep(for: .seconds(3))
                if UIApplication.shared.applicationState != .active { appending(.leftApp /* at unlock */) } }
        }
        observe(UIApplication.didEnterBackgroundNotification) {
            // lock also backgrounds the app; the lock notification arrives FIRST
            let lockedJustNow = lockedAt.map { now - $0 < 1.5 } ?? false
            if !lockedJustNow && UIApplication.shared.isProtectedDataAvailable {
                appending(.leftApp); Notifications.scheduleNudge(in: 10)          // "Budova na teba čaká 🏗️"
            }
        }
        observe(UIApplication.didBecomeActiveNotification) {
            pendingUnlockCheck?.cancel(); appending(.returned); Notifications.cancelNudge()
        }
        // willResignActive alone (Control Center, Notification Center, Siri) is IGNORED
    }
}
```
* Requires a **device passcode** (protected-data notifications only fire with Data Protection). Check on
  the Settings screen and warn if `isProtectedDataAvailable` never changes (F2 spike).
* `UIApplication.shared.isIdleTimerDisabled = false` during the night — auto-lock is welcome.
* **F2 spike first:** build a tiny debug screen that logs every raw notification with timestamps, run it
  for one evening on the phone (lock, unlock, switch apps, pull Control Center, take a call) and verify the
  mapping above **before** building the rest of F2. Record findings in §12.

### 6.3 `AudioKeeper` — keeps the app alive overnight and rings the alarm
```swift
final class AudioKeeper {
    // Info.plist: UIBackgroundModes = ["audio"]
    // session: AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
    //          .playback IGNORES the silent switch → the alarm is audible in silent mode.
    let engine = AVAudioEngine()
    var ambience: AVAudioSourceNode      // generated brown/pink noise, or true silence (setting)
    var alarmPlayer: AVAudioPlayerNode   // alarm_gentle.caf / alarm_retro.caf, looped

    func beginNight(ambience: Ambience, volume: Float)   // start engine + ambience node
    func scheduleAlarm(at wake: Date)                     // a Task sleeping until `wake` (app is alive)
    func ringAlarm()                                      // stop ambience, loop alarm, ramp volume
                                                          //   0.3 → 1.0 over 60 s; STOP after
                                                          //   rules.alarmDuration (2 min) → .alarmStopped
    func stopAll()                                        // on confirm
    // handle AVAudioSession.interruptionNotification (calls): on .ended → restart engine
    // handle mediaServicesWereReset → rebuild engine
}
```
Ambience options (Settings): `Hnedý šum` (brown noise, default, very low volume), `Ružový šum`, `Ticho`
(silent buffer — still keeps the app alive). Generate noise in code; no audio asset needed.

### 6.4 Notifications (UserNotifications, all local)
| id | when | content (sk) | sound |
|---|---|---|---|
| `reminder-<offset>` | bedtime − offset, daily (`UNCalendarNotificationTrigger` repeats) | "O 30 minút je večierka. Čas sa chystať 🌙" | default |
| `nudge` | immediately on `.leftApp` after the setup grace (and at grace end if still away) | "Vráť sa do SleepHole, inak sa stavba o 10 s zrúti 🏗️" | default |
| `grace-end` | start + 4 min 30 s, only if in background | "Ešte 30 s na nastavenie – potom sa vráť do SleepHole 🌙" | default |
| `alarm-backup` | at wake, scheduled at start | "Dobré ráno! Potvrď vstávanie ☀️" | `alarm_gentle.caf` |
| `expiry` | installDate + 6 days 12:00 | "SleepHole zajtra vyprší – pripoj iPhone a spusti ho z Xcode." | default |

Cancel both `alarm-backup*` on confirm. Request authorization on first launch (onboarding).

### 6.5 Confirm: shake OR wake code (D15)
`ShakeDetector`: `motionEnded(.motionShake)` → confirm (only while `canConfirm`). Alternative: a numeric
**wake code** field; the code is set / shown in Nastavenia (default: random 4 digits generated on first
launch, stored in `@AppStorage("wakeCode")`). No plain "tap to confirm" button.

### 6.6 Phone calls
`CXCallObserver` (CallKit, no entitlement) → `.callStarted` when a call becomes active/incoming,
`.callEnded` when it ends. Only needed while a night is running.

---

## 7. Town

### 7.1 Layout — deterministic, grows outward from the centre (implemented: `TownLayout.swift`)
```
Grid is unbounded (Int coordinates, may be negative).
Road lines: every cell with col % 5 == 0 OR row % 5 == 0 is road → blocks of 4×4 lots,
            each block = four 2×2 quadrants.
Blocks are filled one at a time in spiral order: rings 1, 3, 5… (ring = max(|2bx+1|, |2by+1|)),
            inside a ring by angle of the block centre.
Inside a block: 1×1 buildings fill quadrants FRONT-first (SE, NE, SW, NW – nearest the viewer),
            2×2 buildings take whole free quadrants BACK-first (NW, SW, NE, SE). They meet in the middle.
            (First version used 3×3 blocks + ring-by-ring lot order → 2×2s could not fit and the town
             sprawled to radius 19 after 100 nights; now 14, see §12.)
Road visibility – ROADS FIRST (owner 2026-10-07, TOWN-W step 1; before: only road cells touching a building):
            a block's street ring = the 20 road cells around it (`TownLayout.ring(of:)`).
            Drawn (`drawnRoads`) = the rings of every started block (≥ 1 occupied lot) + the ring of the
            frontier block = the first block in spiral order with no occupied lot. Streets are always one
            block ahead of the houses, also in an empty town (it shows the first ring). Rings never
            disappear. Nothing about roads is stored – the town is replayed from the nights.
            `builtRoads` = the old rule (road cells touching an occupied lot, 8-neighbourhood).
Road sprite: mask of drawn N/E/S/W neighbours → catalog entry with that `connects`
             (lit cells → l2-road-lit-we / -ns; empty mask → crossroad fallback). `RoadTiles.swift`.
Street upgrade: the 4 unlit straight cells of the drawn streets that touch a building
             (`straightCells(in: drawnRoads) ∩ builtRoads`), nearest the centre, become lit –
             lamps stay next to houses, never on the empty block ahead.
```
Preview of the real logic: `DUMP_TOWN=… swift test --filter dumpTown` + `tools/render/layout_preview.py`
→ `docs/previews/layout_60_nights.png`.

### 7.2 Rendering (`TownScene: SKScene`, shown with `SpriteView`)
```
build(town):
    terrainLayer (z = -10_000): grass tile (alternate t-grass-a/b by (c+r)%2) under every cell
                                 inside the town's bounding box + 2-cell margin; roads on road cells
    objectLayer: for each PlacedBuilding → SKSpriteNode(texture: tex[state sprite])
        state sprite = complete → entry.file
                       unfinished → entry.file cropped (SKCropNode, bottom 60 %) + o-scaffold-N on top
                       ruins → o-ruin-N  (o-ruin-flowers-N once the ruin is ≥ 7 days old)
        position = scenePoint(centre), anchorPoint = entry.anchor, zPosition = depth*10 + layer
camera: SKCameraNode – SimCity-style SMOOTH free scrolling over one unbounded map (owner request; no
        "load the next block" paging like SleepTown): one-finger pan with inertia/deceleration, pinch zoom
        0.25…1.5 around the fingers, double-tap zooms in; clamp the camera to the town bounds + margin;
        start centred on the newest building. Performance: hide nodes outside the camera rect
        (simple culling on camera move) once the town exceeds ~150 sprites.
Textures: load lazily and cache by file; ~170 PNGs total, fine without atlases (atlas = later optimisation).
```
Growth animation (night screen and result screen): an `SKCropNode` whose mask is a rectangle rising from
the anchor; progress = elapsed / (wake − start). `o-site-N` under it, `o-scaffold-N` over it until complete.

### 7.3 Lit streets (`kind == "road-lit"`)
Picking `l2-road-lit-*` does not occupy a lot: it upgrades the **4 unlit straight road cells nearest to the
town centre** to lit ones (`EW` → `l2-road-lit-we`, `NS` → `l2-road-lit-ns`). Store as
`PlacedBuilding(kind: .streetUpgrade, cells: [...])`. At night (F5) each lamp gets an additive glow sprite.

### 7.4 Living town (F5)
* Day/night: tint the scene by local time (`colorBlendFactor` on a full-screen overlay): day 0, dusk/dawn
  gradients, night = deep blue 0.45. Lamp glows (radial gradient `SKTexture` generated in code) on lit roads,
  park lanterns; random warm window glints on buildings at night (small additive dots, seeded per building).
* Cars: 1 car per ~4 buildings (max 12). Each picks a random road path (BFS on drawn road cells), moves
  cell→cell at ~0.8 cells/s, sprite `v-<type>-<dir>` by movement direction (E→`se`, S→`sw`, W→`nw`, N→`ne`),
  offset slightly to the right-hand lane.
* Population counter: house 4, block 20, big block 60, civic 0 (+jobs), skyscraper 300.

---

## 8. Persistence (SwiftData) + settings
```swift
@Model final class NightRecord {            // one per nightKey
    @Attribute(.unique) var nightKey: String   // "2026-09-29"
    var bedtime: Date; var wake: Date
    var buildingId: String?
    var eventsJSON: Data                       // [NightEvent] – append + save after EVERY event
    var outcome: String?                       // nil while in progress
    var awaySeconds: Double?; var startedAt: Date?; var confirmedAt: Date?
}
@Model final class PlacedBuilding {
    var id: UUID; var nightKey: String; var catalogId: String
    var col: Int; var row: Int; var state: String      // complete | unfinished | ruins
    var createdAt: Date; var completedAt: Date?
}
// Settings via @AppStorage: bedtime, wake, reminderOffsets, ambience, ambienceVolume,
// alarmSound, installDate, onboardingDone, debugFastNights
```
Rules: the unfinished → complete upgrade happens when a later night is **complete**: the oldest
unfinished building becomes complete (bonus, "dostavaná"); the new building is placed as usual.
`Backup.swift`: export/import all records as one JSON file via `ShareLink` / `fileImporter`.

---

## 9. UI (SwiftUI, Slovak, dark-friendly, big touch targets)

| Screen | Content |
|---|---|
| **Dnes** (tab 1, default) | Phase-driven: *idle* → town preview + "Večierka o 22:30 · budíček 6:30" + streak; *canStart* → big button **Začať stavbu** + what will be built; *building* → dark night view: clock, growing building, "Zamkni telefón a dobrú noc 🌙", small "Zrušiť noc" (confirm dialog); *alarm* → huge **Vstal som** + "alebo zatras telefónom"; *result* → animation + outcome text + level-up banner |
| **Mesto** (tab 2) | full-screen `SpriteView(TownScene)`, tap building → name + night date + outcome |
| **Štatistiky** (tab 3, F4) | streak now/best, calendar (colour by outcome), avg start/confirm time, regularity = std-dev of start time (14 nights), Swift Charts line of start times, level progress "L2: ešte 3 noci" |
| **Nastavenia** (tab 4) | bedtime, wake, reminders, ambience + volume, alarm sound (preview), passcode check, backup export/import, "Ako to funguje", debug section (hidden behind 5 taps on version) |

Outcome copy (examples): complete → "Hotovo! Postavil si **Polícia** 🎉"; unfinished → "Budova je
rozostavaná – ďalšia dobrá noc ju dokončí 🚧"; ruins → "Dnes to nevyšlo. Aj to patrí k mestu – zajtra
nová šanca 🌱"; missed → "Včera sa nestavalo. Nič sa nedeje 💙". Never shame.

**Debug mode** (essential for testing without waiting for real nights): "Rýchla noc" sets a temporary
schedule bedtime = now + 1 min, wake = now + 4 min; plus an event-log viewer and "Simulovať 10 nocí" (fills
fake results to exercise town + levels). The `Clock` is injected everywhere, so this is trivial.

---

## 10. Phases, tasks, acceptance

### F0 — Tooling + empty app on the iPhone
Owner (manual):
- [x] Install **Xcode** from the App Store, open once, install iOS platform
- [ ] `sudo xcode-select -s /Applications/Xcode.app` (optional; agents use `DEVELOPER_DIR` meanwhile)
- [x] Xcode → Settings → Accounts → add Apple ID (Personal Team) — team id `8V2VSXHQ86` is in `project.yml`
- [x] iPhone: Settings → Privacy & Security → **Developer Mode** on (appears after first Xcode run); device passcode set
- [x] `brew install xcodegen` (done by agent)
Agent:
- [x] `git init` in `~/Projects/sleephole` (do **not** commit — the owner does)
- [x] `SleepCore/Package.swift` (swift-tools 6.0, platforms iOS 18 / macOS 15) + one passing test
- [x] `project.yml`: app target `SleepHole` (iOS 18, SwiftUI lifecycle), depends on local package
      `SleepCore`; resources: `assets/sprites` as folder reference (bundled as `sprites/`) (the whole folder is bundled — keep only shippable files in it),
      `assets/audio` files; `UIBackgroundModes: [audio]`; bundle id `sk.zrebec.sleephole`; Slovak as
      development language (`sk`)
- [x] Minimal app: `TabView` with 4 empty tabs (Slovak titles) + load `catalog.json` and show the count
- [x] Write owner instructions for running on the device → `docs/RUN_ON_IPHONE.md` (Slovak)
**Accept:** app with the catalog count launches on the owner's iPhone. **Stop.**

### F1 — `SleepCore` + tests
- [x] Clock, TimeOfDay, Schedule, NightWindow (§5.1) + DST tests
- [x] NightEvent/NightLog, `awaySeconds` (§5.3) + tests
- [x] SleepRules/Outcome/`evaluate` (§5.4) + the full table of tests
- [x] Progression (§5.5) + tests incl. 5/15/30 thresholds and streak gentleness
- [x] Catalog decoding (load the real `assets/sprites/catalog.json` in a test) — done in F0
- [x] BuildingPicker (§5.6) with seeded RNG + distribution test (levels ≈ uniform)
- [x] TownLayout + RoadTiles (§7.1) + tests (use the real catalog's `connects`)
**Accept:** `cd SleepCore && swift test` green; give the owner a 10-line Slovak summary of the rules. **Stop.**

### F2 — Night loop without town graphics
- [x] **Spike:** raw lifecycle logger screen, owner tests one evening → record results in §12 (✅ 2026-09-29, device log #2)
      (built 2026-09-29: Nastavenia → „Test detekcie (F2)“ = `DetectionTestView` + `LifecycleMonitor` +
      `AudioKeeper` + `ProbeLog`; waiting for the owner's test log. Pull it with
      `xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer --domain-identifier sk.zrebec.sleephole --source Documents/probe-log.json --destination build/probe-log.json`)
- [x] SwiftData models + store; AppModel phases (§6.1) with `refresh` (`NightRecord`, `AppModel`; town is REPLAYED from finalized real nights, not stored)
- [x] LifecycleMonitor (§6.2), AudioKeeper (§6.3), Notifications (§6.4), ShakeDetector
- [x] Onboarding: first-run guide (`GuideView`) + first-night checklist, flags in `UserProgress` (SwiftData)
- [x] CXCallObserver → call events (§6.6); wake-code + shake confirm (§6.5); 2-min alarm
- [x] Screens: Dnes (all phases, building revealed bottom-up by progress), Nastavenia (schedule, reminder, wake code, sounds), debug (Rýchla noc 4 min / grace 20 s, Nočný denník, Test detekcie)
- [x] Result screen with outcome text + sound + level-up banner
**Accept:** fast debug nights behave per §5.4; then **2–3 real nights**; alarm rings in silent mode;
detection log matches reality. **Stop.**

### F3 — Town rendering
- [x] IsoProjection (§3.3) + unit test against numbers from `demo_town.py`
- [x] TownScene (§7.2): terrain, roads, buildings, ordering, camera pan/zoom
- [x] Unfinished (crop + scaffold), ruins, ruin-flowers after 7 days
- [ ] Growth animation on the night screen and result screen
- [x] Mesto tab + tap-to-inspect
**Accept:** "Simulovať 30 nocí" produces a town that looks like `docs/previews/demo_town.png`. **Stop.**

### F4 — Progression, stats, backup
- [x] Level-up banner + `level_up.caf`; level progress on Dnes
- [x] Street-light upgrade (§7.3); unfinished→complete bonus (§8) — done in F3 (`TownBuilder`)
- [x] Štatistiky screen (§9) with Swift Charts
- [x] JSON backup export/import; 7-day expiry reminder notification
- [x] **Ruin repair** (owner request): a later good night can rebuild a ruin (decide: replaces the new building, or a bonus like the unfinished→complete rule)
- [x] Per-night cap on total time away – done as the away budget (30 s per night, B4, 2026-10-03)
- See `README.md` → „Čo nás čaká“ for the owner-facing roadmap and the XS→XXL idea list
- **Owner extras (2026-09-30, answers recorded):** one commit per step, agent commits (no push).
  - [x] **XS vibrations** (`Night/Haptics.swift`, Core Haptics, `AppModel.buzz`): start of a night/nap and back in
        time after a warning. Lock / setup-end / "Come back!" vibrate only through their notifications (iOS does
        not let apps vibrate in the background, see §12). `AppModel.haptics` logs them.
  - [x] **S achievements + town name:** 12 achievements (`SleepCore/Achievements.swift`) replayed from the real
        nights, naps and `TownSnapshot.repairs` (like coins – old nights count too), +50 🪙 each, +200 for 30 in a
        row / 100 built / first skyscraper; included in `AppModel.coins`; `newAchievements` on the result screen;
        Stats card (locked ones grey, tap = description). Town name (`UserProgress.townName`, default
        "My Town"/"Moje mesto", trimmed, max 30 chars) in the Town header (tap → rename) and Settings, in the backup.
        New UI strings: `python3 tools/i18n/add.py translations.json`.
  - [x] **M weekly journal** (`SleepCore/WeeklyJournal.swift`, `UI/JournalView.swift`): a night belongs to the week
        of its EVENING (key − 1), Monday–Sunday; per week: outcomes, new buildings, coins (nights incl. streak
        bonus + naps), average start/wake, best streak, complete naps, a never-shaming sentence (fewer good nights
        than last week are never mentioned). Stats card "Town journal" (this week + collapsed earlier weeks); the
        finished week appears once on the result screen of the Sunday → Monday night (or of the next night when
        that one was skipped: `WeeklyJournal.finishedWeek`). The result screen scrolls now.
**Accept:** a week of real use. **Stop.**

### LIM — Limits: town rename + schedule changes (owner 2026-09-30) – ✅ implemented 2026-09-30
Owner decisions: rename 1× per **365 days** free, otherwise **5 000 🪙**; schedule (bedtime + wake) free on
**days 1–3 of every month** (the app asks on those days) and during the **first 7 days** (calibration – for the
owner counted from this version), otherwise the change **resets the 🔥 streak** (buildings, coins, levels,
achievements stay).
- [x] **SleepCore `Limits`** (pure, tested): `RenamePolicy` → free (first naming / typo fix within 10 min of the
      last rename / ≥ 365 days since the last free rename) or paid 5 000; `SchedulePolicy` → free (day 1–3 of the
      month, first 7 days, onboarding) or "resets the streak"; next free date for both.
- [x] **Streak breaks:** `Progression.currentStreak/bestStreak` + `Economy.ledger` (streak bonus run) take
      `breaks: [NightKey]` – a paid schedule change resets the run from the next night; history (best streak,
      achievements already earned) is not rewritten.
- [x] **Coin spending:** SwiftData `CoinSpend` (date, amount, reason) – general ledger, reused by the shop later;
      `coins = earned − spent`, never negative; in the backup (optional → old backups load).
- [x] **Storage:** `UserProgress.lastRenameAt/lastFreeRenameAt/scheduleCalibrationStart/schedulePromptMonth`,
      `ScheduleChange` records (date, old → new, free / paid) – the paid ones are the streak breaks.
- [x] **UI:** rename only via an explicit dialog showing the cost ("Free – once a year" / "5 000 🪙, free again on …",
      disabled when coins are short) – the Settings text field that saved on every keystroke goes away. Schedule
      pickers edit a draft + "Save" with a confirmation when it resets the streak (shows the streak length and the
      next free window); footers explain the rules; guide / first setup stay free. Monthly card on "Today" on
      days 1–3: "New month 🌙 Does your bedtime still fit?" [It fits] [Adjust].
- [x] Tests (SleepCore policies + streak breaks + ledger; app: rename cost / spend / backup, schedule save paths,
      monthly card), i18n EN+SK, docs.
**Accept:** owner renames (free, typo fix, paid), changes the schedule inside / outside the window. **Stop.**

### UI — Look & feel (owner 2026-10-02: "interesting features, very plain design")
Owner decisions: living sky background, Today hero = floating island, **keep iOS 18 deployment target**
(every iOS 26 glass call needs an `if #available(iOS 26, *)` fallback), own phase before F5.
Findings that shaped it: no Blender/Codex and no new Kenney purchase needed (the All-in-1 bundle already holds
every Kenney pack; our SceneKit pipeline renders the 3D kits); Kenney "Background Elements" are flat 2D and
clash with the low-poly look → the sky is drawn in code (vector-sharp on every display, tiny, animatable);
Kenney "Particle Pack" (CC0, in the bundle) may supply glow/sparkle textures. iOS 27 SDK adds almost nothing
visual to SwiftUI (`.navigationTransition(.crossFade)`, a tabs picker style) – the visual language is iOS 26
Liquid Glass.
- [x] `SkyPhase` in SleepCore (pure, tested): time + bedtime/wake → dawn / day / dusk / night + blend 0…1
      (dusk = bedtime −90…0 min, dawn = wake −30…+60 min); F5 reuses it for the town tint
- [x] `LivingSky` view (replaces/extends `NightSky`): gradient per phase (`MeshGradient` on iOS 18+), sun/moon arc,
      2–3 parallax cloud layers drifting slowly, stars fade in at dusk; `TimelineView` at low rate, paused when
      the scene is not active; Reduce Motion → static
- [x] Sky behind Today, Stats, Settings (`.scrollContentBackground(.hidden)` on Form), navigation bars transparent
- [x] `GlassCard` modifier: `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))` on iOS 26, otherwise
      `.ultraThinMaterial`; replace the scattered `.thinMaterial` / tinted backgrounds; primary buttons
      `.glassProminent` (fallback `.borderedProminent`); disabled buttons keep contrast on the sky
- [x] Today hero `TownIsland`: floating isometric plate (grass + soil edge) with the latest building + 2–4 trees
      from existing sprites, slow bob; evening start window → crane on the plate; tap → Town tab
- [x] Micro-animations: `.contentTransition(.numericText())` for coins/streak, `symbolEffect` on tab/status icons,
      press scale on big buttons, coin "pop" on the result screen, staggered card appear in Stats
- [x] Town tab: sky instead of the flat meadow edge + navigation bar over the map (header on glass)
- [x] Screenshots light/dark + EN/SK, i18n check, tests green
Done (2026-10-02): SleepCore `Sky.state` (SkyTests) + `TownRender.island` / `groundDiamond`; app `UI/Theme.swift`
(`LivingSky`, `SkyPalette` light/dark, `glassCard`/`glassCapsule`/`glassButton`, `appearIn`, `popIn`, `IslandEdge`),
`Town/TownIslandView.swift` (Canvas, crane in the start window, tap → Town tab via `AppModel.showTown`).
Not done: symbol effects on the tab icons (system tab bar, little gain). Night screen keeps its own `NightSky`.
**Accept:** owner says the app looks nice on the iPhone. **Stop.**

#### UI-2 (owner 2026-10-02, same day)
- [x] Settings → "Appearance & sounds": theme System / Light / Dark (`AppSettings.themeRaw` optional, applied to every
      window via `overrideUserInterfaceStyle` – `preferredColorScheme(nil)` does not reliably return to the system),
      sound effects on/off, voice on/off (both stored as optional "off" flags, old settings load)
- [x] `tools/audio/make_sfx.py` → `fx_sleep` (music-box lullaby), `fx_wow` (arpeggio + chord + twinkles), `fx_sparkle`,
      `fx_whoosh`, `fx_pop` (synthesised), `fx_coins` (Kenney RPG Audio, CC0)
- [x] `Voice` (AVSpeechSynthesizer, best installed voice for EN / SK): good night / nap / building finished / nap done
- [x] `GoodNightSplash` after "Go to sleep" / "Nap" (also quick + test nights), WOW on a finished building
      (`SunRays`, `dropIn`, `SparkleBurst`, 4 s confetti, fanfare → coins → voice), island tap pop
- [x] Developer → "Sound effects test" (every effect, voice line and animation)
**Accept:** owner tests a quick night today (splash, sound, voice, WOW). **Stop.**

#### UI-3 (owner 2026-10-02, afternoon)
- [x] All decorative animations slower: `Motion.pace` = 1.6 (durations/delays ×, speeds ÷); the splash is skipped by a tap
- [x] Confetti 5 s on a finished building, `DustPuff` when it lands, more lasting twinkles
- [x] Coins by level (`Economy.completeReward`, catalog threaded through ledger / stats / journal), guide text updated
- [x] Jokers (D18): SleepCore `Jokers.swift` (+ `JokersTests`), `Outcome.excused`, app `JokerRecord` (SwiftData, backup),
      `AppModel.coreResults()` = joker-protected results used by every rule, `JokerCard` on Today + `JokerSheet`,
      calendar colour + night detail note
- [x] Kenney animals reviewed: **Cube Pets** (24 cute cube animals, CC0) and Prototype Kit dog/horse/bison (untextured
      placeholders). Rendered at town scale with our renderer: `docs/previews/animals_in_town.png`,
      `docs/previews/animals_cube_pets.png` (scratch recipes, not in the catalog yet) – for F5 (living town).
**Accept:** owner tests jokers + the slower WOW. **Stop.**

### P2 — Sleep buddy (owner's spec 2026-10-03) – ✅ accepted by the owner 2026-10-04
**Owner's words:** the buddy must be turned with its head towards me. When I am up, the cat's head is raised and it
looks at me. When I nap or sleep, its head is down, its eyes are closed and it makes "zzz" in a slow animation loop.

**Facts that shape it** (analysis 2026-10-03, see §12): the Cube Pets cat is ONE cube – head and body in one mesh
(`body`, ears included) + `tail` + four `leg-*` + a flat front detail (`Group`). So "head up / head down" is a pose
of the whole cat. The eyes are flat orange polygons on the front face (z = 0.63 in model units: x ±0.12…0.46,
y 0.71…1.06, dark pupils inside) → closed eyes = a fur-coloured eyelid plate + a thin dark lash line in front of
each eye, added by our renderer (no model editing). Today's `buddy-cat` image is turned away and is not in the render
pipeline (B16).

**Design (confirmed by the owner 2026-10-03):**
* **Sprites** (SceneKit pipeline, cat on the Nature Kit camp bed, face towards the camera, all frames on one canvas
  like the crane): `buddy-cat-awake` (sitting, tilted back ≈ 12°, eyes open), `buddy-cat-blink` (same pose, eyes
  closed), `buddy-cat-mid` (half-way down), `buddy-cat-asleep` (legs tucked, body on the bed, face lowered ≈ 10°,
  eyes closed, tail down). Renderer: `Part` gets `pitch` / `roll` and a `pose` per OBJ group, eyelid boxes attached to
  the body. Recipes live in `make_recipes.py` (own output folder, NOT in the town catalog – the picker must never
  see them). Preview: `docs/previews/buddy_poses.png`.
* **Rule in SleepCore** (pure, tested): `Buddy.state(...) -> .awake | .asleep`.
* **View** `BuddyView(state:)` replaces `SleepingBuddy`: awake = slow breathing + a blink every few seconds;
  asleep = slower breathing + the slow "z Z z" loop; a change of state plays awake → mid → asleep (or back) paced by
  `Motion.pace`; Reduce Motion = still frames. Implicit repeating animations, no 20 fps timeline (B8).
* **Where (owner's answer):** Today (where the cat is now), the night screen (beside the construction site), the nap
  screen (instead of the 🌙 emoji).
* **When awake (owner's answer: "it reacts to me"):** always on Today; during a night or a nap only in the setup,
  during a pause and from the alarm on (wake time reached, alarm screen included). Asleep otherwise – also when the
  owner unlocks the phone at night to check the clock, and after a collapse (the cat never judges).
* **B19 goes into the same build (owner's answer):** a stop is remembered – the next night starts silent, ▶ plays the
  last chosen sound again; Settings show it as a switch "play at the start of the night".

**Tasks** (Opus plans and reviews, Sonnet 5.5 workers build – AGENTS.md "WHO DOES WHAT"):
- [x] W1 assets (2026-10-03): four frames 617×637 on one canvas in `assets/buddy/` (`buddy-cat-awake / -blink /
      -mid / -asleep`), preview `docs/previews/buddy_poses.png`; cat yaw 45° (face square to the camera) on the
      Nature Kit bed; recipes in `make_recipes.py` → `buddy_recipes()` → `tools/render/buddy_recipes.json` (the
      town's `recipes.json` and `assets/sprites` are untouched). Re-render: see the docstring of `buddy_recipes()`
- [x] W2 (2026-10-03): SleepCore `Buddy.state(at:running:setupEnds:pauseEnds:wake:)` + `BuddyTests`; app
      `UI/BuddyView.swift` (`BuddyView(state:cloud:)` – no timeline: implicit repeating animations, a blink every
      4–7 s, crossfades awake → mid → asleep of `Motion.t(0.45)` per step, paused off-screen / in the background,
      Reduce Motion = still frames), `AppModel.buddyState(at:)`; imagesets `buddy-cat-awake / -blink / -mid /
      -asleep` (the old `buddy-cat` and `SleepingBuddy` are gone; `buddy_finish.py` copies re-renders into them).
      Placement: Today 132 pt on its cloud at the island's bottom-right; night 104 pt left of the construction site
      (site + crane moved 28 pt right; ≈ 62 pt in the compact morning layout); nap 170 pt instead of the 🌙; collapsed
      night / nap 130 pt asleep under the texts; alarm screen 150 pt awake (dropped by `ViewThatFits` on a phone
      too small). `NapResting` lost its 20 fps timeline (B8). Screenshots in `build/shots/` (git-ignored)
- [x] W3 bug B19 (sleep sound remembered) – built 2026-10-03: `AppSettings.ambienceOff` (optional, nil = on) /
      `playsAtStart`; ■ during a night or nap switches it off, ▶ during a night switches it on, a timer that ran out
      changes nothing; Settings switch "Play when the night starts"; the night sheet shows the stored duration
      (it showed 15 min for "All night"); `SleepSoundMemoryTests` (8 tests), app 111 tests green
- [x] Opus review (2026-10-03): diffs read, screenshots checked, SleepCore 141 tests, app 119 tests / 92.46 %,
      `keys.py` 497 keys / 0 missing / 0 without sk; `assets/sprites` and `recipes.json` untouched
- [x] Installed on the iPhone 2026-10-03 20:40 together with P2b (see there)
- [x] Owner's check on the phone (2026-10-04): the cat behaves as expected → rows moved in §0a

**Owner's feedback after the build (2026-10-03 evening):** Today must not show the town any more (next to the
island the cat looks small and a tap always opened the Town tab) → phase **P2b** below. He also floated "taking care
of the buddy" as a new task; Opus's analysis (chat 2026-10-03), kept here so the idea is not lost:
(1) buddy as the hero of Today + petting = presentation only → P2b, now; (2) the buddy's mood derived from data the
app already has (last night, streak, regularity) = no new duties → a good next step; (3) care with needs that decay
(feeding …) = a second game with duties, clashes with the owner's own rule "no obligations, no punishments"
(`NAVRH-ZVIERATKA.md` §2) and with the still-open coin economy → not now. Town = the long memory of the nights,
buddy = how today feels.

### P2b — The buddy is the hero of Today + three tap reactions (owner 2026-10-03 evening) – ✅ accepted by the owner 2026-10-04
**Owner's decisions (do not re-litigate):**
* The town has its own tab ("Town"). **Today shows no town / island any more** – only the cat with its interaction.
  Nights keep building the town exactly as before. No chip, no thumbnail, no crane on Today – the enabled
  "Go to sleep" button is the signal that building can start.
* The cat on Today reacts to taps – at least three reactions, in this order, then again from the start:
  1. **purr** – a CC0 "murrr" sound;
  2. **arched back** ("mačací chrbát") – needs new renders;
  3. **wink** with one eye (or similar). The details were left to Opus (below).
* No rules, no coins, no duties: petting is only a small joy for the moments when the app has nothing to do.
* Way of working: Opus writes this plan, splits it into tasks for Sonnet 5.5 workers, reviews and tests.

**Reactions (Opus's design):**
| # | Reaction | Frames (crossfades) | Extra | Sound | Haptic |
|---|---|---|---|---|---|
| 1 | `purr` ≈ 2.2 s | awake → `happy` (hold ≈ 1.8 s, tiny wobble ±2°, scale 1.03) → awake | 3 small hearts float up from the head | `fx_purr` | `.purr` – a soft rumble |
| 2 | `arch` ≈ 1.8 s | awake → `arch-1` → `arch-2` (hold ≈ 0.8 s) → `arch-1` → awake | – | `fx_meow` (a short "mrrp") at the start | `.pet` – one light tap |
| 3 | `wink` ≈ 1.2 s | awake → `wink` (hold ≈ 0.7 s) → awake | one sparkle next to the closed eye | `fx_sparkle` (exists), quiet | `.pet` |

Rules of the reactions: only on Today and only while the cat is awake; a tap during a running reaction or during
the awake ↔ asleep transition is ignored; no blink during a reaction; a change to asleep cancels the reaction;
Reduce Motion = frames swap without crossfade and without wobble / hearts / sparkle, sound and haptic still play;
sounds follow Settings → Sound effects (`AppModel.fx`); effects use the `.ambient` audio session, so the iPhone's
silent switch mutes the purr (the haptic still plays). The night, nap and alarm screens get NO tap reactions.

**Assets (worker A – `tools/render/`, `assets/buddy/`, the `buddy-cat-*` imagesets):** eight frames on ONE canvas,
rendered ≈ 1.3× larger than today (the hero is ≈ 250 pt wide → the canvas should be 800–860 px wide):
the four existing ones re-rendered (`awake`, `blink`, `mid`, `asleep` – same poses) plus
* `buddy-cat-happy` – the awake pose, both eyes closed as happy arcs "^ ^" (lash halves tilted the other way than
  the sleepy "︶", ≈ 20–25°), body a touch squashed (x 1.03, y 0.97);
* `buddy-cat-arch-1` / `-arch-2` – half / full "arched back": the cube raised on stretched legs (all four),
  slightly taller and narrower, rear higher than the front (pitch forward ≈ 6–10°), tail straight up and thicker;
  eyes open; must read as "a cat arching its back" and differ from `awake` at a glance;
* `buddy-cat-wink` – the awake pose, ONE eye (the cat's left = +x) closed with a happy arc, the other open, the
  cube rolled ≈ 6–8° towards the closed eye. Needs a one-eye variant of the generated OBJ (`buddy_cat_obj.py`).
`buddy_finish.py` handles all eight (common crop, catalog, preview sheet, imagesets). The worker reports the canvas
size and the normalized positions of: the eyes (awake), the cube's top-right corner (asleep, origin of "z Z z"),
the head's top centre (awake, origin of the hearts), the bed's ground contact (the cloud).

**Sounds (worker S – `tools/audio/`, `assets/audio/`):** `fx_purr.caf` (≈ 2 s of a close, clean purr, fade in 0.15 s,
fade out 0.4 s) and `fx_meow.caf` (one short soft meow / "mrrp", ≤ 0.9 s) from **CC0** Freesound recordings through
the existing pipeline: ids in `tools/audio/freesound.json` with `"use": "fx"`, download by `fetch_freesound.py`
(refuses anything that is not CC0; key in `~/.freesound_key`, never printed or committed), cut in `make_sfx.py`
(`purr()`, `meow()`, same `write()` as the other effects – mono 44.1 kHz PCM CAF, peak −3 dB), credits in
`assets/audio/CREDITS-freesound.txt` and in the app's Credits screen if it lists sounds. Nobody in the pipeline can
listen, so candidates are chosen by description / tags / rating and checked by analysis (purr: amplitude modulation
around 20–30 Hz, no clipping, quiet background; meow: one tonal event). Fallback when nothing suitable is CC0: a
synthesised purr in `make_sfx.py` (say so in the report). The owner judges the sounds in Settings → Developer →
Sound effects test.

**App (worker APP – after A and S):**
* SleepCore `Buddy.swift`: `public enum BuddyReaction: CaseIterable, Sendable { case purr, arch, wink }` +
  `var next: BuddyReaction` (purr → arch → wink → purr) + tests in `BuddyTests`.
* `Haptics.swift`: new cases `.purr` (soft rumble ≈ 1.2 s: continuous, intensity ≈ 0.45, sharpness ≈ 0.1, with a few
  gentle pulses) and `.pet` (one light transient); every `switch` over `Haptic` handles them (also
  `VibrationTestView.title`, the UIKit fallback); strings EN + SK.
* `AppModel`: `@discardableResult func petBuddy() -> BuddyReaction` – returns the next reaction of the cycle (session
  state only, starts with purr, never persisted), plays its sound through `fx(...)` and its haptic through `buzz`.
* `BuddyView`: new frames in `Pose`; an optional `onPet: (() -> BuddyReaction?)?` – when set, the view is tappable
  (`contentShape` = the cat's frame) and a tap while resting awake calls it and plays the reaction's frame timeline
  (a static, testable description of steps: pose + duration); hearts / sparkle overlays; the canvas-dependent
  constants (`aspect`, origin of "z Z z", cloud position) follow the new canvas.
* `HomeView` (`TodayView.swift`): `TownIslandView` and its tap are removed from Today; the hero is
  `BuddyView(state:cloud: true, onPet: { model.petBuddy() })`, ≈ 250 pt wide, centred, with room for the cloud;
  the order stays: expiry card, monthly card, badges, **buddy**, sleep card, nap card, joker card, level info.
  `TownIslandView.swift` and `TownRender.island` stay in the code (unused on Today, still rendered by a test) in
  case the island returns elsewhere – remove them only when the owner says so.
* Sound effects test (Settings → Developer): the two new sounds in the list + three buttons that play the reactions
  on a `BuddyView`.
* Accessibility: the awake buddy on Today gets the hint EN "Tap to pet her" / SK "Ťukni a pohladkaj ju".
* Re-check every placement of the buddy after the new canvas (Today, night, compact morning, nap, collapsed,
  alarm) on screenshots; tests: reaction cycle, `petBuddy` (order, haptics log, nothing persisted), timelines
  (start and end at `awake`, total durations), rendering of the reactions, Today without the island.

**Tasks:**
- [x] A – assets (2026-10-03): eight frames on one canvas **860 × 974 px** (`BUDDY["size"] = 1.3`); `lashes(eyes:,
      style:)` sleepy / happy; `buddy_cat_obj.py` also writes the one-eye `animal-cat-wink.obj`; arch = legs ×2.4 /
      ×2.9, body + mouth detail raised and pitched 5° / 9°, tail puffed; wink = roll −7°; the mouth detail (`Group`)
      now follows the body in every pose (it floated at the chin in the first awake / blink frames). Normalized
      positions on the canvas (x from the left, y from the top): eyes (0.220, 0.463) / (0.384, 0.463), head top
      centre (0.302, 0.256), asleep cube top-right (0.497, 0.343), bed ground contact (0.359, 0.834); the cube is
      0.376 of the canvas wide; only `arch-2` uses the top ≈ 15 % of the canvas. A cube cannot bend: the "arched
      back" reads as standing tall on stretched legs with a puffed tail
- [x] S – sounds (2026-10-03): `fx_purr.caf` (2.0 s, Freesound 326295 "cat purring 2.wav" by blukotek, CC0; one
      breath, pulse train 25 Hz, 70 Hz high-pass) and `fx_meow.caf` (0.53 s, Freesound 262312 "Cat Meow1.wav" by
      steffcaffrey, CC0; a greeting meow, fundamental ≈ 700 Hz – loud once normalised, play it quietly);
      `make_sfx.py purr meow`; nobody could listen – the owner judges them in the sound effects test
- [x] APP – app (2026-10-03): SleepCore `BuddyReaction` (+ `next`); `Haptic.purr` / `.pet`; `AppModel.petBuddy()`
      (session-only cycle, sound + haptic); `BuddyView(state:cloud:onPet:hold:)` – layout box without the canvas's
      empty top (`headroom` = 159 / 974, only the arch frames reach above it), reactions as data
      (`BuddyView.timeline(_:)`: purr = happy 1.8 s + hearts, arch = arch1 → arch2 0.8 s → arch1, wink 0.7 s + sparkle;
      paced totals 3.4 / 2.6 / 1.6 s), taps accepted only while resting awake, `BuddyView.centred(_:)`; Today =
      the cat ≈ 250 pt wide instead of the island (`TownIslandView` kept in the code, unused); other placements
      re-tuned (night 110, nap 180, collapsed 138, alarm 159 pt); sound effects test: purr, meow + a tappable cat;
      Credits: section "Cat sounds"; dev args `-buddyReaction purr|arch|wink`, `-openSoundTest`, `-scrollTo cat`;
      test hook `\.buddyProbe` (hosted tests cannot tap). Screenshots in `build/shots/p2b/`
- [x] Opus review (2026-10-03): renders, diff and screenshots checked; SleepCore 144 tests, app 133 tests / 92.63 %,
      `keys.py` 504 keys / 0 missing / 0 without sk; `assets/sprites` + `recipes.json` untouched; no simulator left on.
      Not verifiable in the simulator: the real purr / meow, the haptics, the silent switch
- [x] Installed on the iPhone 2026-10-03 20:40 with the owner's OK (P2 + P2b + B19 in one build); the app's data
      was pulled first (`docs/device-logs/2026-10-03-before-p2b/`, git-ignored); the app launched and kept running.
      The build carries a FRESH profile valid until 2027-10-03 – see §12
- [x] Owner's check on the phone (2026-10-04): the cat behaves as expected → rows moved in §0a
**Accept:** on Today the owner sees only the cat; three taps give purr, arched back, wink; the Town tab is unchanged.
**Stop.**

### SKY — City in Settings + the real sun and moon (owner 2026-10-02 / 2026-10-03) – 🟡 built, final build not installed yet
**Why:** the sky follows the owner's schedule (dusk = the 90 min before bedtime), so at 20:45 it showed a sunset
while the real sun had set at 18:28. **Owner's spec (2026-10-02):** Settings → city with autocomplete – the label on
its own row, the field on the row below (long names); after the field a black ✕ that turns into a green ✓ once the
city is verified (checked ≈ 500 ms after the typing stops); Apple Maps search (`MKLocalSearchCompleter` +
`MKLocalSearch`) – **no location permission, no tracking**; Today: the sun or the moon on a **semicircle** at its true
position for that city (also a rough clock); brightness and colour of the sky from the real altitude of the sun;
pure maths in SleepCore, unit-tested; **without a city the sky keeps following the schedule.** The night screen keeps
its own always-dark `NightSky`.

**Design (Opus):**
* `SleepCore/Astro.swift` (new, pure): `GeoPoint` (latitude / longitude in degrees, north / east positive);
  `Astro.sun(at:from:)` and `Astro.moon(at:from:)` → altitude + azimuth in degrees (geometric, the moon topocentric);
  `Astro.moonPhase(at:)` → illuminated fraction 0…1 + waxing; `Astro.sunArc(at:from:)` / `moonArc(at:from:)` → the
  last rising and the next setting around `t` when the body is up (horizons −0.833° / +0.125°), nil when it is down
  or never rises / sets (polar day and night). Accuracy wanted: sun ≤ 0.3° and ≤ 3 min, moon ≤ 1.5° and ≤ 10 min,
  phase ≤ 0.03.
* `Sky.state(at:place:)` returns the same `SkyState` the views already draw, from the sun's altitude `a`:
  `daylight` = smoothstep((a + 6) / 12); `glow` = sin(π (a + 6) / 12) inside −6°…+6°, else 0; `phase` = day (a ≥ 6°),
  night (a ≤ −6°), otherwise dawn while the sun rises and dusk while it sets. New fields with defaults (old callers and
  tests keep working): `body` = `.sun` (sun above its horizon) / `.moon` (sun down, moon up) / `.none`, and `moon`
  (illuminated fraction + which side is lit; the southern hemisphere mirrors it). `arc` = the fraction of the way
  from rising to setting, 0…1 left to right; 0.5 when there is no rising / setting.
* App: `AppSettings.city` (optional `SkyCity { name, latitude, longitude }` – old settings and backups load);
  `CitySearch` protocol (`MapKitCitySearch` in the app, a fake in the tests; never `CLLocationManager`);
  Settings section "Sky"; `LivingSky` uses the real state when a city is set (computed at most once a minute – it
  is asked 20× a second) and the schedule otherwise; Today draws the body on a true semicircle (centre x = middle of
  the screen, centre y ≈ 310 pt, radius ≈ 150 pt, a faint dotted arc) that never crosses the large title; the other
  screens keep their flat arc but use the real body / phase; the moon is drawn with its real phase; nothing is drawn
  when both are down.
* Reference values for the tests come from an independent source (PyEphem): `tools/astro/reference.py`.

**Tasks:**
- [x] W1 (2026-10-03) – SleepCore `Astro.swift` (sun: NOAA / Meeus low precision; moon: Astronomical Almanac
      low-precision series + topocentric correction; phase from the real elongation; rising / setting by a 5-min
      search + bisection) and `Sky.state(at:place:)`, `SkyBody`, `MoonLook`. Worst errors against PyEphem: sun
      0.01°, moon 0.3° (azimuth 1.4° near the zenith), phase 0.002, sunrise / sunset a few seconds, moonrise /
      moonset < 4 min. 177 SleepCore tests. One call ≈ 60 µs – the app still caches it per minute
- [x] W2 – app (2026-10-03 night): `SkyCity` + `AppSettings.city`; `App/CitySearch.swift` (`CitySearch`,
      `CityField` – the field's logic without views, `MapKitCitySearch`: completer WITHOUT an address filter – with
      `.locality` it lists a city's districts but not the city itself – and `MKLocalSearch` filtered to localities);
      `UI/SkySection.swift` (Settings → Sky); `RealSky` (per-minute cache), `SkyOverrides` (dev args `-skyCity`,
      `-skyArc`, `-skyBody`, `-skyMoon`, `-cityQuery`, `-scrollTo sky`), `LivingSky(semicircle:)`,
      `SkyDrawing.track / semicirclePoint / litPart` (the moon's real phase); `SkyCityTests` (26 tests). The worker
      stalled before reporting (the Mac went to sleep on battery); Opus reviewed the code on 2026-10-04
- [x] W3 – leftovers (2026-10-04): the buddy animation tests waited a fixed real time and failed under the bigger
      test run → `pump(host, until:timeout:)` polls for the end state (test file only); fresh Settings screenshots
      (the simulator reaches Apple Maps: "Brat" → Bratislava, its districts, the region); **new semicircle
      geometry** – centre (width − 150, 180 pt), radius min(95, …): a compact half circle in the free sky right of
      the title, above the badges (with centre y 310 / radius 150 the body sat half behind the glass badges for much
      of the day); only at the two ends the disc dips behind the badges' top edge, like a horizon
- [x] Opus review (2026-10-04): code read, screenshots checked (`build/shots/sky/`); SleepCore 177 tests, app 159
      tests / 92.36 % (five green runs in a row), `keys.py` 513 keys / 0 missing / 0 without sk; no location API
- [x] Committed 2026-10-04 at the owner's request; the FINAL build was installed on the iPhone on 2026-10-04 17:29
      (data pulled first to `docs/device-logs/2026-10-04-before-sky/`; the first `devicectl … launch` failed with
      FBSOpenApplicationServiceErrorDomain 1, the second one right after it worked – the app keeps running)
- [x] Owner looked at it (2026-10-04 17:30): **rejected** – "much worse than the original … why isn't it from the
      left edge to the right? … unacceptable"; "the one installed last night was better". **Owner's decision: the
      semicircle spans the screen from left to right – the sun in the middle means noon; never shrink or move it.**
      Geometry restored to centre (width / 2, 310 pt), radius min(150, width / 2 − 44). The sun passing behind the
      status badges is fine for him (B7's solid card backing covers it cleanly). Lesson: Opus changed a look the
      owner had already approved, without asking – a confirmed look is changed only on his request
- [x] Reinstalled with the restored semicircle 2026-10-04 17:37 (built from a git worktree at HEAD + the two-file
      revert, because B7 was in progress in the main checkout; the same revert is applied there by the B7 worker).
      `devicectl … launch` fails with "Locked – the device was not unlocked" when the phone's screen is locked:
      installing works on a locked phone, launching does not
      ⚠️ **Interim install 2026-10-03 21:13 at the owner's explicit request ("install now"):** a frozen copy of the
      working tree as it was at 21:12, while W2 was still working – it compiled, launched and kept running on the
      phone, but it was NOT reviewed, its tests were not written yet and the Apple Maps search was never tried.
      The last reviewed build (20:39, P2 + P2b) is kept at `build/DerivedData/Build/Products/Debug-iphoneos/` for a
      rollback. The final SKY build still has to be reviewed, tested and installed
- [x] **Night moon as the night's clock (owner 2026-10-04 evening; built the same evening – `Astro.nightArc`, 10 new
      SleepCore tests, screenshots `build/shots/sky/today-night-moon-*.png`; not on the phone yet):** with a city, `Sky.state(at:place:)` never returns
      `.none` – while the sun is down the body is the moon, its `arc` = the fraction of the way from the last sunset
      to the next sunrise (0.5 in a polar night), its look = the real phase. The real moonrise / moonset no longer
      decides whether the moon shows (it left the sky empty after sunset)
**Accept:** the owner types his city, sees ✓, and Today shows the sun / moon where they really are. **Stop.**

### B7 — Contrast and transparency (bug backlog §11a, owner 2026-10-03: "on the light sky the transparency bothers quite a lot") – ✅ accepted by the owner 2026-10-04; two follow-ups open
**Owner's standing rule:** contrast must always be guaranteed; he dislikes the iOS 26 see-through look and runs
his iPhone with reduced transparency. **Design (Opus, 2026-10-04):**
* Every glass card / capsule gets a **solid backing** under the glass: light mode white at ≈ 0.78, dark mode a deep
  navy at ≈ 0.72; fully opaque when the system's Reduce Transparency is on. Tinted capsules (streak, coins) keep their
  tint on top of the backing. The sky stays visible around the cards, not through the text.
* **Disabled big buttons** ("Go to sleep", "Nap" outside their windows) get their own readable look – a calm solid
  fill and a label at ≥ 4.5 : 1 – instead of grey glass on grey glass.
* **Captions inside cards** use `.primary` at ≈ 0.72 opacity instead of `.secondary` (too weak on a light card).
* **Sun / moon never behind a title:** Stats and Settings draw the sky without the body; Today without a city moves
  the flat arc right of the title (x from 140 pt). With a city the semicircle stays FULL WIDTH (owner's decision
  2026-10-04, see SKY) – it passes below the title and behind the status badges, whose solid backing covers it.
* The night screen (always dark, no cards) and system `Form` rows are untouched.
- [x] Worker (2026-10-04): `GlassCard` backing (light white 0.78, dark navy 0.72, opaque with Reduce Transparency
      or `-solidCards`; the glass is kept on top on iOS 26), `GlassButton` + `CalmDisabledButtonStyle` (`.disabled`
      must come AFTER `.glassButton()` or the modifier cannot see it), `cardCaption()`, readable yellow / green /
      orange on light cards, dark calendar numbers on the bright squares, `LivingSky(showsBody:)` – Stats and
      Settings without sun / moon, flat arc from x = 140; the full-width semicircle restored in the main checkout
- [x] Opus review (2026-10-04): screenshots in `build/shots/b7/` checked (cards, disabled buttons, sun behind the
      badges, Stats dark); SleepCore 177 tests, app 166 tests / 92.54 %, `keys.py` 513 / 0 / 0
- [ ] Follow-up, NOT a priority (owner 2026-10-04 evening: "the blue is readable too"): the pale accent colour (selected tab, "Rename…",
      ≈ 2.4 : 1 on white) and the grey Form headers / footers that sit directly on the sky (≈ 3 : 1 in light mode)
- [x] Installed 2026-10-04 18:27 (a build of the reviewed state without the F6a entitlement). **Owner's verdict the
      same evening: "the contrast is very good, even the statistics are well visible"; the calendar numbers in dark
      mode are readable now.** He wants both open points done next (accent colour, Form headers / footers)
- [x] Committed 2026-10-04 (`964e6ae`)
**Accept:** the owner reads everything on Today, Stats and the result screen without effort, in light and dark. **Stop.**

### F5 — Living town
> Owner 2026-10-02: town + **Cube Pets** (no forest); animals reflect **regularity** and **undisturbed nights**,
> light taps only, plus a **sleep buddy** on the night screen. Three plans (A recommended: pause → sleep buddy →
> residents → album → living town) in [`docs/NAVRH-ZVIERATKA.md`](NAVRH-ZVIERATKA.md) (Slovak) – owner picks one.
- [ ] Day/night tint (→ phase TOWN-W step 4), lamp glows, window glints
- [ ] Cars on roads, population counter
- [ ] Roads first → phase TOWN-W step 1 (owner's decision 2026-10-07: always one block ahead)
- [ ] Cube Pets residents (move-in rules by streak / regularity / undisturbed nights, wander near home, tap = card +
      pet), sleep buddy (renderer needs a model tilt for the lying pose)
**Accept:** owner enjoys looking at it. **Stop.**

### TOWN-W — The town grows and has weather (owner 2026-10-07) – 🟡 steps 0b, 1 and 2 built 2026-10-07 (0b not on the phone), next: checkpoint A (the owner)
> Owner 2026-10-07: "now I want to spend some time on the town". His order: check the shutdown notice (done, §12),
> roads first ("so the player knows the town will really grow"), WeatherKit ("for now – maybe better stations
> later"), rain and snow in the town ("but it has to be testable"), and at the end daylight by day and a dark town
> after dark. His decisions the same day: roads **always one block ahead** (also in an empty town); phone tests at
> **checkpoint A = steps 0b + 1 + 2**, then B (step 3), then C (step 4); a warning when Time Sensitive Notifications
> are off: **yes, in Settings and on Today**. Each step = one Sonnet worker; at most two run at a time (8 GB Mac):
> one in the main tree, one in a git worktree with its own simulator (`SIM=…`), merged back file by file.
> **Sessions (owner 2026-10-07, later): one step = one session.** When a step is reviewed, merged and written into
> this plan, Opus itself runs the `session-handoff` skill and stops; the next step starts in a clean context from
> that handoff. Steps 1 and 2 were started together (two parallel workers), so their handoff comes once both are
> in. No handoff while a worker is still running – its report reaches only the session that started it. A worker
> in the main tree also writes its final report into `build/handoff/` (git-ignored); a worktree worker cannot
> write outside its worktree, so its report exists only in the session – write what matters into this plan.

**Step 0b – Time Sensitive Notifications are off (follow-up of B21)** – built and reviewed 2026-10-07 (one Sonnet
worker, two rounds; tests / simulator only, not committed). App 250 tests (91.96 %), i18n 575 keys / 0 missing /
0 without sk / 0 unused.
- [x] `Notifications`: the pure rule `timeSensitiveOff(authorization:setting:)` – true only when notifications are
      allowed (authorized / provisional / ephemeral) AND `timeSensitiveSetting == .disabled`; denied / not asked give
      no second warning (the "Notifications" row already says it), `.notSupported` gives none either.
      `readTimeSensitiveOff()` asks the centre; `timeSensitiveCheckForLaunch` picks the check (tests → always false
      and no system call; the simulator's `-timeSensitive off|on` pretends; otherwise the real reader)
- [x] `AppModel`: init parameter `timeSensitiveCheck` (default `{ false }`), `timeSensitiveOff`,
      `refreshTimeSensitive()` – called by `SleepHoleApp` at launch and on every return to the app, and after every
      permission request (launch task, both places in the guide); never from the 1 s `refresh()`
- [x] Settings: a row under the "Notifications" status – orange triangle, the title in the primary colour (an
      all-orange title on a white row was ≈ 2 : 1 contrast, changed in review), both sentences as a footnote; the
      existing "Open notification settings" button below it is the way out (no second button)
- [x] Today: `TimeSensitiveCard` after `SafetyAlarmCard` (orange glass card, the pattern of `ExpiryCard`) with the
      same texts and the button; no card → Today is exactly as before
- [x] Tests (`SleepHoleTests/TimeSensitiveTests.swift`: the rule, the launch check, the model with a fake, the card /
      Today / Settings rendered light + dark in both languages) + three `L(...)` strings with Slovak
- [ ] **Unverified until the phone:** the real switch (`readTimeSensitiveOff`) – in the simulator and in tests the
      answer is always pretended. Screenshots: `build/handoff/step0b/` (git-ignored)
- [x] **Answered by the owner at checkpoint A (2026-10-07):** the switch works "excellently" in both directions and the Focus test with it on passed. The card: "quite tall, though for this app nearly mandatory" – his idea: only a tappable, unmissable triangle on Today that leads to the app's Settings, where it is explained and from where iOS's settings open (follow-up A1 below). The questions as asked – (1) while the switch is off the card is tall – "Go to sleep" slides
      below the bottom edge and needs a scroll (it disappears with the switch on). Offer: drop the per-Focus sentence
      from the card and keep it in Settings only. (2) The app says "Časovo citlivé upozornenia" (its own word for
      notifications everywhere); the Slovak iOS may name the switch differently – ask what his phone shows. (3) The
      button on the light card is the accent blue on a near-white pill, the same `.bordered` look as on the safety
      alarm card (the owner on 2026-10-04: "the blue is readable too") – left as it is. Points (2) and (3) were not
      answered; (3) disappears with the card

**Step 1 – Roads first (SleepCore only)**
Rule: a block's street ring = the 20 road cells around it; every started block (≥ 1 building) has its whole ring;
the first EMPTY block in spiral order has its ring too (exactly one block always waits); lit streets stay next to
houses – only a straight cell that touches an occupied lot can be lit. Placement (`nextOrigin`, `place`) does not
change; nothing about roads is stored (the town is replayed from the nights).
- [x] `TownLayout`: `ring(of:)`, `builtRoads` (the old rule), `drawnRoads` (rings of the started blocks ∪ the
      frontier ring), `upgradeStreets` / `canUpgradeStreets` on `straightCells(in: drawnRoads) ∩ builtRoads`
      (a private `lightableCells`); `TownRender` untouched – built and reviewed 2026-10-07
- [x] Tests: empty town = the first ring; one house = its ring + the next block's ring; the owner's shape (6 small
      + 2 big buildings in one block) → the frontier is the next spiral block and moves on when a building lands
      there; rings never disappear (60 nights); lamps only next to houses. Two render tests changed with the rule:
      the empty town is now 100 sprites, 20 of them road (was a 5×5 meadow); the empty island keeps 9 tiles, 3 road
- [x] Screenshots before / after reviewed: the owner's real town (the outlined empty block to the right of his
      full one, T-junctions join cleanly), an empty town (one street loop on the meadow), 3 nights
- [x] §7.1 of this plan updated
- [x] **Closed by the owner at checkpoint A (2026-10-07): it does not bother him, nothing changes.** It was – the first look of the Town tab: the camera's fit is capped at
      scale 4.5 (`TownScene.fitIfPossible`, "a big town is not microscopic"), and it centres on the whole drawn
      area. With two blocks the left end of his block's street loop and the right end of the empty block are off
      screen until he pans (one block used to fit, only the grass was cut). Offer: raise the cap to ≈ 5.7 (both
      loops fit, buildings ≈ 27 % smaller) or leave it. Nothing was changed – the town's look is his to decide
- [ ] Leftover: the test `emptyTownIslandIsNineGrassTiles` should be renamed (3 of its 9 tiles are road now)

**Step 2 – Weather on Today (WeatherKit; the owner's OK for the paid capability 2026-10-07)** – built, reviewed
and merged 2026-10-07 (tests / simulator only). On the merged tree: SleepCore 220 tests, app 246 tests (92.01 %),
i18n 572 keys / 0 missing / 0 without sk / 0 unused.
- [x] SleepCore `Weather.swift`: `WeatherKind` (clear, cloudy, fog, rain, thunder, snow), `WeatherNow` (temperature
      °C, kind, intensity, cloud cover, `isDaylight`, `snowOnGround`, observed at), `WeatherHour`, `WeatherRules`
      (Apple condition string → kind + intensity for all 34 SDK cases – an app test fails when a new SDK adds one;
      refresh after 30 min at the earliest, retry 5 min after a failure; a value older than 90 min is not shown;
      "snow lies": it snows now, or ≥ 5 mm fell since the last hour above +2 °C and it is not above +2 °C now) –
      with tests
- [x] App `SleepHole/Weather/`: `WeatherSource` protocol + `WeatherKitSource`, `NoWeather`, `SimulatedWeather`;
      `WeatherSources.forLaunch` (tests → none, `-weather …` → simulated, a real device → WeatherKit, the simulator
      → none). The source is replaceable (the owner may want better local forecasts later, e.g. MET Norway / Yr).
      WeatherKit is asked twice: `.current`, then `.hourly` for the past 48 h inside `try?` – a failing hourly part
      never loses the temperature, the snow rule then falls back to "it snows now"
- [x] `WeatherStore` (`@Observable`, `AppModel.weather`): last value, last error, cache in UserDefaults
      (`weather.cache`: the value, its coordinates, the time – not in the settings, not in backups); a changed city
      drops the old value at once; refresh on Today every minute (rate-limited by the rules), when the app becomes
      active and when the city changes; never during a night / nap
- [x] **Today: a badge top right, NOT in the title (changed in review).** At noon "Dnes · -12° 🌨️" covered the sun
      on the semicircle, and neither the title nor the semicircle may change. The title stays "Today"; the value is
      one navigation-bar item top right ("14° 🌧️", `.todayWeather()` in `WeatherUI.swift`), no item at all without
      a city or with a stale value. The emoji's day / night follows the sky at display time, not the cached value.
      °F only where the region measures that way. Screenshots at 08:00, noon, 17:30 and at night (light and dark):
      it never touches the title, the sun or the moon
- [x] Attribution (Apple's rule): the Apple logo + "Weather" and the link "Other data sources"
      (`https://developer.apple.com/weatherkit/data-source-attribution/`) in Settings → Sky (only with a city) and in
      Credits. For a later App Store release: Apple wants the mark where the data is shown or easy to reach from
      there – Settings is one tab away; a tap on the badge could show it
- [x] Developer → "Weather test" (`-openWeatherTest`): source, city, past hourly values, the shown value, last
      success / failure / error, "Refresh now", and the simulation (live / clear / cloudy / fog / rain / heavy rain /
      thunder / snow, temperature, snow on the ground). The simulation lives in memory only – it ends when it is set
      back to Live or the app restarts (a stored one could show fake weather for days). It needs a city. Launch
      arguments `-weather`, `-weatherTemp`, `-weatherSnowCover`
- [x] `project.yml`: entitlement `com.apple.developer.weatherkit` (+ the regenerated `SleepHole.entitlements`)
- [x] **Owner:** WeatherKit ticked for the App ID `sk.zrebec.sleephole` on developer.apple.com (asked for: the
      **App Services** tab AND the **Capabilities** tab) – his word 2026-10-07; the first live value on the phone
      (Developer → Weather test) proves it
- [ ] **Unverified until the phone:** the live WeatherKit call (the first device build also proves the capability –
      a missing one shows as a signing error in Xcode or as "Last error" in Weather test), and whether `.hourly`
      returns PAST hours ("Past hourly values" in Weather test; 0 there = the snow rule only knows "it snows now")
- [ ] **B23 – first phone run 2026-10-07 (owner's Xcode build of 15:03): no badge, "Last error" =
      `WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors Code=2`.** Checked from the Mac: the signed app and
      its profile (created 2026-10-07 12:20) carry `com.apple.developer.weatherkit`, a city is set, the phone's
      `weather.cache` is empty – so the Capabilities tab is proven and the code asked; Apple's WeatherKit service
      refuses to issue the token. **Owner:** developer.apple.com → Identifiers → `sk.zrebec.sleephole` → the
      **App Services** tab → WeatherKit ticked → Save; then wait (30 min up to the next morning) and press
      "Refresh now" in Weather test – no new build is needed. Still Code=2 the next day → decide with the owner:
      a second `WeatherSource` (Open-Meteo / MET Norway, no Apple account involved) – see §12, 2026-10-07

**Checkpoint A (owner, on the phone):** Town – the outlined empty block next to his full one, and his word on the
first look (both blocks do not fit the screen until he pans – step 1, open item); Today – the temperature badge top
right, nothing there without a city, the title and the sun / moon as before; Developer → Weather test – a live
value or the error text, "Past hourly values", and a simulated kind shows on Today at once; switching Time
Sensitive Notifications off (iOS Settings → Notifications → SleepHole) shows the card on Today and the row in
Settings as soon as he is back in the app, switching them on hides both; his word on the three open points of
step 0b. With the switch ON: the Focus test again (leave the app during a night in Sleep / Do Not Disturb → the
"Come back" warning must arrive). **Stop.**

**Checkpoint A – result (owner 2026-10-07, the build installed 16:37):** the outlined block is there and the
first look does not bother him; the warning appears and disappears with the iOS switch ("works excellently", "big
praise"); with the switch on the "Come back" warning arrives during a Focus; the weather is still refused by
Apple (Code=2). **Follow-ups he approved, before step 3:**
- [ ] **A1 – Today: a triangle instead of the card.** The tall `TimeSensitiveCard` goes; while the switch is off
      Today shows one tappable orange warning triangle (a navigation-bar item top left, the mirror of the weather
      badge – nothing on Today moves, the semicircle and the title stay). A tap opens the app's Settings tab at the
      notifications section (the row with the explanation and the "Open notification settings" button stays)
- [ ] **A2 – a second weather source: MET Norway** (Locationforecast 2.0, no account, needs an identifying
      User-Agent and a credit). Used when WeatherKit fails; the store remembers which provider gave the shown
      value, the credit in Settings → Sky / Credits follows it, Weather test shows it. No past hours there → the
      "snow lies" rule only knows "it snows now" with this source (to revisit in step 3)
- [ ] **A3 – TestFlight preparation:** `Info.plist` takes version and build from `project.yml` (1.0, next build
      2 – every upload needs a higher one), `PrivacyInfo.xcprivacy` with the reasons for the APIs the app really
      uses. The Developer section stays visible for now (the owner has not decided)

**Step 3 – Rain and snow in the town** (after checkpoint A)
- [ ] `TownScene.setWeather(...)`: particles as children of the camera node (they stay on screen while panning and
      zooming), built in code – rain = slanted streaks, density by intensity; snow = slow flakes; thunder = heavy
      rain, no flashes
- [ ] "Snow lies": a white sheet over `TownRender.groundDiamond` between the grass and the roads – a white meadow,
      cleared roads; roofs stay as they are (snowy roofs need re-rendered sprites – the owner decides after the
      checkpoint)
- [ ] The sky over the town is greyer with denser clouds when it is overcast (`LivingSky`); the sun / moon
      semicircle does not change
- [ ] Reduce Motion: no particles, the snow sheet stays
- [ ] Tests in `TownSceneTests`; testable on the phone through Developer → Weather test

**Checkpoint B (owner):** Developer → Weather test → rain / snow / snow on the ground → Town tab. **Stop.**

**Step 4 – Day and night in the town** (after checkpoint B)
- [ ] SleepCore `TownLight.tint(daylight:glow:overcast:)` with tests: day unchanged, dusk warm, night dark blue
- [ ] `TownScene.setLight(...)`: every sprite, the island's soil edge and the snow sheet are multiplied by the tint;
      the source is `LivingSky.state(at:settings:)` (the real sun with a city, the schedule without one), refreshed
      once a minute – the town is exactly as dark as the sky behind it
- [ ] Developer → Weather test gets a time-of-day choice (live / day / dusk / night); the simulator keeps `-skyTime`
- [ ] Lights at night (lamp glows, warm windows – F5 list) are the next proposal after checkpoint C

**Checkpoint C (owner):** the town by day and after dark. **Accept:** the owner likes how the town looks in every
weather and at night. **Stop.**

### R4 — Closing the app counts as leaving it (owner 2026-10-04 evening) – 🟡 built 2026-10-06, not on the phone yet
**The owner's finding:** with the system alarm, swiping SleepHole away after the setup became an attractive
loophole: nothing warns, nothing collapses, the alarm still rings, and in the morning the building is complete –
because the evaluator treats a relaunch (`.appLaunched`) as "the app was killed – unknown what happened → the
owner's favour". **His decision: "it must not be built if I cheated."**

**Design (Opus):** iOS tells a RUNNING app when it is being terminated (`UIApplication.willTerminateNotification` –
SleepHole runs all night thanks to the background audio; `LifecycleMonitor` already observes it, only as a raw log
line). A swipe in the app switcher delivers it; a kill by iOS for memory, or a crash, does not.
* **Rule:** the app closed while a night / nap runs = leaving the app from that moment until it is opened again –
  the same tolerance as any trip: an immediate warning notification ("SleepHole was closed – open it within N s"),
  10 s to return, counted into the night's 30 s away budget; pauses and the setup time excuse it like any trip.
* **Still the owner's favour:** the app killed by iOS (no termination notice), and a phone restart / shutdown (the
  notice arrives then too – recognised afterwards because the phone's boot time is later than the notice).
* SleepCore: new events `.closedByOwner` (opens an away interval like `.leftApp`; it ends at the next
  `.appLaunched`) and `.restartExcused` (cancels the interval of the `.closedByOwner` before it); `.appLaunched`
  keeps wiping an interval that was opened by `.leftApp` (unknown death → favour); the night story names the
  closure. App: on the termination notice during a running night → append the event, save, schedule the warning(s);
  at the relaunch → compare the boot time (`sysctl kern.boottime`), append `.restartExcused` when the phone had
  restarted, cancel the warnings.
* **To prove on the phone** (quick nights): swipe away and stay away → collapsed; swipe away and reopen within 10 s →
  the building stands; a real restart of the phone → the building stands.
* Same build: when our own alarm starts while the system alarm is already ringing (the app was reopened at the wake
  time), stop the system alarm and arm a new one for wake + alarmDuration – no two alarms at once.
- [x] Worker (Sonnet, 2026-10-06): SleepCore `NightEventKind.closedByOwner` / `.restartExcused`,
      `NightEvaluator.awayIntervals` (a closure owns the open interval; `.appLaunched` ends it, `.restartExcused`
      drops it; a death without the notice stays in the owner's favour), `NightLog.openClosure`,
      `NightReport.Trip.closedApp`, `ClosureTests` (20); app: `LifecycleMonitor.onTerminate` (observed with
      `queue: nil` – a hop to the main queue could come too late), `AppModel.appWillTerminate()` (only before the
      wake time; the event is saved synchronously), the closure warning `closed` / `closed-2` (time sensitive),
      `Night/DeviceBoot.swift` (`kern.boottime`), `.restartExcused` at the relaunch, the relief haptic, the guide
      sentence, "closed the app" in the night story; the system alarm that is already ringing is stopped and
      re-armed for wake + alarmDuration when our alarm starts
- [x] Opus check (2026-10-06 19:35): SleepCore 207 tests, app 232 tests / 92.34 %, `keys.py` 537 / 0 / 0, the
      generic device build compiles
- [x] Installed by the owner from Xcode (2026-10-07 07:44) and tried with three quick nights; the journal was pulled
      and agrees with what he saw: (1) swiped away after the setup, reopened a few seconds later → the building
      stands ✅; (3) the phone switched off and on after the setup → the building stands ✅; the notices arrive with
      the app closed ✅ (no Focus)
- [ ] Still to prove on the phone: (2) swipe away and STAY away → the warning "SleepHole was closed", the building
      collapses, the night story says "closed the app"; (4) reopen the app while the system alarm rings → only one
      alarm rings
**Accept:** closing the app and using the phone collapses the building; an honest slip (reopened in time) and a
phone restart do not. **Stop.**

### F6 — Paid Apple Developer Program (owner 2026-10-04: "next phase: F6, analyse it first"; the paid team is confirmed by a signed build)
**Analysis (Opus, 2026-10-04; sources: the iOS 27 SDK's `AlarmKit.swiftinterface`, Apple's WWDC25 session 230
"Wake up to the AlarmKit API", the app's `Night/Notifications.swift` and `AppModel.ringAlarm`).**

What the paid team unlocks, by value for this app:
1. **Time Sensitive notifications** – a standard capability (entitlement
   `com.apple.developer.usernotifications.time-sensitive`, no approval by Apple): a notification with
   `interruptionLevel = .timeSensitive` breaks through a Focus. Today every urgent notification is `.active` and the
   owner must allow SleepHole in each Focus by hand (comment in `Notifications.schedule`). The build with this
   entitlement is also the technical proof of the paid team (it failed on the free one, finding 2026-09-29).
2. **AlarmKit** (iOS 26+, the phone runs iOS 27): a system alarm that "breaks through the silent mode and the current
   focus" and fires even when the app is not running; it also shows on a paired Apple Watch. Needs only
   `NSAlarmKitUsageDescription` in Info.plist and the user's one-time consent (`AlarmManager.requestAuthorization()`
   or automatically at the first alarm) – **no special entitlement** (the older note in `PLAN.md` was wrong).
   API: `AlarmManager.shared.schedule(id:configuration:)` with `.alarm(schedule: .fixed(date), attributes:
   AlarmAttributes(presentation: AlarmPresentation(alert: .init(title:, stopButton:, secondaryButton:,
   secondaryButtonBehavior: .custom)), tintColor:), secondaryIntent: <a LiveActivityIntent with openAppWhenRun>,
   sound: .named("<file in the bundle>"))`; `cancel(id:)`, `stop(id:)`, `alarms`, `authorizationState`. A widget
   extension is needed only for a countdown / snooze presentation – not for a plain alert.
3. Later, not now: **HealthKit** (sleep from the Apple Watch as a "verified by the watch" badge), **iCloud** (the
   automatic backup off the phone), **TestFlight** (installs without the cable), a **Live Activity / widget** (the
   buddy on the lock screen during a night).

**How AlarmKit fits the alarm we have.** The in-app alarm (background audio keeps the app alive; it rings for 2 min;
confirming while it rings = complete) stays the main alarm – the rules R3 depend on it. Its weak spot is the case
"iOS ended the app at night": then only five 30-second notifications ring (B3), silent in silent mode / a Focus.
→ **AlarmKit replaces that backup**: at the start of a night / nap schedule a system alarm for wake + 30 s with the
owner's alarm sound; the moment the in-app alarm really rings (the place that cancels the backup notifications today,
`startAlarmSound`), cancel it; also on confirm / abandon. If the app is dead, the system alarm rings until stopped;
its second button opens SleepHole on the confirm panel. Outcome rules do not change ("killed by the system → the
owner's favour"). The five notifications remain only where AlarmKit is unavailable (iOS < 26) or not allowed.

**Proposed phases:**
* **F6a – Time Sensitive notifications (S):** `SleepHole/SleepHole.entitlements` + `entitlements:` in `project.yml`;
  `.timeSensitive` for "Come back!" (`nudge`, `nudge-2`), `grace-end`, `pause-soon` / `pause-over`, the backup alarm
  notifications and `alarm-screen`; everything else stays `.active`; Settings text about Focus updated; tests.
* **F6b – AlarmKit backup alarm (M):** `NSAlarmKitUsageDescription` (EN + SK); a `SystemAlarm` protocol (AlarmKit
  behind `#available(iOS 26, *)`, a fake in tests); consent asked at the first night start, its state shown in
  Settings; schedule / cancel as above for nights and naps; App Intent "Open SleepHole"; device test: start a quick
  night, swipe the app away, wait for the system alarm in silent mode.
* **F6c – later:** HealthKit badge, iCloud backup, TestFlight, Live Activity.
**Owner's answers (2026-10-04):** scope = F6a + F6b now; the bedtime reminder is time sensitive too; the alarm:
"I want OUR digital alarm to ring for sure – it is great – and it should also ring when the app is not running; maybe
set the system alarm ~2 min after ours when the night / nap starts, and cancel it when I enter the PIN. Is that
possible or is your solution better? Then I leave it at Recommended." (Per-weekday schedules: "maybe later, undecided".)

**Final design of the system alarm (Opus – the owner's idea merged with the analysis):**
1. Start of a night / nap (consent given, iOS 26+): schedule ONE system alarm for **wake + 30 s** with the owner's
   chosen alarm sound (`.named(<alarm file>)`), title "Good morning ☀️", buttons "Stop" and "Open SleepHole".
   With AlarmKit scheduled, the five backup notifications are not scheduled.
2. At the wake time, when the in-app alarm REALLY rings (`startAlarmSound`, where the backup notifications are
   cancelled today): **move** the system alarm to **wake + 2 min** (= `rules.alarmDuration`, the moment our alarm
   stops) – so if the owner sleeps through our two minutes, the system alarm takes over and rings until stopped.
   If the app is dead, nothing moves it and it rings at wake + 30 s.
3. Confirming the wake-up at or after the wake time (shake or code) **cancels** the system alarm. Cancelling the
   night / ending the nap cancels it too.
4. **Early confirm (bug B11 – owner 2026-10-04, after the explanation: "Poisti to" = keep the safety alarm):** confirming before the wake time does not leave the owner without
   an alarm: the system alarm is moved to the wake time itself and stays as a **safety alarm**; the result screen says
   so ("Safety alarm at 6:00") with a button to switch it off; it also goes away by itself once it has rung and was
   stopped.
5. Stopping the system alarm in the system's own screen does not confirm anything – the outcome rules R3 are
   unchanged (complete only while OUR alarm rings; killed by the system → the owner's favour).
6. No consent or iOS < 26 → the five backup notifications as today.
**Tasks:**
- [x] F6a code (Sonnet, 2026-10-04): `Notifications.isTimeSensitive(_ id:)` (the night notices `nightIds`, the backup
      alarm ids and the bedtime reminders `reminder-*`; the monthly check and the expiry warnings stay normal),
      `content(title:body:sound:urgent:)`, texts in Settings and the guide, `NotificationsTests` (6 tests); app 172
      tests green, `keys.py` 513 / 0 / 0
- [x] F6a entitlement: on in `project.yml`; a signed device build with it succeeded on 2026-10-04 18:47 (after the
      owner restarted Xcode)
- [x] F6a on the phone: installed 2026-10-04 19:11 together with the night moon and the B20 fix (a signed build
      prepared before F6b started; its changes are saved as a patch so they can be committed apart from F6b)
- [ ] The owner's test (2026-10-07): no warning arrived during a Focus (Sleep and Do Not Disturb) – the cause was
      on the phone: Time Sensitive Notifications were switched off (B21 closed, §11a). Still to do: the same test
      with the switch on; the bedtime reminder during a Focus
- [x] Stale text in `Debug/VibrationTestView.swift` reworded (2026-10-04)
- [x] F6b AlarmKit (Sonnet, 2026-10-04 19:15–19:35): `Night/SystemAlarm.swift` – `SystemAlarm` protocol,
      `AlarmKitSystemAlarm` (one alarm, its UUID in UserDefaults; a new alarm is set before the old one is ended;
      `cancel()` stops a ringing and cancels a waiting one; on iOS 26.1+ `AlarmPresentation.Alert(title:
      secondaryButton:secondaryButtonBehavior:)` – the initializer with a stop button is deprecated there),
      `OpenSleepHoleIntent`, `NoSystemAlarm`, `SimulatedSystemAlarm` (`-systemAlarm allowed|denied|notAsked`),
      `SystemAlarms.forLaunch` (the real AlarmKit only on a device, never in the simulator, under tests or with
      `-mute`), `SystemAlarmMemory`; `AppModel`: `armAlarm`, `moveSystemAlarmBehindOurs` (seam
      `alarmSoundStarted()`), `settleSystemAlarm`, `tidySystemAlarm`, `safetyAlarmAt` / `switchOffSafetyAlarm()`, a
      serial queue for the AlarmKit calls; `SafetyAlarmCard` on Today and the result screen; Settings row "System
      alarm"; `NSAlarmKitUsageDescription` (EN in `project.yml`, SK in `Resources/InfoPlist.xcstrings`); expiry /
      signature texts no longer say "free" or "from Xcode". Opus review: the code read against the SDK interface;
      SleepCore 187, app 196 tests / 92.13 %, `keys.py` 524 / 0 / 0, generic device build OK
- [x] F6b follow-up (Sonnet, 2026-10-04 19:40–19:53) – Opus's decision after the review: **the five backup
      notifications are ALWAYS scheduled, also next to the system alarm** (the AlarmKit path cannot be tested before
      it is on the phone – a night must never depend on it alone; this replaces point 1 of the design above, "not
      scheduled"; they are cancelled when our own alarm really rings, as before). Developer → "System alarm test"
      (`Debug/SystemAlarmTestView.swift`, `AppModel.testSystemAlarm(after:)` / `cancelTestSystemAlarm()`; the test
      alarm is kept like a safety alarm, so Today shows the safety card while it waits; refused during a night / nap
      and while a real safety alarm waits). Opus check: SleepCore 187, app 206 tests / 92.15 %, `keys.py`
      533 / 0 / 0, the generic device build compiles the AlarmKit branch
- [x] **The owner installed the F6b build himself from Xcode and tried it (2026-10-04 ≈ 20:00–20:10):** quick
      night, the app swiped away after the setup → the system alarm rang at the wake time + 30 s with a button
      that opens SleepHole (he also saw a button he calls "snooze" – to verify what the system shows as its own
      stop control); "Open SleepHole" → code → "I'm up" → complete night. Observation: after opening the app
      **two alarms rang at once** (ours started for the rest of its 2 minutes while the system alarm was still
      alerting) → when our alarm starts and a system alarm is alerting, stop it and arm a new one for wake +
      alarmDuration. **His finding: swiping the app away is a loophole** – see "R4" below
- [ ] Remaining owner's checks (the build is on the phone): (1) Settings → System alarm →
      Allow; (2) Developer → System alarm test: lock the phone / swipe the app away → it rings in silent mode with
      his alarm sound, "Stop" and "Open SleepHole" work; (3) a quick night with the app swiped away → rings at
      wake + 30 s; (4) a quick night with the app alive → our alarm 2 min, then the system alarm; a confirm cancels
      it; (5) an early confirm → the "Safety alarm" card, it rings at the wake time, the button switches it off;
      (6) the consent alert during the setup does not count as leaving the app
**Accept:** the owner swipes the app away during a quick night and the system alarm still wakes him in silent mode;
"Come back!" arrives during a Focus. **Stop.**

### Backlog from the owner (2026-09-30) – to discuss / schedule
- [ ] **TestFlight (owner asked 2026-10-07: "how do I put the app on TestFlight, to send somebody a mail?")** –
      answered in the chat, nothing built in the app. State of the project checked the same day: the built app is
      version 1.0 (1) (`Info.plist` carries the literal, `MARKETING_VERSION` 0.1.0 in `project.yml` is not used),
      `ITSAppUsesNonExemptEncryption = false` and the icon set exist; **missing: `PrivacyInfo.xcprivacy`** (the app
      reads UserDefaults and the boot time – both need a declared reason); the Settings → Developer section is in
      every build (no `#if DEBUG`) – a tester would see the quick nights and test screens; the Darwin lock signals
      `com.apple.springboard.*` (`LifecycleMonitor`) are undocumented and the silent background audio keeps the app
      alive – both can be questioned by Beta App Review, which only EXTERNAL testers need (internal testers = people
      in his App Store Connect team, no review). Uploading a build is the owner's step (Xcode → Archive → Distribute).
      **First upload 2026-10-07 16:13 refused: ITMS-90035 "Invalid Signature"** – cause found (§12, same day): Xcode's
      cloud signing writes the owner's accented name into the signature's requirement in another Unicode form than
      the certificate has. Way out: a LOCAL Apple Distribution certificate (Xcode → Settings → Accounts → Manage
      Certificates → + → Apple Distribution), then Distribute again; fallback: re-sign the exported IPA with plain
      `codesign` and upload it with Transporter. **Second try 16:24 with the local certificate: upload accepted**, build
      1.0 (1) is at App Store Connect (state "processing" at 16:28; whether processing ends clean is not known –
      Apple mails the owner). Next for a tester: the owner picks internal (friend joins his App Store Connect team,
      no review) or external (mail / link, Beta App Review first). Before the NEXT upload: a worker makes
      `Info.plist` take version and build from `project.yml` and raises the build number (every upload needs a
      higher one), adds the privacy manifest; the Developer section – the owner decides
- [x] **UI polish (2026-09-30):** bigger fonts on the guide's first page; alarm picker as "Zvonenie budíka" label + full-width
      picker below (long names wrapped the row); preview Play/Stop as round Liquid Glass icon buttons
      (▶ / ■, `.buttonStyle(.glass)` on iOS 26, `.bordered` + `.circle` fallback), left-aligned next to each other
- [x] **Sleep sounds + timer (2026-09-30):** white / pink / brown noise, rain (synthesised or CC0 recording); play for 1 (test),
      5, 15, 30, 45, 60 min or all night – after the timer fade to SILENCE but keep the engine running (keep-alive)
- [x] **Coins earned (2026-09-30):** `Economy` in SleepCore (complete 100, unfinished 50, ruins 0, every 7th
      complete night in a row +200; replayed from real nights like the town). Shown on Dnes (🪙 next to 🔥), in the
      town header and on the result screen. Debug nights pay nothing; the "counts for the town" test night pays.
- [x] **Night pause – built 2026-10-03 (owner 2026-10-02, D17):** "🌙 Pause" button on the night screen,
      10 min per pause; 1st pause of a night free, then 50 / 100 / 150 🪙 … (+50 each, charged at the start, only if
      the coins are there – coins never go negative); a night with no pause +30 🪙 ("undisturbed night", max 130/night);
      the building stays complete; pauses show in the night story + weekly journal. Owner's reason: it must not become
      a habit ("I won't buy L2 buildings, I'll spend it on answering Telegram").
      History of the decision: a trip to the bathroom + 10 min of reading should not collapse the
      building. Options: (a) 1 free break per night up to 10 min; (b) a 70-min pool per 7 days; (c) 10 🪙 per minute
      (a 10-min break = a whole night's 100 🪙, ~3 000 of ~5 300 🪙 a month → too harsh). Agent recommendation: an
      intentional "🌙 Pause" button on the night screen, 1 free per night (10 min), +20 🪙 for an undisturbed night,
      a 2nd pause 50 🪙 flat, the building stays complete. Implementation sketch: `NightEventKind.pauseStarted/
      pauseEnded`, the evaluator ignores away time inside a pause ≤ 10 min, the warning flow starts after it;
      `Economy` gets the bonus / spend. Owner decides first.
- [ ] **R&D centre (owner idea 2026-10-02, OPEN):** start with ~300 🪙, every building (also L1) must be bought /
      "developed" before nights can build it, so coins compete between pauses and growth. Risk: one building per
      level → a monotonous town. Agent ideas (chat 2026-10-02): research *blueprint packs* (3–5 variants at once)
      instead of single buildings; L1 starter pack free; higher-level buildings pay more per night (e.g. L1 100,
      L2 120, L3 150, L4 200) so research is an investment with a return; "first of its kind" +50 🪙 and a
      collection book; the picker needs ≥ 4 researched buildings per level (the "last 3 never repeat" rule).
- [ ] **Live weather → phase TOWN-W (steps 2 and 3)** – the owner's OK for WeatherKit 2026-10-07 ("for now; maybe
      better stations later"): the source is replaceable, candidates for later are MET Norway / Yr and Open-Meteo
      (both free, no key).
- [ ] **Robotic announcer voice (owner's idea 2026-10-07):** he likes the computer voice of the game M.A.X.
      ("Construction complete", "Begin"). The game's recordings belong to its publisher – buying the game gives no
      right to reuse or redistribute them, so they must never be committed here or shipped in a build for others.
      Our own lines are fine: (a) on the device – `Voice` (AVSpeechSynthesizer) rendered through AVAudioEngine
      effects (flat pitch, ring modulation, radio band-pass), English and Slovak, no files; (b) offline in
      `tools/audio/` – a free synthesiser + our own processing → CAF files. It must be an original voice in that
      spirit, not a copy of the recordings. Opus recommends (a) first. Waits for the owner.
- [ ] **Building shop (next):** prices L1 100, L2 200, L3 400, L4 1000 (`Economy.price`). Owner's intent: you spend
      a long time in villages/suburbs before a block of flats, police comes much later. Open: when to choose
      (at "Začať stavbu"?), what if coins are short (proposal: a free random L1), pay on start or on completion,
      ruin repair price.
      **Owner's proposal (2026-09-30):** from L2 on you BUY buildings of the unlocked levels; coins are charged
      immediately, but the building is NOT built at once – it goes to a "waiting" pool. Every night the picker
      chooses either a free L1 building or one of the bought, not-yet-built ones. Open details (agent's
      recommendation in the chat of 2026-09-30): chance bought vs. L1, what a ruin does to a bought building,
      refunds, duplicates, lit streets.
- [ ] **Economy (coins)** – owner's idea: a complete night pays coins (e.g. 100 for L1, more for higher levels);
      from L2 on you BUY buildings you want (~200 coins each); an "allowed apps" slot costs 1000 coins and can be
      changed once a year. Needs a design session (open questions in the chat of 2026-09-30).
- [ ] **Allowed apps during the night** (later, after F6): let 3 chosen apps (Podcasts, YT Music, Spotify…) not
      collapse the building. Needs FamilyControls/DeviceActivity (paid account + distribution entitlement) and
      contradicts D3 (no Screen Time APIs) → owner decision required.
- [ ] **Alternative distribution in the EU** (DMA): alternative app marketplaces (e.g. AltStore PAL) / web
      distribution – only relevant if SleepHole ever goes public; requires the paid account + notarization.

### i18n – English version (owner: important for Kenney and Apple)
- UI texts are Slovak literals. SwiftUI `Text("…")` literals are `LocalizedStringKey`s → Xcode extracts them into a
  String Catalog (`Localizable.xcstrings`) automatically; add `en` there.
- Texts built in Swift code need `String(localized:)`: `GuideText`, `SK` plurals (use the catalog's plural
  variations instead), notifications, `AlarmSound.title`, `Ambience.title`, result/outcome texts.
- Catalog building names: add `nameEN` (or a string key) to `catalog.json` via `make_recipes.py`.
- **Sprites with Slovak signs** (MÚZEUM, GALÉRIA, KNIŽNICA, RADNICA, ŠKOLA, HASIČI, POLÍCIA, NEMOCNICA): render an
  English variant of those ~9 sprites (`l3-police@en` …) and pick the file by locale; everything else is language-free.
- Persisted values already use stable ids (ambience ids since 2026-09-30, alarm file names, catalog ids).

### F7 — Assets
- [ ] **More L3 buildings** (owner request 2026-09-29 – L3 has only 5, the town repeats them): e.g. post
      office (POŠTA), church, hotel, stadium, train station, market hall, cinema (KINO), swimming pool
      (KÚPALISKO), town library already exists in L2 – compose from Kenney kits in `make_recipes.py`
- [ ] More L2/L4 variety via `make_recipes.py` (append new ids only), later own Blender models

---

## 11. Testing strategy
* **SleepCore:** Swift Testing, table-driven, `FakeClock`, fixed `TimeZone(identifier: "Europe/Bratislava")`
  and `Locale(identifier: "sk_SK")`. Target ≥ 90 % of the rules code.
* **App:** debug "Rýchla noc" on the simulator for flows; real device for lifecycle/audio (the simulator
  does not emulate protected-data notifications).
* Every bug found in a real night → first a failing SleepCore test from the event log, then the fix.

---

## 11a. Bug backlog – audit of 2026-10-03 (owner request: "analyse the whole project, list the bugs")

Sources: full code read, the owner's data pulled from the iPhone (`docs/device-logs/2026-10-03-audit/`,
git-ignored – no personal details in this public file), simulator runs with that store (`STORE=… tools/sim_shot.sh … -screenshot`).
Severity: H = can cost a night / a wake-up, M = wrong or annoying, L = cosmetic. Cost: XS ≤ 15 min, S ≤ 1 h, M = one session.

| # | Sev. | Cost | Bug | Fix idea |
|---|---|---|---|---|
| ✅ | M | – | Sleeping cat stayed on screen over the Town tab: `withAnimation { tab = 1 }` (island tap) left the TabView half-switched; in the simulator the tab did not switch at all | fixed: plain `tab = 1` |
| ✅ | M | – | Today island lost its road and looked smaller after the 4th house (3×3 window centred on the newest building) | fixed: `TownRender.islandWindow` = occupied lots of the newest block + the streets they touch |
| ✅ B1 | H | – | `AppModel.ringAlarm` cancels the backup-alarm notification before the in-app alarm is known to play; `AudioKeeper.ringAlarm` can return silently, and `alarmPlayer.play()` on an engine that could not start (phone call / another alarm at wake time) raises an Obj-C exception → crash → no alarm at all | cancel the backup only after `isAlarmRinging && engine.isRunning`; guard the play |
| ✅ B2 | H | – | The 7-day expiry reminder (§6.4 `expiry`, ticked in F4) does not exist in code. The profile runs out 7 days after its CREATION, e.g. 2026-10-06 14:23 for the current one | read `ExpirationDate` from `embedded.mobileprovision`, notify 24 h + 3 h before, show the date in Settings |
| ✅ B3 | H | – | If iOS kills the app at night, the only alarm is ONE notification (≤ 30 s sound, silent in silent mode / Focus) | chain 4–5 backup notifications 30 s apart now; AlarmKit in F6 |
| ✅ B4 | M | – | Trip tolerance is per trip: several trips of 6–7 s within a minute pass, while one 12 s trip is 1 s from a collapse | with the pause (D17): one budget of seconds per night instead of 13 s per trip |
| ✅ B5 | M | – | "Regularity" = spread of clock times, so moving the bedtime by half an hour (a free schedule change) shows ±13 min although every start was within ±3 min of its bedtime. Matters for the animal rules | measure start − bedtime (bedtime into `NightResult`) |
| ✅ B6 | M | – | Jokers: the automatic bronze uses up the month, so the morning after the first missed night silver / gold are blocked ("already used") – exactly the holiday case | allow a manual joker that starts on the auto-bronze night to replace it |
| ✅ B7 | M – accepted by the owner 2026-10-04 (two follow-ups in §10 B7) | – | Contrast: disabled "Go to sleep" / "Nap" text is barely readable on glass, secondary captions are weak in dark mode, the sun sits right behind the large titles "Dnes" / "Nastavenia" | own disabled style, captions `.primary.opacity`, keep sun/moon out of the title zone |
| B8 | L | S | Battery / speed (measured: `@Observable` does NOT notify on equal assignments, so the 1 s `refresh()` is harmless): the Today island redraws all its sprites in a `Canvas` 20×/s only to bob 4 pt, plus sky, buddy and flame timelines; `coins` / `streak` / `stats` replay the whole history with several SwiftData fetches on every access; Settings encodes the whole backup for `ShareLink` on every render (each slider tick) | static island + `.offset` animation, cache derived values per data version, lazy backup export |
| ✅ B9 | L | – | "Screen checks" counts the unlock after the alarm as a check | ignore unlocks after `alarmFired` |
| B10 | L | XS | A nap cannot be ended early: waking a few minutes before the end means waiting for the alarm | product decision: allow confirming in the last ~20 % |
| B11 | L | – | Confirming up to 30 min early cancels the alarm; falling asleep again = no alarm | owner 2026-10-04: solved in F6b – after an early confirm a system safety alarm stays armed for the wake time |
| B12 | L | XS | Restore: a backup without a town name / language keeps the current ones ("the backup is the whole truth" otherwise) | assign nil too |
| B13 | L | XS | A counted test night enters the averages / regularity with its daytime start | exclude `bonus-` records from time stats |
| B14 | L | XS | `.audioResumed` is also logged for route changes (headphones) → noisy night journal | separate event kind |
| B15 | L | S | The guide does not mention jokers; first Town view shows a tiny town in a big meadow; night-detail header hides under the nav bar after the auto-scroll; glass tab bar refracts the text under it | texts + insets |
| B16 | L | S | Tooling: `keys.py --prune` reformats the whole catalog; ~~`buddy-cat` is not in the render pipeline~~ (done with P2: `buddy_recipes()`); launch args match bare words (`town`); `test_app.sh` prints a stray "unable to find utility simctl" | fix the tools |
| B17 | – | – | Not detectable by design (no Screen Time API): Notification / Control Center over the app, replying from a banner or the lock screen | document only |
| ✅ B19 | M | – | Sleep sound is not remembered (owner 2026-10-03): after he stops the sound during a night, the next night starts the story again – neither "stopped" nor the sound picked in the night's sheet is stored | persist the night sheet's choice (sound + minutes) into `AppSettings` and a separate "off" flag, so the next night starts silent while ▶ still plays the last sound; test in `AppModelTests` – **fixed 2026-10-03** (see P2, W3), the owner checks it with the P2 build |
| ✅ B20 | L | – | Settings → About shows the app's expiry without the year ("3. 10. 20:39" for 2027-10-03) – it reads as a past date (owner 2026-10-04) | fixed 2026-10-04: `Fmt.dateTimeWithYear` in Settings → About, the Today expiry card and the expiry notifications. Left over: the card still speaks of a "free signature" and of running the app from Xcode – reword now that the team is paid |
| ✅ B21 | – | – | No warning during a Focus (owner 2026-10-07: Sleep and Do Not Disturb – "Come back!" never arrived and the building collapsed after 13 s) | not a bug in the app: Time Sensitive Notifications were switched off in iOS (owner, same day); the code marks the night's notices `.timeSensitive` and the build carries the entitlement. Follow-up he asked for: the app warns while the switch is off (§10 TOWN-W step 0b). Not re-tested with the switch on |
| B22 | L | XS | In a quick night the wake code could not be entered before the alarm (owner 2026-10-07, "does not matter – Cancel night is there"), although `NightWindow.canConfirm` is true from wake − 30 min, i.e. for the whole quick night | reproduce in the simulator first |
| B23 | M | – | No weather badge on the phone: Apple's WeatherKit service refuses the token (`WDSJWTAuthenticatorServiceListener.Errors Code=2`, owner 2026-10-07). The build, its profile and the city are fine (§12, 2026-10-07) | not in the code so far: the owner checks the **App Services** tab of the App ID and waits; still refused the next day → a second `WeatherSource` (§10 TOWN-W step 2) |
| ✅ B18 | H (process) | – | ~70 files had been changed since the last commit (2026-09-30) | done 2026-10-03: 12 commits on `main` (whole files only – what shares files went into one commit); the owner pushes |

**Fixed on 2026-10-03 (same day):** B1 `startAlarmSound()` retries every second and cancels the backup notifications
only when `AudioKeeper.ringAlarm` reports that the sound plays (it no longer calls `play()` on a stopped engine);
B2 `AppExpiry` (reads `ExpirationDate` from `embedded.mobileprovision`) → Today card 48 h ahead, notifications 24 h /
3 h ahead, the date in Settings → About; B3 five backup notifications (wake + 30 … 150 s); B4 + D17 the pause and
`SleepRules.awayBudget` = 30 s per night; B5 `Stats.regularity` = spread of start − bedtime (`NightResult.bedtime`);
B6 a silver / gold joker that starts on the automatic bronze's night replaces it; B9 unlocks after the alarm are no
screen checks.

## 12. Findings log (append-only; agents write here what they learned on the device)
| Date | Finding |
|---|---|
| 2026-09-29 | Asset pipeline: SceneKit offscreen render of Kenney OBJ works; ModelIO needs sandbox disabled. |
| 2026-09-29 | F0: sprites are bundled as folder `sprites/` (lowercase, from the folder reference) → `Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "sprites")`. Audio CAFs sit in the bundle root. Previews moved to `docs/previews/` so they don't ship. Simulator build + launch OK (Xcode 27, iPhone 17 sim). |
| 2026-09-29 | F0 accepted: app runs on the owner's iPhone (dark mode, sprites OK). `DEVELOPMENT_TEAM` must live in `project.yml`, otherwise `xcodegen generate` wipes the signing team. |
| 2026-09-29 | F1: `NightKey` is its own struct (not DateComponents). Night windows use `Calendar.nextDate(... matchingPolicy: .nextTime)` → DST nights are 7 h / 9 h, tested. `.confirmed` also closes an away interval. Town blocks changed to 4×4 lots (pitch 5), see §7.1. Lit streets count as ONE picker item. |
| 2026-09-29 | Rules R2 (D15) implemented in SleepCore, 46 tests green. Agent choices to confirm with owner: 10 s accidental tolerance, calls excused, alarm silent after 2 min but confirm window stays wake+15/+60, night continues after a collapse. |
| 2026-09-29 | Detection design: `protectedDataWillBecomeUnavailable` fires ~10 s AFTER a lock (Data Protection key-discard delay) → not usable to classify a background as a lock. The spike therefore also records Darwin `com.apple.springboard.lockcomplete` / `lockstate` / `hasBlankedScreen`, protected-data state and screen brightness at background time; LifecycleMonitor decides 1.5 s after `didEnterBackground`. Verify on the device. |
| 2026-09-29 | Crash fix: a closure created inside a `@MainActor` class inherits MainActor isolation → Swift 6 runtime check crashes on the audio thread (`_dispatch_assert_queue_fail`, AURemoteIO::IOThread). Real-time callbacks must be created in `nonisolated` functions (`AudioKeeper.makeNoiseNode`). Launch arg `-audioSmokeTest` starts audio at launch for simulator checks. |
| 2026-09-29 | **Device log #1 (iPhone 16 Pro, iOS 26):** background audio keeps running with the screen off and while in Files ✅. Side-button lock: `willResignActive` → `didEnterBackground` (+0.8 s, protectedData=yes, brightness 0.67 – useless) → `hasBlankedScreen` (+1.6 s) → `protectedDataWillBecomeUnavailable` (+1.6 s, NOT 10 s with "require passcode immediately") → `lockcomplete` (+1.6 s) → `lockstate`. Unlock (Face ID): `hasBlankedScreen` → `protectedDataDidBecomeAvailable` → `lockstate` → return to app 2.6 s later (swipe up). App switch (Files): background with no lock signal → leftApp ✅. Fixes: decision delay 1.5 → 3 s; `lockstate` fires on lock AND unlock → read its state via `notify_register_dispatch` + `notify_get_state` (0 = unlocked); unlock-without-return window 3 → 20 s. A late lock signal after a premature leftApp still closes the away interval (`.locked`) and the 10 s tolerance absorbs it. |
| 2026-09-29 | **Device log #2 – spike PASSED.** All scenarios classified correctly with the real evaluator: lock (auto-lock gives brightness=0.00 at background) ✅, Face ID unlock + return ✅, Files 6.8 s after grace → stands ✅, Files ~20 s → collapses ✅, lock screen with the screen waking repeatedly (protectedData toggles on Face ID, `lockstate` stays 1) → not counted ✅, incoming call answered → excused ✅ (audio interruption began/ended, engine restarted). `lockstate`=0 fires only on the swipe-up, app active ~0.8 s later → unlock window 20 → 5 s. Face ID lock screen can't stay open 30 s (auto-blank), so "reading the lock screen" is not a realistic loophole. Replayed as `DeviceLogReplayTests`. Harmless quirk: a lock produces `willResignActive → didBecomeActive` right before the background → a spurious `.returned` (no effect). Still to verify: a whole night (does iOS kill the app?). |
| 2026-09-29 | Test screen got a live "Simulácia noci" (setup grace 10 s) driven by the real `NightEvaluator`. |
| 2026-09-29 | Owner: start window only bedtime −10 min … +5 min (`NightWindow.startLead` = 10 min). Night screen shows an **animated tower crane** (`o-crane-00…15`, primitive boxes in `make_recipes.py`, frames padded to one canvas by `tools/render/align_frames.py`) + blinking "Stavba prebieha…" – the animation is the proof that building goes on; it is replaced by the ruin text when collapsed. |
| 2026-09-29 | **Podcast risk:** a non-mixable `.playback` session gets interrupted when the owner starts a podcast in another app → our audio stops → iOS suspends the app after the lock (no detection, no in-app alarm). Night session now uses `.mixWithOthers`; the alarm switches to a non-mixable session. Audio interruptions are logged as `.audioInterrupted/.audioResumed` night events (diagnostic only). To verify: "Testovacia noc (15 min, príprava 5 min)" with a podcast. |
| 2026-09-29 | Dev launch args (`AppModel.applyLaunchArguments`): `-clearNights`, `-bedtime HH:MM`, `-wake HH:MM`, `-ambience silence|brown`, `-startTestNight` (⚠️ agents: afterwards `xcrun simctl terminate`/`shutdown` the simulator – otherwise the alarm rings on the owner's Mac 4 min later, happened 2026-09-29). On the device: `xcrun devicectl device process launch --terminate-existing --device <UDID> sk.zrebec.sleephole -- -clearNights …` (note the `--`). Settings live in UserDefaults key `settings.v1` (JSON); nights in `Library/Application Support/default.store`. |
| 2026-09-29 | **Podcast test PASSED** (15-min test night, 5-min grace, podcast started during setup, phone locked): no audio interruption events → `.mixWithOthers` works; three unlocks with immediate return not counted; alarm fired exactly at wake; outcome complete. |
| 2026-09-29 | Night screen polish (owner): crane slower (0.22 s/frame), "Stavba prebieha" without dots with a 4 s breathing effect, `NightSky` background (gradient + twinkling stars), building + site plate + crane composed and centred for iPhone 16 Pro width (402 pt), building revealed bottom-up (mask bug fixed). Simulator "iPhone 16 Pro" (CAB9AC31-E34E-404A-B7C5-B18CA7E1A63A, iOS 27) created for layout checks; `-previewProgress 0.5` overrides the progress in screenshots; first launch after install takes ~20–30 s in the simulator. |
| 2026-09-29 | Test night #3 (15 min): 6× lock/unlock with instant return not counted; two short trips after the grace (5.8 s, 4.3 s) stand – NOTE the tolerance is per trip, so many short trips pass; a per-night total cap is a possible later rule (owner to decide). |
| 2026-09-29 | Alarm sounds: 8 choices (`AppSettings.AlarmSound`, each with `rampSeconds`; aggressive ones start at full volume). Settings preview plays through `.playback` (audible with the silent switch), 8 s, disabled during a night. |
| 2026-09-29 | **F3 built.** SleepCore: `TownBuilder` (replays finalized real nights → `TownSnapshot`, ruins/unfinished states, lit-street upgrades, oldest-unfinished bonus), `TownRender` (`IsoProjection`, `SpriteInstance` draw list, bounds/clamp, tap candidates + pixel lookup). App: `TownScene` (SKScene, crop for unfinished, fit-whole-town first view, inertia pan, pinch around fingers, double-tap zoom, alpha-precise taps), `TownSpriteView` (UIViewRepresentable SKView + UIKit gestures), `TownTab` (header with buildings/population, `BuildingSheet`). AppModel owns `townSnapshot/townRender/townVersion/townFocus`, `rebuildTown()` after real nights. One-shot toggle "Ďalšia testovacia noc sa počíta do mesta (1×)" → record id `bonus-<epoch>`, isDebug=false. |
| 2026-09-29 | **Tests & coverage:** SleepCore 66 tests, 95.7 % lines (`tools/coverage.sh`). App target `SleepHoleTests` (hosted, Swift Testing) 39 tests, 88.7 % lines of the app (`tools/test_app.sh` → xcresult + xccov). AppModel takes `clock:`/`settings:`/`servicesEnabled:` for tests; `AudioKeeper.muted` silences tests; `DetectionTest` controller extracted from the view. Pitfalls: ModelContext does NOT retain its ModelContainer (AppModel now holds it; tests must keep the container alive); never call `requestAuthorization` in tests (alert blocks forever); SpriteKit scales are Float (compare with tolerance). Screenshots: `tools/sim_shot.sh out.png 40 -seedNights 60 -openTab town` (seeding is simulator-only; always cleans up the simulator). |
| 2026-09-29 | **Owner fast-night tests (evening):** journal saved in `docs/device-logs/2026-09-29-evening/`. Correct night → building in the town ✅. Leaving after the grace → collapsed ✅, but the "Vráť sa" nudge was NOT seen (likely Focus/DND filtering; Personal Teams cannot use Time Sensitive notifications – build error "Personal development teams … do not support the Time Sensitive Notifications capability"). Confirming after the alarm had stopped gave "complete" → owner says it must be unfinished. |
| 2026-09-29 | **Rules R3** (owner): complete ONLY while the alarm rings (`NightWindow.onTimeConfirm` = 2 min = `alarmDuration`), then unfinished until +60 min, then ruins. The 10 s to return count from the warning: `SleepRules.noticeDelay` = 3 s → collapse after 13 s away. At the alarm a silent notification lights up the lock screen (`Notifications.alarmScreen`, apps cannot turn the screen on). Settings show the notification permission + a hint to allow SleepHole in Focus. 🔥 `StreakBadge` on Dnes/result (`AppModel.streak`). First-run guide (`GuideView`, 6 pages, texts generated from the rule constants) + "Tvoja prvá noc" checklist before the first real night; both stored in SwiftData `UserProgress`. Guide tip about iOS night updates (restart kills the app → counts in the owner's favour, only the backup notification rings). |
| 2026-09-29 | **Bug fixed – "Vráť sa" never sent:** `AppModel.append` checked `collapsedAt` AFTER storing `.leftApp`; an open away interval counts until wake → always "collapsed" → no nudge. Now evaluated before storing (`nudgesSent` counter, regression test `leavingAfterTheGraceSendsExactlyOneWarning`). Finishing the guide also asks for notification permission if the button was skipped. |
| 2026-09-30 | **First real night ✅** (`docs/device-logs/2026-09-30-first-night/`): started 20:57:25, setup in other apps until 21:02:21 (4 s before its end), locked 21:02:28; 4 short unlocks (21:12, 22:01, 23:46, 00:03) with instant return – not counted; confirmed 04:26:03, before the 04:30 alarm (so the alarm never rang); app never killed; outcome complete, building `l1-house-j-a`. |
| 2026-09-30 | **Owner bug fixed:** setup time is now until `max(start, bedtime) + setupGrace` (`NightWindow.setupEnds`) – an early start gives more setup time (20:51 → until 21:05 = 14 min). Warning notification 15 s before the setup ends ("⏳ Ostáva 15 s na prípravu"). The trip rule is unchanged (warning after ~3 s, 10 s to return). `confirmedByShake/confirmedByCode` diagnostic events. Credits screen (Nastavenia → Poďakovanie). Paid-account TO-DO: `docs/TODO-APPLE-DEVELOPER.md`; Kenney thank-you email draft: `docs/drafts/email-kenney.md`. Kenney has NO rain/ambient audio (the All-in-1 bundle already contains everything he made) → rain must be synthesised or come from CC0 recordings. |
| 2026-09-30 | **Settings bug:** two Buttons in one Form row fire TOGETHER on a tap (default style) → "Stop" also triggered "Play", the preview never stopped/switched. Fix: `.buttonStyle(.borderless)` per button (+ glass via `.glassEffect` modifier), `SoundPreview` controller that switches the noise live (`switchTo`) and stops reliably; regression test `soundPreviewSwitchesLiveAndStops`. Pickers are now standard rows (label left, value right) with short titles + a detail footer. |
| 2026-09-30 | **Sleep sound = exact duration** (owner): `AudioKeeper.sleepTimer(seconds:volume:)` plays in a seamless loop for EXACTLY the "Hrať" time (last 5 s fade, silent at the end, engine keeps running; nil = until ■/all night), works with the screen off (background audio). Settings ▶ uses it (`SoundPreview`, no more 10 s preview). During a night the owner can start/stop it from the night screen (`SleepSoundSheet` → `AppModel.playSleepSound/stopSleepSound`) – allowed because the app stays in the foreground. App tests 53, app coverage 90.3 %. |
| 2026-09-30 | **Rain v2:** owner's recording (InspectorJ, Freesound 346642, CC BY 4.0) analysed: 51 % energy < 100 Hz, centroid 235 Hz, ~0.7 distinct drops/s → a dark "wash" (sounds like noise). New `rain_tent.caf` synthesised by `tools/audio/make_rain.py` (drop = impulse → damped fabric resonator 170–420 Hz + tiny click, Poisson 40–100 drops/s with gusts, heavy tree drips, soft rain bed, stereo; ~35 audible drops/s, 60 s seamless loop) + `rain_window.caf` (the recording as a seamless loop, credited in the app + README + `sounds/CREDITS.txt`). `AudioKeeper` plays loop ambiences through an `AVAudioPlayerNode` (.loops); the level/timer logic is shared (`setLevel`). Ambience id "rain" = rain on a tent (old settings still load). |
| 2026-09-30 | **F4 part 1:** `Stats` (SleepCore: streaks, coins, circular-mean start/wake, regularity = circular std-dev, 35-day calendar, 30-night series) + `StatsView` (tiles, calendar grid, averages, regularity verdict, Swift Charts start times vs bedtime, level progress). **Backup:** `BackupFile` JSON (settings, guide flags, all nights with events) – Settings → Záloha: export via ShareLink, import via fileImporter + confirmation (refused during a night / newer version); auto-backup after every real night to Documents (`UIFileSharingEnabled` → Files → On My iPhone → SleepHole). **Level-up celebration** (`ConfettiView` + `LevelUpCard` with sample buildings). **Ruin repair:** a complete night finishes the oldest unfinished building, otherwise repairs the oldest ruin (`repairedLater`, not lit-street ruins). SleepCore 77 tests / 96.8 %, app 60 tests / 91.9 %. |
| 2026-09-30 | **Nap implemented** (D16): SleepCore `NapPlan` (window, session, rules, reward; 100 % covered), `AppSettings.napPlan` optional (old settings still load), `NightRecord.isNap`, `AppModel.napBlockReason/startNap/napSummary`, excluded from town/streak/levels/night stats, coins added; `HomeView` (replaces Idle/CanStart) with both buttons, `NapResting` screen, nap result, Settings → Odpočinok (segmented 30/60 + window), guide row + schedule note, stats card. SleepCore 81 tests / 97 %, app 62 tests / 92 %. |
| 2026-09-30 | **Night story in Štatistiky:** tappable calendar (plain buttons – borderless tinted the day numbers; `Text(verbatim:)` for years, LocalizedStringKey formats Ints as "2 026"; auto-scroll to the detail). `NightReport` (SleepCore) derives start, first lock, alarm fired/stopped, wake + confirm method, trips during/after the setup (with durations), screen checks (= `.unlocked` events), calls, relaunches, collapse; replay-tested on the owner's first real night (2 setup trips, 5 screen checks). `NightDetail` shows it with the building sprite, coins and that afternoon's nap; a missed day says the app did not run. |
| 2026-09-30 | **I18N done** (`docs/IMPLEMENTATION_I18N.md`): `AppLanguage` (en default, sk) + `Lang.current` + `L(_ key: String.LocalizationValue)` looks strings up in `<lang>.lproj` of the bundle (not the system language); `Fmt` for times/dates (SK always 24 h, EN follows the iPhone's 12/24 h via `DateFormatter.dateFormat(fromTemplate: "j")`; ICU puts U+202F before "PM"). Stored in `UserProgress.languageRaw` (nil → EN, no migration, Q1) + `BackupFile.language` (optional). Live switch: `RootView` puts `.id(language)` on each tab's content (tab selection survives) + `.environment(\.locale)`. Keys are extracted by the compiler because `project.yml` sets `LOCALIZED_STRING_MACRO_NAMES = L …` + `SWIFT_EMIT_LOC_STRINGS`; `tools/i18n/keys.py` diffs the `.stringsdata` build output with the catalog (Xcode's catalog sync only runs in the IDE). SK texts were copied verbatim from the pre-i18n code (not from the spec tables – they differ in details). Plurals: `Plural.minutes/seconds/nights` (catalog one/few/many/other) replace the `SK` helper; multi-number sentences embed the plural phrase as `%@` (no multi-variable substitutions needed). Legacy persisted values ("Hnedý šum") are marked `// i18n-ignore`. **Signs:** `render_sprites.swift` renders `<id>.en.png` with the SLOVAK sign's bounds (identical size/anchor → town placement unchanged); `EN_ONLY=1` refreshes `nameEN`/`fileEN` without rewriting any existing PNG – used here so the owner's town stays pixel-identical. `SpriteLibrary` caches per file. SleepCore 84 tests, app 75 tests / 92.3 %. Installed on the iPhone as an update; before that the phone's SwiftData store was pulled to `docs/device-logs/2026-09-30-before-i18n/` (git-ignored) and its migration (new optional `languageRaw`) was verified in the simulator: all nights + the town survive, language nil → EN. |
| 2026-09-30 | **Vibrations too weak (owner):** an unprepared `UIImpactFeedbackGenerator(.medium)` is a barely noticeable tick, and `kSystemSoundID_Vibrate` depends on Settings → Sounds & Haptics (silent mode). Now Core Haptics with long, strong patterns (`Haptics.pattern`), engine created with the app's audio session (`CHHapticEngine(audioSession:)`, `playsHapticsOnly`, no auto-shutdown, `start()` before every play) so it can also play in the background during a night; the system vibration is added for lock/warning. No permission exists for vibrations; the iPhone settings that silence them are listed in Settings → Developer → Vibration test (plays each pattern + shows the Core Haptics result). |
| 2026-09-30 | **Owner test: apps cannot vibrate in the background** – neither Core Haptics nor `kSystemSoundID_Vibrate` work once SleepHole is not on screen (lock, podcast app). In-app haptics now only `start` + `relief`; at night the NOTIFICATIONS vibrate. The "Come back!" nudge used `.defaultCritical` – critical sounds need an Apple entitlement and stay silent without it → `.default`, and it is sent twice (+0.2 s and +5 s, `nudge`/`nudge-2`, both cancelled on return). Night screen: the clock sat right under the Dynamic Island (covered when the island expands for a podcast) → 36 pt lower, the content scrolls above the tab bar. `tools/i18n/keys.py` now reads only the newest `.stringsdata` per file (device + simulator builds) and has `--prune`. |
| 2026-09-30 | **Owner bug: no sleep sound after starting a nap/night** (not from the night screen, not from Settings). Causes: (1) the Settings preview has its own `AudioKeeper`; its `stop()` deactivated the SHARED audio session under the running night → the night's engine went silent for good; (2) a stopped `AVAudioEngine` (session deactivated, route change – headphones/Bluetooth post `AVAudioEngineConfigurationChange`) was never restarted, later changes only set the gain of a dead engine. Fix: `AudioKeeper.runningKeepers` – only the last keeper deactivates the session; `ensureRunning()` (reactivate session, restart engine, reschedule the loop) before every sound change + on configuration changes; Settings ▶/■ control the night's own sound during a night (`model.playSleepSound/stopSleepSound`), the preview stops when a night starts; `sleepSound` also reflects the sound started from Settings at the night start; Core Haptics `playsHapticsOnly`. **Owner bug: broken layout** after the night screen became a ScrollView (narrow, always scrollable, "Cancel night" under the tab bar): `FitOrScroll` (ViewThatFits: full-height layout when it fits, scroll only otherwise), full-width confirm panel, a compact construction site in the morning when the confirm panel shows. |
| 2026-09-30 | **Sound stories** (owner: "like a survival Let's Play without commentary – you imagine what happens from the sounds; random is good here"). Ripping game / YouTube audio is not legal → built from Kenney CC0 packs already in the bundle (Impact Sounds, RPG Audio, Foley Sounds): `tools/audio/make_stories.py` writes 105 one-shots `st_<group>_<n>.caf` (mono 44.1 kHz PCM, trimmed, -3 dB peak) + 3 synthesised 60 s beds `bed_forest/cave/workshop.caf` (AAC in CAF via `afconvert` – ffmpeg can't mux AAC into CAF; gapless thanks to the packet table; levelled to -24 dB RMS, ~0.9 MB each). Ambience cases `story-forest|cave|workshop` (bed through `loopPlayer`), `StoryTeller` (Night/Stories.swift, seeded RNG, 6 scenes per world, never the same scene twice in a row, pauses 6–25 s or sometimes 40–90 s) schedules one-shots on 4 `AVAudioPlayerNode`s → mixer → reverb (cave large chamber 45 % wet) → main mixer; volume/fade follow the sleep timer (`setLevel`). |
| 2026-09-30 | **Stories v2 – chapters + the journey** (owner answers: chapters in order, carpentry workshop, night nature + animals + water + weather, CC0 only). 50 CC0 recordings via the official Freesound API (`tools/audio/freesound.json` manifest, `fetch_freesound.py`, key in `~/.freesound_key` – never in the repo; raw OGG previews in git-ignored `assets/freesound/`, authors in `assets/audio/CREDITS-freesound.txt`). `make_stories.py` cuts 78 clips (window / split-by-silence, `tame()` soft limiter, all mono 44.1 kHz so the 4 story players share one format; AAC 64k) and mixes 7 chapter beds (75 s, AAC 96k, −27 dB RMS, 3 dB headroom – AAC overshoots on camp-fire clicks). Swift: `StoryChapter` (bed, weighted scenes, opening scene, reverb, pauses), `StoryWorld.journey` = cabin → carpentry → wind → storm → lake → after (10–20 min each, sleepy long pauses at the end); `AudioKeeper` crossfades the beds with two players (`crossfadeBed`, 8 s) and keeps the chapter's bed on volume changes / engine restarts. Ambience ids unchanged (`story-workshop` is now the carpentry), new `story-journey`. |
| 2026-09-30 | **5 new alarms, App-Store-safe** (owner wants to publish one day): Zedge is NOT safe (user uploads, personal-use licence) → CC0 Freesound recordings (manifest `use: "alarm"`: dawn chorus, singing bowls, a Symphonion music box playing the public-domain "Klosterglocken", kalimba) + Bach's Prelude in C (public domain, own harp synthesis). `make_alarms.py` renders them (≤ 28.5 s mono PCM CAF – notification sounds must be ≤ 30 s and PCM; `python3 tools/audio/make_alarms.py birds bowl …` renders only the named ones so the old alarms stay byte-identical); peaky recordings are compressed to the loudness of the others (`rms_db`). `AlarmSound` raw values = file names (persisted, never rename). |
| 2026-09-30 | **LIM done.** SleepCore `RenamePolicy` / `SchedulePolicy` (Limits.swift) + `breaks: [NightKey]` in `Progression.currentStreak/bestStreak`, `Economy.ledger/earned`, `Achievements.unlocked`, `Stats.summary`, `WeeklyJournal` – a break is the night key after the change day; `currentStreak` also honours a break for tonight (lastNight + 1) so the streak shows 0 immediately. App: SwiftData `CoinSpend` (coins = earned − spent) + `ScheduleChange` (breakKey only when not free); `UserProgress.lastRenameAt` (anchor; a typo fix does not move it – otherwise endless free edits), `lastFreeRenameAt`, `scheduleCalibrationStart` (set on the first launch with LIM – for the owner 2026-09-30), `schedulePromptMonth`. New ModelContainer types must be registered in `SleepHoleApp` AND every test container. Rename only via `RenameTownAlert` (cost in the message, button disabled when short); Settings schedule = draft + "Save" + confirmation (only when a streak > 0 would be lost); guide first run applies directly (free, not recorded before onboarding), replayed guide shows it read-only. Monthly card (`showsMonthlySchedulePrompt`, days 1–3) + repeating notification `schedule-month` on the 1st at wake + 1 h (re-scheduled with the reminders). Numbers in `L()` get grouping ("5 000" / "5,000"). |
| 2026-10-02 | **Design review (owner: "plain design")**: Today is a white page with two grey disabled buttons, Stats/Settings stock system look, Town has a white nav bar over a flat green field. Kenney purchase pointless (All-in-1 has everything), Blender not needed (SceneKit pipeline), Kenney 2D backgrounds clash with low-poly 3D. Plan: phase UI (living sky + Today island + glass + micro-animations), iOS 18 target kept with iOS 26 glass behind `#available`. |
| 2026-10-02 | **Phase UI built.** Sky follows the owner's schedule (`Sky.state`: dawn wake −30…+60 min, dusk bedtime −90…0, short days split in the middle, DST-safe). Light mode keeps a light sky even at night (black text stays readable), dark mode keeps a deep one – the system appearance is respected, never forced (only the night screen stays dark). Town: transparent `SKView` (`allowsTransparency`) over `LivingSky`, a meadow diamond under the tiles hides seams between road and grass sprites (they showed the sky), brown soil faces make it a floating island; the nav bar is hidden (the header card names the town, the sun sat under the title). Pitfalls: a long `.random(using:)` tuple closure hit "unable to type-check in reasonable time" → plain loops; writing `Localizable.xcstrings` with `json.dump` reformats the whole file (8 000-line diff) → insert entries as text. `tools/sim_shot.sh` takes `APPEARANCE=dark`, the app `-skyTime HH:MM`. `tools/test_app.sh` now really shuts the simulator down. SleepCore 111 tests, app 93 tests / 92.9 %. |
| 2026-10-02 | **UI-2:** theme / effects / voice settings, splash + WOW, 6 new `fx_*` sounds, voice. Gotchas: `String Catalog` here is written as `"key": {` (no space before the colon) – insert new entries as text in sorted position (scratch helper; `json.dump` reformats 8 000 lines); sound-test titles must be literal `L("…")` or `keys.py` cannot see them. App 93 tests / 91.2 %. |
| 2026-10-02 | **UI-3:** jokers + level rewards + slower animations. Bug caught by the app tests: a counted test night can share its NightKey with a real night – `Jokers.apply` first merged results by key and lost one (coins); it now keeps every result and only adds/replaces protected keys (`resultsSharingAKeyAreAllKept`). `tools/i18n/keys.py --prune` rewrites the whole catalog formatting – remove unused keys as text instead. `swift test` with the Command Line Tools sometimes fails with "TestingMacros plugin not found" → run it with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. SleepCore 123 tests, app 96 tests / 93.0 %. |
| 2026-10-02 | **Sleeping buddy (first taste of plan A, no rules):** Today shows a Cube Pets cat asleep on a Nature Kit camp bed, turned away (Cube Pets have no closed eyes), on a little cloud with breathing + "z Z z" (`SleepingBuddy`, asset `buddy-cat` in Assets.xcassets – rendered from a scratch recipe: bed rot 90 scale 1.6, cat pos (0.05, 0.27, 0) rot 135 scale 0.24; move it into `make_recipes.py` when the pets get their own catalog ids). A `Canvas` inside that ZStack got a zero size – plain `Ellipse` views instead. **Owner bug fixed:** the nap result showed a small 16:9 patch of sky with black bars – a `.background` on a `Group` is sized per child; `TodayView` now gives the Group a full-screen frame first. |
| 2026-10-03 | **Audit + two owner bugs.** (1) Cat over the Town: an ANIMATED TabView selection change (`withAnimation { tab = 1 }`) leaves the tab view half-switched – never animate `tab`. (2) Island: see `islandWindow`. Device data is pulled with `devicectl device copy from … --domain-type appDataContainer` into the git-ignored `docs/device-logs/` (what the nights showed stays out of this public file). The provisioning profile lasts 7 days from its CREATION (`security cms -D -i SleepHole.app/embedded.mobileprovision`), reinstalling does not extend it. New dev args `-screenshot`, `-theme`, `-thenTab 1|island|abandon`; `STORE=<pulled folder> tools/sim_shot.sh` runs the simulator on the owner's real store. Verified: the theme override survives the night screen's `preferredColorScheme(.dark)`. SleepCore 125 tests, app 96 tests / 93.0 %. Bug backlog → §11a. |
| 2026-10-03 | **Pause (D17) + audit fixes B1–B6, B9 built.** SleepCore: `PausePolicy` (10 min, price 0/50/100…, +30 undisturbed bonus), event `.pauseStarted` (a pause is a fixed window `[t, t + 10 min]`, away time inside it is subtracted like a call), `SleepRules.awayBudget` (30 s per night, per trip still 13 s; `NightEvaluator.allowance` tells the warning how many seconds are really left), `NightResult.pauses` (nil = a night from before the pause: old rules, no bonus – older nights keep their coins and their story) and `.bedtime`. App: `NightRecord.pauses: Int?` (new optional attribute – the owner's real store opened fine in the simulator, the migration is automatic), pause button + countdown + resting crane on the night screen, "Out of the app tonight: 12 s of 30 s", notifications `pause-soon` / `pause-over` only while away, result line "+30 for a night without a pause". Test nights never pay for a pause. Dev args: `-thenTab pause`, `-expiresIn HOURS`. A quick night's setup lasts until bedtime (+60 s) + 20 s = 80 s – wait ≥ 90 s before a screenshot of the pause button. SleepCore 136 tests, app 103 tests / 92.4 %. |
| 2026-10-03 | **Owner's confirmations + the verification board (§0a).** Confirmed on the iPhone: the "Come back!" warning, the town map (pan, two zoom levels, tap), coins and streak, the language switch (survives restarts), the theme switch, the voice (works; he keeps it off), the alarm with the ringer switched off. F3 accepted. New bug B19 (sleep sound: stop / night choice not remembered). What the pulled app data showed is summarised only as "used / never used on the phone" in §0a (public repo – no details of the nights here). **Way of working changed (AGENTS.md "WHO DOES WHAT"): Opus plans / analyses / reviews, Sonnet 5.5 subagents implement.** |
| 2026-10-03 | **Cube Pets have named parts and animations** (corrects `NAVRH-ZVIERATKA.md`, "no animations"): `animal-cat` = `body` (the cube is head and body in one, ears included), `Group` (a flat detail on the front face), `tail`, four `leg-*`; the OBJ keeps them as `g` groups, the GLB adds 8 node animations (static, idle, walk, run, eat, dance, gesture-positive / -negative – rotations of body, tail and legs only). There is no separate head and no closed-eye variant – a pose (legs tucked, body lowered / tilted) and closed eyes have to be made in our renderer. |
| 2026-10-03 | **Buddy render (P2, W1).** ModelIO does NOT keep OBJ `g` groups as nodes: the cat loads as ONE node with one geometry of 7 elements (submeshes named `<group>_colormap`, all sharing one vertex source, so every bounding box equals the whole cat's). The renderer now re-splits such a node per element when a part uses a pose. New optional recipe fields: `Part.pitch / roll / pivot`, `Part.pose` (group name or `leg-*` wildcard → hidden / move / rot / scale / pivot), `Part.children` + `attach`, `Part.chamfer / center`, `Recipe.bounds` (shared canvas for animation frames), `src: "@path"` (repo-relative OBJ). Closed eyes: a flat fur-coloured lid does not match (the face has a vertical fur gradient and smooth normals) → `tools/render/buddy_cat_obj.py` writes a cat OBJ whose eye polygons take the face's gradient UVs (`build/buddy/`, git-ignored) + four thin dark lash boxes. Old recipes render as before (differences ≤ 10 px = the same GPU noise two runs of the old renderer show). |
| 2026-10-03 | **P2 buddy in the app + B19.** Built by three Sonnet workers, reviewed by Opus. Lessons: a hosted test window's scene phase is `.background`, so views that pause in the background need an override to be tested (`\.buddyAnimates`); a nested `RunLoop.run` starves SwiftUI `.task`s in the hosted tests → animation tests are `async` and wait with `Task.sleep`; restarting a running `repeatForever` animation with new parameters needs a step back to rest first; two crossfade steps in one update collapse (1 → 0 → 1 = no change) → a 50 ms frame break between the steps. New dev launch args: `-buddy awake|asleep`, `-testNightMinutes N` (the normal, non-compact night layout), `-startNap`, `-mute` (**without `-mute` a test night's alarm rings on the Mac's speakers**). `tools/test_app.sh` prints "unable to find utility simctl" once during the run although the simulator does shut down (tooling, B16). B19: `stopSleepSound()` never stored anything – see P2 W3. |
| 2026-10-03 | **P2b built** (three Sonnet workers: assets, sounds, app). Lessons: an animation canvas grows with its tallest frame – give the view a layout box without the empty top (`headroom`) and let only the tall frames overflow, otherwise every placement shifts; the canvas is not centred on the character (bed + shadow extend right) → centre on a chosen x (0.37), not on the frame; a purr's energy sits mostly below 200 Hz, which a phone speaker cannot play – judge loudness by the band above 200 Hz; effects play through the `.ambient` session, so the silent switch mutes them (the haptic still plays). |
| 2026-10-03 | **Install of P2 + P2b and a fresh profile.** `xcodebuild … -allowProvisioningUpdates` keeps signing with the cached profile in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` as long as it is valid (the first build still carried the profile of 2026-09-29). Moving that file aside and building again made Xcode fetch a new one. **The new profile has `TimeToLive` 365 – it is valid until 2027-10-03**, not for 7 days: the team now behaves like a paid Apple Developer Program team. To confirm with the owner; if so, the 7-day reinstall is history and phase F6 (Time Sensitive notifications, AlarmKit, HealthKit, TestFlight – `docs/TODO-APPLE-DEVELOPER.md` part B) can be planned. Until he decides, the hard rule "no paid-only APIs" stays. Device build + install: `xcodebuild -scheme SleepHole -configuration Debug -destination id=<device> -derivedDataPath build/DerivedData -allowProvisioningUpdates build`, check `security cms -D -i <app>/embedded.mobileprovision` (`ExpirationDate`), then `xcrun devicectl device install app --device <device> <app>`. |
| 2026-10-04 | **SKY finished after an interruption.** The MacBook went to sleep on battery during the night (a keep-awake app does not prevent that) and the app worker stalled without a report – its code was complete; a third worker did the leftovers. Lessons: long unattended runs need the charger; view tests that wait a FIXED real time for an animation to end become flaky as the suite grows – poll for the end state with a generous timeout; a body drawn behind glass cards reads as clutter – keep sky decoration in free sky; `MKLocalSearchCompleter` with a `.locality` address filter lists a city's districts but not the city itself, so the completer runs unfiltered and only `MKLocalSearch` (the resolve step) is filtered to localities. |
| 2026-10-04 | **Owner's verdicts:** the night with the new build went well, the alarm rang in silent mode; the buddy (P2) and its tap reactions (P2b) behave as expected → both accepted (the arched back needs more poses – with our own renders, F7); the real sun and moon behave exactly as expected. The pause was not used that night (he tries it the next one); the sleep-sound stop (B19) was remembered at the nap of 2026-10-04. **Paid Apple Developer Program: active** – the owner received Apple's "Thank you for joining the Apple Developer Program" mail, and the profile of 2026-10-03 is valid for 365 days. The Team ID did not change, so the bundle id and the app's data stay. Xcode's cached account data still calls the team a "Personal Team" (it refreshes in Xcode → Settings → Accounts). Phase F6 can now be planned; the definitive technical proof is the first build with a paid-only capability (Time Sensitive notifications failed on the free team, see 2026-09-29). |
| 2026-10-04 | **The paid team is NOT confirmed – correction of the entry above.** F6a added the time-sensitive entitlement; the owner's Xcode then refused to build: "Personal development teams, including … do not support the Time Sensitive Notifications capability" and "Provisioning profile … doesn't include the com.apple.developer.usernotifications.time-sensitive entitlement". So team `8V2VSXHQ86` is still treated as a free Personal Team, although the profile fetched on 2026-10-03 is valid for 365 days and Apple sent the welcome mail. Opus's earlier conclusion ("the Team ID did not change, the paid team is active") was an inference from the profile's lifetime and was wrong or premature. Likely causes: the paid membership lives on a separate team with its own Team ID (then `DEVELOPMENT_TEAM` must change and the bundle id may have to be registered again – see `TODO-APPLE-DEVELOPER.md` B), or Xcode's account data needs a refresh (Settings → Accounts, sign out / in). The entitlement is commented out in `project.yml` until the owner reports what Xcode → Settings → Accounts and developer.apple.com → Membership details show; the F6a code stays (without the entitlement iOS treats `.timeSensitive` as an ordinary notification). **Lesson: a capability is proven only by a signed device build with it – not by a mail or a profile's lifetime.** Also: a worker's unfinished project change (`project.yml`) broke the owner's own Xcode build – while workers change the project file, tell the owner not to build from Xcode, or work in a worktree. |
| 2026-10-04 | **The paid team IS confirmed (18:47).** The owner restarted Xcode; a signed device build with the time-sensitive entitlement then succeeded and its new profile contains `com.apple.developer.usernotifications.time-sensitive` (valid until 2027-10-04). So the Team ID did stay the same – Xcode had only kept the old "Personal Team" account data until its restart. The entitlement is switched on again in `project.yml`. |
| 2026-10-04 | **Owner's requests in the evening:** (1) the sky must always show something: once the sun has set, the moon appears at the left end of the semicircle and moves along it with real time (he saw neither sun nor moon after sunset – the real moon was still down); (2) Settings → About shows the expiry as "3. 10. 20:39" without the year, which reads as a date in the past → show the year (B20); (3) the contrast follow-ups (accent colour, Form headers) are not a priority – "the blue is readable too". App Store question answered in the chat: an Xcode install lasts as long as its profile (1 year on the paid team), TestFlight builds 90 days, App Store installs do not expire. |
| 2026-10-07 | **R4 and the Focus on the phone (owner's three quick nights, journal pulled into the git-ignored `docs/device-logs/`).** F6b + R4 are committed (three commits) and the owner installed the build himself (07:44). The journal agrees with every observation of his. (1) **A phone shutdown delivered NO termination notice:** no `.closedByOwner` was logged, the relaunch was a plain `.appLaunched` → excused as an unknown death (the owner's favour). The building stands as designed, but the `.restartExcused` / boot-time path has not run on a device yet. (2) A swipe in the app switcher after the setup logged `.closedByOwner`; the relaunch 4 s later ended the trip, the building stands. (3) A closure DURING the setup is free; the owner came back right after the "15 s of setup left" notice. (4) **No warning during a Focus** (Sleep, Do Not Disturb): the trips of 17 s are in the journal, the building collapsed at 13 s → bug B21; the installed build does carry the time-sensitive entitlement. (5) `devicectl … --device` accepts the device's NAME – no UDID is needed in commands. (6) `swift test` with the Command Line Tools fails ("plugin for module 'TestingMacros' not found") – always run it with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The owner turns to the TOWN next: roads first (F5 list) and the weather on Today (backlog). |
| 2026-10-07 | **B21 closed, the shutdown notice checked, the town roadmap (owner, later the same day).** (1) B21: the owner had Time Sensitive Notifications switched off in iOS – no bug in the app; he wants a warning in the app (TOWN-W step 0b). The app can read only its own switch (`UNNotificationSettings.timeSensitiveSetting`), not the per-Focus one. Not re-tested with the switch on. (2) Shutdown: `willTerminateNotification` is posted when iOS ends the app in an orderly way (a swipe in the app switcher); at a power-off the system just kills the processes and Apple promises no notice there – so the missing `.closedByOwner` of this morning is expected. Both paths end the same (an unknown death is excused; with a notice the boot time decides). Open: one test does not show whether it is always like that, and the journal keeps no raw lifecycle signals during a real night (`ProbeLog` is filled only by the Developer detection test). Nothing to change. (3) WeatherKit facts checked against the SDK and Apple's pages: `CurrentWeather` / `HourWeather` carry `temperature`, `condition`, `cloudCover`, `isDaylight`, and the hourly `snowfallAmount` (iOS 18+, our deployment target); 500 000 calls a month are included in the membership; the App ID needs WeatherKit ticked on the App Services tab AND on the Capabilities tab; Apple's forecast blends NOAA, ECCC, DWD, Met Office / ECMWF, JMA and Météo-France (no SHMÚ, no MET Norway) – hence the replaceable `WeatherSource`. (4) This Mac has 8 cores and 8 GB RAM → at most two workers build at the same time; the iPhone 17 simulator has the same point size as the 16 Pro. (5) Owner's idea: robotic announcer lines in the style of the game M.A.X. ("Construction complete") – the original recordings cannot go into this public repo or into any build for others; our own synthesised lines can (backlog). |
| 2026-10-07 | **TOWN-W steps 1 and 2 built (two parallel Sonnet workers, reviewed by Opus).** (1) Roads first: `drawnRoads` = the rings of the started blocks + the frontier ring; the lighting pool is `straightCells(in: drawnRoads) ∩ builtRoads`. An intersection cell that used to be "straight" at a corner can be a junction now, so a replayed town may get its lamps on slightly different cells (the owner's town has no lit street yet). The Town tab's first look is capped at camera scale 4.5 and centres on the whole drawn area – with the block ahead the two street loops no longer fit a 402 pt screen (both fit at ≈ 5.7); left for the owner to judge on the phone. (2) Weather: the SDK's `WeatherCondition` has 34 cases, all mapped; `snowfallAmount` is a length (converted to mm); the attribution URL `weatherkit.apple.com/legal-attribution.html` only redirects (308) to `developer.apple.com/weatherkit/data-source-attribution/`, which is used. The title with the weather in it covered the noon sun (worst: "Dnes · -12° 🌨️") → the value is a navigation-bar item top right; on iOS 26+ the system gives it its own capsule, and an item with empty content would leave an EMPTY capsule, so the item is built only when there is a value. (3) Working notes: the simulator on this Mac is slow under two builds – `tools/sim_shot.sh` needs a wait of 40–75 s, 6–25 s gives white frames; the Agent tool's worktree was branched from `ebf09ed` (two docs commits behind local `main`), merged back with `git apply` of the worktree's diff + copies of the new files (the nine changed files were untouched in the main tree); a worktree worker cannot write outside its worktree (its report could not go to `build/handoff/`); when it finished, the main session's working directory moved into the worktree – commands on the main tree then need `git -C` / absolute paths. `.claude/worktrees/` is git-ignored now. Not verified: anything on a device. |
| 2026-10-07 | **WeatherKit refuses the app on the phone (B23).** The owner ran the tree with steps 1 + 2 from Xcode (15:03) and saw no weather badge; Weather test → "Last error": `Error Domain=WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors Code=2 "(null)"`. (1) How it was narrowed down without touching the running app: `codesign -d --entitlements -` on the device build in Xcode's DerivedData and `security cms -D -i embedded.mobileprovision` show the WeatherKit entitlement in the binary and in the profile; `devicectl device copy from … --source Library/Preferences/sk.zrebec.sleephole.plist` shows the settings (a city is set) and no `weather.cache` key = no fetch ever succeeded. The pulled file holds the wake code – read it in the scratchpad and delete it, never into the repo. `devicectl` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` too. (2) What Code=2 means (Apple Developer Forums, threads 837650, 842908, 834574, read 2026-10-07): the WeatherKit service does not issue a token for this App ID. The cause a DTS engineer found most often: the **capability** is on but the **app service** (the second tab of the App ID) is not – also for a developer who was sure he had ticked both. Others: it started to work by itself the next morning; and one App ID stayed refused for weeks with everything correct while a new App ID of the same team worked at once (FB23888627, no fix by September 2026). (3) A new App ID is no way out here – the bundle id carries the owner's town and nights. The fallback is the replaceable `WeatherSource`. (4) The design "no value → no badge" hides a failing source completely; the only place that tells is Developer → Weather test. |
| 2026-10-07 | **TOWN-W step 0b built (one Sonnet worker, reviewed by Opus in two rounds); steps 1 + 2 committed (five commits, the owner pushes).** (1) An app can read its own switch only together with the permission: the warning shows when notifications are allowed and `timeSensitiveSetting` is `.disabled`. (2) Review catches: the worker's screenshot named "light" was a DARK one (white title, deep sky) – the picture, not the file name, is the evidence; a `Label` coloured `.orange` as a whole puts orange text on a white Form row (≈ 2 : 1) – colour only the icon. (3) `tools/sim_shot.sh` sets the appearance right after `simctl boot`; twice that did not take and the shot came out dark although light was asked for. Opus repeated both Today shots (`-timeSensitive off` and `on`, no `-theme`): both light – the card has nothing to do with it. For a shot that must be light or dark, add `-theme light|dark`. (4) New dev argument `-timeSensitive off|on` (simulator only). (5) The owner asked about TestFlight – see the backlog entry in §10. |
| 2026-10-07 | **TestFlight upload refused with ITMS-90035 "Invalid Signature … is not properly signed" – an Xcode cloud-signing bug with an accented name, not the project.** The owner archived (Release, Xcode 27.0 / 27A266a) and chose Distribute App; the upload itself completed and App Store Connect then failed the build. How it was found, all on the Mac: the distribution logs are in the user's temp folder (`getconf DARWIN_USER_TEMP_DIR` → `SleepHole_<date>.xcdistributionlogs/`, the error in `IDEDistribution.standard.log` / `ContentDelivery.log`, the codesign calls in `IDEDistributionPipeline.log`), and the exported app is still next to them in `XcodeDistPipeline.~~~*/Root/Payload/`. There: `codesign --verify` says "valid on disk" but **"does not satisfy its designated Requirement"**; `codesign -d -r-` shows the requirement `certificate leaf[subject.CN] = 0x…` with the name's accented letter as a plain letter + a combining accent (decomposed), while the certificate's CN holds the single precomposed letter – a byte comparison, so it fails. Every other clause passes (Apple anchor, identifier, team, distribution leaf), the profile ("iOS Team Store Provisioning Profile", WeatherKit + time sensitive, `beta-reports-active`) is right. Why: with no Apple Distribution identity in the keychain Xcode uses a cloud-managed certificate (`DISTRIBUTION_MANAGED`); for that it signs ad hoc with an explicit `--requirements` text built from the certificate's name and pastes Apple's remote signature in (`codesign -e --edit-cms`) – the name gets decomposed on the way into the codesign process. A locally signed build (the archive, development certificate) lets codesign derive the requirement from the certificate itself and is fine. Never write the owner's name into this public repo – the logs and certificates contain it. |
| 2026-10-07 | **The local Apple Distribution certificate fixed the upload (16:24); the phone got the current tree (16:37).** With an "Apple Distribution" identity in the keychain Xcode signs the export itself (`codesign -f -s <hash>`, no `--requirements`, no remote signature): the exported app "satisfies its Designated Requirement", the log says "Upload succeeded", App Store Connect shows the build upload 1.0 (1) as PROCESSING. The three `90035` entries in that attempt's `ContentDelivery.log` belong to the record of the first try. Device install by Opus on the owner's request: `xcodegen generate`, `xcodebuild … -destination 'platform=iOS,name=<device name>' -derivedDataPath build/DerivedData -allowProvisioningUpdates build`, `xcrun devicectl device install app --device '<device name>' build/DerivedData/Build/Products/Debug-iphoneos/SleepHole.app` – the build carries the WeatherKit and time-sensitive entitlements, its profile runs until 2027-10-07. The owner: the weather still does not arrive (B23 unchanged). |
| 2026-09-29 | Owner's first real night: bedtime 21:00, wake 04:30, ambience silence, podcast during the 5-min setup. |
| 2026-09-29 | The owner's iPhone can be installed from the CLI with `xcrun devicectl device install app --device <UDID>` when connected + unlocked (UDID from `xcrun devicectl list devices`; the repo is PUBLIC – never commit device ids, device logs or personal data). |
| 2026-09-29 | Owner: town view must scroll smoothly like SimCity (one continuous map), see §7.2. |
| 2026-09-29 | `swift test` in SleepCore uses Swift Testing (`import Testing`) fine with the Xcode toolchain. |

---

## 13. Glossary
| Slovak (UI) | Meaning |
|---|---|
| Začať stavbu | start the night |
| Vstal som | wake-up confirmation |
| Hotová / Rozostavaná / Ruina | complete / unfinished / ruins |
| Večierka / Budíček | bedtime / wake time |
| Séria | streak |
| Stavebná noc | a night that produced a building (counts toward levels) |
| Dostavaná | an unfinished building completed by a later good night |
