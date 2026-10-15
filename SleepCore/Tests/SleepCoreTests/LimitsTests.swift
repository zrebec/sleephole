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

    func key(_ s: String) -> NightKey { NightKey(s)! }
    func state(_ start: Date?, _ now: Date) -> SchedulePolicy.State {
        SchedulePolicy.state(at: now, weekStart: start, calendar: bratislava)
    }

    @Test func theDecemberExample() {
        let start = at(2026, 12, 16, 21, 40)
        #expect(state(nil, start) == .open)
        #expect(state(start, start) == .changeWeek(lastDay: key("2026-12-22")))
        #expect(state(start, at(2026, 12, 22, 23, 59)) == .changeWeek(lastDay: key("2026-12-22")))
        #expect(state(start, at(2026, 12, 23, 0, 0)) == .locked(lastDay: key("2027-01-22"), freeFrom: key("2027-01-23")))
        #expect(state(start, at(2027, 1, 22, 23, 59)) == .locked(lastDay: key("2027-01-22"), freeFrom: key("2027-01-23")))
        #expect(state(start, at(2027, 1, 23, 0, 0)) == .open)
        #expect(state(start, at(2027, 6, 1, 12)) == .open)                  // nothing opens by itself
        #expect(SchedulePolicy.lockEnded(at: at(2027, 1, 23, 8), weekStart: start, calendar: bratislava) == key("2027-01-23"))
        #expect(SchedulePolicy.lockEnded(at: at(2027, 1, 22, 8), weekStart: start, calendar: bratislava) == nil)
        #expect(SchedulePolicy.lockEnded(at: at(2027, 1, 23, 8), weekStart: nil, calendar: bratislava) == nil)
    }

    @Test func theLockClampsToTheLengthOfTheMonth() {
        // a week ending 30 Jan → the lock starts 31 Jan → free from 28 Feb 2027 (29 Feb 2028)
        let p = SchedulePolicy.plan(opening: at(2027, 1, 24, 10), calendar: bratislava)
        #expect(p.lastDay == key("2027-01-30") && p.freeFrom == key("2027-02-28") && p.lockLastDay == key("2027-02-27"))
        let leap = SchedulePolicy.plan(opening: at(2028, 1, 24, 10), calendar: bratislava)
        #expect(leap.freeFrom == key("2028-02-29"))
        #expect(state(at(2027, 1, 24, 10), at(2027, 2, 27, 23)) == .locked(lastDay: key("2027-02-27"), freeFrom: key("2027-02-28")))
        #expect(state(at(2027, 1, 24, 10), at(2027, 2, 28, 0, 1)) == .open)
    }

    @Test func manyChangesInOneWeekDoNotExtendIt() {
        // the stored date is the opening only: later changes in the week never move it
        let start = at(2026, 12, 16, 9)
        for d in [16, 18, 22] {
            #expect(state(start, at(2026, 12, d, 20)) == .changeWeek(lastDay: key("2026-12-22")))
        }
        #expect(SchedulePolicy.allowsChange(state(start, at(2026, 12, 22, 23))))        // the last day still counts
        #expect(!SchedulePolicy.allowsChange(state(start, at(2026, 12, 23, 1))))
        #expect(SchedulePolicy.allowsChange(.open))
    }

    @Test func thePaidUnlockNeedsALockAndEnoughCoins() {
        let locked = state(at(2026, 12, 16, 9), at(2026, 12, 30, 9))
        #expect(SchedulePolicy.unlockPrice == 2000)
        #expect(SchedulePolicy.unlock(state: locked, coins: 5000) == .ok)
        #expect(SchedulePolicy.unlock(state: locked, coins: 2000) == .ok)
        #expect(SchedulePolicy.unlock(state: locked, coins: 1500) == .notEnoughCoins(missing: 500))
        #expect(SchedulePolicy.unlock(state: .open, coins: 9000) == .notLocked)
        #expect(SchedulePolicy.unlock(state: .changeWeek(lastDay: key("2026-12-22")), coins: 9000) == .notLocked)
        // the unlock opens a new week from today, followed by the usual one-month lock
        let today = at(2026, 12, 30, 9)
        #expect(state(today, today) == .changeWeek(lastDay: key("2027-01-05")))
        #expect(state(today, at(2027, 1, 6, 9)) == .locked(lastDay: key("2027-02-05"), freeFrom: key("2027-02-06")))
    }

    // MARK: the evening rule (default schedule 22:30 – 06:30, early start from 19:30)

    func starts(_ now: Date, new: Schedule = Schedule(bedtime: TimeOfDay(23, 0), wake: TimeOfDay(7, 0))) -> NightKey? {
        SchedulePolicy.startsFrom(changedAt: now, current: Schedule(), new: new, calendar: bratislava)
    }

    @Test func aChangeBeforeTheEarlyStartAppliesAtOnce() {
        #expect(starts(at(2026, 12, 16, 9)) == nil)
        #expect(starts(at(2026, 12, 16, 19, 29)) == nil)
        // after the morning is over the night in question is tonight's again
        #expect(starts(at(2026, 12, 16, 7, 31)) == nil)
    }

    @Test func aChangeFromTheEarlyStartWaitsForTheNextNight() {
        #expect(starts(at(2026, 12, 16, 19, 30)) == key("2026-12-18"))      // tonight is the night of 17 Dec
        #expect(starts(at(2026, 12, 16, 23, 30)) == key("2026-12-18"))
    }

    @Test func theEarlierOfTheTwoSchedulesDecides() {
        // new bedtime earlier (20:00 → early start 17:00): at 18:00 tonight can already be started under the NEW times
        let earlier = Schedule(bedtime: TimeOfDay(20, 0), wake: TimeOfDay(6, 30))
        #expect(starts(at(2026, 12, 16, 18), new: earlier) == key("2026-12-18"))
        #expect(starts(at(2026, 12, 16, 16, 59), new: earlier) == nil)
        // new bedtime later (01:00): under the OLD times the early start (19:30) has passed
        let later = Schedule(bedtime: TimeOfDay(1, 0), wake: TimeOfDay(8, 0))
        #expect(starts(at(2026, 12, 16, 20), new: later) == key("2026-12-18"))
    }

    @Test func aChangeAfterMidnightWaitsForTheComingEvening() {
        // 02:00 on 17 Dec is still the night of 17 Dec (it began at 22:30): the new times start with the night of 18 Dec
        #expect(starts(at(2026, 12, 17, 2)) == key("2026-12-18"))
        #expect(starts(at(2026, 12, 17, 7, 20)) == key("2026-12-18"))       // before the morning is over
    }

    @Test func aPendingScheduleIsDueWhenItsNightComes() {
        let p = PendingSchedule(schedule: Schedule(bedtime: TimeOfDay(23, 0), wake: TimeOfDay(7, 0)), fromNight: key("2026-12-18"))
        #expect(!p.isDue(at: at(2026, 12, 16, 23), current: Schedule(), calendar: bratislava))
        #expect(!p.isDue(at: at(2026, 12, 17, 7, 29), current: Schedule(), calendar: bratislava))   // the night of 17 Dec is not over
        #expect(p.isDue(at: at(2026, 12, 17, 7, 31), current: Schedule(), calendar: bratislava))
        #expect(p.isDue(at: at(2026, 12, 20, 12), current: Schedule(), calendar: bratislava))
        let data = try! JSONEncoder().encode(p)
        #expect(try! JSONDecoder().decode(PendingSchedule.self, from: data) == p)
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
