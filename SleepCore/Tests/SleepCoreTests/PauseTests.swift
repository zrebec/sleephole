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
        // the 5th trip starts with 26 s used (< 30 s): it is a full trip, so it stands (32.5 s away in total)…
        #expect(NightEvaluator.evaluate(l) == .complete)
        #expect(NightEvaluator.collapsedAt(l) == nil)
        // …but a 6th trip starts with the budget used up and collapses the building at the moment of leaving
        var more = events.dropLast()
        more.append((t, .leftApp)); more.append((t + 6.5 / 60, .returned)); more.append((wakeMin, .confirmed))
        let sixth = night.bedtime + t * 60
        let collapse = NightEvaluator.collapsedAt(log(Array(more)))!
        #expect(abs(collapse.timeIntervalSince(sixth)) < 0.001)
        #expect(NightEvaluator.evaluate(log(Array(more))) == .ruins)
    }

    @Test func twoAccidentalTripsStillFit() {
        let l = log([(0, .started), (100, .leftApp), (100 + 12.0 / 60, .returned),
                     (200, .leftApp), (200 + 12.0 / 60, .returned), (wakeMin, .confirmed)])
        #expect(NightEvaluator.evaluate(l) == .complete)                         // 24 s of 30
        #expect(NightEvaluator.awayAfterSetup(l, until: night.wake) == 24)
        #expect(NightEvaluator.allowance(l, at: night.bedtime + 300 * 60) == 13)  // a third trip is still a full one
        #expect(NightEvaluator.allowance(l, at: night.bedtime + 50 * 60) == 13)   // before any trip: the full 13 s
        #expect(NightEvaluator.allowance(l, rules: legacy, at: night.bedtime + 300 * 60) == 13)
    }

    /// Bug of a real night: four short trips used 25.5 s and the fifth got only the rest, so its warning came too late.
    @Test func aTripStartedWithBudgetLeftIsAFullTrip() {
        func sec(_ s: Double) -> Double { s / 60 }
        var events: [(Double, NightEventKind)] = [(0, .started)]
        var t = 100.0
        for d in [5.5, 4, 5, 11] {
            events.append((t, .leftApp)); events.append((t + sec(d), .returned)); t += 1
        }
        let before = night.bedtime + t * 60
        #expect(NightEvaluator.awayAfterSetup(log(events), until: before) == 25.5)
        #expect(NightEvaluator.allowance(log(events), at: before) == 13)             // not 4.5
        #expect(NightEvaluator.budgetState(log(events), at: before) == .low)
        events.append((t, .leftApp)); events.append((t + sec(6.8), .returned))
        let after = log(events + [(wakeMin, .confirmed)])
        #expect(NightEvaluator.collapsedAt(after) == nil)
        #expect(NightEvaluator.evaluate(after) == .complete)
        let end = night.bedtime + (t + 1) * 60
        #expect(NightEvaluator.budgetState(after, at: end) == .spent)                // 32.3 s used
        #expect(NightEvaluator.allowance(after, at: end) == 0)
        // a further detectable trip collapses the building exactly at its start
        let next = events + [(t + 1, .leftApp), (t + 1 + sec(4), .returned), (wakeMin, .confirmed)]
        #expect(NightEvaluator.collapsedAt(log(next)) == end)
        #expect(NightEvaluator.evaluate(log(next)) == .ruins)
    }

    @Test func aTripWithAlmostNoBudgetLeftStillGetsThirteenSeconds() {
        func sec(_ s: Double) -> Double { s / 60 }
        // 29.9 s used by two trips, then a trip of 12 s (stands) or 14 s (collapses 13 s after its start)
        let base: [(Double, NightEventKind)] = [(0, .started), (100, .leftApp), (100 + sec(12), .returned),
                                                (110, .leftApp), (110 + sec(12), .returned),
                                                (120, .leftApp), (120 + sec(5.9), .returned)]
        let start = night.bedtime + 130 * 60
        #expect(abs(NightEvaluator.awayAfterSetup(log(base), until: start) - 29.9) < 0.001)
        let ok = log(base + [(130, .leftApp), (130 + sec(12), .returned), (wakeMin, .confirmed)])
        #expect(NightEvaluator.collapsedAt(ok) == nil)
        let bad = log(base + [(130, .leftApp), (130 + sec(14), .returned), (wakeMin, .confirmed)])
        #expect(NightEvaluator.collapsedAt(bad) == start + 13)
    }

    @Test func budgetStateBoundaries() {
        func sec(_ s: Double) -> Double { s / 60 }
        func state(afterAway s: Double) -> AwayBudgetState? {
            let l = log([(0, .started), (100, .leftApp), (100 + sec(s), .returned)])
            return NightEvaluator.budgetState(l, at: night.bedtime + 101 * 60)
        }
        #expect(NightEvaluator.budgetState(log([(0, .started)]), rules: legacy, at: night.bedtime + 100 * 60) == nil)
        #expect(NightEvaluator.budgetState(log([(0, .started)]), at: night.bedtime + 100 * 60) == .fine)
        #expect(state(afterAway: 10) == .fine)
        #expect(state(afterAway: 17) == .fine)       // 13 s left = one full trip
        #expect(state(afterAway: 17.5) == .low)
        #expect(state(afterAway: 29.5) == .low)
        #expect(state(afterAway: 30) == .spent)      // used == budget
    }

    // MARK: forgiven (B24)

    @Test func forgivenUndoesACollapse() {
        func sec(_ s: Double) -> Double { s / 60 }
        let trip: [(Double, NightEventKind)] = [(0, .started), (100, .leftApp), (100 + sec(40), .returned)]
        #expect(NightEvaluator.collapsedAt(log(trip)) != nil)
        let l = log(trip + [(101, .forgiven), (wakeMin, .confirmed)])
        #expect(NightEvaluator.collapsedAt(l) == nil)
        #expect(NightEvaluator.awayAfterSetup(l, until: night.wake) == 0)
        #expect(NightEvaluator.budgetState(l, at: night.bedtime + 102 * 60) == .fine)
        #expect(NightEvaluator.evaluate(l) == .complete)
        #expect(NightEvaluator.awaySeconds(l) == 0)
        #expect(NightReport(log: l).nightTrips.isEmpty)
    }

    @Test func revokedForgivenessBringsTheCollapseBack() {
        func sec(_ s: Double) -> Double { s / 60 }
        let trip: [(Double, NightEventKind)] = [(0, .started), (100, .leftApp), (100 + sec(40), .returned)]
        let forgiven = log(trip + [(101, .forgiven), (wakeMin, .confirmed)])
        #expect(NightEvaluator.evaluate(forgiven) == .complete)                      // regression: no revoke, as before
        let l = log(trip + [(101, .forgiven), (150, .forgivenessRevoked), (wakeMin, .confirmed)])
        #expect(NightEvaluator.collapsedAt(l) == NightEvaluator.collapsedAt(log(trip)))
        #expect(NightEvaluator.collapsedAt(l) != nil && NightEvaluator.evaluate(l) == .ruins)
        #expect(NightEvaluator.awaySeconds(l) == NightEvaluator.awaySeconds(log(trip)))
        #expect(NightReport(log: l).nightTrips.count == NightReport(log: log(trip)).nightTrips.count)
        #expect(NightReport(log: l).nightTrips.count == 1 && NightReport(log: forgiven).nightTrips.isEmpty)
        let data = try! JSONEncoder().encode(NightEventKind.forgivenessRevoked)
        #expect(try! JSONDecoder().decode(NightEventKind.self, from: data) == .forgivenessRevoked)
    }

    @Test func forgivenDropsAnOpenTripAndTripsAfterItCountNormally() {
        func sec(_ s: Double) -> Double { s / 60 }
        let open: [(Double, NightEventKind)] = [(0, .started), (100, .leftApp), (101, .forgiven)]
        #expect(NightEvaluator.collapsedAt(log(open)) == nil)
        let at = night.bedtime + 200 * 60
        #expect(NightEvaluator.collapsedAt(log(open + [(200, .leftApp), (200 + sec(14), .returned)])) == at + 13)
        #expect(NightEvaluator.collapsedAt(log(open + [(200, .leftApp), (200 + sec(12), .returned)])) == nil)
    }

    @Test func aClosureBeforeForgivenDoesNotCount() {
        let l = log([(0, .started), (100, .closedByOwner), (101, .forgiven), (150, .appLaunched), (wakeMin, .confirmed)])
        #expect(NightEvaluator.collapsedAt(l) == nil && NightEvaluator.evaluate(l) == .complete)
    }

    @Test func forgivenRoundTrips() throws {
        let data = try JSONEncoder().encode(NightEventKind.forgiven)
        #expect(String(data: data, encoding: .utf8) == "\"forgiven\"")
        #expect(try JSONDecoder().decode(NightEventKind.self, from: data) == .forgiven)
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
