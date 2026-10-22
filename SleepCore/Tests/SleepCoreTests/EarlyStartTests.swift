import Foundation
import Testing
@testable import SleepCore

@Suite struct EarlyStartTests {
    let b = night.bedtime
    let rules = SleepRules()

    @Test func canStartEarlyWindow() {
        #expect(!night.canStartEarly(at: b - 3 * 3600 - 1))
        #expect(night.canStartEarly(at: b - 3 * 3600))
        #expect(night.canStartEarly(at: b - 600 - 1))
        #expect(!night.canStartEarly(at: b - 600))
        #expect(!night.canStartEarly(at: b))
        #expect(!night.canStartEarly(at: b + 60))
    }

    /// Owner 2026-10-19, build 10b: the gentle mode starts until bedtime + 30 min.
    @Test func gentleStartDeadlineIs30Minutes() {
        var gentle = SleepRules(); gentle.startDeadline = SleepRules.gentleStartDeadline
        #expect(night.startCloses(gentle) == b + 30 * 60 && night.startCloses() == b + 5 * 60)
        #expect(night.canStart(at: b + 20 * 60, rules: gentle) && !night.canStart(at: b + 20 * 60))
        #expect(night.canStart(at: b + 30 * 60, rules: gentle) && !night.canStart(at: b + 30 * 60 + 1, rules: gentle))
        let l = log([(20, .started), (wakeMinutes + 1, .confirmed)])
        #expect(NightEvaluator.evaluate(l, rules: gentle) == .complete)
        #expect(NightEvaluator.evaluate(l) == .missed)
        #expect(NightEvaluator.evaluate(log([(30, .started), (wakeMinutes + 1, .confirmed)]), rules: gentle) == .complete)
        #expect(NightEvaluator.evaluate(log([(30.02, .started), (wakeMinutes + 1, .confirmed)]), rules: gentle) == .missed)
    }

    @Test func normalStartWindowIsUnchanged() {
        #expect(!night.canStart(at: b - 600 - 1))
        #expect(!night.canStart(at: b - 3 * 3600))
        #expect(night.canStart(at: b - 600))
        #expect(night.canStart(at: b + 5 * 60))
        #expect(!night.canStart(at: b + 5 * 60 + 1))
    }

    @Test func isEarlyStart() {
        #expect(night.isEarlyStart(b - 600 - 1))
        #expect(!night.isEarlyStart(b - 600))
        #expect(!night.isEarlyStart(b))
        #expect(!night.isEarlyStart(b + 120))
    }

    @Test func setupEnds() {
        let early = b - 100 * 60
        #expect(night.setupEnds(start: early, rules: rules) == early + 15 * 60)
        #expect(night.setupEnds(start: b - 600, rules: rules) == b + 5 * 60)
        #expect(night.setupEnds(start: b - 601, rules: rules) == b + 5 * 60 - 1)   // no jump at the boundary
        #expect(night.setupEnds(start: b + 3 * 60, rules: rules) == b + 8 * 60)
    }

    @Test func earlyNightIsComplete() {
        let l = log([(-100, .started), (-99, .locked), (nightMinutes, .alarmFired), (nightMinutes + 1, .confirmed)])
        #expect(NightEvaluator.evaluate(l) == .complete)
    }

    @Test func tripInsideEarlySetupIsFree() {
        let l = log([(-100, .started), (-95, .leftApp), (-90, .returned),
                     (nightMinutes, .alarmFired), (nightMinutes + 1, .confirmed)])
        #expect(NightEvaluator.collapsedAt(l) == nil)
        #expect(NightEvaluator.evaluate(l) == .complete)
    }

    @Test func tripAfterEarlySetupCollapsesBeforeBedtime() {
        let tripStart = b + (-100 + 20) * 60
        var l = log([(-100, .started), (-80, .leftApp)])
        l.append(.returned, at: tripStart + 20)
        l.append(.confirmed, at: night.wake)
        #expect(NightEvaluator.evaluate(l) == .ruins)
        #expect(NightEvaluator.collapsedAt(l) == tripStart + 13)
    }

    @Test func pauseReportsSetupForEarlyStart() {
        let l = log([(-100, .started)])
        let t = b - 95 * 60
        #expect(PausePolicy.block(l, at: t, coins: 1000) == .setup(until: b - 85 * 60))
    }

    @Test func napsAndDebugNightsAreNeverEarly() {
        let start = at(2026, 9, 29, 13)
        let nap = NapPlan().session(startingAt: start, calendar: bratislava)
        #expect(!nap.isEarlyStart(start))
        let debug = NightWindow(key: night.key, bedtime: start, wake: start + 600)
        #expect(!debug.isEarlyStart(start))
    }
}
