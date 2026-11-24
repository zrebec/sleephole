import Foundation
import Testing
@testable import SleepCore

/// 13ae (B55): the rule-side "a call is open" and "a trip is open", and the promise that a warning's seconds and the
/// projected collapse moment equal what `NightEvaluator` decides.
struct TripStateTests {
    let rules: SleepRules = .forNewNights

    func started() -> NightLog {
        var l = NightLog(window: night, buildingId: "l1-house-a-0")
        l.append(.started, at: night.bedtime - 300)
        return l
    }
    var grace: Date { night.bedtime + 300 }

    @Test func aCallIsOpenFromItsStartUntilItsEnd() {
        var l = started()
        #expect(!TripState.callIsOpen(l, at: grace))
        l.append(.callStarted, at: grace + 60)
        #expect(TripState.callIsOpen(l, at: grace + 70))
        l.append(.callEnded, at: grace + 200)
        #expect(!TripState.callIsOpen(l, at: grace + 210))
    }

    @Test func aRelaunchResetsAndALongCallStaysOpen() {
        var l = started()
        l.append(.callStarted, at: grace + 60)
        #expect(TripState.callIsOpen(l, at: grace + 60 + 5 * 3600))        // the evaluator subtracts it up to the wake time
        l.append(.appLaunched, at: grace + 100)
        #expect(!TripState.callIsOpen(l, at: grace + 110))
    }

    @Test func theOpenTripIsNamedByItsFirstEvent() {
        var l = started()
        #expect(TripState.openTrip(l, rules: rules) == nil)
        l.append(.usedLockScreen, at: grace + 10)
        l.append(.leftApp, at: grace + 12)
        #expect(TripState.openTrip(l, rules: rules) == .usedLockScreen)      // strict: the lock-screen trip owns it
        l.append(.returned, at: grace + 20)
        #expect(TripState.openTrip(l, rules: rules) == nil)
        var gentle = rules; gentle.lockScreenCollapses = false
        var g = started()
        g.append(.usedLockScreen, at: grace + 10)
        #expect(TripState.openTrip(g, rules: gentle) == .usedLockScreen)
        g.append(.leftApp, at: grace + 12)
        #expect(TripState.openTrip(g, rules: gentle) == .leftApp)            // gentle: a real leave takes over
    }

    /// A trip that begins during a call is counted from the call's end only: the warning's seconds and the projected
    /// collapse (`date + allowance`) are exactly what the evaluator decides.
    @Test func aTripDuringACallCollapsesAtTheCallsEndPlusItsAllowance() {
        for lock in [false, true] {
            var l = started()
            l.append(.callStarted, at: grace + 60)
            l.append(lock ? .usedLockScreen : .leftApp, at: grace + 65)
            l.append(.callEnded, at: grace + 200)
            #expect(TripState.openTrip(l, rules: rules) == (lock ? .usedLockScreen : .leftApp))
            let allowance = NightEvaluator.allowance(l, rules: rules, at: grace + 200, lockScreen: lock)
            #expect(allowance == 18)                                         // 3 s + 15 s: the full tolerance
            #expect(NightEvaluator.collapsedAt(l, rules: rules) == grace + 200 + allowance)
        }
    }

    @Test func aTripThatBeganBeforeTheCallKeepsOnlyItsCountedSeconds() {
        var l = started()
        l.append(.leftApp, at: grace + 60)
        l.append(.callStarted, at: grace + 62)             // 2 s counted before the call
        l.append(.callEnded, at: grace + 100)
        let allowance = NightEvaluator.allowance(l, rules: rules, at: grace + 100)
        #expect(allowance == 18)                           // a full trip while budget is left
        #expect(NightEvaluator.collapsedAt(l, rules: rules) == grace + 100 + allowance)
    }

    @Test func aTripStampedInsideACallCountsFromTheCallsEnd() {
        var l = started()
        l.append(.callStarted, at: grace + 60)
        l.append(.callEnded, at: grace + 100)
        l.append(.leftApp, at: grace + 99)                 // stamped a second before the call ended, stored after it
        #expect(TripState.countedFrom(l, at: grace + 99) == grace + 100)
        #expect(TripState.countedFrom(l, at: grace + 100) == grace + 100)
        #expect(TripState.countedFrom(l, at: grace + 30) == grace + 30)
        #expect(NightEvaluator.collapsedAt(l, rules: rules) == grace + 100 + 18)    // what the evaluator does with it
    }
}
