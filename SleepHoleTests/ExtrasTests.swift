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
        try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self, BoxRecord.self,
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
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
        #expect(m.coins == 300 + 3 * 30 + 3 * 35 + 100)
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
            #expect(pattern.duration >= (h == .pet ? 0 : 0.5), "\(h) too short")      // .pet: one light tap
            #expect(!VibrationTestView.title(h).isEmpty)
            Haptics.play(h)                                   // simulator: no Taptic Engine → the fallback path
        }
        #expect(Haptics.lastResult != "–")
        let (m, _) = model(store(), at: date(1, 12))
        render(NavigationStack { VibrationTestView() }, m)
    }

    /// The petting vibrations (plan P2b): a soft rumble of ~1.2 s with gentle pulses, and ONE light tap.
    @Test func purrAndPetPatternsAreSoft() throws {
        let purr = try Haptics.pattern(.purr)
        #expect(purr.duration >= 1.1 && purr.duration <= 1.4)
        let pet = try Haptics.pattern(.pet)
        #expect(pet.duration < 0.5)
        #expect(Haptic.allCases.count == 4)
        #expect(VibrationTestView.title(.purr) != VibrationTestView.title(.pet))
        #expect(VibrationTestView.title(.purr) == "Purr" && VibrationTestView.title(.pet) == "Petting the cat")
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

    func day(_ month: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: h, minute: mi))!
    }

    // MARK: the change week (build 8, owner 2026-10-15)

    @Test func theChangeWeekOpensLocksAndUnlocksForCoinsWithoutTouchingTheStreak() {
        let (m, clock) = model(store(), at: date(5, 12))
        #expect(m.scheduleState == .open)                                  // before the guide: nothing is running
        m.completeOnboarding()                                             // the guide set the first schedule: day 1 = 5. 10.
        #expect(m.scheduleState == .changeWeek(lastDay: NightKey("2026-10-11")!))
        var s = m.settings.schedule
        s.bedtime = TimeOfDay(22, 0)
        #expect(m.applySchedule(s) == .applied)                            // noon: well before the early start of tonight
        #expect(m.settings.schedule.bedtime == TimeOfDay(22, 0) && m.settings.pendingSchedule == nil)
        #expect(m.scheduleChanges().last?.free == true && m.scheduleChanges().last?.rule == 1 && m.streakBreaks.isEmpty)
        s.bedtime = TimeOfDay(22, 30)
        clock.now = date(8, 12)
        #expect(m.applySchedule(s) == .applied)                            // as many changes as he likes ...
        #expect(m.changeWeekStart == date(5, 12) && m.scheduleChanges().count == 2)   // ... and the week is not extended
        for d in 8...25 { night(m, clock, day: d) }
        clock.now = date(26, 9); m.refresh()
        let streak = m.streak, coins = m.coins
        #expect(streak == 18 && coins >= SchedulePolicy.unlockPrice)
        #expect(m.scheduleState == .locked(lastDay: NightKey("2026-11-11")!, freeFrom: NightKey("2026-11-12")!))
        s.wake = TimeOfDay(6, 0)
        #expect(m.applySchedule(s) == .locked && m.settings.schedule.wake == TimeOfDay(6, 30))   // refused
        s = m.settings.schedule; s.reminderOffsets = [45]
        #expect(m.applySchedule(s) == .applied && m.settings.schedule.reminderOffsets == [45])    // the reminder stays free
        #expect(m.unlockSchedule() == .unlocked)
        #expect(m.coinsSpent == 2000 && m.spends().last?.reason == "schedule-unlock" && m.coins == coins - 2000)
        #expect(m.scheduleState == .changeWeek(lastDay: NightKey("2026-11-01")!) && m.changeWeekStart == date(26, 9))
        #expect(m.unlockSchedule() == .notLocked && m.coinsSpent == 2000)
        s.wake = TimeOfDay(6, 0)
        #expect(m.applySchedule(s) == .applied && m.settings.schedule.wake == TimeOfDay(6, 0))
        #expect(m.streak == streak && m.streakBreaks.isEmpty)               // a change never resets the streak
        // the lock after the paid week ends on 2. 12. – the card asks once
        clock.now = day(12, 1, 9); m.refresh()
        #expect(!m.showsChangeWeekCard && m.scheduleState != .open)
        clock.now = day(12, 2, 9); m.refresh()
        #expect(m.scheduleState == .open && m.showsChangeWeekCard)
        render(TodayView(), m)
        render(ChangeWeekCard(), m)
        m.answerChangeWeekCard(adjust: true)
        #expect(!m.showsChangeWeekCard && m.settingsRequest == 1)
        clock.now = day(12, 3, 9); m.refresh()
        #expect(!m.showsChangeWeekCard && m.scheduleState == .open)         // nothing opens by itself, the card came once
    }

    @Test func theUnlockIsRefusedWithoutEnoughCoinsAndOutsideALock() {
        let (m, clock) = model(store(), at: date(5, 12))
        m.completeOnboarding()
        #expect(m.unlockSchedule() == .notLocked)                           // in the change week
        clock.now = date(20, 12); m.refresh()
        #expect(m.scheduleState == .locked(lastDay: NightKey("2026-11-11")!, freeFrom: NightKey("2026-11-12")!))
        #expect(m.coins == 0 && m.unlockSchedule() == .notEnoughCoins(missing: 2000))
        #expect(m.coinsSpent == 0 && m.coins == 0)                          // coins never go negative
    }

    @Test func everyoneWhoUpdatedStartsOpenAndTheFirstChangeOpensAWeek() throws {
        let c = store()
        let (old, _) = model(c, at: date(5, 12))
        let p = try c.mainContext.fetch(FetchDescriptor<UserProgress>()).first!
        p.onboardingCompletedAt = date(1, 12)                               // an existing user: guide done long ago
        p.scheduleCalibrationStart = date(1, 12)                            // the old calibration week (ended on 8. 10.)
        c.mainContext.insert(ScheduleChange(at: date(3, 10), from: "22:30–6:30", to: "23:00–7:00", free: false, breakKey: "2026-10-04"))
        try c.mainContext.save()
        _ = old
        let (m, _) = model(c, at: date(5, 12))
        #expect(m.onboardingDone && m.changeWeekStart == nil && m.scheduleState == .open)
        #expect(m.streakBreaks == [NightKey("2026-10-04")!])                // the history stays as it was
        #expect(!m.showsChangeWeekCard)                                     // no week was ever opened: no "lock ended" card
        var s = m.settings.schedule
        s.wake = TimeOfDay(6, 0)
        #expect(m.applySchedule(s) == .applied)                             // the UI asked first; the model opens the week
        #expect(m.scheduleState == .changeWeek(lastDay: NightKey("2026-10-11")!))
        #expect(m.scheduleChanges().map(\.rule) == [nil, 1] && m.streakBreaks == [NightKey("2026-10-04")!])
    }

    @Test func aChangeFromTheEarlyStartWaitsForTheNextNightAndIsAppliedWhenItComes() {
        let (m, clock) = model(store(), at: date(5, 12))
        m.completeOnboarding()
        clock.now = date(5, 20); m.refresh()                                // 19:30 (early start of tonight) has passed
        var s = m.settings.schedule
        s.bedtime = TimeOfDay(23, 0); s.wake = TimeOfDay(7, 0)
        #expect(m.applySchedule(s) == .fromTomorrow)
        #expect(m.settings.schedule == Schedule() && m.editableSchedule == s)
        #expect(m.settings.pendingSchedule == PendingSchedule(schedule: s, fromNight: NightKey("2026-10-07")!))
        s.reminderOffsets = [10]
        #expect(m.applySchedule(s) == .applied)                             // only the reminder: at once, for both
        #expect(m.settings.schedule.reminderOffsets == [10] && m.settings.pendingSchedule?.schedule.reminderOffsets == [10])
        // back to the times in effect: nothing waits any more
        var back = Schedule(); back.reminderOffsets = [10]
        #expect(m.applySchedule(back) == .applied)
        #expect(m.settings.pendingSchedule == nil && m.settings.schedule.bedtime == TimeOfDay(22, 30))
        // again, and tonight still runs with the old times
        #expect(m.applySchedule(s) == .fromTomorrow)
        clock.now = date(5, 22, 25); m.refresh(); m.startNight()
        #expect(m.active?.bedtime == date(5, 22, 30))
        clock.now = date(6, 6, 31); m.refresh(); m.confirm(code: "1234"); m.acknowledgeResult()
        #expect(m.settings.schedule.bedtime == TimeOfDay(22, 30))           // the morning of the old night: not yet
        clock.now = date(6, 8); m.refresh()
        #expect(m.settings.schedule.bedtime == TimeOfDay(23, 0) && m.settings.schedule.wake == TimeOfDay(7, 0))
        #expect(m.settings.pendingSchedule == nil && m.window.bedtime == date(6, 23))
        clock.now = date(6, 22, 49); m.refresh()
        #expect(m.phase == .idle)
        clock.now = date(6, 22, 50); m.refresh()
        #expect(m.phase == .canStart)                                       // the new times: start opens 10 min before 23:00
    }

    @Test func aChangeAfterMidnightAppliesFromTheComingEvening() {
        let (m, clock) = model(store(), at: date(5, 12))
        m.completeOnboarding()
        clock.now = date(6, 2); m.refresh()                                 // the night of 6. 10. began yesterday evening
        var s = m.settings.schedule
        s.bedtime = TimeOfDay(23, 0)
        #expect(m.applySchedule(s) == .fromTomorrow)
        #expect(m.settings.pendingSchedule?.fromNight == NightKey("2026-10-07")!)    // = the evening of 6. 10.
        clock.now = date(6, 7, 31); m.refresh()                             // the old night is over
        #expect(m.settings.schedule.bedtime == TimeOfDay(23, 0) && m.settings.pendingSchedule == nil)
    }

    @Test func theScheduleSectionAndTheLockEndNotificationRender() {
        let (m, _) = model(store(), at: date(5, 12))
        m.completeOnboarding()
        for state in [SchedulePolicy.State.open, .changeWeek(lastDay: NightKey("2026-10-09")!),
                      .locked(lastDay: NightKey("2026-11-11")!, freeFrom: NightKey("2026-11-12")!)] {
            m.debugScheduleState = state
            render(SettingsView(), m)
        }
        #expect(SettingsView.daysLeft(until: NightKey("2026-10-09")!, now: date(5, 12), calendar: cal) == Plural.days(5))
        #expect(SettingsView.daysLeft(until: NightKey("2026-10-09")!, now: date(9, 12), calendar: cal) == Plural.days(1))
        #expect(Notifications.monthlyCheckContent().interruptionLevel == .active)
        Notifications.scheduleLockEnded(on: NightKey("2999-01-01")!, wake: TimeOfDay(23, 30))   // 00:30 – wraps past midnight
        Notifications.scheduleLockEnded(on: NightKey("2000-01-01")!, wake: TimeOfDay(6, 30))    // in the past: nothing scheduled
        Notifications.scheduleLockEnded(on: nil, wake: TimeOfDay(6, 30))
    }
}
