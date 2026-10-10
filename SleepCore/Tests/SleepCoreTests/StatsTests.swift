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

    /// Three nights with one bedtime, then a bedtime half an hour later (a free schedule change). Every start is
    /// within a few minutes of its own bedtime → regular, although the clock times are 30 min apart.
    @Test func regularityIsMeasuredAgainstEachNightsBedtime() {
        func r(_ day: Int, bed: (Int, Int), start: (Int, Int, Int)) -> NightResult {
            NightResult(key: NightKey(year: 2026, month: 10, day: day + 1), outcome: .complete, buildingId: nil,
                        startedAt: at(2026, 10, day, start.0, start.1, start.2), bedtime: at(2026, 10, day, bed.0, bed.1))
        }
        let nights = [r(1, bed: (22, 0), start: (21, 57, 0)), r(2, bed: (22, 0), start: (21, 55, 0)),
                      r(3, bed: (22, 0), start: (22, 2, 0)), r(4, bed: (22, 30), start: (22, 27, 0))]
        let s = Stats.summary(nights, today: NightKey(year: 2026, month: 10, day: 5), calendar: bratislava)
        #expect(s.regularityMinutes! > 2 && s.regularityMinutes! < 3.5)                  // ±3 min, not ±13
        // results without a bedtime (old code paths) still give the spread of clock times
        let old = nights.map { NightResult(key: $0.key, outcome: .complete, buildingId: nil, startedAt: $0.startedAt) }
        let o = Stats.summary(old, today: NightKey(year: 2026, month: 10, day: 5), calendar: bratislava)
        #expect(o.regularityMinutes! > 10)
    }

    /// Night i with Apple Health data: fell asleep `fell` minutes after the 21:00 start (nil = no value).
    func sleepNight(_ i: Int, fell: Int?, start: Int = 0) -> NightResult {
        let n = night(i, .complete, start: start)
        return NightResult(key: n.key, outcome: n.outcome, buildingId: "x", startedAt: n.startedAt, confirmedAt: n.confirmedAt,
                           fellAsleepAt: fell.flatMap { f in n.startedAt.map { $0 + Double(f * 60) } },
                           asleepSeconds: fell == nil ? nil : 7 * 3600)
    }

    @Test func fellAsleepAveragesTakeOnlyNightsWithAValue() {
        let r = [sleepNight(0, fell: 20), sleepNight(1, fell: nil), sleepNight(2, fell: 40), night(3, .complete)]
        let s = Stats.summary(r, today: first.adding(days: 4, calendar: bratislava), calendar: bratislava)
        #expect(s.averageFellAsleep == TimeOfDay(21, 30))                 // 21:20 and 21:40
        #expect(s.averageMinutesToSleep == 30)
        #expect(s.series[0].asleepMinutes == 560)                         // 21:20 → minutes after noon
        #expect(s.series[1].asleepMinutes == nil && s.series[3].asleepMinutes == nil)
    }

    @Test func fellAsleepWrapsAroundMidnightAndNegativeCountsAsZero() {
        let r = [sleepNight(0, fell: 175), sleepNight(1, fell: 185), sleepNight(2, fell: -10)]
        let s = Stats.summary(r, today: first.adding(days: 3, calendar: bratislava), calendar: bratislava)
        #expect(s.series[0].asleepMinutes == 715)                         // 23:55, minutes after noon
        #expect(s.series[1].asleepMinutes == 725)                         // 00:05 → continuous with the evening axis
        #expect(s.averageMinutesToSleep == 120.0)                    // (175 + 185 + 0) / 3
        let two = Stats.summary(Array(r.prefix(2)), today: first.adding(days: 3, calendar: bratislava), calendar: bratislava)
        #expect(two.averageFellAsleep == TimeOfDay(0, 0))                 // 23:55 and 00:05 meet at midnight
    }

    @Test func withoutSleepDataNothingElseChanges() {
        let plain = [night(0, .complete, start: -4), night(1, .complete, start: 2), night(2, .unfinished, start: 5, wake: 20)]
        let s = Stats.summary(plain, today: first.adding(days: 3, calendar: bratislava), calendar: bratislava)
        #expect(s.averageFellAsleep == nil && s.averageMinutesToSleep == nil && s.series.allSatisfy { $0.asleepMinutes == nil })
        let withData = plain.enumerated().map { i, n in
            NightResult(key: n.key, outcome: n.outcome, buildingId: n.buildingId, startedAt: n.startedAt, confirmedAt: n.confirmedAt,
                        fellAsleepAt: n.startedAt.map { $0 + Double((10 + i) * 60) })
        }
        let t = Stats.summary(withData, today: first.adding(days: 3, calendar: bratislava), calendar: bratislava)
        #expect(t.averageStart == s.averageStart && t.averageWake == s.averageWake && t.regularityMinutes == s.regularityMinutes
                && t.coins == s.coins && t.currentStreak == s.currentStreak && t.calendar == s.calendar)
    }
}
