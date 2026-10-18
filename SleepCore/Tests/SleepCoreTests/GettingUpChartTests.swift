import Foundation
import Testing
@testable import SleepCore

/// Step 9l: the chart's getting-up value and the clock times of a started night saved by a joker (B34).
@Suite struct GettingUpChartTests {
    let first = NightKey("2026-10-10")!
    func at(_ k: NightKey, _ h: Int, _ m: Int = 0, back: Int = 0) -> Date {
        let d = k.adding(days: -back, calendar: bratislava)
        return bratislava.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: h, minute: m))!
    }
    func started(_ k: NightKey, _ o: Outcome, confirmed: Bool = true, sleepEnd: Bool = false, calm: Int? = nil) -> NightResult {
        NightResult(key: k, outcome: o, buildingId: o.isBuildNight ? "l1-house-a-0" : nil,
                    startedAt: at(k, 22, 30, back: 1), confirmedAt: confirmed ? at(k, 6) : nil, pauses: 0,
                    bedtime: at(k, 22, 30, back: 1), fellAsleepAt: at(k, 23, 0, back: 1), asleepSeconds: 7 * 3600,
                    calmHours: calm, calmHoursTotal: calm == nil ? nil : 8,
                    sleepEndedAt: sleepEnd ? at(k, 6, 20) : nil)
    }

    @Test func seriesCarriesGettingUp() {
        let c = first.adding(days: 1, calendar: bratislava), h = first.adding(days: 2, calendar: bratislava)
        let n = first.adding(days: 3, calendar: bratislava)
        let r = [started(first, .complete), started(c, .ruins, confirmed: false, sleepEnd: true),
                 started(h, .complete, confirmed: true, sleepEnd: true), started(n, .unfinished, confirmed: false)]
        let s = Stats.summary(r, today: first.adding(days: 4, calendar: bratislava), calendar: bratislava).series
        #expect(s[0].upMinutes == 1080)                       // confirmation 6:00 = 18 h after noon
        #expect(s[1].upMinutes == 1100)                       // no confirmation → Health 6:20
        #expect(s[2].upMinutes == 1080)                       // the confirmation wins over Health
        #expect(s[3].upMinutes == nil)                        // neither
    }

    @Test func excusedStartedNightKeepsItsTimesButNotItsEconomy() {
        let a = first, b = first.adding(days: 1, calendar: bratislava), c = first.adding(days: 2, calendar: bratislava)
        let plain = [started(a, .complete, calm: 8), started(b, .ruins, calm: 5), started(c, .complete, calm: 8)]
        let manual = [JokerUse(tier: .bronze, firstNight: b)]
        let (out, _) = Jokers.apply(results: plain, manual: manual, lastNight: c, calendar: bratislava)
        let x = out.first { $0.key == b }!
        #expect(x.outcome == .excused && x.buildingId == nil && x.calmHours == nil && x.pauses == nil)
        #expect(x.startedAt != nil && x.fellAsleepAt != nil && x.confirmedAt != nil && x.asleepSeconds == 7 * 3600)
        let ledger = Economy.ledger(out, calendar: bratislava)
        #expect(ledger.first { $0.key == b }?.coins == 0 && ledger.first { $0.key == b }?.calmBonus == 0)
        #expect(Progression.currentStreak(out, lastNight: c, calendar: bratislava) == 2)       // neither grows nor breaks
        let s = Stats.summary(out, today: c.adding(days: 1, calendar: bratislava), calendar: bratislava)
        #expect(s.series.first { $0.key == b }?.startMinutes != nil && s.series.first { $0.key == b }?.upMinutes == 1080)
        #expect(s.builtNights == 2)
    }

    @Test func aMissedNightStaysWithoutTimes() {
        let r = [started(first, .complete), started(first.adding(days: 2, calendar: bratislava), .complete)]
        let miss = first.adding(days: 1, calendar: bratislava)
        let (out, uses) = Jokers.apply(results: r, manual: [], lastNight: first.adding(days: 2, calendar: bratislava), calendar: bratislava)
        #expect(uses.count == 1)
        let x = out.first { $0.key == miss }!
        #expect(x.outcome == .excused && x.startedAt == nil && x.confirmedAt == nil && x.sleepEndedAt == nil)
    }

    @Test func aTestNightWithoutTimesAndSeparateFromTheRealOne() {
        let t = NightResult(key: first, outcome: .complete, buildingId: "x", startedAt: at(first, 15), confirmedAt: at(first, 15, 15),
                            isTestNight: true)
        let w = t.withoutClockTimes
        #expect(w.startedAt == nil && w.confirmedAt == nil && w.isTestNight == true && w.outcome == .complete)
    }
}
