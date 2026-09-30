import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// Owner extras 2026-09-30: achievements, town name (idea S) and the weekly journal (idea M).
@MainActor
struct ExtrasTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func store() -> ModelContainer {
        try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func model(_ c: ModelContainer, at now: Date) -> (AppModel, FakeClock) {
        let clock = FakeClock(now)
        var s = AppSettings(); s.wakeCode = "1234"
        return (AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s,
                         servicesEnabled: false), clock)
    }

    func night(_ m: AppModel, _ clock: FakeClock, day: Int) {
        clock.now = date(day, 22, 25); m.refresh(); m.startNight()
        clock.now = date(day + 1, 6, 31); m.refresh(); m.confirm(code: "1234")
        m.acknowledgeResult()
    }

    func render<V: View>(_ view: V, _ m: AppModel) {
        let host = UIHostingController(rootView: view.environment(m).environment(sprites))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.15)
        window.isHidden = true
    }

    // MARK: town name

    @Test func townNameDefaultsToTheLanguageAndIsStored() throws {
        let c = store()
        let (m, _) = model(c, at: date(1, 12))
        #expect(m.townName == "My Town" && m.customTownName == nil)
        m.language = .sk
        #expect(m.townName == "Moje mesto")
        #expect(m.renameCost() == .free(.firstNaming))
        #expect(m.renameTown("   Zajačikovo   ") == .renamed)                 // first naming: free
        #expect(m.townName == "Zajačikovo" && m.renameTown("Zajačikovo") == .unchanged)
        #expect(m.renameCost() == .free(.typoFix))
        m.renameTown(String(repeating: "x", count: 50))                    // within 10 min: free
        #expect(m.townName.count == AppModel.townNameMaxLength)
        m.renameTown("Zajačikovo")
        #expect(m.coinsSpent == 0)
        let (again, _) = model(c, at: date(1, 12))                       // stored in the database
        #expect(again.townName == "Zajačikovo")
        // backup round trip
        let data = try again.makeBackup().encoded()
        let (other, _) = model(store(), at: date(1, 12))
        try other.restore(BackupFile.decode(data))
        #expect(other.townName == "Zajačikovo")
        other.renameTown("  ")                                            // empty = back to the default
        #expect(other.customTownName == nil && other.townName == "Moje mesto")
        other.language = .en
    }

    // MARK: achievements

    @Test func achievementsPayCoinsOnceAndShowOnTheResultScreen() {
        let (m, clock) = model(store(), at: date(1, 12))
        #expect(m.achievements.isEmpty)
        for d in 1...2 { night(m, clock, day: d) }
        clock.now = date(3, 22, 25); m.refresh(); m.startNight()
        clock.now = date(4, 6, 31); m.refresh(); m.confirm(code: "1234")
        #expect(m.newAchievements == [.streak3])
        render(ResultView(), m)
        m.acknowledgeResult()
        #expect(m.achievements.map(\.achievement) == [.firstBuilding, .streak3])
        #expect(m.coins == 300 + 100)
        render(StatsView(), m)
        render(AchievementsCard(), m)
        render(NewAchievements(achievements: Achievement.allCases), m)
        for a in Achievement.allCases { #expect(!a.icon.isEmpty && !a.title.isEmpty && !a.detail.isEmpty) }
    }

    @Test func townHeaderWithAName() {
        let (m, clock) = model(store(), at: date(1, 12))
        night(m, clock, day: 1)
        m.renameTown("Zajačikovo")
        render(TownTab(), m)
        render(SettingsView(), m)
    }

    // MARK: weekly journal

    @Test func finishedWeekOnTheResultScreenAfterSundayNight() {
        let (m, clock) = model(store(), at: date(5, 12))                  // Monday 5 Oct 2026
        for d in 5...10 { night(m, clock, day: d) }                        // Mon … Sat evenings
        #expect(m.finishedWeek == nil)
        clock.now = date(11, 22, 25); m.refresh(); m.startNight()          // Sunday evening
        clock.now = date(12, 6, 31); m.refresh(); m.confirm(code: "1234")
        let week = m.finishedWeek
        #expect(week?.monday == NightKey("2026-10-05") && week?.complete == 7 && week?.built == 7)
        render(ResultView(), m)
        m.acknowledgeResult()
        #expect(m.finishedWeek == nil)
        night(m, clock, day: 12)                                           // Monday evening: already shown
        #expect(m.finishedWeek == nil)
        #expect(m.journalWeeks.count == 2 && m.currentMonday == NightKey("2026-10-12"))
        render(StatsView(), m)
        render(JournalCard(), m)
    }

    @Test func journalSentencesAreNeverShaming() throws {
        let (m, clock) = model(store(), at: date(5, 12))
        night(m, clock, day: 5)
        let one = try #require(m.journalWeeks.first)
        let empty = m.journalWeek(monday: NightKey("2026-09-28")!)
        for lang in AppLanguage.allCases {
            m.language = lang
            #expect(!WeekJournalView.sentence(empty, previous: nil).isEmpty)
            #expect(WeekJournalView.sentence(one, previous: nil) != WeekJournalView.sentence(empty, previous: nil))
            #expect(WeekJournalView.sentence(one, previous: empty) == WeekJournalView.sentence(one, previous: nil))
            render(WeekJournalView(week: one, previous: one), m)
            render(JournalCard(), m)                                       // empty current week
        }
        m.language = .en
        #expect(WeekJournalView.range(one) == "10/5 – 10/11")
    }

    // MARK: vibrations

    @Test func everyVibrationHasAStrongPatternAndATestButton() throws {
        for h in Haptic.allCases {
            let pattern = try Haptics.pattern(h)
            #expect(pattern.duration >= 0.5, "\(h) too short")
            #expect(!VibrationTestView.title(h).isEmpty)
            Haptics.play(h)                                   // simulator: no Taptic Engine → the fallback path
        }
        #expect(Haptics.lastResult != "–")
        let (m, _) = model(store(), at: date(1, 12))
        render(NavigationStack { VibrationTestView() }, m)
    }

    // MARK: limits (owner 2026-09-30)

    @Test func renamingIsFreeOnceAYearOtherwiseItCosts5000Coins() throws {
        let c = store()
        let (m, clock) = model(c, at: date(1, 12))
        m.renameTown("Zajačikovo")                                         // first naming
        clock.now += 3600
        #expect(m.renameCost() == .free(.yearly))
        #expect(m.renameTown("Líščikovo") == .renamed)                     // the yearly free one
        #expect(m.nextFreeRename != nil && m.coinsSpent == 0)
        clock.now += 3600
        #expect(m.renameCost() == .paid(5000))
        #expect(m.renameTown("Ježkovo") == .notEnoughCoins && m.townName == "Líščikovo")
        #expect(RenameTownAlert.costText(.paid(5000), coins: 1200, nextFree: m.nextFreeRename).contains("800"))   // "3,800"
        for d in 1...60 { night(m, clock, day: d) }                        // earn ≥ 5 000 🪙
        let before = m.coins
        #expect(before >= 5000 && m.renameTown("Ježkovo") == .renamed)
        #expect(m.coins == before - 5000 && m.coinsSpent == 5000 && m.spends().first?.reason == "rename-town")
        // the spend survives a backup
        let data = try m.makeBackup().encoded()
        let (other, _) = model(store(), at: date(1, 12))
        try other.restore(BackupFile.decode(data))
        #expect(other.coinsSpent == 5000 && other.townName == "Ježkovo" && other.renameCost(at: clock.now) == .free(.typoFix))
        for cost in [RenamePolicy.Cost.free(.firstNaming), .free(.typoFix), .free(.yearly), .paid(5000)] {
            #expect(!RenameTownAlert.costText(cost, coins: 9000, nextFree: nil).isEmpty)
        }
        render(SettingsView(), m)
        render(TownTab().renameTownAlert(isPresented: .constant(true)), m)
    }

    @Test func scheduleChangesAreFreeInTheirWindowsOtherwiseTheStreakStartsAgain() {
        let (m, clock) = model(store(), at: date(5, 12))                  // calibration: 5.–12. 10.
        m.completeOnboarding()
        var s = m.settings.schedule
        s.bedtime = TimeOfDay(22, 0)
        #expect(m.scheduleChangeCost() == .free(.calibration) && m.scheduleCalibrationEnds != nil)
        m.applySchedule(s)                                                 // free: first week
        #expect(m.scheduleChanges().last?.free == true && m.streakBreaks.isEmpty)
        s.bedtime = TimeOfDay(22, 30)
        m.applySchedule(s)
        for d in 5...14 { night(m, clock, day: d) }
        clock.now = date(15, 12); m.refresh()
        #expect(m.streak == 10 && m.scheduleChangeCost() == .resetsStreak)
        let coins = m.coins
        s.reminderOffsets = [45]
        m.applySchedule(s)                                                 // only the reminder: always free
        #expect(m.streak == 10 && m.settings.schedule.reminderOffsets == [45])
        s.wake = TimeOfDay(6, 0)
        m.applySchedule(s)                                                 // outside the window: streak again
        #expect(m.streak == 0 && m.streakBreaks == [NightKey("2026-10-16")!])
        #expect(m.coins == coins && m.stats.bestStreak == 10)              // nothing else is taken away
        #expect(m.nextFreeScheduleChange == cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!)
        clock.now = date(15, 22, 25); m.refresh(); m.startNight()
        clock.now = date(16, 6, 1); m.refresh(); m.confirm(code: "1234"); m.acknowledgeResult()
        #expect(m.streak == 1)
        m.applySchedule(s)                                                 // unchanged: nothing recorded
        #expect(m.scheduleChanges().count == 3)
        for cost in [SchedulePolicy.Change.free(.monthStart), .free(.calibration), .resetsStreak] {
            #expect(!SettingsView.scheduleRules(cost, nextFree: clock.now, calibrationEnds: clock.now).isEmpty)
        }
        render(SettingsView(), m)
        render(GuideView(replay: true), m)
    }

    @Test func theMonthlyCardAsksOnDays1to3() {
        let (m, clock) = model(store(), at: date(15, 12))
        m.completeOnboarding()
        #expect(!m.showsMonthlySchedulePrompt)
        clock.now = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!
        #expect(m.showsMonthlySchedulePrompt && m.scheduleChangeCost() == .free(.monthStart))
        render(TodayView(), m)
        render(MonthlyScheduleCard(), m)
        m.answerMonthlyPrompt(adjust: true)
        #expect(!m.showsMonthlySchedulePrompt && m.settingsRequest == 1)
        clock.now = cal.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 9))!
        #expect(m.showsMonthlySchedulePrompt)                              // next month asks again
        m.answerMonthlyPrompt(adjust: false)
        #expect(!m.showsMonthlySchedulePrompt && m.settingsRequest == 1)
        Notifications.scheduleMonthlyCheck(wake: TimeOfDay(23, 30))        // wraps past midnight
    }
}
