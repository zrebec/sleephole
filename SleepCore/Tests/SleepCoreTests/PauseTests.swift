import Foundation
import Testing
@testable import SleepCore

/// Night pause (D17) + the per-night budget of seconds out of the app (owner 2026-10-03).
@Suite struct PauseTests {
    let wakeMin = nightMinutes
    /// Rules of a night from before 2026-10-03: no budget, 13 s per trip, as often as you like.
    let legacy: SleepRules = { var r = SleepRules(); r.awayBudget = nil; return r }()

    @Test func prices() {
        #expect((1...5).map(PausePolicy.price(number:)) == [0, 50, 100, 150, 200])
        #expect(PausePolicy.duration == 600 && PausePolicy.undisturbedBonus == 30)
    }

    // MARK: budget (B4)

    /// Five trips of 6–7 s within a minute (seen in a real night).
    @Test func manyShortTripsNoLongerPass() {
        var events: [(Double, NightEventKind)] = [(0, .started), (6, .locked), (72, .unlocked), (72.01, .returned)]
        var t = 72.5
        for _ in 0..<5 {
            events.append((t, .leftApp)); events.append((t + 6.5 / 60, .returned))
            t += 12.0 / 60
        }
        events.append((wakeMin, .confirmed))
        let l = log(events)
        #expect(NightEvaluator.evaluate(l, rules: legacy) == .complete)          // how it was
        #expect(NightEvaluator.evaluate(l) == .ruins)                            // 32.5 s > the 30 s budget
        // it collapses during the 5th trip, when the 30 s are used up (4 × 6.5 = 26 s before it → 4 s left)
        let fifth = night.bedtime + (72.5 + 4 * 12.0 / 60) * 60
        let collapse = NightEvaluator.collapsedAt(l)!
        #expect(abs(collapse.timeIntervalSince(fifth) - 4) < 0.001)
    }

    @Test func twoAccidentalTripsStillFit() {
        let l = log([(0, .started), (100, .leftApp), (100 + 12.0 / 60, .returned),
                     (200, .leftApp), (200 + 12.0 / 60, .returned), (wakeMin, .confirmed)])
        #expect(NightEvaluator.evaluate(l) == .complete)                         // 24 s of 30
        #expect(NightEvaluator.awayAfterSetup(l, until: night.wake) == 24)
        #expect(NightEvaluator.allowance(l, at: night.bedtime + 300 * 60) == 6)   // what a third trip may take
        #expect(NightEvaluator.allowance(l, at: night.bedtime + 50 * 60) == 13)   // before any trip: the full 13 s
        #expect(NightEvaluator.allowance(l, rules: legacy, at: night.bedtime + 300 * 60) == 13)
    }

    @Test func setupTimeDoesNotUseTheBudget() {
        let l = log([(0, .started), (0.5, .leftApp), (4.9, .returned), (100, .leftApp), (100 + 12.0 / 60, .returned),
                     (wakeMin, .confirmed)])
        #expect(NightEvaluator.awayAfterSetup(l, until: night.wake) == 12)
        #expect(NightEvaluator.evaluate(l) == .complete)
    }

    // MARK: pause

    @Test func aPauseExcusesTenMinutes() {
        let l = log([(0, .started), (1, .locked), (180, .unlocked), (180.01, .returned), (180.2, .pauseStarted),
                     (180.5, .leftApp), (188, .returned), (189, .locked), (wakeMin, .confirmed)])
        #expect(NightEvaluator.evaluate(l) == .complete)
        #expect(NightEvaluator.awayAfterSetup(l, until: night.wake) == 0)
        #expect(NightEvaluator.result(for: l, key: l.key).pauses == 1)
        #expect(NightEvaluator.result(for: l, key: l.key, rules: legacy).pauses == nil)
        #expect(NightEvaluator.result(for: l, key: l.key).bedtime == night.bedtime)
    }

    @Test func stayingOutAfterThePauseCollapses() {
        // pause 180.2 … 190.2; back at 190.2 + 12 s stands, + 20 s collapses 13 s after the pause ended
        let ok = log([(0, .started), (180.2, .pauseStarted), (180.5, .leftApp), (190.2 + 12.0 / 60, .returned),
                      (wakeMin, .confirmed)])
        #expect(NightEvaluator.evaluate(ok) == .complete)
        let late = log([(0, .started), (180.2, .pauseStarted), (180.5, .leftApp), (190.2 + 20.0 / 60, .returned),
                        (wakeMin, .confirmed)])
        #expect(NightEvaluator.evaluate(late) == .ruins)
        #expect(NightEvaluator.collapsedAt(late) == night.bedtime + 190.2 * 60 + 13)
    }

    @Test func blockReasons() {
        let started = log([(0, .started)])
        let t = { (min: Double) in night.bedtime + min * 60 }
        #expect(PausePolicy.block(started, at: t(2), coins: 0) == .setup(until: t(5)))
        #expect(PausePolicy.block(started, at: t(6), coins: 0) == nil)                        // the first one is free
        #expect(PausePolicy.block(started, at: t(6), coins: 0, isNap: true) == .nap)
        let one = log([(0, .started), (100, .pauseStarted)])
        #expect(PausePolicy.block(one, at: t(105), coins: 999) == .running(until: t(110)))
        #expect(PausePolicy.activeUntil(one, at: t(105)) == t(110))
        #expect(PausePolicy.activeUntil(one, at: t(110)) == nil)
        #expect(PausePolicy.block(one, at: t(120), coins: 20) == .notEnoughCoins(missing: 30))    // the 2nd costs 50
        #expect(PausePolicy.block(one, at: t(120), coins: 50) == nil)
        let two = log([(0, .started), (100, .pauseStarted), (120, .pauseStarted)])
        #expect(PausePolicy.block(two, at: t(140), coins: 99) == .notEnoughCoins(missing: 1))     // the 3rd costs 100
        let fallen = log([(0, .started), (100, .leftApp), (101, .returned)])
        #expect(PausePolicy.block(fallen, at: t(120), coins: 999) == .collapsed)
    }

    // MARK: coins

    @Test func anUndisturbedNightPaysThirtyMore() {
        let k = NightKey("2026-10-05")!
        func r(_ day: Int, _ o: Outcome, pauses: Int?) -> NightResult {
            NightResult(key: k.adding(days: day, calendar: bratislava), outcome: o, buildingId: "l1-house-a-0", pauses: pauses)
        }
        let ledger = Economy.ledger([r(0, .complete, pauses: 0), r(1, .complete, pauses: 1), r(2, .complete, pauses: nil),
                                     r(3, .unfinished, pauses: 0), r(4, .ruins, pauses: 0)], calendar: bratislava)
        #expect(ledger.map(\.coins) == [130, 100, 100, 50, 0])
        #expect(ledger.map(\.undisturbedBonus) == [30, 0, 0, 0, 0])
    }

    // MARK: story of the night

    @Test func reportListsPausesAndFreeTrips() {
        let l = log([(0, .started), (1, .locked), (180.2, .pauseStarted), (180.5, .leftApp), (188, .returned),
                     (300, .leftApp), (300 + 5.0 / 60, .returned), (wakeMin, .alarmFired), (wakeMin + 0.3, .unlocked),
                     (wakeMin + 0.5, .confirmed)])
        let r = NightReport(log: l)
        #expect(r.pauses == [night.bedtime + 180.2 * 60])
        #expect(r.nightTrips.map(\.duringPause) == [true, false])
        #expect(r.screenChecks.isEmpty)                                 // the unlock after the alarm is no "check"
    }
}
