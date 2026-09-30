import Foundation
import Testing
@testable import SleepCore

@Suite struct StatsTests {
    let first = NightKey("2026-10-01")!

    /// Night i: started at bedtime 21:00 + startOffset[i] min, confirmed 04:30 + wakeOffset min.
    func night(_ i: Int, _ o: Outcome, start: Int = 0, wake: Int = 0) -> NightResult {
        let k = first.adding(days: i, calendar: bratislava)
        let prev = k.adding(days: -1, calendar: bratislava)
        let s = bratislava.date(from: DateComponents(year: prev.year, month: prev.month, day: prev.day, hour: 21))! + Double(start * 60)
        let w = bratislava.date(from: DateComponents(year: k.year, month: k.month, day: k.day, hour: 4, minute: 30))! + Double(wake * 60)
        return NightResult(key: k, outcome: o, buildingId: "x", startedAt: s, confirmedAt: w)
    }

    @Test func summaryOfAFewNights() {
        let r = [night(0, .complete, start: -4), night(1, .complete, start: 2), night(2, .unfinished, start: 5, wake: 20),
                 night(3, .complete, start: -3)]
        let s = Stats.summary(r, today: first.adding(days: 4, calendar: bratislava), calendar: bratislava)
        #expect(s.currentStreak == 3 && s.bestStreak == 3)
        #expect(s.builtNights == 4 && s.completeNights == 3 && s.coins == 350 && s.maxLevel == 1)
        #expect(s.averageStart == TimeOfDay(21, 0))
        #expect(s.averageWake == TimeOfDay(4, 35))
        #expect(s.regularityMinutes.map { $0 > 2 && $0 < 5 } == true)
        #expect(s.calendar.count == 35 && s.calendar.last?.outcome == .complete)
        #expect(s.calendar.filter { $0.outcome != nil }.count == 4)
        #expect(s.series.count == 4 && s.series[0].startMinutes == 536)        // 20:56 → minutes after noon
    }

    @Test func circularTimesAcrossMidnight() {
        #expect(Stats.circularMean([23 * 60 + 50, 10])! .rounded() == 0 || Stats.circularMean([1430, 10])!.rounded() == 1440)
        #expect(abs(Stats.circularStd([1430, 10])! - 10) < 0.01)
        #expect(Stats.circularMean([]) == nil && Stats.circularStd([600]) == nil)
        #expect(Stats.timeOfDay(1439.6) == TimeOfDay(0, 0))
    }

    @Test func emptyHistory() {
        let s = Stats.summary([], today: first, calendar: bratislava)
        #expect(s.currentStreak == 0 && s.coins == 0 && s.averageStart == nil && s.regularityMinutes == nil)
        #expect(s.calendar.allSatisfy { $0.outcome == nil } && s.series.isEmpty)
    }
}
