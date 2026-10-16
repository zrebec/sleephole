# Agenda archive – the old session-start agenda of `AGENTS.md`

Moved here VERBATIM on 2026-10-16, when the owner asked to organise the work by build ("we have a lot now – we must
start to behave sensibly"). It is history: what was open on each day up to 2026-10-16, his answers and Opus's notes.
The current agenda is the short one in `AGENTS.md`; the roadmap is plan §0b; the findings are plan §12. Nothing here
is an instruction any more – read it only to look something up.

---

## 📌 FIRST THING EVERY SESSION – tell the owner (owner's explicit request, 2026-10-02)

Whatever the owner's first message is (even just "Ahoj"), **start your reply by listing this agenda in Slovak**,
then answer. Remove items here when they are done.

0. **Open phone checks (plan §10 F6 and R4, bug B21 in §11a):**
   * **NEWEST – 2026-10-16 morning (plan §12, row of that day):** the night collapsed – one trip out of the app
     lasted 13.15 s against the 13 s limit (the 30 s budget was NOT the cause; Strict mode on, but a `.leftApp`
     counts in gentle mode too). He believes he only looked at the pulled-down Notification Center – open (B17):
     does iOS 26 send the app to the background under it? A 1-minute check in Developer → detection test decides.
     **He installed TestFlight build 1.0 (7) over 8g that night** – the store was migrated down (nothing of value
     lost), so B31 is back, no calm-hour coins, and the OLD schedule rule (streak reset) applies: he must not change
     bedtime / wake until build 8 is back. **11:04 the same morning, on his word: the Debug build 8g is back on his
     phone, installed OVER the TestFlight build (no uninstall); the store is migrated up again and identical to the
     morning copy (36 records, the build-8 columns back).** He will run the Notification Center check in build 8.
     App Store Connect read in his Chrome (nothing changed): version 1.0 with build 7 still "Waiting for Review";
     TestFlight build 7: 26 invites, 12 installs, 18 sessions, no crashes, no feedback. His question "build 8 today
     or tomorrow?" – Opus recommends: his real night with build 8 first, then upload 8 the next morning (commit 8g
     before it). **His request: once build 8 is in Apple's review, repeat this whole agenda to him.**
     **Noon the same day (plan §12, points 5–8 of that row):** his detection test proved it – on iOS 26 Notification
     Center sends the app to the background (B17 updated). Tips given, HIS decision open: keep the rule + say it in the
     guide / FAQ, point to the free pause, count the return from `willEnterForeground` (~0.8 s in the user's favour).
     He left the review swap to Opus → **decided: build 7 stays in review** (build 8's evening rule would break the
     review recipe's "bedtime in 3 minutes" within 3 h of the reviewer's bedtime – the recipe must be rewritten and tried
     on a clean install before build 8 is submitted). **His answers ~12:15:** A, B, C yes (no overlapping texts; B and C
     silent), D rejected; times set in the first-run guide = the review recipe (as SleepTown); the cat's ruins line B
     approved → **step 8h of build 8 (in work, NOT installed – his rest window; install only on his word)**; the
     Notification Center test is DONE (nothing left to test – Opus had phrased it badly). He wants the repair badge, so
     tonight's good night should rebuild the ruined library. **~12:40 he switched on the silver joker after all**
     (1 000 🪙 spent; the ruined night is protected, the ruin is gone, so no repair badge tonight); the 🔥 badge kept
     "Your streak starts today" – **B32 (plan §10 REL):** the data are right (replay: streak 15), the badge does not
     refresh; reopening the app shows the real value. **8h is built and reviewed (fallback text approved by him), NOT
     installed.** **8i (B32: everything redraws after any store write, his yes) and 8j (the museum line "kto im bol
     modelom", his wording) are built and reviewed too (app 498, i18n 0 / 0 / 0), NOT installed** – install 8h–8j on
     his word, never during his rest or at night; then his night with the full build 8, then commit + upload 8.
   * **NEWEST – 2026-10-15 morning (plan §12, row of that day):** his first night with build 7 was complete; the pause,
     the Face ID reminder and "no reminder for the Camera without Face ID" are confirmed by him. **New bug B31 (§11a):**
     the wake code cannot be typed on the night screen before the alarm (the shake works). Build 1.0 (7) is still
     "Waiting for Review". **The same morning:** he sent build 7 to the external group "SE" himself (Beta App
     Review); the age rating's new social-media questions are already answered "No" (Opus read them, nothing to do);
     **Build 8 (plan §10 REL) – COMPLETE and on his phone since 2026-10-15 13:47:** 8a B31 + seconds "15s" + the cat's
     comic bubble (he likes it; B31 confirmed by him), 8b calm hours +5 🪙, 8c "týždeň na zmeny" (7 days of changes,
     then a month locked, early unlock 2 000 🪙, no streak reset, evening change from tomorrow), 8d the setup notice only
     while outside the app, 8e the real moon phase without a city, 8f the cat talks about the sky (13 lines); **8g the cat's sentences in a random order (news of the day first) is on
     his phone since 21:02 – uncommitted** (8a–8f are committed, he pushes). Ask too: (e) does the cat feel less
     predictable; (f) the commit of 8g. **Ask in the morning:** (a) how the night went – the calm-hours line, no setup notice, the moon;
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
