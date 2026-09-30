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
| F3 | Town rendering (SpriteKit) | 🟡 built + installed 2026-09-29 (owner asked for a surprise – no details were told), awaiting first real nights | town shows all past nights |
| F4 | Progression, level-ups, statistics, backup | 🟡 stats/backup/level-up/ruin repair done 2026-09-30; shop + i18n next | one week of use |
| I18N | English (default) + Slovak, in-app switch stored in SQLite | ✅ done (2026-09-30), installed on the owner's iPhone | owner switches the language in Settings and checks both |
| F5 | Living town (day/night, lamps, cars) | ⬜ todo | "I like looking at it" |
| F6 | *(optional, paid account)* HealthKit, AlarmKit, TestFlight | ⬜ later | owner decides to pay |
| F7 | *(optional)* own / extended assets | ⬜ later | — |

**Rule:** work on the first phase that is not ✅, do only that phase, then stop and hand over to the
owner (see AGENTS.md "Checkpoint protocol"). Tick sub-tasks (`- [x]`) in this file as you finish them.

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
Road visibility: a road cell is drawn iff it touches (8-neighbourhood) an occupied cell.
Road sprite: mask of drawn N/E/S/W neighbours → catalog entry with that `connects`
             (lit cells → l2-road-lit-we / -ns; empty mask → crossroad fallback). `RoadTiles.swift`.
Street upgrade: the 4 unlit straight road cells nearest the centre become lit.
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
- [ ] Maybe a per-night cap on total time away (tolerance is per trip today) – ask the owner
- See `README.md` → „Čo nás čaká“ for the owner-facing roadmap and the XS→XXL idea list
**Accept:** a week of real use. **Stop.**

### F5 — Living town
- [ ] Day/night tint, lamp glows, window glints
- [ ] Cars on roads, population counter
**Accept:** owner enjoys looking at it. **Stop.**

### F6 — Paid Apple Developer Program *(only when the owner decides)*
HealthKit sleep analysis (Apple Watch) as a bonus badge "overené hodinkami", AlarmKit alarm (request the
entitlement), TestFlight, drop the expiry reminder.

### Backlog from the owner (2026-09-30) – to discuss / schedule
- [x] **UI polish (2026-09-30):** bigger fonts on the guide's first page; alarm picker as "Zvonenie budíka" label + full-width
      picker below (long names wrapped the row); preview Play/Stop as round Liquid Glass icon buttons
      (▶ / ■, `.buttonStyle(.glass)` on iOS 26, `.bordered` + `.circle` fallback), left-aligned next to each other
- [x] **Sleep sounds + timer (2026-09-30):** white / pink / brown noise, rain (synthesised or CC0 recording); play for 1 (test),
      5, 15, 30, 45, 60 min or all night – after the timer fade to SILENCE but keep the engine running (keep-alive)
- [x] **Coins earned (2026-09-30):** `Economy` in SleepCore (complete 100, unfinished 50, ruins 0, every 7th
      complete night in a row +200; replayed from real nights like the town). Shown on Dnes (🪙 next to 🔥), in the
      town header and on the result screen. Debug nights pay nothing; the "counts for the town" test night pays.
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
