import Foundation
import Testing
@testable import SleepCore

/// W7 (build 14b2, owner 2026-11-26): on a night whose silent pre-alarm was set, nothing counts between the pre-alarm's fire
/// time and the wake time – no trip out of the app, no recognised phone use, no closed app, no calm hour spoiled.
/// Bedtime 22:30; the pre-alarm fires at wake − 25 s. A trip gets 3 s + 10 s (the default rules).
@Suite struct PreAlarmExcuseTests {
    /// Started at bedtime, the setup ends at bedtime + 5 min and seven whole calm hours end exactly at the wake time, so the
    /// seconds before the wake time lie inside the LAST whole hour.
    let win = NightWindow(key: night.key, bedtime: night.bedtime, wake: night.bedtime + 300 + 7 * 3600)
    var wake: Date { win.wake }
    var fire: Date { wake - PreAlarmPlan.lead }
    var strict: SleepRules { SleepRules() }
    var gentle: SleepRules { var r = SleepRules(); r.lockScreenCollapses = false; return r }
    func marked(_ r: SleepRules) -> SleepRules { var r = r; r.excusedFrom = fire; return r }

    /// A night started at bedtime, with the given events `secondsBeforeWake` before the wake time.
    func makeLog(_ events: [(Double, NightEventKind)]) -> NightLog {
        var l = NightLog(window: win, buildingId: "x")
        l.append(.started, at: win.bedtime)
        l.append(.locked, at: win.bedtime + 1)
        for (secondsBeforeWake, kind) in events { l.append(kind, at: wake - secondsBeforeWake) }
        return l
    }

    // MARK: the rule

    @Test func countingEndIsTheEarlierOfWakeAndTheFireTime() {
        #expect(strict.countingEnd(wake: wake) == wake)
        #expect(marked(strict).countingEnd(wake: wake) == fire)
        var late = strict; late.excusedFrom = wake + 5
        #expect(late.countingEnd(wake: wake) == wake)
    }

    @Test(arguments: [false, true])
    func aTripAtWakeMinus20sCountsNothingOnAMarkedNight(isGentle: Bool) {
        let base = isGentle ? gentle : strict
        let l = makeLog([(20, .leftApp)])                                      // left and never came back
        // unmarked, as today: 20 s away > 13 s → the building collapsed at wake − 7 s
        #expect(NightEvaluator.collapsedAt(l, rules: base) == wake - 7)
        #expect(NightEvaluator.awaySeconds(l, rules: base) == 20)
        #expect(NightEvaluator.evaluate(l, rules: base) == .ruins)
        // marked: the trip lies after the fire time → nothing, no budget used, the night is not ruined
        #expect(NightEvaluator.collapsedAt(l, rules: marked(base)) == nil)
        #expect(NightEvaluator.awaySeconds(l, rules: marked(base)) == 0)
        #expect(NightEvaluator.awayIntervals(l, rules: marked(base)).isEmpty)
        #expect(NightEvaluator.awayAfterSetup(l, rules: marked(base), until: wake) == 0)
    }

    @Test func aRecognisedPhoneUseAtWakeMinus20sIsNoTripOnAMarkedStrictNight() {
        let l = makeLog([(20, .usedLockScreen)])
        #expect(NightEvaluator.collapsedAt(l, rules: strict) == wake - 7)         // unmarked: 13 s allowance
        #expect(NightEvaluator.collapsedAt(l, rules: marked(strict)) == nil)
        #expect(NightEvaluator.awaySeconds(l, rules: marked(strict)) == 0)
    }

    @Test func aClosedAppAfterTheFireTimeCountsNothing() {
        let l = makeLog([(20, .closedByOwner)])                                   // swiped away, never opened again
        #expect(NightEvaluator.collapsedAt(l, rules: strict) != nil)
        #expect(NightEvaluator.collapsedAt(l, rules: marked(strict)) == nil)
        let reopened = makeLog([(20, .closedByOwner), (2, .appLaunched)])
        #expect(NightEvaluator.collapsedAt(reopened, rules: marked(strict)) == nil)
        #expect(NightEvaluator.awaySeconds(reopened, rules: marked(strict)) == 0)
    }

    @Test func aTripThatStartedBeforeTheFireTimeIsCutAtIt() {
        // out at wake − 35 s, never back: 10 s count (to wake − 25 s) – less than the 13 s allowance → no collapse; the budget
        // is charged only up to the cut
        let l = makeLog([(35, .leftApp)])
        #expect(NightEvaluator.collapsedAt(l, rules: strict) == wake - 22)        // unmarked: 13 s from wake − 35 s
        let r = marked(strict)
        #expect(NightEvaluator.collapsedAt(l, rules: r) == nil)
        #expect(NightEvaluator.awaySeconds(l, rules: r) == 10)
        #expect(NightEvaluator.awayIntervals(l, rules: r).map { $0.1 } == [fire])
        #expect(NightEvaluator.awayAfterSetup(l, rules: r, until: wake) == 10)
        #expect(NightEvaluator.evaluate(makeLog([(35, .leftApp), (0, .confirmed)]), rules: r) == .complete)
    }

    @Test func aTripLongEnoughToCollapseBeforeTheFireTimeStillCollapses() {
        let l = makeLog([(60, .leftApp)])                                         // 13 s later = wake − 47 s, before the fire time
        #expect(NightEvaluator.collapsedAt(l, rules: marked(strict)) == wake - 47)
    }

    @Test func aTripWithTheBudgetAlmostSpentIsCutAtTheFireTime() {
        // 25 s away earlier in the night (two trips of 12 s + 13 s... kept under the per-trip allowance) leave 5 s of budget;
        // a trip begun at wake − 30 s is a full trip, cut at the fire time after 5 s: no collapse
        let l = makeLog([(3600, .leftApp), (3588, .returned), (1800, .leftApp), (1788, .returned), (30, .leftApp)])
        #expect(NightEvaluator.collapsedAt(l, rules: marked(strict)) == nil)
        #expect(NightEvaluator.awayAfterSetup(l, rules: marked(strict), until: wake) == 24 + 5)
    }

    @Test func oldNightsAreUnchanged() {
        // no marker (nil): the evaluator is exactly what it was
        var r = strict
        #expect(r.excusedFrom == nil)
        let l = makeLog([(20, .leftApp)])
        #expect(NightEvaluator.collapsedAt(l, rules: r) == wake - 7)
        r.excusedFrom = nil
        #expect(NightEvaluator.collapsedAt(l, rules: r) == wake - 7)
    }

    // MARK: the calm hours

    @Test func aLockScreenUseAtWakeMinus10sDoesNotSpoilTheLastCalmHour() {
        let l = makeLog([(10, .usedLockScreen), (9, .locked)])
        let plain = CalmHours.count(log: l, rules: strict)
        let excused = CalmHours.count(log: l, rules: marked(strict))
        #expect(plain.calm == plain.total - 1)                                    // unmarked: the last hour is spoiled
        #expect(excused.calm == excused.total && excused.total == plain.total)
        #expect(CalmHours.count(log: l, rules: marked(gentle)).calm == excused.total)
    }

    @Test func aUseBeforeTheFireTimeStillSpoilsItsHour() {
        let l = makeLog([(26, .usedLockScreen), (25.5, .locked)])
        let excused = CalmHours.count(log: l, rules: marked(strict))
        #expect(excused.calm == excused.total - 1)
    }

    @Test func aTripAfterTheFireTimeSpoilsNoCalmHour() {
        let l = makeLog([(20, .leftApp), (5, .returned)])
        #expect(CalmHours.count(log: l, rules: strict).calm == CalmHours.count(log: l, rules: strict).total - 1)
        let excused = CalmHours.count(log: l, rules: marked(strict))
        #expect(excused.calm == excused.total)
    }

    // MARK: sync

    @Test func theSyncedMarkerIsTheEarlierOneOfTheSameRunAndNeverLost() {
        let a = Date(timeIntervalSinceReferenceDate: 800_000_000), b = a + 5
        #expect(SyncMerge.preAlarmAt(kept: nil, other: a, sameRun: true) == a)
        #expect(SyncMerge.preAlarmAt(kept: a, other: nil, sameRun: true) == a)
        #expect(SyncMerge.preAlarmAt(kept: b, other: a, sameRun: true) == a)
        #expect(SyncMerge.preAlarmAt(kept: nil, other: nil, sameRun: true) == nil)
        #expect(SyncMerge.preAlarmAt(kept: nil, other: a, sameRun: false) == nil)
        #expect(SyncMerge.preAlarmAt(kept: b, other: a, sameRun: false) == b)
        let once = SyncMerge.preAlarmAt(kept: nil, other: a, sameRun: true)
        #expect(SyncMerge.preAlarmAt(kept: once, other: a, sameRun: true) == once)
    }
}
