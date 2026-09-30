import Foundation
import Testing
@testable import SleepCore

@Suite struct LimitsTests {
    let now = at(2026, 10, 15, 12)
    let day: TimeInterval = 24 * 3600

    // MARK: rename

    @Test func firstNamingIsFreeAndNeverCounts() {
        #expect(RenamePolicy.cost(at: now, hasCustomName: false, lastRenameAt: nil, lastFreeRenameAt: nil)
                == .free(.firstNaming))
        // an older version stored a name without dates → the yearly free rename is available
        #expect(RenamePolicy.cost(at: now, hasCustomName: true, lastRenameAt: nil, lastFreeRenameAt: nil)
                == .free(.yearly))
        // back to the default name after a rename: not a "first naming" any more
        #expect(RenamePolicy.cost(at: now, hasCustomName: false, lastRenameAt: now - 30 * day,
                                  lastFreeRenameAt: now - 30 * day) == .paid(5000))
    }

    @Test func oneFreeRenameEvery365Days() {
        let free = now - 364 * day
        #expect(RenamePolicy.cost(at: now, hasCustomName: true, lastRenameAt: free, lastFreeRenameAt: free) == .paid(5000))
        #expect(RenamePolicy.cost(at: free + 365 * day, hasCustomName: true, lastRenameAt: free, lastFreeRenameAt: free)
                == .free(.yearly))
        #expect(RenamePolicy.nextFree(after: now, lastFreeRenameAt: free) == free + 365 * day)
        #expect(RenamePolicy.nextFree(after: now, lastFreeRenameAt: nil) == nil)
        #expect(RenamePolicy.nextFree(after: now, lastFreeRenameAt: now - 400 * day) == nil)
        #expect(RenamePolicy.Cost.paid(5000).coins == 5000 && RenamePolicy.Cost.free(.yearly).coins == 0)
    }

    @Test func aTypoCanBeFixedForTenMinutes() {
        let renamed = now - 9 * 60
        #expect(RenamePolicy.cost(at: now, hasCustomName: true, lastRenameAt: renamed, lastFreeRenameAt: renamed)
                == .free(.typoFix))
        #expect(RenamePolicy.cost(at: renamed + 10 * 60, hasCustomName: true, lastRenameAt: renamed,
                                  lastFreeRenameAt: renamed) == .paid(5000))
    }

    // MARK: schedule

    @Test func scheduleChangesAreFreeOnDays1to3AndInTheFirstWeek() {
        for d in 1...3 {
            #expect(SchedulePolicy.change(at: at(2026, 11, d, 23, 59), calibrationStart: nil, calendar: bratislava)
                    == .free(.monthStart))
        }
        #expect(SchedulePolicy.change(at: at(2026, 11, 4, 0, 1), calibrationStart: nil, calendar: bratislava)
                == .resetsStreak)
        let start = at(2026, 11, 10, 8)
        #expect(SchedulePolicy.change(at: start + 6.9 * day, calibrationStart: start, calendar: bratislava)
                == .free(.calibration))
        #expect(SchedulePolicy.change(at: start + 7 * day, calibrationStart: start, calendar: bratislava) == .resetsStreak)
        #expect(SchedulePolicy.calibrationEnds(after: start, calibrationStart: start) == start + 7 * day)
        #expect(SchedulePolicy.calibrationEnds(after: start + 8 * day, calibrationStart: start) == nil)
    }

    @Test func nextFreeWindowIsTheFirstOfNextMonth() {
        let mid = at(2026, 12, 15, 12)
        #expect(SchedulePolicy.nextFreeWindow(after: mid, calibrationStart: nil, calendar: bratislava) == at(2027, 1, 1, 0))
        let inside = at(2026, 12, 2, 12)
        #expect(SchedulePolicy.nextFreeWindow(after: inside, calibrationStart: nil, calendar: bratislava) == inside)
    }

    @Test func aStreakBreakStartsWithTonightsNight() {
        #expect(SchedulePolicy.streakBreak(changedAt: at(2026, 10, 15, 14), calendar: bratislava) == NightKey("2026-10-16"))
    }

    // MARK: streak breaks everywhere

    func results(_ n: Int, from first: NightKey = NightKey("2026-10-01")!) -> [NightResult] {
        (0..<n).map { NightResult(key: first.adding(days: $0, calendar: bratislava), outcome: .complete, buildingId: "x") }
    }

    @Test func aBreakResetsTheCurrentStreakButKeepsTheBest() {
        let r = results(10)                                           // 1.–10. 10.
        let cut = [NightKey("2026-10-06")!]                           // changed on the 5th
        #expect(Progression.currentStreak(r, lastNight: NightKey("2026-10-10")!, calendar: bratislava) == 10)
        #expect(Progression.currentStreak(r, lastNight: NightKey("2026-10-10")!, calendar: bratislava, breaks: cut) == 5)
        #expect(Progression.bestStreak(r, calendar: bratislava, breaks: cut) == 5)
        #expect(Progression.currentStreak(r, lastNight: NightKey("2026-10-10")!, calendar: bratislava,
                                          breaks: [NightKey("2026-11-01")!]) == 10)   // a future break: no effect yet
        #expect(Progression.currentStreak(r, lastNight: NightKey("2026-10-10")!, calendar: bratislava,
                                          breaks: [NightKey("2026-10-11")!]) == 0)   // changed today: 0 at once
    }

    @Test func theStreakBonusAndAchievementsRestartAfterABreak() {
        let r = results(10)
        #expect(Economy.ledger(r, calendar: bratislava).filter { $0.streakBonus > 0 }.count == 1)       // 7th night
        let cut = [NightKey("2026-10-05")!]
        #expect(Economy.ledger(r, calendar: bratislava, breaks: cut).filter { $0.streakBonus > 0 }.isEmpty)
        #expect(Economy.earned(r, calendar: bratislava, breaks: cut) == 1000)
        let a = Achievements.unlocked(results: r, catalog: nil, calendar: bratislava, breaks: cut).map(\.achievement)
        #expect(a.contains(.streak3) && !a.contains(.streak7))
        let s = Stats.summary(r, today: NightKey("2026-10-11")!, calendar: bratislava, breaks: cut)
        #expect(s.currentStreak == 6 && s.bestStreak == 6 && s.coins == 1000)
        let w = WeeklyJournal.weeks(results: r, calendar: bratislava, breaks: cut)
        #expect(w.map(\.coins).reduce(0, +) == 1000)
        #expect(WeeklyJournal.week(monday: NightKey("2026-09-28")!, results: r, calendar: bratislava, breaks: cut).nights > 0)
    }
}
