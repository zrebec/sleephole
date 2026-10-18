import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// The first-run guide, the first-night checklist and their database flags (`UserProgress`).
@MainActor
struct GuideTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func makeModel(_ c: ModelContainer, at now: Date) -> (AppModel, FakeClock) {
        let clock = FakeClock(now)
        let m = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: AppSettings(),
                         servicesEnabled: false)
        return (m, clock)
    }

    func store() -> ModelContainer {
        try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self,
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    func render<V: View>(_ view: V, _ model: AppModel) {
        let host = UIHostingController(rootView: view.environment(model).environment(sprites))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.15)
        window.isHidden = true
    }

    @Test func guideIsStoredInTheDatabase() {
        let c = store()
        let (m, _) = makeModel(c, at: date(5, 12))
        #expect(!m.onboardingDone)
        m.completeOnboarding()
        #expect(m.onboardingDone)
        let rows = (try? c.mainContext.fetch(FetchDescriptor<UserProgress>())) ?? []
        #expect(rows.count == 1 && rows[0].onboardingCompletedAt != nil)
        let (again, _) = makeModel(c, at: date(6, 12))                  // relaunch keeps it
        #expect(again.onboardingDone)
    }

    @Test func firstNightBriefingOnlyBeforeTheFirstRealNight() {
        let c = store()
        let (m, clock) = makeModel(c, at: date(5, 22, 25))
        m.refresh()
        #expect(m.needsFirstNightBriefing)
        m.startTestNight()                                               // debug nights never need it
        #expect(!m.needsFirstNightBriefing)
        m.cancelFastNight()
        m.acknowledgeFirstNightBriefing()
        #expect(!m.needsFirstNightBriefing && m.firstNightBriefed)
        m.resetGuide()
        #expect(!m.onboardingDone && m.needsFirstNightBriefing)
        m.startNight()                                                   // a started real night also ends it
        #expect(!m.needsFirstNightBriefing)
        _ = clock
    }

    @Test func guideTextUsesTheRealRules() {
        Lang.current = .sk
        defer { Lang.current = .en }
        #expect(GuideText.pageCount == 9 && GuideView.pageCount == 9)
        let setup = AppSettings().setupGrace
        #expect(GuideText.page(2, setup: setup).text.contains("10 minút pred večierkou do 5 minút po nej"))
        #expect(GuideText.page(2, setup: setup).text.contains("3 hodiny skôr"))
        #expect(GuideText.page(3, setup: setup).text.contains("do večierky + 5 minút") && GuideText.page(3, setup: setup).text.contains("15s pred koncom"))
        #expect(GuideText.page(4, setup: setup).text.contains("15s"))
        #expect(GuideText.page(5, setup: setup).text.contains("Chceš si prečítať správu? Ťukni na 🌙 Pauza – 10 minút mimo appky"))
        #expect(GuideText.page(6, setup: setup).text.contains("30 minút pred budíkom") && GuideText.page(6, setup: setup).text.contains("Do 10 minút po budíku"))
        #expect(GuideText.page(7, setup: setup).text.contains("100–200 🪙") && GuideText.page(7, setup: setup).text.contains("+30") && GuideText.page(7, setup: setup).text.contains("+5"))
        let g = GuideText.ruleGroups
        #expect(g.count == 10 && g.map(\.title).prefix(9) == ["Rozvrh", "Večer", "Noc", "Pauza", "Ráno", "Mince a mesto", "Žolíky", "Odpočinok", "Súkromie"])
        #expect(g[0].items[1].replacingOccurrences(of: "\u{a0}", with: " ").contains("2 000 🪙"))
        #expect(g[1].items[2] == "Príprava trvá do večierky + zvolený čas (5, 10 alebo 15 minút v Nastaveniach), pri skoršom štarte 15 minút od štartu.")
        #expect(g[2].items[1].contains("15s") && g[2].items[1].contains("30s") && g[2].items[3].hasPrefix("Stiahnuté Centrum hlásení"))
        #expect(g[2].items[5].contains("8s"))
        #expect(g[3].items[0].contains("50, 100, 150 🪙"))
        #expect(g[4].items[0].contains("2 minúty") && g[4].items[1].contains("30 minút") && g[4].items[2].contains("10 minút") && g[4].items[2].contains("60 minút"))
        #expect(g[5].items[2].contains("od konca prípravy") && g[5].items[3].contains("1–5") && g[5].items[3].contains("6–15") && g[5].items[3].contains("od 31. noci"))
        #expect(g[6].items[0].contains("1 noc") && g[6].items[1].replacingOccurrences(of: "\u{a0}", with: " ").contains("3 noci za 1 000 🪙"))
        #expect(g[7].items[0].contains("13:00") && g[7].items[0].contains("+50 🪙") && g[7].items[0].contains("+25 🪙"))
        #expect(Plural.minutes(60) == "1 minútu" && Plural.seconds(3) == "3 sekundy" && Plural.nights(1) == "1 noc")
        #expect(Plural.hours(3 * 3600) == "3 hodiny" && Plural.hours(3600) == "1 hodinu" && Plural.hours(5 * 3600) == "5 hodín")
    }

    @Test func guideTextInEnglish() {
        Lang.current = .en
        let setup = AppSettings().setupGrace
        #expect(GuideText.page(2, setup: setup).text == "Tap “Go to sleep” from 10 minutes before bedtime until 5 minutes after it. Tired sooner? You can start up to 3 hours early.")
        #expect(GuideText.page(3, setup: setup).text == "After the start there's time for a podcast or story, until bedtime + 5 minutes. In another app? I'll call you 15s before the end.")
        #expect(GuideText.page(5, setup: setup).text == "Want to read a message? Tap 🌙 Pause – 10 minutes outside the app, the first one each night is free.")
        #expect(GuideText.page(7, setup: setup).text.hasPrefix("A finished night pays 100–200 🪙, +30 without a pause, +5 for every calm hour."))
        let g = GuideText.ruleGroups
        #expect(g[0].items[1] == "Your first change opens a change week (7 days). Then the schedule stays for a month; unlocking it sooner costs 2,000 🪙.")
        #expect(g[1].items[2] == "The setup lasts until bedtime + your setup time (5, 10 or 15 minutes in Settings), or 15 minutes from an early start.")
        #expect(g[2].items[3] == "On iOS 26, pulling down Notification Center counts as leaving the app – use 🌙 Pause to read a message.")
        #expect(g[3].items[0] == "🌙 Pause: 10 minutes outside the app. The first of a night is free, then 50, 100, 150 🪙.")
        #expect(g[5].items[1] == "No pause +30, every calm hour +5, every 7th finished night in a row +200.")
        #expect(g[5].items[2].contains("between the end of the setup and the alarm"))
        #expect(g[5].items[3] == "Levels: nights 1–5 level 1, 6–15 up to level 2, 16–30 up to level 3, from night 31 up to level 4.")
        #expect(g[6].items[1] == "Silver: 3 nights for 1,000 🪙. Gold: 7 nights for 5,000 🪙. Each kind once a month.")
        #expect(Plural.minutes(60) == "1 minute" && Plural.seconds(3) == "3 seconds" && Plural.nights(1) == "1 night")
    }

    /// The setup time on page 4 follows the Settings value (build 9, step 9b), in both languages.
    @Test func pageFourFollowsTheSetupSetting() {
        defer { Lang.current = .en }
        for minutes in AppSettings.setupMinuteOptions {
            var settings = AppSettings()
            settings.setupMinutes = minutes
            Lang.current = .en
            #expect(GuideText.page(3, setup: settings.setupGrace).text.contains("until bedtime + \(minutes) minutes."))
            Lang.current = .sk
            #expect(GuideText.page(3, setup: settings.setupGrace).text.contains("do večierky + \(minutes) minút."))
        }
    }

    /// Every number in a page or a rule comes from a constant of the app: each digit run of every sentence, in both
    /// languages, must be one the constants produce (typed labels such as "level 1" or "iOS 26" are listed by hand).
    @Test func everyNumberInTheGuideComesFromAConstant() {
        defer { Lang.current = .en }
        let r = GuideText.rules, t = Progression.thresholds, nap = NapPlan.default
        let m = { (x: TimeInterval) in Int(x / 60) }
        var allowed: Set<Int> = [
            m(NightWindow.startLead), m(r.startDeadline), Int(NightWindow.earlyStartLead / 3600), m(r.earlySetup),
            Int(SetupReminder.lead), Int(r.accidentalTolerance), Int(r.awayBudget ?? 0), Int(GuideText.lockWindow),
            m(PausePolicy.duration), PausePolicy.priceStep, PausePolicy.priceStep * 2, PausePolicy.priceStep * 3,
            PausePolicy.undisturbedBonus, m(NightWindow.earlyConfirm), m(NightWindow.onTimeConfirm),
            m(NightWindow.lateConfirm), m(r.alarmDuration), Economy.calmHourBonus, Economy.streakBonusEvery,
            Economy.streakBonus, SchedulePolicy.weekDays, SchedulePolicy.unlockPrice, RenamePolicy.price,
            m(RenamePolicy.typoWindow), t[1].minBuilt, t[1].minBuilt + 1, t[2].minBuilt, t[2].minBuilt + 1,
            t[3].minBuilt, t[3].minBuilt + 1, nap.windowStart.hour, nap.windowEnd.hour, nap.windowStart.minute,
            NapPlan.reward(.complete), NapPlan.reward(.unfinished),
            1, 2, 3, 4, 26,                                            // level labels and "iOS 26"
        ]
        allowed.formUnion(AppSettings.setupMinuteOptions)
        allowed.formUnion((1...4).map { Economy.completeReward(level: $0) })
        allowed.formUnion(JokerTier.allCases.flatMap { [$0.nights, $0.price] })
        allowed.formUnion(NapPlan.allowedMinutes)
        for lang in AppLanguage.allCases {
            Lang.current = lang
            var sentences = (0..<GuideText.pageCount).map { GuideText.page($0, setup: AppSettings().setupGrace).text }
            sentences += GuideText.ruleGroups.flatMap(\.items)
            for text in sentences {
                // "2,000" / "2 000" → 2000
                let flat = text.replacingOccurrences(of: "(?<=\\d)[,\u{a0}\u{202f} ](?=\\d{3}\\b)", with: "", options: .regularExpression)
                let runs = flat.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                for n in runs { #expect(allowed.contains(n), "\(n) in “\(text)” (\(lang))") }
            }
        }
    }

    /// Reference phones in points: width, height, top safe area, bottom safe area.
    static let phones: [(name: String, w: CGFloat, h: CGFloat, top: CGFloat, bottom: CGFloat)] = [
        ("SE", 375, 667, 20, 0), ("13 mini", 375, 812, 50, 34), ("16", 393, 852, 59, 34),
        ("16 Pro / 17", 402, 874, 62, 34), ("11", 414, 896, 48, 34), ("16 Plus", 430, 932, 59, 34),
        ("16 / 17 Pro Max", 440, 956, 62, 34),
    ]

    func room(_ p: (name: String, w: CGFloat, h: CGFloat, top: CGFloat, bottom: CGFloat)) -> CGFloat {
        p.h - p.top - p.bottom - (44 + 2 * GuideLayout.buttonBarPadding) - GuideLayout.dotsHeight
    }

    func chosenStyle(_ p: (name: String, w: CGFloat, h: CGFloat, top: CGFloat, bottom: CGFloat), replay: Bool,
                     model m: AppModel) -> GuideStyle {
        GuideStyle.choose(width: p.w, room: room(p), replay: replay, model: m)
    }

    /// Hard acceptance (owner): no guide page scrolls on any supported iPhone at the default text size, in both
    /// languages, first run and replay – with the style the guide picks for that display.
    @Test func noGuidePageScrollsOnAnyPhone() {
        defer { Lang.current = .en }
        let c = store()
        let (m, _) = makeModel(c, at: date(5, 22, 25))
        for p in Self.phones {
            for lang in AppLanguage.allCases {
                Lang.current = lang
                for replay in [false, true] {
                    let style = chosenStyle(p, replay: replay, model: m)
                    for i in 0..<GuideText.pageCount {
                        let view = GuidePageView(index: i, replay: replay, style: style, notificationsAllowed: .constant(nil),
                                                 showRules: .constant(false)).environment(m).environment(sprites)
                        let h = UIHostingController(rootView: view)
                            .sizeThatFits(in: CGSize(width: p.w, height: CGFloat.greatestFiniteMagnitude)).height
                        #expect(h <= room(p), "\(p.name) page \(i + 1) (\(lang), replay \(replay)) needs \(h) pt, room \(room(p)) pt, style \(style)")
                    }
                }
            }
        }
    }

    @Test func bigPhonesGetBiggerTextWithTheFullLineHeight() {
        defer { Lang.current = .en }
        let c = store()
        let (m, _) = makeModel(c, at: date(5, 22, 25))
        let se = Self.phones[0], pro = Self.phones[3], max = Self.phones[6]
        for lang in AppLanguage.allCases {
            Lang.current = lang
            for replay in [false, true] {
                let sSE = chosenStyle(se, replay: replay, model: m)
                let sPro = chosenStyle(pro, replay: replay, model: m)
                let sMax = chosenStyle(max, replay: replay, model: m)
                #expect(sPro.lineHeight >= 1.5 && sMax.lineHeight >= 1.5, "\(lang) \(replay): \(sPro) \(sMax)")
                #expect(sMax.textSize > sSE.textSize && sMax.textSize > 17, "\(lang) \(replay): \(sSE) \(sMax)")
                #expect(sMax.textSize >= sPro.textSize)
            }
        }
    }

    @Test func theStylePickerIsMonotoneAndAlwaysAnswers() {
        let all = GuideStyle.candidates
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.textSize >= $1.textSize })
        #expect(all.first?.lineHeight == 1.5 && all.last == GuideStyle.smallest)
        #expect(GuideStyle.pick(fits: { _ in false }) == GuideStyle.smallest)       // nothing fits: the last one
        #expect(GuideStyle.pick(fits: { _ in true }) == all[0])
        for (n, expected) in all.enumerated() {                                       // the first that fits, whatever the room
            #expect(GuideStyle.pick(fits: { s in all.firstIndex(of: s)! >= n }) == expected)
        }
    }

    @Test func theLateConfirmationLineReadsInBothLanguages() {
        defer { Lang.current = .en }
        func line() -> String {
            L("You confirmed \(Plural.minutes(16 * 60)) after the alarm – within \(Plural.minutes(NightWindow.onTimeConfirm)) the building would be complete.")
        }
        Lang.current = .en
        #expect(line() == "You confirmed 16 minutes after the alarm – within 10 minutes the building would be complete.")
        Lang.current = .sk
        #expect(line() == "Vstávanie bolo potvrdené 16 minút po budíku – do 10 minút by bola budova hotová.")
    }

    @Test func guideAndBriefingRender() {
        let c = store()
        let (m, _) = makeModel(c, at: date(5, 22, 25))
        m.refresh()
        render(GuideView(), m)
        render(GuideView(replay: true), m)
        render(RulesView(), m)
        render(ScheduleFields(schedule: .constant(Schedule())), m)
        render(FirstNightBriefing(), m)
        render(HomeView(), m)
        render(RootView(), m)                                             // shows the guide cover
        m.completeOnboarding()
        render(RootView(), m)
    }

    @Test func finishingTheGuideMarksItDone() {
        let c = store()
        let (m, _) = makeModel(c, at: date(5, 12))
        GuideView.complete(replay: true, model: m)
        #expect(!m.onboardingDone)                                        // a replay changes nothing
        GuideView.complete(replay: false, model: m)
        #expect(m.onboardingDone)
    }

    // MARK: - App Review's recipe (docs/REVIEW-NOTES.md, "A WHOLE NIGHT IN ABOUT 15 MINUTES")

    /// A fresh install at 20:30 – inside the 3 h before the default bedtime (22:30), the worst case for the evening rule.
    @Test func reviewRecipeWorksOnAFreshInstall() {
        let c = store()
        let (m, clock) = makeModel(c, at: date(5, 20, 30))
        m.refresh()
        #expect(!m.onboardingDone && m.settings.schedule.bedtime == TimeOfDay(22, 30))

        // 1. Guide page 2: bedtime in 3 min, wake in 15 min (the binding of `ScheduleFields` calls `applySchedule`).
        var s = m.settings.schedule
        s.bedtime = TimeOfDay(20, 33); s.wake = TimeOfDay(20, 45)
        #expect(m.applySchedule(s) == .applied)
        GuideView.complete(replay: false, model: m)
        #expect(m.onboardingDone)

        // 2. Tonight uses the new times at once; "Go to sleep" opens at bedtime - 10 min.
        #expect(m.settings.schedule.bedtime == TimeOfDay(20, 33) && m.settings.pendingSchedule == nil)
        #expect(m.window.bedtime == date(5, 20, 33) && m.window.wake == date(5, 20, 45))
        #expect(m.phase == .canStart)
        clock.now = date(5, 20, 22); m.refresh()
        #expect(m.phase != .canStart)                                      // 11 min before: not the normal start
        clock.now = date(5, 20, 23); m.refresh()
        #expect(m.phase == .canStart)                                      // exactly bedtime - 10 min
        clock.now = date(5, 20, 32); m.refresh()                           // "now + 2 min", 1 min before bedtime
        #expect(m.phase == .canStart && m.needsFirstNightBriefing)         // the checklist shows once
        m.acknowledgeFirstNightBriefing()
        #expect(!m.needsFirstNightBriefing)

        // 3. Start; setup runs to bedtime + 5 min (the default); the app stays in front.
        m.startNight()
        #expect(m.phase == .building)
        #expect(m.settings.setupMinutes == 5 && AppSettings.setupMinuteOptions == [5, 10, 15])
        #expect(m.graceEnds == date(5, 20, 38))
        clock.now = date(5, 20, 39); m.refresh()
        #expect(m.phase == .building && m.active?.log.has(.leftApp) == false)

        // 4. The wake time: the alarm rings; confirming is open (it opens 30 min before the wake time).
        #expect(m.active?.window.confirmOpens == date(5, 20, 15))
        clock.now = date(5, 20, 45); m.refresh()
        #expect(m.phase == .alarm && m.active?.log.has(.alarmFired) == true)
        clock.now = date(5, 20, 45) + 5; m.refresh()
        #expect(!m.confirm(code: m.settings.wakeCode == "0000" ? "1111" : "0000"))   // a wrong code does nothing
        #expect(m.confirm(code: m.settings.wakeCode))

        // 5. A complete night, a building in the town, the coins as the rules say (L1 100 + 30 without a pause, + any achievement).
        #expect(m.phase == .result)
        #expect(m.shownResult?.outcome == .complete)
        #expect(m.builtNights == 1 && m.townSnapshot?.buildings.count == 1)
        #expect(m.coins == 130 + Achievements.coins(m.achievements))    // the first-building achievement adds its own coins
        #expect(m.coinsEarned >= 130)
    }

    /// The same change through Settings, at the same time of day, waits for tomorrow - the reason the notes say
    /// "please use the guide".
    @Test func theSameChangeInSettingsWaitsForTomorrow() {
        let c = store()
        let (m, _) = makeModel(c, at: date(5, 20, 30))
        m.completeOnboarding()
        var s = m.settings.schedule
        s.bedtime = TimeOfDay(20, 33); s.wake = TimeOfDay(20, 45)
        #expect(m.applySchedule(s) == .fromTomorrow)
        #expect(m.settings.schedule.bedtime == TimeOfDay(22, 30))
        #expect(m.settings.pendingSchedule?.schedule.bedtime == TimeOfDay(20, 33))
        #expect(m.window.bedtime == date(5, 22, 30))                       // tonight is still the old night
    }

    /// The shared schedule editor (Settings + the replayed guide): what "Save" does in each change-week state.
    @Test func scheduleEditorSaveSteps() {
        let old = Schedule()
        var times = old; times.bedtime = TimeOfDay(23, 0)
        var reminder = old; reminder.reminderOffsets = [45]
        let week = SchedulePolicy.State.changeWeek(lastDay: NightKey("2026-10-11")!)
        #expect(ScheduleEditor.saveStep(old: old, draft: times, state: .open) == .confirm)       // opens a change week: asks first
        #expect(ScheduleEditor.saveStep(old: old, draft: reminder, state: .open) == .apply)      // the reminder is free
        #expect(ScheduleEditor.saveStep(old: old, draft: times, state: week) == .apply)          // in the week it saves at once
    }

    @Test func scheduleEditorCompactMessage() {
        let week = SchedulePolicy.State.changeWeek(lastDay: NightKey("2026-10-11")!)
        #expect(ScheduleEditor.showsPendingNote(state: week, pending: true, compact: true))
        #expect(ScheduleEditor.showsPendingNote(state: week, pending: false, compact: true) == false)
        #expect(ScheduleEditor.showsPendingNote(state: week, pending: true, compact: false) == false)   // Settings has its footer
        #expect(ScheduleEditor.showsPendingNote(state: .open, pending: true, compact: true))
    }
}
