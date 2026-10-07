import Foundation
import Testing
@testable import SleepCore

/// R4 (owner 2026-10-04): closing the app during a night counts as leaving it. iOS tells the running app that it is
/// being terminated (`.closedByOwner`); the next launch (`.appLaunched`) ends that trip. A death WITHOUT the notice
/// and a phone restart (`.restartExcused`) stay in the owner's favour.
@Suite struct ClosureTests {
    let wakeMin = nightMinutes
    let sec = { (s: Double) in s / 60 }                         // seconds → the minutes `log()` takes
    func time(_ min: Double) -> Date { night.bedtime + min * 60 }

    // MARK: outcome

    @Test(arguments: [
        ("closed after the setup, back after 8 s",
         [(0.0, NightEventKind.started), (100, .closedByOwner), (100 + 8.0 / 60, .appLaunched), (wakeMinutes, .confirmed)], Outcome.complete),
        ("closed, back after 13 s (the limit)",
         [(0, .started), (100, .closedByOwner), (100 + 13.0 / 60, .appLaunched), (wakeMinutes, .confirmed)], .complete),
        ("closed, back after 14 s",
         [(0, .started), (100, .closedByOwner), (100 + 14.0 / 60, .appLaunched), (wakeMinutes, .confirmed)], .ruins),
        ("closed, back after 60 s",
         [(0, .started), (100, .closedByOwner), (101, .appLaunched), (wakeMinutes, .confirmed)], .ruins),
        ("closed and never reopened",
         [(0, .started), (100, .closedByOwner)], .ruins),
        ("closed, never reopened, a confirmation logged anyway",
         [(0, .started), (100, .closedByOwner), (wakeMinutes + 1, .confirmed)], .ruins),
        ("closed during the setup, back before its end",
         [(0, .started), (2, .closedByOwner), (3, .appLaunched), (wakeMinutes, .confirmed)], .complete),
        ("closed during the setup, back 8 s after its end",
         [(0, .started), (4, .closedByOwner), (5 + 8.0 / 60, .appLaunched), (wakeMinutes, .confirmed)], .complete),
        ("closed during the setup, back 20 s after its end",
         [(0, .started), (4, .closedByOwner), (5 + 20.0 / 60, .appLaunched), (wakeMinutes, .confirmed)], .ruins),
        ("closed during a pause, back inside it",
         [(0, .started), (180, .pauseStarted), (181, .closedByOwner), (185, .appLaunched), (wakeMinutes, .confirmed)], .complete),
        ("closed during a pause, back 20 s after it",
         [(0, .started), (180, .pauseStarted), (181, .closedByOwner), (190 + 20.0 / 60, .appLaunched), (wakeMinutes, .confirmed)], .ruins),
        ("closed during a pause, back 8 s after it",
         [(0, .started), (180, .pauseStarted), (181, .closedByOwner), (190 + 8.0 / 60, .appLaunched), (wakeMinutes, .confirmed)], .complete),
        ("closed, the phone restarted, opened hours later",
         [(0, .started), (100, .closedByOwner), (300, .restartExcused), (300, .appLaunched), (wakeMinutes, .confirmed)], .complete),
        ("closed and restarted, never opened until the morning",
         [(0, .started), (100, .closedByOwner), (wakeMinutes - 1, .restartExcused), (wakeMinutes - 1, .appLaunched), (wakeMinutes, .confirmed)], .complete),
        ("killed without the notice (a plain relaunch after leaving) – as before",
         [(0, .started), (30, .leftApp), (wakeMinutes - 5, .appLaunched), (wakeMinutes - 4, .returned), (wakeMinutes, .confirmed)], .complete),
        ("left, then closed, back late – counted from leaving",
         [(0, .started), (100, .leftApp), (100 + 2.0 / 60, .closedByOwner), (101, .appLaunched), (wakeMinutes, .confirmed)], .ruins),
        ("left, then closed, back within the limit of the leaving",
         [(0, .started), (100, .leftApp), (100 + 2.0 / 60, .closedByOwner), (100 + 9.0 / 60, .appLaunched), (wakeMinutes, .confirmed)], .complete),
        ("closed after the wake time (the alarm rang) – nothing counts",
         [(0, .started), (wakeMinutes + 0.3, .closedByOwner), (wakeMinutes + 0.8, .appLaunched), (wakeMinutes + 1, .confirmed)], .complete),
        ("closed, but the app turned out to be alive (returned) and a later death is no closure",
         [(0, .started), (100, .closedByOwner), (100 + 5.0 / 60, .returned), (200, .leftApp), (250, .appLaunched), (wakeMinutes, .confirmed)], .complete),
    ] as [(String, [(Double, NightEventKind)], Outcome)])
    func outcome(name: String, events: [(Double, NightEventKind)], expected: Outcome) {
        #expect(NightEvaluator.evaluate(log(events)) == expected, "\(name)")
    }

    // MARK: away time

    @Test func aClosureIsAwayUntilTheAppIsOpenedAgain() {
        let l = log([(0, .started), (100, .closedByOwner), (100 + sec(8), .appLaunched), (100 + sec(8), .returned)])
        #expect(NightEvaluator.awaySeconds(l) == 8)
        #expect(NightEvaluator.awayAfterSetup(l, until: night.wake) == 8)
        #expect(NightEvaluator.collapsedAt(l) == nil)
    }

    @Test func aClosureCollapsesAtTheSameMomentAsATripOfTheSameLength() {
        let closed = log([(0, .started), (100, .closedByOwner), (101, .appLaunched)])
        let left = log([(0, .started), (100, .leftApp), (101, .returned)])
        #expect(NightEvaluator.collapsedAt(closed) == night.bedtime + 100 * 60 + 13)
        #expect(NightEvaluator.collapsedAt(closed) == NightEvaluator.collapsedAt(left))
        #expect(NightEvaluator.awaySeconds(closed) == 60)
    }

    @Test func aClosureThatIsNeverUndoneCountsUntilTheWake() {
        let l = log([(0, .started), (100, .closedByOwner)])
        #expect(NightEvaluator.awaySeconds(l) == (wakeMin - 100) * 60)
        #expect(NightEvaluator.collapsedAt(l) == night.bedtime + 100 * 60 + 13)
        #expect(NightEvaluator.evaluate(l) == .ruins)
        #expect(NightEvaluator.result(for: l, key: l.key).outcome == .ruins)
    }

    @Test func closedDuringTheSetupOnlyCountsAfterItsEnd() {
        let back = log([(0, .started), (4, .closedByOwner), (6, .appLaunched)])      // reopened at 6 min = 1 min after the end
        #expect(NightEvaluator.awaySeconds(back) == 2 * 60)                              // the away time of the whole trip
        #expect(NightEvaluator.awayAfterSetup(back, until: night.wake) == 60)            // …of which the setup is free
        #expect(NightEvaluator.collapsedAt(back) == night.bedtime + 5 * 60 + 13)
        let inTime = log([(0, .started), (2, .closedByOwner), (3, .appLaunched)])
        #expect(NightEvaluator.awayAfterSetup(inTime, until: night.wake) == 0)
        #expect(NightEvaluator.collapsedAt(inTime) == nil)
    }

    @Test func aPauseExcusesAClosureInsideIt() {
        let l = log([(0, .started), (180, .pauseStarted), (181, .closedByOwner), (185, .appLaunched)])
        #expect(NightEvaluator.awayAfterSetup(l, until: night.wake) == 0)
        #expect(NightEvaluator.collapsedAt(l) == nil)
        // the part after the pause is not excused: back 20 s after it ends → collapsed 13 s after the end
        let late = log([(0, .started), (180, .pauseStarted), (181, .closedByOwner), (190 + sec(20), .appLaunched)])
        #expect(NightEvaluator.collapsedAt(late) == time(190) + 13)
    }

    @Test func severalShortClosuresShareTheBudget() {
        // 3 × 12 s = 36 s > the 30 s of the night; each alone is within the 13 s of one trip
        var events: [(Double, NightEventKind)] = [(0, .started)]
        for (i, at) in [100.0, 200, 300].enumerated() {
            events.append((at, .closedByOwner))
            events.append((at + sec(12), .appLaunched))
            #expect(NightEvaluator.collapsedAt(log(events)) == (i < 2 ? nil : time(300) + 6), "closure \(i + 1)")
        }
        let l = log(events + [(wakeMin, .confirmed)])
        #expect(NightEvaluator.evaluate(l) == .ruins)
        #expect(NightEvaluator.awayAfterSetup(l, until: night.wake) == 36)
        #expect(NightEvaluator.allowance(log(Array(events.prefix(5))), at: time(400)) == 6)    // what a third closure may take
        var legacy = SleepRules(); legacy.awayBudget = nil
        #expect(NightEvaluator.evaluate(l, rules: legacy) == .complete)                         // old nights: no budget
    }

    @Test func aRestartExcusesTheClosureBeforeIt() {
        let l = log([(0, .started), (100, .closedByOwner), (200, .restartExcused), (200, .appLaunched), (200.01, .returned),
                     (wakeMin, .confirmed)])
        #expect(NightEvaluator.awaySeconds(l) == 0)
        #expect(NightEvaluator.collapsedAt(l) == nil)
        #expect(NightEvaluator.evaluate(l) == .complete)
    }

    @Test func aPlainRelaunchAfterLeavingIsStillTheOwnersFavour() {
        // no termination notice: iOS killed the app (memory) or it crashed
        let l = log([(0, .started), (30, .leftApp), (wakeMin - 5, .appLaunched), (wakeMin - 4, .returned)])
        #expect(NightEvaluator.awaySeconds(l) == 0)
        // …and it does not matter that a closure from the EARLIER part of the night was answered
        let both = log([(0, .started), (100, .closedByOwner), (100 + sec(5), .appLaunched), (200, .leftApp), (300, .appLaunched)])
        #expect(NightEvaluator.awaySeconds(both) == 5)
        #expect(NightEvaluator.collapsedAt(both) == nil)
    }

    @Test func leftThenClosedThenALateLaunchCountsFromLeaving() {
        let l = log([(0, .started), (100, .leftApp), (100 + sec(2), .closedByOwner), (100 + sec(40), .appLaunched)])
        #expect(NightEvaluator.awaySeconds(l) == 40)
        #expect(NightEvaluator.collapsedAt(l) == time(100) + 13)
    }

    @Test func aRestartAfterLeavingAndClosingIsExcusedAsAWhole() {
        let l = log([(0, .started), (100, .leftApp), (100 + sec(2), .closedByOwner), (150, .restartExcused), (150, .appLaunched)])
        #expect(NightEvaluator.awaySeconds(l) == 0)
        #expect(NightEvaluator.collapsedAt(l) == nil)
    }

    @Test func aClosureBeforeTheStartOrAfterTheWakeIsClipped() {
        let before = log([(-20, .closedByOwner), (-10, .appLaunched), (0, .started), (wakeMin, .confirmed)])
        #expect(NightEvaluator.awaySeconds(before) == 0)
        let after = log([(0, .started), (wakeMin + 3, .closedByOwner), (wakeMin + 9, .appLaunched), (wakeMin + 10, .confirmed)])
        #expect(NightEvaluator.awaySeconds(after) == 0)
    }

    @Test func aClosureDuringACallStillCounts() {
        // the call excuses the app being pushed to the background, not the owner swiping it away; the open call is
        // forgotten at the relaunch as it always was
        let l = log([(0, .started), (100, .callStarted), (100 + sec(1), .closedByOwner), (101, .appLaunched)])
        #expect(NightEvaluator.collapsedAt(l) == time(100) + 1 + 13)
    }

    // MARK: the log

    @Test func theOpenClosureIsTheOneNoLaunchHasAnsweredYet() {
        #expect(log([(0, .started), (100, .closedByOwner)]).openClosure == time(100))
        // diagnostics around the closure do not hide it
        #expect(log([(0, .started), (100, .closedByOwner), (100 + sec(1), .audioInterrupted)]).openClosure == time(100))
        #expect(log([(0, .started), (100, .closedByOwner), (101, .appLaunched)]).openClosure == nil)
        #expect(log([(0, .started), (100, .closedByOwner), (101, .restartExcused), (101, .appLaunched)]).openClosure == nil)
        #expect(log([(0, .started), (100, .closedByOwner), (101, .appLaunched), (200, .closedByOwner)]).openClosure == time(200))
        #expect(log([(0, .started), (100, .leftApp)]).openClosure == nil)
    }

    @Test func theNewEventsDecodeAndOldLogsStillDo() throws {
        let l = log([(0, .started), (100, .closedByOwner), (101, .restartExcused), (101, .appLaunched)])
        let back = try JSONDecoder().decode([NightEvent].self, from: JSONEncoder().encode(l.events))
        #expect(back == l.events)
        #expect(NightEventKind.closedByOwner.rawValue == "closedByOwner" && NightEventKind.restartExcused.rawValue == "restartExcused")
        let old = #"[{"kind":"started","at":0},{"kind":"leftApp","at":10},{"kind":"appLaunched","at":20}]"#
        #expect(try JSONDecoder().decode([NightEvent].self, from: Data(old.utf8)).map(\.kind) == [.started, .leftApp, .appLaunched])
    }

    // MARK: the story of the night

    @Test func theStoryNamesAClosureAndItsReopening() {
        let l = log([(0, .started), (100, .closedByOwner), (100 + sec(8), .appLaunched), (100 + sec(8), .returned),
                     (200, .leftApp), (200 + sec(5), .returned), (wakeMin, .confirmed)])
        let r = NightReport(log: l)
        #expect(r.nightTrips.map(\.closedApp) == [true, false])
        #expect(r.nightTrips[0].duration == 8 && r.nightTrips[0].start == time(100))
        #expect(r.relaunches.isEmpty)                                    // opening a closed app is no "restart"
        #expect(r.collapsedAt == nil)
    }

    @Test func theStoryFlagsAClosureThatWasNeverUndoneAndOneInTheSetupOrAPause() {
        let never = NightReport(log: log([(0, .started), (100, .closedByOwner)]))
        #expect(never.nightTrips.count == 1 && never.nightTrips[0].closedApp && never.nightTrips[0].end == nil)
        #expect(never.collapsedAt == time(100) + 13)

        let setup = NightReport(log: log([(0, .started), (2, .closedByOwner), (3, .appLaunched)]))
        #expect(setup.setupTrips.count == 1 && setup.setupTrips[0].closedApp && setup.nightTrips.isEmpty)

        let paused = NightReport(log: log([(0, .started), (180, .pauseStarted), (181, .closedByOwner), (185, .appLaunched)]))
        #expect(paused.nightTrips.map(\.duringPause) == [true] && paused.nightTrips[0].closedApp)
    }

    @Test func aClosureOpenedOnlyAfterTheNightIsNeverComeBack() {
        let r = NightReport(log: log([(0, .started), (100, .closedByOwner), (wakeMin + 5, .appLaunched)]))
        #expect(r.nightTrips.count == 1 && r.nightTrips[0].closedApp && r.nightTrips[0].end == nil)
        #expect(r.relaunches.isEmpty && r.collapsedAt == time(100) + 13)
    }

    @Test func theStoryOfAPhoneRestartHasNoTripButShowsTheRestart() {
        let r = NightReport(log: log([(0, .started), (100, .closedByOwner), (300, .restartExcused), (300, .appLaunched)]))
        #expect(r.setupTrips.isEmpty && r.nightTrips.isEmpty)
        #expect(r.relaunches == [time(300)])                             // "The app restarted" is exactly right here
        #expect(r.collapsedAt == nil)
    }

    @Test func aLeavingThatTurnedIntoAClosureIsOneFlaggedTrip() {
        let r = NightReport(log: log([(0, .started), (100, .leftApp), (100 + sec(2), .closedByOwner), (101, .appLaunched)]))
        #expect(r.nightTrips.count == 1 && r.nightTrips[0].closedApp && r.nightTrips[0].duration == 60)
        #expect(r.relaunches.isEmpty)
        // a plain death after leaving is still an unknown end and still a "restart"
        let killed = NightReport(log: log([(0, .started), (100, .leftApp), (101, .appLaunched)]))
        #expect(killed.nightTrips.map(\.closedApp) == [false] && killed.nightTrips[0].end == nil && killed.relaunches.count == 1)
    }
}
