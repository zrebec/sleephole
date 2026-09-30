import Foundation
import Testing
@testable import SleepCore

@Suite struct NapTests {
    let plan = NapPlan()                                      // 30 min, 13:00–15:00

    @Test func windowIsInclusive() {
        #expect(!plan.canStart(at: at(2026, 10, 1, 12, 59), calendar: bratislava))
        #expect(plan.canStart(at: at(2026, 10, 1, 13, 0), calendar: bratislava))
        #expect(plan.canStart(at: at(2026, 10, 1, 15, 0), calendar: bratislava))      // edge: exactly at the end
        #expect(!plan.canStart(at: at(2026, 10, 1, 15, 0, 1), calendar: bratislava))
        #expect(!plan.canStart(at: at(2026, 10, 1, 18, 0), calendar: bratislava))
    }

    @Test func sessionLastsTheChosenTimeAndConfirmsOnlyAtTheEnd() {
        var p = NapPlan(minutes: 60)
        let w = p.session(startingAt: at(2026, 10, 1, 15, 0), calendar: bratislava)
        #expect(w.wake == at(2026, 10, 1, 16, 0))                                    // 15:00 → 16:00
        #expect(!w.canConfirm(at: at(2026, 10, 1, 15, 59)) && w.canConfirm(at: at(2026, 10, 1, 16, 0)))
        #expect(w.setupEnds(start: w.bedtime, rules: NapPlan.rules) == at(2026, 10, 1, 15, 2))
        p = NapPlan(minutes: 45)                                                      // only 30/60 allowed
        #expect(p.minutes == 30)
    }

    @Test func napOutcomesAndRewards() {
        let w = plan.session(startingAt: at(2026, 10, 1, 13, 10), calendar: bratislava)
        var l = NightLog(window: w, buildingId: "")
        l.append(.started, at: w.bedtime)
        l.append(.locked, at: w.bedtime + 60)
        l.append(.confirmed, at: w.wake + 30)
        #expect(NightEvaluator.evaluate(l, rules: NapPlan.rules) == .complete)
        var away = NightLog(window: w, buildingId: "")
        away.append(.started, at: w.bedtime)
        away.append(.leftApp, at: w.bedtime + 5 * 60)
        away.append(.returned, at: w.bedtime + 6 * 60)
        away.append(.confirmed, at: w.wake + 30)
        #expect(NightEvaluator.evaluate(away, rules: NapPlan.rules) == .ruins)
        #expect(NapPlan.reward(.complete) == 50 && NapPlan.reward(.unfinished) == 25 && NapPlan.reward(.ruins) == 0)
        #expect(NapPlan.reward(.missed) == 0)
    }

    @Test func codableRoundTrip() throws {
        let p = NapPlan(minutes: 60, windowStart: TimeOfDay(12, 30), windowEnd: TimeOfDay(14, 30))
        #expect(try JSONDecoder().decode(NapPlan.self, from: JSONEncoder().encode(p)) == p)
        let w = NightWindow(key: NightKey("2026-10-01")!, bedtime: Date(), wake: Date())
        #expect(w.earlyConfirmOverride == nil)
    }
}
