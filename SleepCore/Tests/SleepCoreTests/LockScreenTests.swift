import Foundation
import Testing
@testable import SleepCore

/// Using the phone on the lock screen (`.usedLockScreen`) counts exactly like `.leftApp`; the screen / recognition
/// kinds are diagnostics only.
@Suite struct LockScreenKindTests {
    let sec = { (s: Double) in s / 60 }
    func time(_ min: Double) -> Date { night.bedtime + min * 60 }

    @Test(arguments: [
        ("back after 8 s", [(100.0 + 8.0 / 60, NightEventKind.returned)]),
        ("back after 14 s", [(100 + 14.0 / 60, .returned)]),
        ("screen off after 20 s", [(100 + 20.0 / 60, .locked)]),
        ("never back", []),
    ] as [(String, [(Double, NightEventKind)])])
    func sameAsLeftApp(name: String, end: [(Double, NightEventKind)]) {
        func run(_ kind: NightEventKind) -> ([(Date, Date)], Date?, Outcome, TimeInterval) {
            let l = log([(0, .started), (100, kind)] + end + [(wakeMinutes, .confirmed)])
            return (NightEvaluator.awayIntervals(l), NightEvaluator.collapsedAt(l), NightEvaluator.evaluate(l),
                    NightEvaluator.awayIntervals(l).reduce(0) { $0 + $1.1.timeIntervalSince($1.0) })
        }
        let a = run(.usedLockScreen), b = run(.leftApp)
        #expect(a.0.count == b.0.count && zip(a.0, b.0).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }, "\(name)")
        #expect(a.1 == b.1 && a.2 == b.2 && a.3 == b.3, "\(name)")
    }

    @Test func forgivenForgivesIt() {
        let l = log([(0, .started), (100, .usedLockScreen), (101, .forgiven), (wakeMinutes, .confirmed)])
        #expect(NightEvaluator.awayIntervals(l).isEmpty)
        #expect(NightEvaluator.evaluate(l) == .complete)
    }

    @Test func diagnosticKindsChangeNothing() {
        let plain: [(Double, NightEventKind)] = [(0, .started), (100, .leftApp), (100 + sec(5), .returned), (wakeMinutes, .confirmed)]
        let noisy: [(Double, NightEventKind)] = [(0, .started), (50, .screenOn), (50 + sec(3), .screenOff), (51, .ownerRecognised),
                                                 (51, .dataLocked), (100, .leftApp), (100 + sec(5), .returned),
                                                 (150, .screenOn), (150 + sec(6), .ownerRecognised), (151, .screenOff),
                                                 (wakeMinutes, .confirmed)]
        let a = log(plain), b = log(noisy)
        #expect(NightEvaluator.awayIntervals(a).map(\.0) == NightEvaluator.awayIntervals(b).map(\.0))
        #expect(NightEvaluator.awayIntervals(a).map(\.1) == NightEvaluator.awayIntervals(b).map(\.1))
        #expect(NightEvaluator.collapsedAt(a) == NightEvaluator.collapsedAt(b))
        #expect(NightEvaluator.evaluate(a) == NightEvaluator.evaluate(b))
        let onlyDiag = log([(0, .started), (100, .screenOn), (100.1, .ownerRecognised), (200, .screenOff), (201, .dataLocked), (wakeMinutes, .confirmed)])
        #expect(NightEvaluator.awayIntervals(onlyDiag).isEmpty && NightEvaluator.evaluate(onlyDiag) == .complete)
    }

    @Test func theNewAudioKindsChangeNothingAndOldLogsStillDecode() throws {
        let plain: [(Double, NightEventKind)] = [(0, .started), (100, .leftApp), (100 + sec(5), .returned), (wakeMinutes, .confirmed)]
        let noisy: [(Double, NightEventKind)] = [(0, .started), (50, .audioRouteChanged), (60, .audioServicesReset),
                                                 (100, .leftApp), (100 + sec(5), .returned), (wakeMinutes, .confirmed)]
        let a = log(plain), b = log(noisy)
        #expect(NightEvaluator.awayIntervals(a).map(\.0) == NightEvaluator.awayIntervals(b).map(\.0))
        #expect(NightEvaluator.collapsedAt(a) == NightEvaluator.collapsedAt(b))
        #expect(NightEvaluator.evaluate(a) == NightEvaluator.evaluate(b))
        let old = Data(#"[{"kind":"audioResumed","at":0},{"kind":"started","at":1}]"#.utf8)
        #expect(try JSONDecoder().decode([NightEvent].self, from: old).map(\.kind) == [.audioResumed, .started])
        #expect(NightEventKind.audioRouteChanged.rawValue == "audioRouteChanged" && NightEventKind.audioServicesReset.rawValue == "audioServicesReset")
    }

    @Test func rawValuesRoundTrip() throws {
        let kinds: [NightEventKind] = [.usedLockScreen, .screenOn, .screenOff, .ownerRecognised, .dataLocked]
        #expect(kinds.map(\.rawValue) == ["usedLockScreen", "screenOn", "screenOff", "ownerRecognised", "dataLocked"])
        let events = kinds.enumerated().map { NightEvent($1, at: Date(timeIntervalSince1970: Double($0))) }
        let back = try JSONDecoder().decode([NightEvent].self, from: JSONEncoder().encode(events))
        #expect(back == events)
    }

    @Test func theReportMarksLockScreenTripsAndListsTheWakes() {
        let l = log([(0, .started), (50, .screenOn), (50 + sec(3), .screenOff),
                     (100, .usedLockScreen), (100 + sec(9), .locked),
                     (200, .leftApp), (200 + sec(4), .returned),
                     (250, .screenOn), (250 + sec(9), .usedLockScreen), (251, .returned),
                     (wakeMinutes, .confirmed)])
        let r = NightReport(log: l)
        #expect(r.nightTrips.map(\.onLockScreen) == [true, false, true])
        #expect(r.nightTrips[0].duration == 9)
        #expect(r.lockScreenWakes == [time(50), time(250)])
        // a leftApp, then usedLockScreen inside the same trip: the trip began elsewhere
        let mixed = NightReport(log: log([(0, .started), (100, .leftApp), (100 + sec(2), .usedLockScreen), (101, .returned), (wakeMinutes, .confirmed)]))
        #expect(mixed.nightTrips.map(\.onLockScreen) == [false])
    }
}

/// "Care instead of enforcement" (owner 2026-10-09): with `lockScreenCollapses == false` (gentle mode) the
/// lock-screen use is logged but is no away time; a `.leftApp` inside it is a normal counted trip from then on.
@Suite struct GentleLockScreenTests {
    let sec = { (s: Double) in s / 60 }
    let gentle: SleepRules = { var r = SleepRules(); r.lockScreenCollapses = false; return r }()
    func time(_ min: Double) -> Date { night.bedtime + min * 60 }

    @Test func sixtySecondsOnTheLockScreenCostsNothing() {
        let l = log([(0, .started), (100, .usedLockScreen), (101, .locked), (wakeMinutes, .confirmed)])
        #expect(NightEvaluator.awaySeconds(l, rules: gentle) == 0)
        #expect(NightEvaluator.collapsedAt(l, rules: gentle) == nil)
        #expect(NightEvaluator.evaluate(l, rules: gentle) == .complete)
        #expect(NightEvaluator.awayAfterSetup(l, rules: gentle, until: time(200)) == 0)
        #expect(NightEvaluator.budgetState(l, rules: gentle, at: time(200)) == .fine)
        #expect(NightEvaluator.result(for: l, key: l.key, rules: gentle).awaySeconds == 0)
    }

    @Test func neverComingBackIsStillFree() {
        let l = log([(0, .started), (100, .usedLockScreen), (wakeMinutes, .confirmed)])
        #expect(NightEvaluator.collapsedAt(l, rules: gentle) == nil)
        #expect(NightEvaluator.evaluate(l, rules: gentle) == .complete)
    }

    @Test func strictIsUnchanged() {
        let l = log([(0, .started), (100, .usedLockScreen), (101, .locked), (wakeMinutes, .confirmed)])
        #expect(SleepRules().lockScreenCollapses)
        #expect(NightEvaluator.evaluate(l) == .ruins)
        #expect(NightEvaluator.awaySeconds(l) == 60)
    }

    @Test func leftAppInsideTheTripCollapsesFromThatMoment() {
        // lit at 100, another app at 100 min + 12 s, back 20 s later → 20 s > 13 s
        let l = log([(0, .started), (100, .usedLockScreen), (100 + sec(12), .leftApp), (100 + sec(32), .returned),
                     (wakeMinutes, .confirmed)])
        #expect(NightEvaluator.collapsedAt(l, rules: gentle) == time(100) + 12 + 13)
        #expect(NightEvaluator.evaluate(l, rules: gentle) == .ruins)
    }

    @Test func leftAppInsideTheTripBackInTimeStands() {
        let l = log([(0, .started), (100, .usedLockScreen), (100 + sec(12), .leftApp), (100 + sec(20), .returned),
                     (wakeMinutes, .confirmed)])
        #expect(NightEvaluator.awaySeconds(l, rules: gentle) == 8)         // only the part after .leftApp
        #expect(NightEvaluator.evaluate(l, rules: gentle) == .complete)
        // strict: the whole trip from the lock screen counts, the later .leftApp changes nothing
        #expect(NightEvaluator.awaySeconds(l) == 20)
    }

    @Test func closingTheAppInsideTheTripCountsFromTheClosure() {
        let l = log([(0, .started), (100, .usedLockScreen), (100 + sec(12), .closedByOwner), (101, .appLaunched),
                     (wakeMinutes, .confirmed)])
        #expect(NightEvaluator.awaySeconds(l, rules: gentle) == 48)
        #expect(NightEvaluator.evaluate(l, rules: gentle) == .ruins)
    }

    @Test func aPauseAndACallStillExcuse() {
        let l = log([(0, .started), (100, .pauseStarted), (101, .usedLockScreen), (102, .leftApp), (105, .returned),
                     (150, .callStarted), (150 + sec(5), .usedLockScreen), (150 + sec(5), .leftApp), (152, .callEnded),
                     (152, .returned), (wakeMinutes, .confirmed)])
        #expect(NightEvaluator.evaluate(l, rules: gentle) == .complete)
    }

    @Test func theReportKeepsTheTripButMarksItNotCounted() {
        let l = log([(0, .started), (100, .usedLockScreen), (101, .locked), (wakeMinutes, .confirmed)])
        let r = NightReport(log: l, rules: gentle)
        #expect(r.nightTrips.count == 1)
        #expect(r.nightTrips[0].onLockScreen && r.nightTrips[0].notCounted)
        #expect(r.collapsedAt == nil)
        // strict: the same trip counts
        #expect(!NightReport(log: l).nightTrips[0].notCounted)
    }

    @Test func theReportSplitsAtTheLeftApp() {
        let l = log([(0, .started), (100, .usedLockScreen), (100 + sec(12), .leftApp), (100 + sec(20), .returned),
                     (wakeMinutes, .confirmed)])
        let t = NightReport(log: l, rules: gentle).nightTrips
        #expect(t.count == 2)
        #expect(t[0].notCounted && t[0].onLockScreen && t[0].duration == 12)
        #expect(!t[1].notCounted && !t[1].onLockScreen && t[1].duration == 8)
    }
}
