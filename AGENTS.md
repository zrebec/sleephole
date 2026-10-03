# AGENTS.md — SleepHole

You are working on **SleepHole**, a personal native iPhone app (Swift / SwiftUI / SpriteKit / SwiftData)
that builds a sleep habit: start a building at bedtime, leave the phone alone, confirm waking up in the
morning → a low-poly isometric town grows night by night. A SleepTown-like game for one person.

**You have no memory of previous sessions.** Everything you need is in the files below. Read them in order
before doing anything:

1. `docs/IMPLEMENTATION_PLAN.md` — **the plan** (English): status board (§0), decisions, architecture,
   pseudo-code, phase task lists with checkboxes, findings log. **Source of truth for implementation.**
2. `docs/PLAN.md` — product background and the owner's decisions (Slovak). Source of truth for intent.
3. `assets/sprites/catalog.json` + `docs/previews/demo_town.png` — the finished art and how it should look.

## 📌 FIRST THING EVERY SESSION – tell the owner (owner's explicit request, 2026-10-02)

Whatever the owner's first message is (even just "Ahoj"), **start your reply by listing this agenda in Slovak**,
then answer. Remove items here when they are done.

0. ⚠️ **The provisioning profile on the iPhone expires on 2026-10-06 at 14:23 (Bratislava time)** – the 7 days run
   from the profile's creation (2026-09-29), NOT from the last install. After that the app does not launch until a
   build with a fresh profile is installed. The app now warns by itself (Today card 48 h ahead, notifications 24 h
   and 3 h ahead, the date in Settings → About) – still remind the owner and offer to renew it.
1. **Owner tests the night pause** (built 2026-10-03): "🌙 Pause" on the night screen after the setup; and checks the
   remaining bug backlog (plan §11a: B7–B16 are open, B1–B6 + B9 are fixed).
2. **Sleep buddy (plan A, step 2)** – the pet sleeps with you on the night screen (today only a static cat on Today).
3. **City + real sun & moon (S–M, owner 2026-10-02):** Settings → city with autocomplete (label on its own row, the
   field on the row below – long names), a black ✕ after the field turns into a green ✓ once the city is verified
   (debounced ~500 ms check). MapKit `MKLocalSearchCompleter` + `MKLocalSearch` – no location permission, no
   tracking. Today: the sun or the moon on a **semicircle** at its true position for that city (also a rough clock),
   sky brightness and colour from the real sun altitude (pure math in SleepCore: NOAA solar position + simplified
   lunar position/phase, unit-tested). Without a city the sky keeps following the schedule.
4. Then the owner picks plan A / B / C (`docs/NAVRH-ZVIERATKA.md`, 5 open questions at the end).

## How to work

* **Find the current phase:** the first row in §0 of the plan that is not ✅. Work **only** on that phase,
  task by task, ticking `- [x]` in the plan as you go.
* **Checkpoint protocol:** when the phase's acceptance criteria are met, STOP. Update §0 (status) and §12
  (findings), then give the owner a short summary **in Slovak**: what was done, how to test it on the
  iPhone (exact steps), what the next phase will be. Do not start the next phase until the owner says so.
* **The owner commits.** Never `git commit`/`push` unless explicitly asked. Keep changes small and focused.
  When he asks for commits: whole files only (no partial staging), one commit per topic where the files allow it,
  otherwise one commit that describes every topic; he pushes.
* **Long sessions:** before the owner clears the context he runs the `session-handoff` skill (installed at user
  level, `~/.claude/skills/session-handoff`) – a chat-only summary the next session starts from. The plan below
  stays the source of truth; the handoff only carries what is not written down yet.
* **Tests first for logic.** All rules live in the `SleepCore` Swift package and are unit-tested
  (`cd SleepCore && swift test`). UI/system code stays thin.
* If something in the plan is wrong or impossible, don't silently diverge: write it into §12, propose the
  fix to the owner, and adjust the plan once agreed.

## Hard rules (owner decisions — do not change without asking)

* iPhone only, native Swift. No PWA, no Android, no cross-platform frameworks.
* **No Screen Time APIs** (FamilyControls, ManagedSettings, DeviceActivity). The app never blocks anything;
  it only detects leaving the app.
* Free **Personal Team** signing: no HealthKit, AlarmKit, iCloud, push until phase F6.
* Night rules **R3** (plan D15 + findings 2026-09-29/30): start only bedtime −10…+5 min; setup until
  max(start, bedtime) + 5 min; after it, leaving the app → warning after ~3 s and 10 s to return (and at most
  30 s out of the app per night in total – see "Away budget"), else the
  building collapses (calls excused); screen off is fine, the app must stay in the foreground; confirm by shake
  or wake code from wake −30 min; complete only while the alarm rings (2 min), unfinished until +60 min. Tone is **cute and never cruel** — no shaming
  copy, ambiguity is resolved in the owner's favour.
* Levels: nights 1–5 → L1, 6–15 → L1–L2, 16–30 → L1–L3, 31+ → L1–L4 (plan §5.5).
* Coins 🪙 (owner 2026-10-02): complete night by building level L1 100 / L2 120 / L3 150 / L4 200, unfinished half,
  +30 for a complete night without a pause, every 7th complete night in a row +200; nap 50 / 25.
* **Jokers 🛡️** (owner 2026-10-02, plan D18): one per calendar month – bronze 1 night free (also used by itself on the
  first missed night that would break a streak), silver 3 nights 1 000 🪙, gold 7 nights 5 000 🪙. Protected nights
  are `Outcome.excused`: the streak neither breaks nor grows, no building, no coins.
* **Decorative animations** are paced by `Motion.pace` (owner: slower) and must never block the UI (a tap skips them).
  Building prices (shop, next): L1 100, L2 200, L3 400, L4 1000.
* Nap "Odpočinok" (plan D16): 30/60 min, only in its window (default 13:00–15:00), once a day, never builds.
  The home screen always shows both "Ísť spať" and "Odpočinok" buttons (disabled outside their windows).
* UI languages: **English (default) + Slovak** (in-app switch stored in SwiftData `UserProgress.languageRaw`).
  **Every UI string goes through `L("English key")`** (never a bare `Text("…")` literal); the Slovak text (correct
  diacritics) goes into `SleepHole/Resources/Localizable.xcstrings`. Dates/times via `Fmt`. After adding strings:
  build, then `python3 tools/i18n/keys.py` must report 0 missing / 0 without sk. `I18nTests` fails on any Slovak
  literal left in `SleepHole/`. Code, comments, identifiers, agent docs: **English**.
* Limits (owner 2026-09-30, plan LIM): renaming the town – first naming free, typo fix 10 min, 1× per 365 days free,
  else **5 000 🪙**; bedtime / wake changes free on **days 1–3 of every month** and in the **first 7 days**, else
  the 🔥 streak starts again (nothing else is taken away). Coins = earned − spent (`CoinSpend`), never negative.
* Never rename a shipped sprite id (ids are persisted). Add new ones instead.
* **Night pause (owner 2026-10-02, plan D17 – built 2026-10-03):** an intentional "🌙 Pause" button on the night
  screen (after the setup, never for a nap), 10 min each; the 1st pause of a night is free, the 2nd costs 50 🪙, the 3rd
  100, the 4th 150 (+50 each, charged at the start, only if the coins are there); a complete night with no pause pays
  **+30 🪙** (so up to 130 for a level-1 night); the building stays complete. A pause must never turn into a habit.
* **Away budget (owner 2026-10-03):** outside pauses and calls, all trips out of the app after the setup share **30 s
  per night** (`SleepRules.awayBudget`); one trip is still limited to 3 s notice + 10 s. Nights stored before
  2026-10-03 (`NightRecord.pauses == nil`) keep the old rules and get no +30. The **R&D centre** idea is still OPEN.
* **Decorative animations** are paced by `Motion.pace` (owner: slower) and must never block the UI (a tap skips them).
  Building prices (shop, next): L1 100, L2 200, L3 400, L4 1000.
* Nap "Odpočinok" (plan D16): 30/60 min, only in its window (default 13:00–15:00), once a day, never builds.
  The home screen always shows both "Ísť spať" and "Odpočinok" buttons (disabled outside their windows).
* UI languages: **English (default) + Slovak** (in-app switch stored in SwiftData `UserProgress.languageRaw`).
  **Every UI string goes through `L("English key")`** (never a bare `Text("…")` literal); the Slovak text (correct
  diacritics) goes into `SleepHole/Resources/Localizable.xcstrings`. Dates/times via `Fmt`. After adding strings:
  build, then `python3 tools/i18n/keys.py` must report 0 missing / 0 without sk. `I18nTests` fails on any Slovak
  literal left in `SleepHole/`. Code, comments, identifiers, agent docs: **English**.
* Limits (owner 2026-09-30, plan LIM): renaming the town – first naming free, typo fix 10 min, 1× per 365 days free,
  else **5 000 🪙**; bedtime / wake changes free on **days 1–3 of every month** and in the **first 7 days**, else
  the 🔥 streak starts again (nothing else is taken away). Coins = earned − spent (`CoinSpend`), never negative.
* Never rename a shipped sprite id (ids are persisted). Add new ones instead.
* **Night pause (owner 2026-10-02, plan D17, not implemented yet):** an intentional "🌙 Pause" button on the night
  screen, 10 min each; the 1st pause of a night is free, the 2nd costs 50 🪙, the 3rd 100, the 4th 150 (+50 each);
  a night with no pause pays **+30 🪙** ("undisturbed night", so up to 130 per night); the building stays complete.
  Goal: a pause must never turn into a habit. The **R&D centre** idea (buy/develop every building) is still OPEN.
* **The GitHub repo is PUBLIC.** Never commit device logs, the device UDID, the wake code, health or other
  personal information about the owner. Pulled journals go to `docs/device-logs/` (git-ignored).

## Commands

```bash
cd SleepCore && swift test                        # domain logic tests (works without Xcode)
xcodegen generate                                 # regenerate SleepHole.xcodeproj from project.yml
xcodebuild -scheme SleepHole -destination 'platform=iOS Simulator,name=iPhone 17' build
# Sprite pipeline (only when assets change; needs the raw Kenney bundle, run OUTSIDE the sandbox):
python3 tools/render/make_recipes.py
swift tools/render/render_sprites.swift tools/render/recipes.json assets/sprites
python3 tools/render/contact_sheet.py assets/sprites && python3 tools/render/demo_town.py assets/sprites
```

## Map

| Path | What |
|---|---|
| `docs/IMPLEMENTATION_PLAN.md` | the plan (read first) |
| `docs/PLAN.md` | product decisions (Slovak) |
| `docs/NAVRH-ZVIERATKA.md` | next plans A/B/C: pause, sleep buddy, Cube Pets residents, living town (Slovak, owner picks) |
| `docs/IMPLEMENTATION_I18N.md` | full spec for the EN/SK multi-language phase (string inventory, architecture, tests) |
| `SleepCore/` | pure Swift package: schedule, night evaluation, progression, picker, town layout |
| `SleepHole/` | iOS app target (created in F0) |
| `SleepHole/Resources/Localizable.xcstrings` | all UI texts: key = English, `sk` translation, plural variations |
| `tools/i18n/keys.py` | compares the keys extracted from `L(...)` (build output) with the String Catalog |
| `project.yml` | XcodeGen spec (created in F0) |
| `assets/sprites/` | 174 rendered isometric sprites + `catalog.json` (ship in the app) |
| `assets/audio/` | alarm loops + sound effects, CAF (ship in the app) |
| `tools/render/` | asset pipeline: recipe generator, SceneKit renderer, previews, reference projection |
| `tools/audio/` | alarm synthesis (`make_alarms.py`), rain loops (`make_rain.py`), UI sound effects `fx_*.caf` (`make_sfx.py`) |
| `tools/test_app.sh`, `tools/coverage.sh`, `tools/sim_shot.sh` | app tests + coverage, SleepCore coverage, simulator screenshots |
| `docs/device-logs/` | journals pulled from the owner's iPhone – **git-ignored (public repo, personal data)** |
| `assets/Kenney Game Assets All-in-1 3/` | raw CC0 source bundle, git-ignored, only for re-rendering |

## About the owner

Former IT analyst / PHP & Java developer, new to iOS. Speaks Slovak. Works in small checkpointed steps and
tests everything on the real phone; energy and time vary day to day — keep steps small, explanations
clear, and never pressure the pace. When he asks you to decide, give a clear recommendation with reasons.
