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
   * **NEWEST – 2026-10-15 morning (plan §12, row of that day):** his first night with build 7 was complete; the pause,
     the Face ID reminder and "no reminder for the Camera without Face ID" are confirmed by him. **New bug B31 (§11a):**
     the wake code cannot be typed on the night screen before the alarm (the shake works). Build 1.0 (7) is still
     "Waiting for Review". **The same morning:** he sent build 7 to the external group "SE" himself (Beta App
     Review); the age rating's new social-media questions are already answered "No" (Opus read them, nothing to do);
     **Build 8 (plan §10 REL) – COMPLETE and on his phone since 2026-10-15 13:47:** 8a B31 + seconds "15s" + the cat's
     comic bubble (he likes it; B31 confirmed by him), 8b calm hours +5 🪙, 8c "týždeň na zmeny" (7 days of changes,
     then a month locked, early unlock 2 000 🪙, no streak reset, evening change from tomorrow), 8d the setup notice only
     while outside the app, 8e the real moon phase without a city, 8f the cat talks about the sky (13 lines). Nothing
     is committed. **Ask in the morning:** (a) how the night went – the calm-hours line, no setup notice, the moon;
     (b) his feedback on the cat's sky lines; (c) his yes to raise `CURRENT_PROJECT_VERSION` to 8, upload, add build 8
     to the tester groups with a "What to Test" list, and whether to swap it into the App Store review (build 7 was
     "Waiting for Review"); (d) the commits (whole files, detailed messages; he pushes – `site/index.html` changed too).
     Build 9 = the guide variant B (texts in `docs/guide-texts-draft.json`, his review pending) + configurable setup.
   * **2026-10-14 (plan §12, row of that day; Opus read App Store Connect through his Chrome, changed
     nothing):** the P0 rows of the overview (1, 2, 32) are done and proven. **Apple has updated the Developer
     Program License Agreement – until he (the Account Holder) accepts it on developer.apple.com, no build can be
     uploaded and nothing can be submitted; his own click.** Build 6: 14 of 15 testers installed it (two on iPads –
     the app runs there in iPhone mode), no crashes, one anonymous feedback "不支持汉语" ("no Chinese"). The DSA
     declaration (non-trader) and the 175 countries are done; the release option is "Manually release". Ask: does
     the seller name on the Business page (it differs from the name in the copyright) look the way he wants it on
     the store page.
     **His answers the same afternoon (plan §12, second row of 2026-10-14):** he accepted the new agreement; B23 is
     closed (WeatherKit answers); 9+ is fine; **build 6 is attached to version 1.0 (Opus, on his word – the real icon
     shows next to the name now)**; **Apple may review the app, but nothing is released** (manual release) – before
     "Add for Review": the iPad check (a Sonnet worker ran it that afternoon – see §12) and the 15-minute recipe on
     a clean install; Strict mode stays on; the lock-screen question is closed by Opus (all four options of
     2026-10-08 are covered by what is on the phone); R4 "swipe away and stay away" collapses ✓; the system alarm
     rings after an early confirm ✓; the twelve texts are confirmed; CARE-2 confirmed again (+10 per calm hour, +11
     when the phone lies still). **Open, waiting for his word:** the lit street (`l2-road-lit-*`) as a night's
     build felt like a joke to him (his night of 2026-10-13 → 14, level range L1–L3) – Opus proposes to take lit
     streets out of the draw (XS–S, build 7); the residents' ranges and town size names and the Slovak texts for
     everybody (both tables were in the chat); what "a little tuning of the home screen UI" and "some AI
     optimisation" mean; a Chinese translation is NOT recommended now (one anonymous tester, no native reviewer,
     mainland China needs an ICP filing) – one backlog line. His questions about selling were answered in the chat
     and stay out of this public repo.
     **Evening of 2026-10-14 – BUILD 7 IS IN WORK (plan §10 REL, steps 7a–7d):** he said yes to the lit street out of
     the draw, wants TALK (the cat talks about the town and the residents' chatter – texts by Opus), approved the
     neutral Slovak table (row 9 is the nap: "Výborný šlofík 💙"; creative forms instead of "zaspal si") and asked for
     a Debug "Texts" screen with every text in its own box. His "bug" (a night ended by a shake 12 s after its
     start) was a QUICK TEST night – its confirm window opens at once; fixed in 7a together with a clear "you can
     confirm from …" line and a refused early shake. The iPad simulator check passed; the 15-minute recipe still
     needs a person. **Build 6 was SUBMITTED that evening and REFUSED by Apple's scan (ITMS-90699, undocumented lock notifications) →
     build 7 (7a–7e, documented lock detection only) is committed, on his phone since 20:05 and uploaded 20:11; next:
     build 7 RESUBMITTED 20:23 ("Waiting for Review", manual release); the testers only after his night with build 7 –
     ASK in the morning how the night went (the new lock detection, reminders, alarm, the buddy's bubble).** Earlier: 7a is built
     and reviewed (uncommitted; its Debug build is on his phone since 17:18 – ask what he saw: the "you can confirm
     from …" line, the orange "too early" note after a shake, a quick test night that can be confirmed only in its
     last 30 s); next session: 7b POP.** The `SyncEngineTests` timing tests are
     flaky on this Mac (they fail at HEAD too, §12) – do not chase them as a 7a regression. One step per session, then `session-handoff`.
   * **2026-10-12 afternoon: RELEASE 1.0 IS IN WORK (phase REL, plan §10 REL and the two
     §12 rows of that afternoon; the scope is FROZEN – hard rule below).** State: the compact Today is confirmed by
     him on the phone; **build 1.0 (5) is uploaded (14:42, "Upload succeeded") and its Debug build is on his phone
     since 14:42** (privacy link in Settings → About, Release clean-up, truthful AlarmKit text; app 498 tests green
     in Opus's own run); the support / landing page and the privacy policy are live
     (`https://zrebec.github.io/sleephole/`, source `site/`); all store texts are in App Store Connect (he pasted
     them, Opus checked them; paste sheet in his iCloud Drive `SleepHole/APPSTORE-TEXTY-EN.md`); the analysis is
     `docs/ROZBOR-APP-REVIEW.md` – he chose route (a). The final English screenshots (`tools/store_shots.sh`, two
     sizes in `build/store/en-US/`) were being shot by a worker when this was written – check the folders.
     **Ask, in this order:** (a) what he saw in build 5 on the phone (Today; does the "Privacy policy" row open
     the page – nobody has tapped it on a device); (b) builds 4, 5 and 6 are processed and in both tester
     groups (seen 2026-10-14); build 6 is attached to version 1.0 (2026-10-14, on his word);
     (c) **the app starts FREE (his decision that afternoon, "for now"):** Opus set the price to 0.00 in all
     175 countries through his Chrome and took "Pay once" out of the store description and the landing page; the
     Paid Apps Agreement stays unsigned. The Digital Services Act declaration (non-trader) is "Active" since
     2026-10-12 and the availability is set (175 countries) – both done. A price comes back only after an
     accountant has told him how such income is taxed and which levies follow (the chat answer of that afternoon
     had the sources; his reasons are personal and stay out of this public repo – be gentle, never push); (d) the age rating 9+ is fine with him (2026-10-14). **Still owed before "Add for Review":** the 15-minute
     night recipe of the review notes tried on a clean install (NOT his phone) – it needs taps, a person has to do
     it (the iPad simulator check passed 2026-10-14, §12); the release option stays on "Manually release this
     version". Then, while Apple reviews: the documented-only lock
     detection as a fallback. Everything of that day is committed (he pushes) – check `git status` all the same. His idea "the newest building instead of the cat on Today" is in the
     backlog, frozen. The next upload needs `CURRENT_PROJECT_VERSION` 7 (6 is uploaded).
     **Added the same day, late afternoon (plan §12, last row of 2026-10-12):** a tester's first night ended
     "unfinished" because she confirmed later than 2 minutes after the alarm, and the app did not say why → **he
     decided: the on-time window is 10 minutes** (hard rule R3 below is changed) + two text fixes = **build 6, uploaded 17:11 and on his
     phone since 17:12** (SleepCore 336 / app 500 tests green; naps share the 10-minute window). He checked it the same evening
     (privacy link opens, the Stats label is right). **Build 6 is in both tester groups and on the public link,
     and the beta is listed on departures.to (`/apps/23674`).** **B23:** WeatherKit was not ticked under the App
     ID's "App Services" on developer.apple.com – ticked at about 18:20 on his word; **he confirmed 2026-10-14
     that WeatherKit answers – B23 is closed.** Earlier
     note, kept for the record: the listing was to follow build 6 on departures.to (he asked to wait for build 6; Opus fills the form in his Chrome,
     he approves before it is sent). Through his Chrome Opus already set: all 175 countries, a limit of 200
     testers on the public link. Two announcement posts went out on his accounts with his approved text.
     **Added late in the evening of 2026-10-12 (plan §12, the row "Late evening") – ASK THIS BEFORE ANYTHING ELSE:**
     he wrote that he wants to POSTPONE the App Store release until the business side of selling is clear, and
     asked whether selling only in the USA avoids it (it does not). Opus separated the two things for him: a FREE
     release needs none of it, and the price is 0. **He answered that "free now, paid later" is not for him – it
     would make him look like a corporation; do not offer it again. So the release waits: TestFlight goes on, and
     the app enters the store with its final price model from day one (or stays free for good – his call later).
     **2026-10-14: he agreed that Apple may review it meanwhile (manual release – nothing is published).** A one-page plan with seven questions for the offices is in his iCloud Drive
     (`SleepHole/PREDAJ-PLAN-A-OTAZKY.md`). He wrote that he is getting frustrated – be brief and kind, never push.
     Done that evening on his word: nine screenshots uploaded in both sizes (his own upload had failed because the
     version page opens on the new "Header and Search Results" tab – screenshots belong to "App Previews and
     Screenshots"). The placeholder icon next to the app's name: every build carries the icon, but no build is
     attached to version 1.0 – Opus asked whether it may select build 6 there (his yes is needed). Item 12 of
     `docs/PREHLAD-PLANOV.md` (sleep statistics) was rewritten to his wish: one line per night with four colours
     (green went to bed, blue fell asleep, pink the alarm, the fourth = when he really got up – its colour is not
     chosen yet). Uncommitted:
     `AGENTS.md`, the plan, the overview.
   * **The night of 2026-10-07 → 08 (bugs B24 + B25 + B26, plan §11a and §12):** the building collapsed
     with ~1.5 s of warning (the 30 s budget had shortened the trip); three builds went onto the phone that night
     at his request (23:16, 23:29, 00:07), the night was forgiven three times (`-forgiveNight`) and it ended
     `complete`. On 2026-10-08 he asked for a full reconstruction: the journal part is done and written up in Slovak
     in the git-ignored `docs/device-logs/2026-10-08-morning/REKONSTRUKCIA.md` (a copy is in his iCloud Drive
     `SleepHole/`). **The comparison with Apple Health is DONE (2026-10-11 evening):** section 8 of the write-up was
     filled from his own JSON backup – the app stores per night what Apple Health says, per source – so the full
     Health export was not needed; only sleep stages would need it, and only if he asks. The values stay in the
     git-ignored write-up and its iCloud copy. The night brought
     no false alarm from the lock screen, but the new warning ("Put your phone down! Switch the screen off", the
     phone's own sound) never fired – still to try on purpose: on the watch, on the phone, did the phone sound, did
     switching the screen off save the building; does he use StandBy. Everything is still UNCOMMITTED – check
     `git status`. Be brief and kind, and never install while he sleeps.
     **He is sure the app has a bug here and he is right (2026-10-08, plan §12 last row):** three lock-screen videos
     were never seen by the old build. Two holes remain in the installed build (Face ID recognising him later than
     8 s after the screen lit is never re-checked; the warning can be missed). The four fix options of that day are
     CLOSED (Opus 2026-10-14, on his "decide what helps most"): the late recognition is re-checked (LOCK-W), the
     12 s hold rule counts use without Face ID, the system-alarm warning of Strict mode rings for the whole 10 s,
     and the test was run many times – nothing more to build. He wants short, strict answers on this topic – no padding.
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
     **2026-10-10: PHASE HEALTH IS BUILT AND ON THE PHONE (plan §10 HEALTH): Apple Health sleep data is read
     (read-only, switch in Settings, default off), every real night got "fell asleep / slept / source", the chart
     shows one bar per night from the build start to falling asleep, tap selects a night; the source rule prefers
     the system's own measurement (rule version 3). B29 is fixed and on the phone. Version 1.0 (2) was uploaded to
     TestFlight by him that morning (the first try was refused for a missing `NSHealthUpdateUsageDescription`).
     Everything of that morning is committed (he pushes).**
     **2026-10-10 afternoon – THE PROPOSAL DOCUMENT WAITS FOR HIS ANSWERS (phase NEXT, plan §10 NEXT; nothing of
     it is built):** after the 100-night simulation he answered its findings, added his own (the tester sees
     nothing in TestFlight, Today is "big", the night's detail is unreadable) and asked about a light sensor and
     the microphone. Opus wrote `docs/NAVRH-MESTO-STATISTIKY.md` (Slovak, mock-ups in
     `docs/previews/navrh-2026-10-10/`) and put the PDF into his iCloud Drive (`SleepHole/NAVRH-2026-10-10.pdf`):
     a month calendar with periods, the night's detail in blocks with a timeline, residents (100 nights ≈ 40
     thousand, town size names), a compact Today, the town camera (B30), the buddy talking, the island whose
     coast follows the town, coins (strict-mode commitment, building office, town services) and a movement spike.
     **Ask for his answers to the eight questions at the document's end and which sub-phase goes first** (Opus
     recommends the calendar together with the residents). Two things he must hear again if he has not read it:
     the earlier finding "the map is enough for 130–150 buildings" was WRONG (the ground grows with the town, as
     a rectangle), and Opus disagrees with "unpaid fees → buildings burn" (it contradicts CARE; proposed
     principle: only a night can take a building, never coins).
     **NEW 2026-10-10 late afternoon – phase SYNC (plan §10 SYNC): he wants one town on all of a user's devices
     through iCloud BEFORE build 3** (a tester alternates phone and tablet; today nothing syncs). **Decided by
     him the same evening:** one file per device in the user's iCloud Drive container + a clear merge rule, the
     switch ON by default, two nights at once → the better one counts, Health data never into iCloud. **The whole phase is built, reviewed and committed 2026-10-11 (SleepCore 326 / app 484 tests green, i18n 642
     keys 0 / 0 / 0). His test with one iPhone passed (~09:15): he deleted the app, the new build was installed
     and the town came back from iCloud. After it a code review brought ten points – step S4 fixed seven and
     added what he asked for around Apple Health (values are read right after a sync, a new install takes over
     the Health switch, a button "Načítať spánok znova"). **S4 is CONFIRMED on the phone (owner 2026-10-11
     evening: "I read it again, the data came from Apple Health, all fine"; the phone carries version 1.0 (3) –
     he ran it from Xcode at 12:40).** **Build 1.0 (3) IS UPLOADED (2026-10-11 12:52, "Upload
     succeeded", Apple was processing it):** his own upload from Xcode failed at the very end on an expired
     sign-in (a slow line, 8 minutes), so on his request Opus archived and uploaded from the command line (plan
     §12, 2026-10-11 – the commands are there). Build 3 went out WITHOUT S4 having run on a phone – his
     decision. **State from his screenshots the same afternoon: build 3 is processed and sits in the internal
     group with the status "Testing" (the two internal testers still had build 2 installed); in the external
     group build 2 was still "Waiting for Review" since 2026-10-10. He then sent build 3 to the external group
     too (his words, the same evening). Ask whether Apple approved it, whether the public link works and
     whether the testers updated.** He offered his
     Firefox for those clicks; the browser tool drives only Chrome with the Claude extension and none was
     connected. Not proven on devices: two live devices syncing (a tester with a phone and a tablet will show).
     The proposal document's eight questions are still unanswered.**
     **2026-10-12 morning – PHASE EARLY IS CONFIRMED AND FINISHED (plan §10 EARLY and the three §12 rows of that
     day).** A tester had wanted to go to bed 100 minutes before her bedtime and the app refused; the owner decided
     (2026-10-11): from bedtime − 3 h, no penalty, the setup 15 min from the start, the morning unchanged. **His own
     night of 2026-10-11 → 12 was an early start and he confirmed it ("the alarm worked, the building was built, the
     coins agree to the last one"); the journal agrees.** The same morning, on his "finish P0": the six review
     follow-ups, a review of ALL texts (twelve changed – the table was in the chat, he has not commented yet), green
     "✓ Hotovo" badges for finished rows on Settings → Developer → "Plány a návrhy", and build number 4 (SleepCore
     335 / app 497 tests green, i18n 652 keys 0 / 0 / 0; two commits, he pushes). **Build 1.0 (4) is uploaded to App
     Store Connect (08:41, "Upload succeeded"); the phone carries the Debug build 1.0 (4) since 08:45.**
     **Ask first:** (a) did he add build 4 to both tester groups, and did the tester who reported the early bedtime
     get it; (b) how the plans screen reads on the phone – nobody has seen it yet – and whether the green badges are
     what he meant; (c) the twelve changed texts are confirmed (2026-10-14); (d) his next early night: the bedtime reminders now
     skip only that evening's weekday (six weekly triggers, untried on a device) – does the reminder of the
     FOLLOWING evening arrive; and were the 15 minutes of setup tight (he finished 24 s before their end); (e) the
     Strict switch is still ON on his phone (that night was stored as strict) – is that what he wants.
     **Two things Opus must remember from that morning:** he caught a premature "build 4 is uploaded" in the
     overview – a status is written only after the proof is seen (memory `done-only-when-done`); and an export from
     the command line can hang silently on a keychain dialog on his Mac (plan §12, 2026-10-12) – look for it and
     tell him at once. **`docs/PREHLAD-PLANOV.md`** (a copy is in his iCloud Drive `SleepHole/`): every open item in
     one table with effort and priority; rows 1 and 2 (P0) are done, row 31 is new (the Slovak texts address
     everybody as a man). **He agreed with the overview and its order (2026-10-12): TODAY + POP in parallel next,
     then CAL, CARE-2a (+10 per calm hour; the +11 waits for the movement spike) and an analysis of the App Review
     risk.** The three answers the first steps need are still open: may the buddy on Today shrink to about 200 pt;
     the residents' ranges and the town size names; the App Store subtitle / privacy page / public contact.
     **The App Store page (2026-10-11 evening):** he asked what
     App Store Connect needs (icon, subtitle…) and for help with the texts. The guide with text proposals in
     English and Slovak is in his iCloud Drive (`SleepHole/APPSTORE-NAVOD.md`): fields and limits, subtitle /
     promotional text / keywords / description, a privacy policy draft, the questionnaires, and what is not
     text (screenshots 6.9", price, the Paid Apps agreement, the EU trader status that shows his contact
     publicly). **Ask which subtitle he picked, where the privacy page should live and which contact may be
     public.** Opus advised against listing the beta in third-party directories for now (Apple itself has no
     catalogue of betas) and to make the store screenshots only after Today and the calendar are redone.
     Also open: (1) TestFlight – build 2 is uploaded; the friend got his invitation as an internal tester in the end
     (the public link said "not accepting new testers" because Apple's review had not finished); the guide in his iCloud Drive (`SleepHole/TESTFLIGHT-NAVOD.md`) now explains the missing step
     (an Internal Testing group holding the friend and the build), the public link for several friends and the
     text for Apple's review – ask what worked and whether he cut the friend's roles to Marketing; raise
     `CURRENT_PROJECT_VERSION` to 7 before the next upload (6 is uploaded since 2026-10-12 17:11); (2) CARE-2 (calm-hour coins +10 / +11 when the phone
     lies still) is confirmed (again 2026-10-14) but NOT built; (3) the Dynamic Island / Live Activity try. Never write his sleep values
     or the names of his devices and apps into the repo. Everything up to the morning of 2026-10-12 (build 4) is
     committed; he pushes – check `git status` all the same. A build in the Xcode app rewrites the two String Catalogs – restore them with `git checkout`
     before a commit (plan §12, 2026-10-11).
     **The forgiven night
     of 2026-10-07 → 08 is taken back (his decision 2026-10-08, done on the phone 2026-10-09 12:28 with
     `-revokeForgiveness`):** the record reads `ruins`, the automatic bronze joker of October turns it into a joker
     night, the honest night of 2026-10-09 is untouched; streak / best / built nights 10 → 9, coins 2120 → 1940.
     The question whether his Stats showed those numbers is closed (2026-10-14 – later nights changed them).
     October's joker is spent – a missed night this month breaks the streak.
     Also still unanswered: did the phone's own 3 s sound play.
   * **Weather animations across Today (plan §10 TOWN-W step 2b) are ON HOLD:** research and the wind data are
     done, the drawing is not started. He asked for the result "tomorrow" before the lock screen took over – say
     honestly that it is not built, and ask what "like a wiper on a car" means before building it.
   * **Time Sensitive Notifications – done:** the warning for a switched-off iOS switch works on the phone and the
     Focus test with the switch on passed (owner 2026-10-07). Nothing open here.
   * **R4 – closing the app counts as leaving it:** on the phone since 2026-10-07; reopening in time and a phone
     restart keep the building (confirmed). Swipe away and STAY away → collapse: confirmed by him 2026-10-14. Still
     to prove: only one alarm when the app is reopened while the system alarm rings.
   * **System alarm (F6b):** it rang with the app swiped away (2026-10-04). The safety alarm after an early confirm rings
     (him, 2026-10-14). Still to check: the Developer → System alarm test, what the system's own stop button says
     (he saw "snooze").
   * **Five ideas of 2026-10-09 (plan §10 backlog, top item) – considerations, nothing approved:** the town as an
     island on water (M), live weather over the whole screen like the HTC HD2 (= TOWN-W step 2b, M), starting a
     night / nap from the Apple Watch (a spike first), HealthKit "when I really fell asleep" (S–M), a Fantasy Town
     theme (M–L). Do not start any of them without his word; ask which one he wants first.
1. **The pause works (owner 2026-10-15, his real night with build 7: the free pause, "one minute left", then "the
   pause is over, come back").** Open bugs in plan §11a: B8, B10, B12–B16, B22, B31 (B7 contrast is accepted – two
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
5. **TestFlight (owner 2026-10-07 – a friend wants to test; he is new to it, explain in plain steps):** build
   1.0 (2) is uploaded (2026-10-10 morning). The friend was added as an internal tester and saw nothing; more
   friends want to help, so the next step is an external group with a public link (Beta App Review first) – see
   item 0 and the guide in his iCloud Drive. **Raise `CURRENT_PROJECT_VERSION` in `project.yml` before every
   further upload** (6 is uploaded since 2026-10-12 17:11; the next one is 7). He uploads himself (Xcode →
   Organizer → Distribute App); when he asks, Opus can archive and upload from the command line (plan §12,
   2026-10-11) – adding a build to the tester groups stays his clicks.

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
* Night rules **R3** (plan D15 + findings 2026-09-29/30): start only bedtime −10…+5 min; setup until
  max(start, bedtime) + 5 min; **an early start ("Go to sleep early today", owner 2026-10-11, plan §10 EARLY) is
  allowed from bedtime − 3 h, after a short confirmation, with no penalty – the night counts in full and the morning
  does not change; its setup lasts 15 min from the start**; after the setup, leaving the app → warning after ~3 s and 10 s to return (and at most
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
