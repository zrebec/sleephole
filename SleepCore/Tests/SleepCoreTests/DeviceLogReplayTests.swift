import Foundation
import Testing
@testable import SleepCore

/// Replays the monitor's derived events from the owner's real device test (iPhone 16 Pro, 2026-09-29)
/// with the debug rules (setup grace 10 s). Keeps detection + rules honest against reality.
@Suite struct DeviceLogReplayTests {
    let rules: SleepRules = { var r = SleepRules(); r.setupGrace = 10; return r }()

    func t(_ hms: String) -> Date {                       // "15:29:54.457" on 2026-09-29
        let p = hms.split(separator: ":").map { Double($0)! }
        return at(2026, 9, 29, Int(p[0]), Int(p[1])) + p[2]
    }

    func night(_ start: String, _ events: [(String, NightEventKind)]) -> NightLog {
        let s = t(start)
        var l = NightLog(window: NightWindow(key: NightKey("2026-09-29")!, bedtime: s, wake: s + 7200),
                         buildingId: "x")
        l.append(.started, at: s)
        for (time, kind) in events { l.append(kind, at: t(time)) }
        return l
    }

    @Test func lockThenFaceIDUnlockStands() {
        let l = night("15:27:46.715", [("15:28:02.151", .returned), ("15:28:02.181", .locked),
                                       ("15:28:47.274", .unlocked), ("15:28:48.046", .returned)])
        #expect(NightEvaluator.collapsedAt(l, rules: rules) == nil)
    }

    @Test func shortTripToFilesStands() {        // 6.8 s away after the grace
        let l = night("15:29:16.774", [("15:29:29.810", .leftApp), ("15:29:36.573", .returned)])
        #expect(NightEvaluator.collapsedAt(l, rules: rules) == nil)
    }

    @Test func tripOf12sAfterGraceNowStands() {  // 12.2 s after the grace: within notice (3 s) + 10 s
        let l = night("15:29:52.107", [("15:29:54.457", .leftApp), ("15:30:14.303", .returned)])
        #expect(NightEvaluator.collapsedAt(l, rules: rules) == nil)
    }

    @Test func eveningTestTrip21sCollapses() {   // owner's test night 29.09 18:58 (grace 20 s)
        var r = SleepRules(); r.setupGrace = 20
        let l = night("18:58:08.357", [("18:58:33.333", .leftApp), ("18:58:54.450", .returned)])
        #expect(NightEvaluator.collapsedAt(l, rules: r) != nil)
    }

    @Test func lockScreenWithScreenWakesStands() {
        let l = night("15:30:18.250", [("15:30:39.250", .returned), ("15:30:39.281", .locked),
                                       ("15:31:28.024", .unlocked), ("15:31:28.836", .returned)])
        #expect(NightEvaluator.collapsedAt(l, rules: rules) == nil)
    }

    @Test func incomingCallStands() {
        let l = night("15:32:05.882", [("15:32:30.002", .callStarted), ("15:32:44.092", .callEnded)])
        #expect(NightEvaluator.collapsedAt(l, rules: rules) == nil)
    }
}
