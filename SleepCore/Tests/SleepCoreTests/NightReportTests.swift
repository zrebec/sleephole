import Foundation
import Testing
@testable import SleepCore

/// The owner's first real night (29.→30. 9. 2026), replayed for the night story in Štatistiky.
@Suite struct NightReportTests {
    let events: [(String, NightEventKind)] = [
        ("29.09 20:57:25", .started),
        ("29.09 20:57:40", .leftApp),
        ("29.09 21:00:41", .returned),
        ("29.09 21:00:48", .leftApp),
        ("29.09 21:02:21", .returned),
        ("29.09 21:02:28", .returned),
        ("29.09 21:02:28", .locked),
        ("29.09 21:12:47", .unlocked),
        ("29.09 21:12:47", .returned),
        ("29.09 21:12:51", .returned),
        ("29.09 21:12:51", .locked),
        ("29.09 22:01:27", .unlocked),
        ("29.09 22:01:37", .returned),
        ("29.09 22:01:37", .locked),
        ("29.09 23:45:59", .unlocked),
        ("29.09 23:46:00", .returned),
        ("29.09 23:46:03", .returned),
        ("29.09 23:46:03", .locked),
        ("30.09 00:03:14", .unlocked),
        ("30.09 00:03:15", .returned),
        ("30.09 00:03:20", .returned),
        ("30.09 00:03:20", .locked),
        ("30.09 04:25:54", .unlocked),
        ("30.09 04:25:55", .returned),
        ("30.09 04:26:03", .confirmed),
    ]

    func d(_ s: String) -> Date {          // "30.09 04:26:03"
        let p = s.split(whereSeparator: { ". :".contains($0) }).map { Int($0)! }
        return at(2026, p[1], p[0], p[2], p[3], p[4])
    }

    var firstNight: NightLog {
        var l = NightLog(window: NightWindow(key: NightKey("2026-09-30")!, bedtime: at(2026, 9, 29, 21, 0),
                                             wake: at(2026, 9, 30, 4, 30)), buildingId: "l1-house-j-a")
        for (t, k) in events { l.append(k, at: d(t)) }
        return l
    }

    @Test func storyOfTheFirstRealNight() {
        let r = NightReport(log: firstNight)
        #expect(r.startedAt == d("29.09 20:57:25"))
        #expect(r.setupEnds == at(2026, 9, 29, 21, 5))                    // bedtime + 5 min (early start)
        #expect(r.firstLockAt == d("29.09 21:02:28"))
        #expect(r.confirmedAt == d("30.09 04:26:03") && r.confirmMethod == nil)   // before the method was logged
        #expect(r.alarmFiredAt == nil)                                     // confirmed before the alarm
        #expect(r.setupTrips.count == 2 && r.nightTrips.isEmpty)
        #expect(r.setupTrips[0].duration.map { abs($0 - 181) < 1 } == true)   // 20:57:40 → 21:00:41
        #expect(r.screenChecks.count == 5)                                // 21:12, 22:01, 23:45, 00:03, 04:25
        #expect(r.screenChecks.last == d("30.09 04:25:54"))
        #expect(r.collapsedAt == nil && r.calls.isEmpty && r.relaunches.isEmpty && r.abandonedAt == nil)
    }

    @Test func tripsCallsRelaunchesAndConfirmMethod() {
        let w = NightWindow(key: NightKey("2026-10-02")!, bedtime: at(2026, 10, 1, 21, 0), wake: at(2026, 10, 2, 4, 30))
        var l = NightLog(window: w, buildingId: "x")
        l.append(.started, at: at(2026, 10, 1, 21, 0))
        l.append(.leftApp, at: at(2026, 10, 1, 22, 0))
        l.append(.returned, at: at(2026, 10, 1, 22, 0, 8))
        l.append(.callStarted, at: at(2026, 10, 1, 23, 0))
        l.append(.callEnded, at: at(2026, 10, 1, 23, 5))
        l.append(.callStarted, at: at(2026, 10, 2, 1, 0))                   // never ended
        l.append(.leftApp, at: at(2026, 10, 2, 2, 0))
        l.append(.appLaunched, at: at(2026, 10, 2, 3, 0))
        l.append(.leftApp, at: at(2026, 10, 2, 3, 30))                      // never back
        l.append(.alarmFired, at: w.wake)
        l.append(.alarmStopped, at: w.wake + 120)
        l.append(.confirmedByShake, at: w.wake + 130)
        let r = NightReport(log: l)
        #expect(r.nightTrips.count == 3 && r.nightTrips[1].end == nil && r.nightTrips[2].end == nil)
        #expect(r.nightTrips[0].duration == 8)
        #expect(r.calls.count == 2 && r.calls[1].end == nil && r.relaunches.count == 1)
        #expect(r.confirmMethod == .shake && r.alarmStoppedAt == w.wake + 120 && r.firstLockAt == nil)
        var code = l
        code.append(.confirmedByCode, at: w.wake + 140)
        #expect(NightReport(log: code).confirmMethod == .code)
    }
}
