# AGENTS.md — SleepHole

You are working on **SleepHole**, a native iPhone app (Swift / SwiftUI / SpriteKit / SwiftData)
that builds a sleep habit: start a building at bedtime, leave the phone alone, confirm waking up in the
morning → a low-poly isometric town grows night by night. A SleepTown-like game. It started as the owner's
personal app and he is its first tester, but **it is built for many users and headed for the App Store**
(owner 2026-10-09, see the hard rule "Built for many users").

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
   * **FIRST – the night of 2026-10-07 → 08 (bugs B24 + B25 + B26, plan §11a and §12):** the building collapsed
     with ~1.5 s of warning (the 30 s budget had shortened the trip); three builds went onto the phone that night
     at his request (23:16, 23:29, 00:07), the night was forgiven three times (`-forgiveNight`) and it ended
     `complete`. On 2026-10-08 he asked for a full reconstruction: the journal part is done and written up in Slovak
     in the git-ignored `docs/device-logs/2026-10-08-morning/REKONSTRUKCIA.md` (a copy is in his iCloud Drive
     `SleepHole/`). **Still owed: the comparison with Apple Health and his sleep-tracking app** (his permission is given) – it needs
     his Health export (Health → profile picture → Export All Health Data → AirDrop to the Mac; unpack it in the
     scratchpad, read only the night's window, delete it afterwards, nothing of it into the repo) and a
     screenshot of the night from that app; ask whether he has sent them, then add section 8 of the write-up. The night brought
     no false alarm from the lock screen, but the new warning ("Put your phone down! Switch the screen off", the
     phone's own sound) never fired – still to try on purpose: on the watch, on the phone, did the phone sound, did
     switching the screen off save the building; does he use StandBy. Everything is still UNCOMMITTED – check
     `git status`. Be brief and kind, and never install while he sleeps.
     **He is sure the app has a bug here and he is right (2026-10-08, plan §12 last row):** three lock-screen videos
     were never seen by the old build. Two holes remain in the installed build (Face ID recognising him later than
     8 s after the screen lit is never re-checked; the warning can be missed). Four fix options are on the table and
     he has NOT chosen yet – ask which: the 2-minute test, the late recognition, counting without Face ID, a 10 s
     sound + vibration. He wants short, strict answers on this topic – no padding.
     **His "basal test" is built (2026-10-08, `SleepHoleTests/LockScreenTests.swift`, plan §12):** in the app's logic
     the warning leaves 8 s after the lock screen lights up and the building falls 13 s later (21 s in all); the hole
     "Face ID recognises him after the 8 s" is proven by a test (3 known issues in the suite). **The same steps ran
     on his REAL phone the same day (plan §12):** the detection fired 3 of 3 times (~8 s after the lock screen lit),
     the building fell 13 s after the warning. **His finding: the warning is NOT visible on the phone – the Camera
     hides it; only the Apple Watch alerts (loudly).** He wants a warning that covers the lock-screen Camera. He ran
     the no-code check (Developer → System alarm test with the Camera open on the lock screen): **the AlarmKit alarm
     DOES cover the Camera – but it would not stop (new bug B27, plan §11a; he was alarmed: "help, the phone keeps
     ringing").** **Phase LOCK-W (plan §10) is in work since 2026-10-08, approved by him ("áno, priprav návrh" +
     his three test variants):** the lock-screen warning as an AlarmKit alarm that the app ends itself (screen off /
     back in the app / 10 s at the latest), the B27 fix, the late Face ID hole. **On the phone since 2026-10-09 12:28, and his three
     variants passed the same day (14:32–14:40, plan §10 LOCK-W + §12):** with Face ID the alarm covers the Camera,
     screen off and the way back into the app silence it and keep the building, leaving it collapses the building.
     **2026-10-09 afternoon – a long working session on LOCK-W (plan §10 LOCK-W
     task list and the three §12 rows of that day are the record):** a developer recorder, the lock-screen lab
     (`-lockLab`, debug nights only), measured the phone twice; the owner decided the rule for the lock screen
     WITHOUT an unlock (lit 12 s + the phone held → warning, collapse 13 s later) and three notification rules
     (now hard rules below). Built and reviewed, **NOT on the phone yet (the phone carries the build of 15:38: lab +
     15 s setup + one lock-screen notification)**: one notification per trip with new texts, a notification at the
     collapse, the seconds in the alarm title, the fix for B28 (the warning alarm rang 21.5 s because iOS suspended
     the app), and the 12 s rule itself (`HoldDetector`; SleepCore 260 / app 341 tests green 17:01, a device build
     waits in `build/DerivedDataDevice`). **Installed 17:05 and tested: the 12 s rule works on the
     phone (detection 12.7–12.8 s after the screen lit, the app ends the warning at exactly 10 s); B28 is still
     unproven (the alarm gave the audio back after ~2 s both times).** **THEN HE CHANGED THE DIRECTION – phase CARE (plan §10 CARE, read
     it first): care and rewards instead of enforcement, to be changed NOW, before TestFlight / the App Store.**
     Decided by him: lock-screen use no longer collapses the building by default (it costs a calm-time reward), the
     system-alarm warning becomes an opt-in strict mode, caring texts, coins per calm hour, Live Activities /
     Dynamic Island wherever a notification is used today, then Apple Health, then the shop; a flexible bedtime only
     after a written proposal. **Done and on the phone since 2026-10-09 20:37: the joker change (each kind once a
     month) and the softer texts he reviewed line by line (real warnings keep "⚠️ Pozor!", only what they say got
     kinder).** **CARE-1 logic is ON THE PHONE since 2026-10-09 21:00 (lock-screen use no longer
     collapses the building unless "Strict mode" is switched on in Settings); he tried both modes the same evening
     ("it is better already, only a calm warning"; "strict mode works, the siren sounded").** At 21:06 the Strict
     switch was still ON – ask whether the night of 2026-10-09 → 10 ran gentle or strict and how it went.
     **ORDER HE SET FOR 2026-10-10 (plan §10 CARE, the task "ORDER FOR 2026-10-10"): (1) fix B29 (two `.leftApp`
     for one trip, plan §11a) and close the lock-screen chapter; (2) APPLE HEALTH – he is "really looking forward
     to it": analysis first, then small steps; (3) the Dynamic Island / Live Activity try.** CARE-2 is confirmed by him (+10 coins per hour of
     the night with the screen off, +11 when the phone was not even moved) – not built, after Apple Health.
     Everything up to CARE-1 was committed on 2026-10-09 at his request (he pushes). TestFlight: the upload of
     2026-10-07 succeeded; his screenshot showed only the Distribution page ("1.0 Prepare for Submission") – the
     build's state is on the TestFlight tab, ask him for it. He will try himself: the calm reminder during the
     Sleep Focus, the notification with the app swiped away. B28 unproven ("it would ring to death"), B26 open.
     **The forgiven night
     of 2026-10-07 → 08 is taken back (his decision 2026-10-08, done on the phone 2026-10-09 12:28 with
     `-revokeForgiveness`):** the record reads `ruins`, the automatic bronze joker of October turns it into a joker
     night, the honest night of 2026-10-09 is untouched; streak / best / built nights 10 → 9, coins 2120 → 1940.
     Ask only whether the numbers on his phone agree (Stats 9 / 9 / 9 / 1940, the 8th as a joker; Town 9 buildings).
     October's joker is spent – a missed night this month breaks the streak.
     Also still unanswered: did the phone's own 3 s sound play.
   * **Weather animations across Today (plan §10 TOWN-W step 2b) are ON HOLD:** research and the wind data are
     done, the drawing is not started. He asked for the result "tomorrow" before the lock screen took over – say
     honestly that it is not built, and ask what "like a wiper on a car" means before building it.
   * **Time Sensitive Notifications – done:** the warning for a switched-off iOS switch works on the phone and the
     Focus test with the switch on passed (owner 2026-10-07). Nothing open here.
   * **R4 – closing the app counts as leaving it:** on the phone since 2026-10-07; reopening in time and a phone
     restart keep the building (confirmed). Still to prove: swipe away and STAY away → collapse; only one alarm when
     the app is reopened while the system alarm rings.
   * **System alarm (F6b):** it rang with the app swiped away (2026-10-04). Still to check: the Developer → System
     alarm test, the safety alarm after an early confirm, what the system's own stop button says (he saw "snooze").
   * **Weather (B23):** the owner sees the weather on the phone since 2026-10-09 and believes WeatherKit works –
     the phone's cache said `metNorway` that day (12:28): the second source (follow-up A2) is proven on the phone,
     Apple's token is not. Ask what Weather test says under "Answered by" and "Note".
   * **Five ideas of 2026-10-09 (plan §10 backlog, top item) – considerations, nothing approved:** the town as an
     island on water (M), live weather over the whole screen like the HTC HD2 (= TOWN-W step 2b, M), starting a
     night / nap from the Apple Watch (a spike first), HealthKit "when I really fell asleep" (S–M), a Fantasy Town
     theme (M–L). Do not start any of them without his word; ask which one he wants first.
1. **The pause is still untried:** no night up to 2026-10-06 → 07 used the "🌙 Pause" (journal). Ask only whether he
   still wants to try it. Open bugs in plan §11a: B8, B10, B12–B16, B22, B23 (B7 contrast is accepted – two
   follow-ups are listed in plan §10 B7; B11 is solved inside F6b).
2. **Sleep buddy (P2 + P2b): accepted by the owner 2026-10-04.** His remark: the "arched back" has too few poses –
   leave it until we render our own models (F7).
3. **City + real sun & moon (phase SKY, plan §10)** – built and reviewed 2026-10-04 (Settings → Sky with the Apple
   Maps city search, the real sky cached per minute, sun / moon on a small semicircle right of the title, the moon's
   real phase). Check the SKY task list: is it committed, is the FINAL build on the iPhone (an interim build of
   2026-10-03 21:13 with an older semicircle is / was there), has the owner seen the sun and the moon on the
   semicircle? Next in line after it: bug B7 (contrast / transparency on the light sky – the owner asked for it).
4. **Phase TOWN-W is running (plan §10 TOWN-W, approved by the owner 2026-10-07):** steps 0b, 1 and 2 are built,
   committed and on the phone; checkpoint A passed 2026-10-07 (roads ✓, the Time Sensitive warning ✓, the Focus
   test ✓; Apple still refuses the weather, B23). The three follow-ups he approved are built, reviewed and merged
   the same evening and on the phone since 2026-10-07 23:16 (not checked by him yet): A1 a tappable warning triangle top left on Today instead of the tall
   card (opens Settings at the notifications), A2 MET Norway as the second weather source (used when WeatherKit
   fails), A3 version / build numbers from `project.yml` + the privacy manifest. Check `git status` (were they
   committed?) and ask whether the build is on the phone and what he saw: the triangle + its tap, a temperature
   top right on Today, Weather test → "Answered by" / "Note". **Next after his check: step 3** rain and snow in
   the town → B; 4 day and night in the town → C. Stop at every checkpoint. Waiting ideas: the robotic announcer
   voice (plan §10 backlog), plan A / B / C (`docs/NAVRH-ZVIERATKA.md`, 5 open questions at the end).
5. **TestFlight (owner 2026-10-07 – a friend wants to test; he is new to it, explain in plain steps):** the first
   build 1.0 (1) was uploaded 2026-10-07 16:27 (the first try failed on Xcode's cloud signing and his accented
   name – solved with a local Apple Distribution certificate, plan §12). Ask: did Apple's "completed processing"
   mail (or a mail with problems) arrive, and does he want the friend as an internal or an external tester? The
   project is ready for the next upload (version 1.0, build 2, privacy manifest – follow-up A3); **raise
   `CURRENT_PROJECT_VERSION` in `project.yml` before every further upload.** He uploads himself (Xcode →
   Archive → Distribute App).

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
* **One step = one session (owner 2026-10-07):** when a step of a multi-step phase is reviewed, merged and written
  into the plan, Opus itself runs the `session-handoff` skill (user level, `~/.claude/skills/session-handoff`) – a
  chat-only summary the next session starts from – and stops; the next step starts in a clean context. No handoff
  while a worker is still running. Use parallel workers inside a step where the files allow it (worktree + its own
  simulator; this Mac builds at most two at a time). The plan below stays the source of truth; the handoff only
  carries what is not written down yet.
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
  **using the phone on the LOCK screen is detected too** (owner 2026-10-07, B25: camera / video from the lock
  screen) – the screen lit for more than 8 s with the user recognised, or lit for 12 s while the phone is held; it
  ends with the screen going off. **Since phase CARE (owner 2026-10-09) it brings the building down only in "Strict
  mode" (Settings, default OFF); by default the app only reminds gently and the building stays** – unlocking into
  another app from there is leaving the app in both modes. The mode is stored with each night at its start; nights
  stored before CARE count as strict;
  screen off is fine, the app must stay in the foreground; confirm by shake or wake code from wake −30 min;
  complete only while the alarm rings (2 min), unfinished until +60 min. Tone is **cute and never cruel** — no
  shaming copy, ambiguity is resolved in the owner's favour.
  **Closing the app (swiping it away) during a night or nap counts as leaving it** (owner 2026-10-04, plan R4) –
  an immediate warning, the same tolerance; the app killed by iOS itself and a restart of the phone stay in the
  owner's favour.
* Levels: nights 1–5 → L1, 6–15 → L1–L2, 16–30 → L1–L3, 31+ → L1–L4 (plan §5.5).
* Coins 🪙 (owner 2026-10-02): complete night by building level L1 100 / L2 120 / L3 150 / L4 200, unfinished half,
  +30 for a complete night without a pause, every 7th complete night in a row +200; nap 50 / 25.
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
  per night** (`SleepRules.awayBudget`); one trip is still limited to 3 s notice + 10 s. **No collapse without a
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
* **Lock screen without an unlock (owner 2026-10-09, measured with the lock-screen lab, plan §12):** using the phone
  on the lock screen counts even when Face ID / Touch ID never recognised the user (Camera, anything started from
  the lock screen): the lock screen lit for 12 s without a break while the phone is held in the hand (it moves) →
  what follows depends on the mode: by default one calm reminder ("💤 Telefón má teraz voľno"), in Strict mode the
  warning and the same 13 s (about 25 s from the first touch to the collapse). With the user recognised the 8 s
  stay. A phone that lies or stands still is never counted, whatever lights its screen.
* **Built for many users, not only for the owner (owner 2026-10-09: "it is an app for many users – write it down
  and put it into the rules; do not count only with me").** The app is headed for the App Store: **a one-time
  purchase, no in-app purchases, and no data about users is ever collected** – everything stays on the device;
  integrations such as HealthKit only read locally. Consequences for every design: (1) never decide a rule from the
  owner's own setup (whether HE uses StandBy, the always-on display, a Focus, Face ID, an Apple Watch) – a rule has
  to hold for any user, any setting and any supported iPhone (Touch ID, no passcode at all); find out how iOS
  behaves by measuring on a device, not by asking what he uses; (2) anything that touches Focus modes is optional
  and switchable in Settings – not everyone wants Focus modes; (3) cheating must not be easy (he names SleepTown as
  the bad example), yet ambiguity is still resolved in the user's favour and the tone stays cute.
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
| `SleepHole/Weather/` | the weather over the owner's city: replaceable `WeatherSource` (WeatherKit / none / simulated), `WeatherStore`, Today's badge; rules in `SleepCore/…/Weather.swift` |
| `tools/test_app.sh`, `tools/coverage.sh`, `tools/sim_shot.sh` | app tests + coverage, SleepCore coverage, simulator screenshots |
| `docs/device-logs/` | journals pulled from the owner's iPhone – **git-ignored (public repo, personal data)** |
| `assets/Kenney Game Assets All-in-1 3/` | raw CC0 source bundle, git-ignored, only for re-rendering |

## About the owner

Former IT analyst / PHP & Java developer, new to iOS. Speaks Slovak. Works in small checkpointed steps and
tests everything on the real phone; energy and time vary day to day — keep steps small, explanations
clear, and never pressure the pace. When he asks you to decide, give a clear recommendation with reasons.
