import Foundation
import Testing
@testable import SleepCore

/// The rest screen's rule (13k): when the night screen may turn black.
@Suite struct RestScreenTests {
    let setupEnds = Date(timeIntervalSinceReferenceDate: 1_000)
    var facts: RestScreen.Facts {
        RestScreen.Facts(isBuilding: true, setupEnds: setupEnds, pauseRunning: false, sceneActive: true,
                         voiceOverRunning: false, presentationOpen: false)
    }
    func rests(_ f: RestScreen.Facts, at s: Double, lastActivity: Double = 0) -> Bool {
        RestScreen.shouldRest(f, now: Date(timeIntervalSinceReferenceDate: s),
                              lastActivity: Date(timeIntervalSinceReferenceDate: lastActivity))
    }

    @Test func notDuringTheSetup() {
        #expect(!rests(facts, at: 990, lastActivity: 0))
        #expect(!rests(facts, at: 999.9, lastActivity: 0))
    }

    @Test func thirtySecondsAfterTheSetupOrTheLastTouch() {
        #expect(!rests(facts, at: 1_029, lastActivity: 500))       // 29 s after the setup ended
        #expect(rests(facts, at: 1_030, lastActivity: 500))        // 30 s
        #expect(!rests(facts, at: 2_029, lastActivity: 2_000))     // 29 s after a touch
        #expect(rests(facts, at: 2_030, lastActivity: 2_000))
    }

    /// B51 (owner 2026-11-11): the nap's screen did not go dark – a nap rests exactly like a night (the facts carry no
    /// difference any more: the same setup, the same 30 s, the same blockers).
    @Test func aNapRestsLikeANight() {
        #expect(!rests(facts, at: 1_029, lastActivity: 500))
        #expect(rests(facts, at: 1_030, lastActivity: 500))
        #expect(RestScreen.mayRest(facts, now: Date(timeIntervalSinceReferenceDate: 5_000)))
    }

    @Test func theBlockerNamesTheFirstReason() {
        func b(_ f: RestScreen.Facts, _ s: Double = 5_000) -> RestScreen.Blocker? {
            RestScreen.blocker(f, now: Date(timeIntervalSinceReferenceDate: s))
        }
        #expect(b(facts) == nil)
        #expect(b(facts, 999) == .phase)                       // the setup is not over
        var f = facts; f.isBuilding = false; #expect(b(f) == .phase)
        f = facts; f.setupEnds = nil; #expect(b(f) == .phase)
        f = facts; f.sceneActive = false; #expect(b(f) == .inactive)
        f = facts; f.pauseRunning = true; #expect(b(f) == .pause)
        f = facts; f.voiceOverRunning = true; #expect(b(f) == .voiceOver)
        f = facts; f.presentationOpen = true; #expect(b(f) == .presentation)
        f.pauseRunning = true; #expect(b(f) == .pause)         // the order: pause first
    }

    @Test func aRunningPauseDoesNotRest() {
        var f = facts; f.pauseRunning = true
        #expect(!rests(f, at: 5_000))
    }

    @Test func voiceOverDoesNotRest() {
        var f = facts; f.voiceOverRunning = true
        #expect(!rests(f, at: 5_000))
    }

    @Test func anOpenSheetOrFocusedFieldDoesNotRest() {
        var f = facts; f.presentationOpen = true
        #expect(!rests(f, at: 5_000))
    }

    @Test func onlyWhileBuilding() {
        var f = facts; f.isBuilding = false              // the alarm, the result, idle
        #expect(!rests(f, at: 5_000))
        #expect(!RestScreen.mayRest(f, now: Date(timeIntervalSinceReferenceDate: 5_000)))
    }

    @Test func notWhenTheSceneIsNotActive() {
        var f = facts; f.sceneActive = false
        #expect(!rests(f, at: 5_000))
    }

    @Test func noNightNoRest() {
        var f = facts; f.setupEnds = nil
        #expect(!rests(f, at: 5_000))
    }

    @Test func aShorterDelay() {
        let now = Date(timeIntervalSinceReferenceDate: 1_004)
        #expect(RestScreen.shouldRest(facts, now: now, lastActivity: .distantPast, delay: 4))
        #expect(!RestScreen.shouldRest(facts, now: now, lastActivity: .distantPast, delay: 5))
    }

    @Test func theOffsetStaysNearTheCentreAndMoves() {
        var seen = Set<String>()
        for m in 0..<600 {
            let o = RestScreen.offset(minute: m)
            #expect(abs(o.x) <= 16 && abs(o.y) <= 16)
            #expect(o == RestScreen.offset(minute: m))
            seen.insert("\(o.x),\(o.y)")
        }
        #expect(seen.count > 500)
    }
}
