import Foundation
import Testing
@testable import SleepCore

/// B50 (owner 2026-11-10): the last start minute shown on Today counts whole.
@Suite struct LastStartMinuteTests {
    var gentle: SleepRules { var r = SleepRules(); r.startDeadline = SleepRules.gentleStartDeadline; return r }
    let w = Schedule(bedtime: TimeOfDay(21, 30), wake: TimeOfDay(6, 30)).window(containing: at(2026, 10, 1, 21), calendar: bratislava)

    @Test func endOfShownMinuteHelper() {
        #expect(NightWindow.endOfShownMinute(at(2026, 10, 1, 22, 0)) == at(2026, 10, 1, 22, 1))
        #expect(NightWindow.endOfShownMinute(at(2026, 10, 1, 22, 0, 37)) == at(2026, 10, 1, 22, 1))
    }

    @Test func gentleStartLastMinuteCountsWhole() {
        let r = gentle
        #expect(w.canStart(at: at(2026, 10, 1, 22, 0), rules: r))
        #expect(w.canStart(at: at(2026, 10, 1, 22, 0, 59).addingTimeInterval(0.999), rules: r))
        #expect(!w.canStart(at: at(2026, 10, 1, 22, 1), rules: r))
        #expect(!w.canStart(at: at(2026, 10, 1, 21, 19, 59).addingTimeInterval(0.999), rules: r))
        #expect(w.canStart(at: at(2026, 10, 1, 21, 20), rules: r))
    }

    @Test func strictStartLastMinuteCountsWhole() {
        let r = SleepRules()
        #expect(w.canStart(at: at(2026, 10, 1, 21, 35, 59).addingTimeInterval(0.999), rules: r))
        #expect(!w.canStart(at: at(2026, 10, 1, 21, 36), rules: r))
    }

    @Test func evaluateAcceptsTheWholeMinute() {
        func outcome(_ start: Date, _ r: SleepRules) -> Outcome {
            var l = NightLog(window: w, buildingId: "x")
            l.append(.started, at: start)
            l.append(.confirmed, at: w.wake)
            return NightEvaluator.evaluate(l, rules: r)
        }
        #expect(outcome(at(2026, 10, 1, 22, 0, 40), gentle) == .complete)
        #expect(outcome(at(2026, 10, 1, 22, 1), gentle) == .missed)
        #expect(outcome(at(2026, 10, 1, 21, 35, 59), SleepRules()) != .missed)
        #expect(outcome(at(2026, 10, 1, 21, 36), SleepRules()) == .missed)
    }

    @Test func napLastMinuteCountsWhole() {
        let plan = NapPlan()
        #expect(plan.canStart(at: at(2026, 10, 1, 15, 0), calendar: bratislava))
        #expect(plan.canStart(at: at(2026, 10, 1, 15, 0, 59).addingTimeInterval(0.999), calendar: bratislava))
        #expect(!plan.canStart(at: at(2026, 10, 1, 15, 1), calendar: bratislava))
        #expect(!plan.canStart(at: at(2026, 10, 1, 12, 59, 59).addingTimeInterval(0.999), calendar: bratislava))
        #expect(plan.canStart(at: at(2026, 10, 1, 13, 0), calendar: bratislava))
    }
}
