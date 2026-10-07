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

0. **Open phone checks (plan §10 F6 and R4, bug B21 in §11a):**
   * **Time Sensitive Notifications (B21 closed):** the Focus test of 2026-10-07 brought no warning only because the
     switch was off in iOS. The app gets a warning for it (plan §10 TOWN-W step 0b). Still open: the same Focus test
     with the switch on.
   * **R4 – closing the app counts as leaving it:** on the phone since 2026-10-07; reopening in time and a phone
     restart keep the building (confirmed). Still to prove: swipe away and STAY away → collapse; only one alarm when
     the app is reopened while the system alarm rings.
   * **System alarm (F6b):** it rang with the app swiped away (2026-10-04). Still to check: the Developer → System
     alarm test, the safety alarm after an early confirm, what the system's own stop button says (he saw "snooze").
1. **The pause is still untried:** no night up to 2026-10-06 → 07 used the "🌙 Pause" (journal). Ask only whether he
   still wants to try it. Open bugs in plan §11a: B8, B10, B12–B16, B22 (B7 contrast is accepted – two
   follow-ups are listed in plan §10 B7; B11 is solved inside F6b).
2. **Sleep buddy (P2 + P2b): accepted by the owner 2026-10-04.** His remark: the "arched back" has too few poses –
   leave it until we render our own models (F7).
3. **City + real sun & moon (phase SKY, plan §10)** – built and reviewed 2026-10-04 (Settings → Sky with the Apple
   Maps city search, the real sky cached per minute, sun / moon on a small semicircle right of the title, the moon's
   real phase). Check the SKY task list: is it committed, is the FINAL build on the iPhone (an interim build of
   2026-10-03 21:13 with an older semicircle is / was there), has the owner seen the sun and the moon on the
   semicircle? Next in line after it: bug B7 (contrast / transparency on the light sky – the owner asked for it).
4. **Phase TOWN-W is running (plan §10 TOWN-W, approved by the owner 2026-10-07):** 0b a warning when Time Sensitive
   Notifications are off, 1 roads first (always one block ahead), 2 weather on Today (WeatherKit) → **checkpoint A**
   (the owner ticks WeatherKit for the App ID on developer.apple.com: App Services + Capabilities); then 3 rain and
   snow in the town → B; 4 day and night in the town → C. Stop at every checkpoint. Waiting ideas: the robotic
   announcer voice (plan §10 backlog), plan A / B / C (`docs/NAVRH-ZVIERATKA.md`, 5 open questions at the end).

## ⚠️ WHO DOES WHAT – OWNER'S RULE (2026-10-03) – IMPORTANT

**CLAUDE OPUS (THE MAIN SESSION) PLANS, ANALYSES AND REVIEWS. IT DOES NOT WRITE THE IMPLEMENTATION ITSELF.
EVERY IMPLEMENTATION TASK IS HANDED TO A SUBAGENT THAT RUNS ON CLAUDE SONNET 5.5 (`model: "sonnet"`) –
THE CHEAPER WORKER. OPUS IS THE ARCHITECT, SONNET SUBAGENTS ARE THE WORKERS.**

* **Opus (main session):** reads the plan, analyses, designs, asks the owner, splits the work into small tasks,
  writes each task's brief, reviews what comes back (diff, test output, screenshots), keeps the plan and this file
  up to date, talks to the owner in Slovak.
* **Sonnet 5.5 subagents (workers):** code, tests, UI strings, asset renders, builds, simulator screenshots – one
  small, self-contained task per subagent.
* **A brief must stand on its own** (a worker has no memory of the conversation): the goal, the files to touch, the
  acceptance criteria, the commands to run (`swift test`, `tools/test_app.sh`, `python3 tools/i18n/keys.py`), and
  "read `AGENTS.md` first – the hard rules apply to you too".
* **Workers never commit, never push and never install on the iPhone.** Opus checks the result (tests green, i18n
  0 missing) before it tells the owner that something is done.
* Keeping `docs/IMPLEMENTATION_PLAN.md` and `AGENTS.md` current is planning work – Opus does it itself.

## How to work

* **Verification board (plan §0a):** what the owner **confirmed** on the iPhone 🟢, what only **ran** there 📱 and
  what is checked **only by tests / the simulator** 🖥. When the owner confirms or rejects something, move the row
  the same day – "built" is not "confirmed".
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
* Signing: the owner's **paid Apple Developer Program** team `8V2VSXHQ86` (since 2026-10, proven by a signed build).
  In use: Time Sensitive notifications (F6a), WeatherKit (owner's OK 2026-10-07, phase TOWN-W). Other paid-only APIs (HealthKit, iCloud, push) only when the owner
  asks for them. AlarmKit needs no entitlement.
* Night rules **R3** (plan D15 + findings 2026-09-29/30): start only bedtime −10…+5 min; setup until
  max(start, bedtime) + 5 min; after it, leaving the app → warning after ~3 s and 10 s to return (and at most
  30 s out of the app per night in total – see "Away budget"), else the building collapses (calls excused);
  screen off is fine, the app must stay in the foreground; confirm by shake or wake code from wake −30 min;
  complete only while the alarm rings (2 min), unfinished until +60 min. Tone is **cute and never cruel** — no
  shaming copy, ambiguity is resolved in the owner's favour.
  **Closing the app (swiping it away) during a night or nap counts as leaving it** (owner 2026-10-04, plan R4) –
  an immediate warning, the same tolerance; the app killed by iOS itself and a restart of the phone stay in the
  owner's favour.
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
* **Sky (owner 2026-10-04):** with a city set, the sun / moon on Today travels a semicircle that spans the screen from
  left to right (centre in the middle, 310 pt down, radius 150 pt) – the sun in the middle means noon. Never shrink
  or move it. In general: a look the owner has confirmed is changed only when he asks for it.
  **Something is always on the semicircle:** from sunrise to sunset the sun (left → right), from sunset to sunrise
  the moon as the night's clock (it appears at the left end the moment the sun has set and reaches the right end at
  sunrise), drawn with its real phase – even when the real moon is below the horizon.
* **Night pause (owner 2026-10-02, plan D17 – built 2026-10-03):** an intentional "🌙 Pause" button on the night
  screen (after the setup, never for a nap), 10 min each; the 1st pause of a night is free, the 2nd costs 50 🪙, the 3rd
  100, the 4th 150 (+50 each, charged at the start, only if the coins are there); a complete night with no pause pays
  **+30 🪙** (so up to 130 for a level-1 night); the building stays complete. A pause must never turn into a habit.
* **Away budget (owner 2026-10-03):** outside pauses and calls, all trips out of the app after the setup share **30 s
  per night** (`SleepRules.awayBudget`); one trip is still limited to 3 s notice + 10 s. Nights stored before
  2026-10-03 (`NightRecord.pauses == nil`) keep the old rules and get no +30. The **R&D centre** idea is still OPEN.
* **The GitHub repo is PUBLIC.** Never commit device logs, the device UDID, the wake code, health or other
  personal information about the owner. Pulled journals go to `docs/device-logs/` (git-ignored).

## Commands

```bash
cd SleepCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # domain logic tests (the
                                                  # Command Line Tools alone lack the Testing macros)
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
| `assets/buddy/` | the sleep buddy's four frames (source of the `buddy-cat-*` imagesets in `Assets.xcassets`), NOT part of the town catalog |
| `assets/audio/` | alarm loops + sound effects, CAF (ship in the app) |
| `tools/render/` | asset pipeline: recipe generator, SceneKit renderer, previews, reference projection; buddy: `buddy_recipes()` in `make_recipes.py`, `buddy_cat_obj.py`, `buddy_finish.py` |
| `tools/audio/` | alarm synthesis (`make_alarms.py`), rain loops (`make_rain.py`), UI sound effects `fx_*.caf` (`make_sfx.py`) |
| `tools/test_app.sh`, `tools/coverage.sh`, `tools/sim_shot.sh` | app tests + coverage, SleepCore coverage, simulator screenshots |
| `docs/device-logs/` | journals pulled from the owner's iPhone – **git-ignored (public repo, personal data)** |
| `assets/Kenney Game Assets All-in-1 3/` | raw CC0 source bundle, git-ignored, only for re-rendering |

## About the owner

Former IT analyst / PHP & Java developer, new to iOS. Speaks Slovak. Works in small checkpointed steps and
tests everything on the real phone; energy and time vary day to day — keep steps small, explanations
clear, and never pressure the pace. When he asks you to decide, give a clear recommendation with reasons.
