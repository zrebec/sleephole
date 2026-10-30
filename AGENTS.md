# AGENTS.md — SleepHole

You are working on **SleepHole**, a native iPhone app (Swift / SwiftUI / SpriteKit / SwiftData)
that builds a sleep habit: start a building at bedtime, leave the phone alone, confirm waking up in the
morning → a low-poly isometric town grows night by night. A SleepTown-like game. It started as the owner's
personal app and he is its first tester, but **it is built for many users and headed for the App Store**
(owner 2026-10-09, see the hard rule "Built for many users").

**You have no memory of previous sessions.** Everything you need is in the files below. Read them in order
before doing anything:

1. `docs/IMPLEMENTATION_PLAN.md` — **the plan** (English): status board (§0), **the roadmap by build (§0b)**,
   decisions, architecture, pseudo-code, phase and build task lists with checkboxes, findings log. **Source of truth
   for implementation.**
2. `docs/PLAN.md` — product background and the owner's decisions (Slovak). Source of truth for intent.
3. `assets/sprites/catalog.json` + `docs/previews/demo_town.png` — the finished art and how it should look.

## 🌅 MONDAY 2026-10-19 – READ `docs/ZAJTRA-RANO.md` FIRST (owner's request 2026-10-18)

On 2026-10-19, before anything else (right after listing the agenda below), read `docs/ZAJTRA-RANO.md` and follow its
steps **exactly and in order** – the morning journal check, build 9's upload, the testers ("What to Test" EN / SK, the
message to his three friends), the clean-install review recipe, his reinstall test of B35, departures.to. Tick a step
there only after its proof is seen. When the whole file is done, say so to him and remove this section.

## 📌 FIRST THING EVERY SESSION – tell the owner (owner's explicit request, 2026-10-02)

Whatever the owner's first message is (even just "Ahoj"), **start your reply by listing this agenda in Slovak**, then
answer. **Keep it short (owner 2026-10-16):** only what is open now, about 30 lines at most. Remove an item the moment it
is done; history goes to plan §12, and the old long agenda is in `docs/AGENDA-ARCHIVE.md` (moved there verbatim
2026-10-16). Work by build – the roadmap is plan §0b.

1. **Build 12 = the boxes, in work since 2026-10-29 ~09:55 (his word "Spusti 11b4a").** His prep-page answers (`state/answers`
   v5 of https://claude.ai/artifact/HA3T7auWRYkfkhLfHRoY6h): the shop is its own tab, the cat unwraps the box, the collection
   inside the shop, "Simulated Gambling" no. Steps (plan §10 REL "Build 12"): **11b4a the shop + the purchase (on his
   phone since 2026-10-29 14:59; his t1–t7 all fine; r1–r3 the morning of 30 Oct on the page above, rewritten as the build
   page)**, **11b4a2 the name (on his phone 18:48, his t8): on screen a box is a "parcel" / "balíček" – never the old
   Slovak word (vulgar slang), never "box" or "package" in a UI text; the code keeps "box"**; the night 29 → 30 complete and his second parcel 06:07 (3× the price); **11b4c the collection + using a parcel joker on his phone since 2026-10-30 07:49 (his z1–z5 on the build page v5)**, **11b4c2 the list of parcels bought (his addition 2026-10-30 ~07:45) on his phone since 14:03 (his z6 on the build page v6)**, **11b4b the opening built and reviewed ~15:10 (merged `9b38dcf`), install on his word**, 11b4d the bubble (+ the coins title digit grouping, §12). Using a joker won from a box
   (no screen yet) → 11b4c (his answer); his first box right away with 11b4a alone, no opening yet (his pick). **Tell him
   where the boxes stand whenever a step ends** ("boxes: n of 4 steps in the app, first box about …"). His worry "it must not
   get mixed up" → records, not counters. Build 11 (1.0 (11)) is with the testers since 07:30; PR #2 merged by him; its page
   https://claude.ai/artifact/Xhg4qaa1hW9tSfKnb5Uxbo (ticks closed 2026-10-30, §12; its description aligned the same day). Leftover worktree
   `.claude/worktrees/agent-a17bd1e1fd4a93e5c` – removing it offered; protecting `main` on GitHub is his click.
2. **Apple's review:** 2026-10-24 ~19:32 build 7 was removed from the review and **1.0 (10) submitted with "Manually release"
   and the build-10 notes (`docs/REVIEW-NOTES.md` = the field, 3 986 / 4 000 characters)** – "Waiting for Review" (still on
   2026-10-30 ~14:20 – 16 days in the queue with the 14 Oct submission; the new Developer Program License Agreement (issued 29 Oct) accepted by him 2026-10-30, checked; the new age-rating questions already
   read NO (nothing to save); **2026-10-30 ~14:55 he requested an expedited review – Apple: "We'll expedite review for SleepHole"** (plan §12); once 1.0 is
   approved, build 12 goes up as 1.1 (12)). Tell him the answer at once. The release itself only on his word (and see the price note in 7). **When a build goes
   to review, repeat this whole agenda to him (his request 2026-10-16).**
3. **His streak:** the night of 2026-10-15 → 16 collapsed (one trip of 13.15s; Notification Center counts as leaving on
   iOS 26); the silver joker saved it (1 000 🪙). October's bronze and silver are used and he will not buy the gold – the
   next failed night this month breaks the streak. Be kind about it.
4. **Later builds (renumbered 2026-10-29):** 13 polishing + accessibility (11d, incl. 10h's `ThickProgressStyle`; the flaky
   `SyncEngineTests` test; "Cancel night" under the tab bar); 14 nights off (11c) + statistics, the bug list and Plans (his
   answer 2026-10-25). **PURPOSE (his idea 2026-10-24, §0b row 13):** the store and TestFlight
   texts are done (plan §12); the guide's first page and the Strict-mode footer wait for build 13; the testers' answers about
   missing notifications decide a stronger gentle mode. Still open: the eight questions at the end of
   `docs/NAVRH-MESTO-STATISTIKY.md`; from 2026-10-14 the seller name on the Business page, "a little tuning of the home screen
   UI", "some AI optimisation", "like a wiper on a car"; from `docs/ZAJTRA-RANO.md` departures.to (Health + Audio).
5. **Owed device checks:** the review recipe on a clean install (NOT the second tester's phone – her iCloud brings her data
   back; a phone whose Apple ID never had SleepHole, or a fresh simulator – asked him), also trying 10f's first-run guide (his
   wish 2026-10-22); R4 – the app killed by iOS in the night and opened while the SYSTEM alarm rings → only one alarm (untried).
6. **Open bugs (plan §11a):** none. B36, B10, B8, B30 and B37 are fixed in build 10 (B10 and the gentle start confirmed by
   him, B37's caption is his c8). His wishes for later: when a bad night comes he checks the cat's ruins line; next month the
   bronze joker → the cat's "streak was safe" line.
7. **Standing notes:** the app is free for now (price 0 since 2026-10-12; a price only after an accountant – never push; his
   reasons stay out of this public repo); he runs the gentle mode since 2026-10-22 (Strict off); App Store Connect can be
   read in his Chrome – every change needs his yes, agreements, bank, tax and legal declarations stay his own clicks; what
   the 2026-10-24 store edits replaced is in plan §12 (for a revert).

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
* **Work by build (owner 2026-10-16: "we must start to behave sensibly").** The roadmap is plan §0b; the build
  in work is its first row that is not finished, and its step list (`8a`, `8b`, … in §10 REL) is the ONLY work in
  progress. Tick `- [x]` as you go. Only the owner adds a step to the build in work; any new idea – his or yours – goes
  into §0b (a later build or "Later") in one line, with your proposed build, and waits. A build is finished only
  when it is reviewed, on his phone, tried in one real night, committed, uploaded and in the tester groups (§0b rule 3).
* **A page for every build (owner 2026-10-22: "do all builds like this from now on, with the permanent store too"):** when a build reaches his phone, publish a Slovak claude.ai page like the build 9 / 10 pages (map below): the steps and the bugs fixed and how, tests for now / evening / morning with the expected result, how to switch the phone, what is confirmed and what is open, and a reply form. Publish it with `capabilities: {db: {}}` – ticks and answers go to `state/answers`, which Opus reads with `ArtifactData`; the browser keeps a copy under the build's key prefix, so never rename keys or ids on a republish.
* **Checkpoint protocol:** when a step or a build is done, STOP. Update §0 / §0b (status) and §12 (findings), then
  give the owner a short summary **in Slovak**: what was done, how to test it on the iPhone (exact steps), what comes
  next. Do not start the next step or build until the owner says so.
* **Keep the agenda short:** the session-start agenda above lists only what is open now (≈30 lines); when something
  is done, delete it there and write the finding into §12.
* **Git: a branch per build and per step (owner 2026-10-25: "the app is getting serious – separate branches, every build
  and step its own branch; you may publish the branches; I will forbid a direct push to main"; his picks the same day:
  a build branch + step branches, Opus opens the pull request, he merges).** `main` holds finished builds only and is
  never pushed to directly. The build in work has `build/<n>` (from `main`); each step has `step/<code>-<short-name>`
  (e.g. `step/11a2-b38-tab-bar`) from the build branch's tip. When a step is reviewed (tests green, i18n 0 / 0 / 0) and
  written into the plan, Opus commits it on its step branch, merges it into the build branch with `--no-ff` and pushes
  both (`git push -u origin <branch>`); the plan, the agenda and `PLAN-BUILDOV.md` are committed on the build branch.
  When the build is finished (plan §0b rule 3), Opus opens the pull request `build/<n>` → `main` (`gh pr create`, a
  detailed description); **merging it is the owner's click on GitHub – Opus never merges into `main` and never pushes
  `main`.** Commits: whole files only (no partial staging), one commit per topic where the files allow it, otherwise one
  commit that describes every topic; detailed messages; the repo is public – scrub personal details first. Workers
  never commit or push. Keep changes small and focused.
* **One step = one session (owner 2026-10-07):** when a step of a multi-step phase is reviewed, merged and written
  into the plan, Opus itself runs the `session-handoff` skill (user level, `~/.claude/skills/session-handoff`) – a
  chat-only summary the next session starts from – and stops; the next step starts in a clean context. No handoff
  while a worker is still running. Use parallel workers inside a step where the files allow it (worktree + its own
  simulator; this Mac builds at most two at a time). The plan below stays the source of truth; the handoff only
  carries what is not written down yet.
* **One simulator job at a time (2026-10-12, plan §12).** Two simulators, or a simulator and a build, running
  together overload this Mac: screenshots come out black or white and tests fail falsely. Run workers that need the
  simulator one after the other; a web-only or Python-only worker may run beside one of them.
* **The owner's Chrome can be driven (since 2026-10-12):** he installed Chrome with the Claude extension and is
  signed in to App Store Connect there (he works in Firefox otherwise). Every change in his account needs his
  explicit yes for that action; bank and tax data, agreements and the trader declaration stay his own clicks.
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
* Night rules **R3** (plan D15 + findings 2026-09-29/30): start only bedtime −10…+5 min (**from build 10b: until +30 min in
  the gentle mode, Strict mode keeps +5 – owner 2026-10-19**); setup until
  max(start, bedtime) + the setup time (Settings, 5 / 10 / 15 min, default 5 – build 9, owner 2026-10-15; stored with the night at its start); **an early start ("Go to sleep early today", owner 2026-10-11, plan §10 EARLY) is
  allowed from bedtime − 3 h, after a short confirmation, with no penalty – the night counts in full and the morning
  does not change; its setup lasts 15 min from the start**; after the setup, leaving the app → warning after ~3 s and 15 s to return (10 s for nights stored before build 9j – owner 2026-10-18) (and at most
  30 s out of the app per night in total – see "Away budget"), else the building collapses (calls excused);
  **using the phone after a lock is detected too – with DOCUMENTED signals only (owner 2026-10-14, after Apple's
  ITMS-90699 refused the undocumented lock notifications):** the phone recognises the user (Face ID / Touch ID /
  code – `protectedDataDidBecomeAvailable`) and stays in use outside the app for 8 s, on the lock screen or in
  another app (the two cannot be told apart) → "used the phone"; it ends with the lock / screen-off notification or
  the return to the app. Lock-screen use WITHOUT recognition (the Camera, the phone in the hand) is no longer seen,
  and unlocking into another app is no longer a separate "leaving" (owner: "the app teaches, it is not a prison").
  **Since phase CARE (owner 2026-10-09) it brings the building down only in "Strict mode" (Settings, default OFF); by
  default the app only reminds gently and the building stays.** A phone without a passcode, or without Face ID /
  Touch ID, cannot tell locking from leaving → a background trip is never counted there (Settings says so); closing
  the app (R4) still counts. The mode is stored with each night at its start; nights stored before CARE count as
  strict; **a pause may start only if it ends before confirming opens (owner 2026-10-14);**
  screen off is fine, the app must stay in the foreground; confirm by shake or wake code from wake −30 min;
  **complete when confirmed within 10 min after the wake time (owner 2026-10-12, was 2 min: a tester's first night
  ended "unfinished" because she confirmed a quarter of an hour after the alarm and the app did not say why – the
  alarm itself still rings 2 min; `NightWindow.onTimeConfirm`)**, unfinished until +60 min. Tone is **cute and never cruel** — no
  shaming copy, ambiguity is resolved in the owner's favour.
  **Closing the app (swiping it away) during a night or nap counts as leaving it** (owner 2026-10-04, plan R4) –
  an immediate warning, the same tolerance; the app killed by iOS itself and a restart of the phone stay in the
  owner's favour.
* Levels: nights 1–5 → L1, 6–15 → L1–L2, 16–30 → L1–L3, 31+ → L1–L4 (plan §5.5).
* Coins 🪙 (owner 2026-10-02): complete night by building level L1 100 / L2 120 / L3 150 / L4 200, unfinished half,
  +30 for a complete night without a pause, every 7th complete night in a row +200; nap 50 / 25; **+5 per calm hour** (owner 2026-10-15, CARE-2a: whole hours from max(bedtime, end of the setup) to the wake time without a trip out of the app, a recognised use or a pause – calls do not spoil an hour; complete and unfinished nights only; nights from build 8 on).
* **Jokers 🛡️** (owner 2026-10-02, plan D18; changed 2026-10-09): **each kind once per calendar month, independently of
  the others** – bronze 1 night free (also used by itself on the first missed night that would break a streak; one
  bronze a month, by hand or automatic), silver 3 nights 1 000 🪙, gold 7 nights 5 000 🪙. So after the month's bronze
  a silver and a gold can still be bought, and a month with a silver or a gold still gets its automatic bronze.
  Protected nights are `Outcome.excused`: the streak neither breaks nor grows, no building, no coins.
* **Decorative animations** are paced by `Motion.pace` (owner: slower) and must never block the UI (a tap skips them).
  Building prices (shop, next): L1 100, L2 200, L3 400, L4 1000.
* Nap "Odpočinok" (plan D16): 30/60 min, only in its window (default 13:00–15:00), once a day, never builds.
  The home screen always shows both "Ísť spať" and "Odpočinok" buttons (disabled outside their windows).
* UI languages: **English (default) + Slovak** (in-app switch stored in SwiftData `UserProgress.languageRaw`).
  **Every UI string goes through `L("English key")`** (never a bare `Text("…")` literal); the Slovak text (correct
  diacritics) goes into `SleepHole/Resources/Localizable.xcstrings`. Dates/times via `Fmt`. **Seconds are written with NO space after the number – `15s`, `%llds`, in English and Slovak, in every text (owner 2026-10-15: "nowhere with a space, nowhere at all"); minutes stay "10 min".** After adding strings:
  build, then `python3 tools/i18n/keys.py` must report 0 missing / 0 without sk. `I18nTests` fails on any Slovak
  literal left in `SleepHole/`. Code, comments, identifiers, agent docs: **English**.
* Limits (owner 2026-09-30, plan LIM): renaming the town – first naming free, typo fix 10 min, 1× per 365 days free,
  else **5 000 🪙**; bedtime / wake follow the **change week** ("týždeň na zmeny", owner 2026-10-15, replaces days 1–3 + the streak reset): the first change opens 7 calendar days of free changes (a confirmation first; onboarding opens the first one), then the schedule is locked for a month (free again from the same day next month); an earlier unlock costs **2 000 🪙** and opens a new week; a change saved once tonight's building can start (early start included) applies from tomorrow; a schedule change never resets the streak; only bedtime and wake are limited; after the update to build 8 everyone starts with an unused week. Coins = earned − spent (`CoinSpend`), never negative.
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
  per night** (`SleepRules.awayBudget`); one trip is still limited to 3 s notice + 15 s (owner 2026-10-18: build 9i for using the phone in Strict
  mode – B33, the warning alarm rings until the collapse, it starts ~2.5 s late; build 9j for leaving the app; stored
  with each night and nap, older nights keep 3 + 10 s); two full trips can use the budget up. **No collapse without a
  real warning (owner 2026-10-07, B24):** a trip that starts while some of the 30 s is left is always a full trip
  with the full warning – the budget never shortens it; the night screen says in orange when the budget is low and
  when it is used up, and only a trip that starts after that collapses the building at once. Nights stored before
  2026-10-03 (`NightRecord.pauses == nil`) keep the old rules and get no +30. The **R&D centre** idea is still OPEN.
* **After bedtime nothing is changed (owner 2026-10-08):** from the owner's bedtime (the schedule in the app's settings)
  until he is up in the morning, Opus installs nothing on the iPhone, forgives or repairs no night (`-forgiveNight`
  and the like) and starts no rule change he asks for – it writes the request down (plan §12 + the agenda above) and
  asks again in the morning; he decides then. Reading is fine (pulling the journal). Stopping something that will
  not stop (a stuck alarm) is fine too. Reason: on 2026-10-07 → 08 three builds went onto the phone and the night was
  forgiven three times on requests made after bedtime – in the morning he wanted none of it to count.
* **Warnings and notifications (owner 2026-10-09):** (1) **one** warning notification per trip – never several in a
  row; each notification has its own meaning and says in plain words what is wrong, what to do and **how many
  seconds are left** (a first-time user must understand it; texts approved by him are in the String Catalog);
  (2) **the remaining seconds are always shown** wherever the app warns (notification, the system-alarm warning, the
  night screen); (3) **when the building collapses a notification always follows** ("so that the user at least
  knows it does not matter any more") – iOS decides whether it shows on the phone or on the watch, the app sends it
  in every case; (4) the system-alarm warning on the lock screen (it covers the Camera) rings only in Strict mode; (5) **a real
  warning looks like one and speaks kindly (owner's review 2026-10-09):** leaving the app, the closed app and the
  end of a pause keep "⚠️ Pozor! …" in the title, the body says what to do "…, nech dnešná stavba pokračuje" –
  soften what a text says, never the fact that it warns; no threats ("inak sa stavba zrúti") in new texts.
* **Lock screen without an unlock (owner 2026-10-09) – WITHDRAWN 2026-10-14:** the 12 s "lit while held" rule needed
  the undocumented lit-screen signal that Apple refuses (ITMS-90699). Only recognised use counts now (rule R3
  above); the calm reminder ("💤 Telefón má teraz voľno") and the Strict-mode warning stay for that case.
* **Built for many users, not only for the owner (owner 2026-10-09: "it is an app for many users – write it down
  and put it into the rules; do not count only with me").** The app is headed for the App Store: **a one-time
  purchase, no in-app purchases, and no data about users is ever collected** – everything stays on the device;
  integrations such as HealthKit only read locally. Consequences for every design: (1) never decide a rule from the
  owner's own setup (whether HE uses StandBy, the always-on display, a Focus, Face ID, an Apple Watch) – a rule has
  to hold for any user, any setting and any supported iPhone (Touch ID, no passcode at all); find out how iOS
  behaves by measuring on a device, not by asking what he uses; (2) anything that touches Focus modes is optional
  and switchable in Settings – not everyone wants Focus modes; (3) cheating must not be easy (he names SleepTown as
  the bad example), yet ambiguity is still resolved in the user's favour and the tone stays cute.
* **Scope freeze until version 1.0 is in the App Store (owner 2026-10-12: "we are closing now, no new features,
  although I had them planned").** Open items are closed one by one; nothing new is started – no new phase, no new
  rule, no "small extra" inside a task. A new idea (his or Opus's) goes into the plan's backlog in one line and
  waits; Opus says so kindly and returns to the open item. The order he started: TODAY → App Review risk → POP →
  Slovak texts for everybody → CAL → store page and screenshots → the owed phone checks (plan §12, 2026-10-12).
  Only he lifts the freeze.
* **Nothing undocumented is ever hidden from App Review (Opus's rule of 2026-10-12, written into
  `docs/ROZBOR-APP-REVIEW.md` for the owner – not his decision yet):** the Darwin lock signals and the background
  audio are described truthfully in the review notes; their names are never obfuscated or assembled at run time to
  get past a scan.
* **Developer screens that only inform are read-only views of ONE file in the project (owner 2026-10-16, hard rule).**
  Settings → Developer is for the owner and Opus only (maybe others later – not planned). Every screen there whose purpose
  is information (today "Plans and proposals"; later the bug list, …) has exactly one source of truth: a file in the
  project, bundled into Debug builds only (excluded from Release, like `docs/PREHLAD-PLANOV.md` in `project.yml`). The
  screen only reads it – filters and search are fine, but nothing on it can be set, edited or stored; a change is made
  only in the file, and the next build shows it. For documents the file is an `.md` in `docs/`; never keep a second
  copy in Swift code or in the store. The "Texts" screen follows the same rule with its own source: it reads the app's
  compiled String Catalog (`Localizable.xcstrings` → `Localizable.strings` / `.stringsdict` in the bundle), which is
  the only source of every text – no `.md` copy of the texts. Tools on that page that DO something (detection test,
  lock lab, system alarm test, …) are not information screens and are not covered by this rule.
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
| `docs/PLAN-BUILDOV.md` | the owner's Slovak copy of the roadmap (plan §0b), also in his iCloud `SleepHole/PLAN-BUILDOV.md` and as the private claude.ai page https://claude.ai/artifact/AARvd5DQy2uwS5v69oNkyF (source: a scratchpad file of 2026-10-19 – gone with the session; read the page with the Artifact tool, edit, republish) – **when §0b changes, update all three** |
| (claude.ai page) | the owner's bug list B1–B32, one sentence and a status each: https://claude.ai/artifact/4FjAHsDvwxE67poxMeLzSb (updated 2026-10-19) – rebuilt from plan §11a; when a bug is added or changes state, update §11a first, then the page |
| (claude.ai pages) | per-build pages for the owner (Slovak, 2026-10-22), each with a reply form whose answers (and ticks) go to the page's shared store – read them with `ArtifactData` `get` `state/answers` (the browser also keeps a local copy under the `b10.` / `b9.` keys; never rename them): build 10 https://claude.ai/artifact/P5jc2DhAxdEwfEtKnhzkLX (what 10a–10e fixed, what to try, the switch for the night, the morning questions), build 9 https://claude.ai/artifact/T1hEdc9dpk56MAmwQxk7nr (9a–9o, the bugs, what was confirmed, what is open). Sources: scratchpad files of 2026-10-22 – read a page with the Artifact tool to edit it |
| (claude.ai page) | the price-model comparison (Slovak, 2026-10-22, private): https://claude.ai/artifact/1mJPVNdRK9EAVjsLAkGfRD – a one-time price vs a subscription with a trial vs a 7-day trial + one-time unlock: Apple's rules, money per sale, indie practice, effort, Opus's view. His decision is open; never push (memory) |
| (claude.ai page) | the build 11 proposal (Slovak, 2026-10-22): https://claude.ai/artifact/Xhg4qaa1hW9tSfKnb5Uxbo – 11a–11d, the economy numbers, the loot-box assessment, box rules and contents, nights off rules, accessibility, eight questions; answers in its store `state/answers` (browser prefix `b11.` – never rename the field names / ids). Source: a scratchpad file of 2026-10-22 – read the page with the Artifact tool to edit it |
| (claude.ai page) | the economy simulation 11b1 for the owner (Slovak, 2026-10-26): https://claude.ai/artifact/9LZJ8RKQYyf9BJ6nr57tz4 – the three profiles, today's coins, the boxes by odds A / B / C / C-new / C-new-reserve / D, collections, the joker reserve, four questions; answers in its store `state/answers` (browser prefix `e11b1.` – never rename q1–q5; answered 2026-10-26 ~13:55, v10). Source: a scratchpad file of 2026-10-26; the numbers come from `ECON_SIM=… swift test --filter EconomySimulation` |
| (claude.ai page) | the owner's App Store Connect snapshot (Slovak, read-only, 2026-10-22 ~11:40): https://claude.ai/artifact/RMgAr81NV5bmSGHuSeR3d5 – the review state, the store page, the notes for Apple vs `docs/REVIEW-NOTES.md`, TestFlight, what tomorrow's switch to build 10 needs. A snapshot, not kept current; re-read App Store Connect before acting |
| `docs/AGENDA-ARCHIVE.md` | the old long session-start agenda, moved there verbatim 2026-10-16 – history only, no instructions |
| `docs/REVIEW-NOTES.md` | the App Review notes text (English) for App Store Connect → App Review Information → Notes; since build 9 the 15-minute recipe sets the times in the first-run guide – keep the file and the field identical (changing the field needs his yes) |
| `docs/TEST-BUILD-8.md` | the owner's test list for build 8 (Slovak): "now" and "tonight" – the base of the testers' "What to Test" |
| `docs/PLAN.md` | product decisions (Slovak) |
| `docs/NAVRH-ZVIERATKA.md` | next plans A/B/C: pause, sleep buddy, Cube Pets residents, living town (Slovak, owner picks) |
| `docs/NAVRH-FLEXIBILITA.md` | research and options for a flexible bedtime / alarm outside Strict mode (Slovak, 2026-10-19, after the second tester's first run): sleep-regularity studies, Apple Health and SleepTown, options A–F, Opus's recommendation, five questions; a copy in his iCloud `SleepHole/` and the private claude.ai page https://claude.ai/artifact/EbHqHizVfMU8GFk4wr86L4 (source: a scratchpad file of 2026-10-19 – read the page with the Artifact tool to edit it) |
| `docs/NAVRH-MESTO-STATISTIKY.md`, `docs/previews/navrh-2026-10-10/` | proposals of 2026-10-10 after the 100-night simulation (Slovak) and their SVG mock-ups – the spec of phase NEXT (plan §10); the owner picks |
| `docs/PREHLAD-PLANOV.md` | the owner's overview of everything open (Slovak, 2026-10-11): one table with effort and priority per item + short descriptions; priorities are Opus's recommendation – the plan's §10 stays the spec. **Bundled into Debug builds and shown in Settings → Developer → "Plans and proposals" (`SleepHole/Debug/PlansView.swift`) – keep the main table's five columns (`#` first) or the parser loses it; no `http` links. A `✅` in a row's priority cell marks it finished (green badges on the screen) – set it only after the proof is seen** |
| `docs/ROZBOR-APP-REVIEW.md` | what Apple's review can question and the way to a submission (Slovak, 2026-10-12): twelve risks with guideline numbers, the three undocumented lock signals and their documented fallback, the steps to a review with a manual release, five decisions asked from the owner. A copy is in his iCloud Drive `SleepHole/` |
| `site/`, `.github/workflows/pages.yml` | the public support page and the privacy policy (English, owner's decision 2026-10-12: on GitHub, public contact `zrebec@zrebec.sk`); the workflow publishes `site/` to `https://zrebec.github.io/sleephole/` (+ `privacy.html`) – the App Store page and the app link there. Whatever the policy says must stay true of the shipped build: change it together with any change of what leaves the device |
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
| `SleepHole/Weather/` | the weather over the owner's city: replaceable `WeatherSource` (WeatherKit / none / simulated), `WeatherStore`, Today's badge; rules in `SleepCore/…/Weather.swift` |
| `tools/test_app.sh`, `tools/coverage.sh`, `tools/sim_shot.sh` | app tests + coverage, SleepCore coverage, simulator screenshots |
| `docs/device-logs/` | journals pulled from the owner's iPhone – **git-ignored (public repo, personal data)** |
| `assets/Kenney Game Assets All-in-1 3/` | raw CC0 source bundle, git-ignored, only for re-rendering |

## About the owner

Former IT analyst / PHP & Java developer, new to iOS. Speaks Slovak. Works in small checkpointed steps and
tests everything on the real phone; energy and time vary day to day — keep steps small, explanations
clear, and never pressure the pace. When he asks you to decide, give a clear recommendation with reasons.
