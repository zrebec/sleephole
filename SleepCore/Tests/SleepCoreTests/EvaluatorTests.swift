import Foundation
import Testing
@testable import SleepCore

@Suite struct EvaluatorTests {
    let wakeMin = nightMinutes                                  // minutes from bedtime to wake

    // MARK: away time

    @Test func lockingIsNeverAway() {
        let l = log([(0, .started), (1, .locked), (200, .unlocked), (200.01, .returned), (201, .locked),
                     (wakeMin, .alarmFired), (wakeMin + 2, .confirmed)])
        #expect(NightEvaluator.awaySeconds(l) == 0)
    }

    @Test func leftAndReturned() {
        let l = log([(0, .started), (10, .leftApp), (13, .returned), (wakeMin + 1, .confirmed)])
        #expect(NightEvaluator.awaySeconds(l) == 3 * 60)
    }

    @Test func leftThenLockedStopsTheClock() {
        let l = log([(0, .started), (10, .leftApp), (11, .locked), (300, .unlocked), (300.01, .returned)])
        #expect(NightEvaluator.awaySeconds(l) == 60)
    }

    @Test func leftAndNeverCameBackCountsUntilWake() {
        let l = log([(0, .started), (60, .leftApp)])
        #expect(NightEvaluator.awaySeconds(l) == (wakeMin - 60) * 60)
    }

    @Test func delayedLeftAppFromUnlockIsSortedIn() {
        // unlocked at 100, no return within 3 s → monitor appends .leftApp stamped with the unlock time
        var l = log([(0, .started), (1, .locked), (100, .unlocked), (105, .returned)])
        l.append(.leftApp, at: night.bedtime + 100 * 60)
        #expect(NightEvaluator.awaySeconds(l) == 5 * 60)
    }

    @Test func killedAppIsResolvedInOwnersFavour() {
        let l = log([(0, .started), (30, .leftApp), (wakeMin - 5, .appLaunched), (wakeMin - 4, .returned)])
        #expect(NightEvaluator.awaySeconds(l) == 0)
    }

    @Test func awayIsClippedToTheNight() {
        let l = log([(-20, .leftApp), (-10, .returned), (0, .started), (wakeMin + 3, .leftApp),
                     (wakeMin + 9, .returned), (wakeMin + 10, .confirmed)])
        #expect(NightEvaluator.awaySeconds(l) == 0)
    }

    @Test func callsAreExcused() {
        let l = log([(0, .started), (60, .callStarted), (60.01, .leftApp), (80, .callEnded), (80.05, .returned)])
        #expect(NightEvaluator.awaySeconds(l) < 5)
    }

    // MARK: outcome (owner rules 2026-09-29: start ≤ bedtime+5, 5 min setup grace, then any
    //        background > 10 s collapses; confirm wake−30…+15 complete, …+60 unfinished)

    @Test(arguments: [
        ("perfect night", [(0.0, NightEventKind.started), (1, .locked), (wakeMinutes + 1, .confirmed)], Outcome.complete),
        ("start 10 min early", [(-10, .started), (wakeMinutes, .confirmed)], .complete),
        ("start +5", [(5, .started), (wakeMinutes, .confirmed)], .complete),
        ("start +6 → missed", [(6, .started), (wakeMinutes, .confirmed)], .missed),
        ("podcast setup 4 min", [(0, .started), (0.5, .leftApp), (4.5, .returned), (5, .locked), (wakeMinutes, .confirmed)], .complete),
        ("setup overruns grace by 12 s", [(0, .started), (0.5, .leftApp), (5 + 12 / 60, .returned), (wakeMinutes, .confirmed)], .complete),
        ("setup overruns grace by 20 s", [(0, .started), (0.5, .leftApp), (5 + 20 / 60, .returned), (wakeMinutes, .confirmed)], .ruins),
        ("accidental swipe 5 s at 2:00", [(0, .started), (210, .leftApp), (210 + 5 / 60, .returned), (wakeMinutes, .confirmed)], .complete),
        ("checked phone 30 s at 2:00", [(0, .started), (210, .leftApp), (210.5, .returned), (wakeMinutes, .confirmed)], .ruins),
        ("unlock → camera (no return)", [(0, .started), (1, .locked), (200, .leftApp), (201, .locked), (wakeMinutes, .confirmed)], .ruins),
        ("unlock → straight back", [(0, .started), (1, .locked), (200, .unlocked), (200.01, .returned), (201, .locked), (wakeMinutes, .confirmed)], .complete),
        ("phone call 20 min", [(0, .started), (100, .callStarted), (100.01, .leftApp), (120, .callEnded), (120.05, .returned), (wakeMinutes, .confirmed)], .complete),
        ("stayed out after call", [(0, .started), (100, .callStarted), (100.01, .leftApp), (120, .callEnded), (122, .returned), (wakeMinutes, .confirmed)], .ruins),
        ("killed while locked", [(0, .started), (1, .locked), (wakeMinutes - 1, .appLaunched), (wakeMinutes + 1, .confirmed)], .complete),
        ("confirm −30 (earliest)", [(0, .started), (wakeMinutes - 30, .confirmed)], .complete),
        ("confirm +2 (alarm still ringing)", [(0, .started), (wakeMinutes + 2, .confirmed)], .complete),
        ("confirm +2:16 (alarm stopped)", [(0, .started), (wakeMinutes + 2 + 16 / 60, .confirmed)], .unfinished),
        ("confirm +60", [(0, .started), (wakeMinutes + 60, .confirmed)], .unfinished),
        ("confirm +61", [(0, .started), (wakeMinutes + 61, .confirmed)], .ruins),
        ("never confirmed", [(0, .started)], .ruins),
        ("abandoned", [(0, .started), (60, .abandoned), (wakeMinutes, .confirmed)], .ruins),
        ("morning: left app before confirming", [(0, .started), (wakeMinutes + 0.2, .leftApp), (wakeMinutes + 1, .returned), (wakeMinutes + 1.5, .confirmed)], .complete),
    ] as [(String, [(Double, NightEventKind)], Outcome)])
    func outcome(name: String, events: [(Double, NightEventKind)], expected: Outcome) {
        #expect(NightEvaluator.evaluate(log(events)) == expected, "\(name)")
    }

    @Test func collapseMomentIsReported() {
        let l = log([(0, .started), (1, .locked), (120, .leftApp), (125, .returned)])
        #expect(NightEvaluator.collapsedAt(l) == night.bedtime + 120 * 60 + 13)      // 10 s after the ~3 s notice
        let grace = log([(0, .started), (1, .leftApp), (9, .returned)])
        #expect(NightEvaluator.collapsedAt(grace) == night.bedtime + 5 * 60 + 13)
    }

    /// Owner bug 2026-09-30: starting early must not shorten the setup time.
    @Test func earlyStartGetsSetupUntilBedtimePlusGrace() {
        let early = night.bedtime - 9 * 60                                  // 20:51 for a 21:00 bedtime → 14 min
        #expect(night.setupEnds(start: early) == night.bedtime + 5 * 60)
        #expect(night.setupEnds(start: night.bedtime + 3 * 60) == night.bedtime + 8 * 60)   // late start: full 5 min
        // away 12 min right after an early start → still in the setup, stands
        let l = log([(-9, .started), (-8.5, .leftApp), (4, .returned), (4.5, .locked), (wakeMinutes, .confirmed)])
        #expect(NightEvaluator.collapsedAt(l) == nil)
        // away beyond bedtime + 5 min (+ 13 s) → collapses
        let late = log([(-9, .started), (-8.5, .leftApp), (5.5, .returned), (wakeMinutes, .confirmed)])
        #expect(NightEvaluator.collapsedAt(late) == night.bedtime + 5 * 60 + 13)
    }

    @Test func startAndConfirmWindows() {
        // owner rule: start only from bedtime − 10 min to bedtime + 5 min
        #expect(!night.canStart(at: night.bedtime - 10 * 60 - 1))
        #expect(night.canStart(at: night.bedtime - 10 * 60))
        #expect(night.canStart(at: night.bedtime + 5 * 60))
        #expect(!night.canStart(at: night.bedtime + 5 * 60 + 1))
        #expect(!night.canConfirm(at: night.wake - 31 * 60))
        #expect(night.canConfirm(at: night.wake - 30 * 60))
        #expect(!night.canConfirm(at: night.confirmLateUntil + 1))
    }

    @Test func neverStartedIsMissed() {
        #expect(NightEvaluator.evaluate(nil) == .missed)
        #expect(NightEvaluator.evaluate(log([(10, .leftApp)])) == .missed)
    }

    @Test func customRules() {
        var rules = SleepRules()
        rules.accidentalTolerance = 10 * 60
        rules.awayBudget = nil                               // the tolerance alone decides
        let l = log([(0, .started), (100, .leftApp), (105, .returned), (wakeMin + 1, .confirmed)])
        #expect(NightEvaluator.evaluate(l, rules: rules) == .complete)
        #expect(NightEvaluator.evaluate(l) == .ruins)
    }

    @Test func resultCarriesTheDetails() {
        let l = log([(5, .started), (6, .leftApp), (7, .returned), (wakeMin + 1, .confirmed)])
        let r = NightEvaluator.result(for: l, key: l.key)
        #expect(r.outcome == .complete && r.awaySeconds == 60 && r.buildingId == "l1-house-a-0")
        #expect(r.startedAt == night.bedtime + 300)
    }
}

let wakeMinutes = nightMinutes
