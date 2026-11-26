import Foundation
import Testing
@testable import SleepCore

/// A developer night that models a real one on a scale (build 14, step 14a5): 1 min = 1 h, a pause lasts 10 s.
/// The window is 8 min long, the setup 15 s; every time below is in seconds from the bedtime.
@Suite struct ScaledNightTests {
    let bedtime = night.bedtime
    var window: NightWindow {
        NightWindow(key: night.key, bedtime: bedtime, wake: bedtime + 480,
                    earlyConfirmOverride: NightWindow.testNightConfirmLead)
    }
    var rules: SleepRules {
        var r = SleepRules.forNewNights
        r.setupGrace = 15
        r.hourLength = 60
        r.pauseLength = 10
        return r
    }
    /// The same night with the defaults (real hours, 10-minute pauses).
    var realRules: SleepRules { var r = rules; r.hourLength = 3600; r.pauseLength = PausePolicy.duration; return r }

    private func scaledLog(_ events: [(Double, NightEventKind)]) -> NightLog {
        var l = NightLog(window: window, buildingId: "l1-house-a-0")
        l.append(.started, at: bedtime)
        for (s, k) in events { l.append(k, at: bedtime + s) }
        l.append(.confirmed, at: bedtime + 480)
        return l
    }

    @Test func defaultsAreTheRealNight() {
        let r = SleepRules()
        #expect(r.hourLength == 3600 && r.pauseLength == PausePolicy.duration)
        #expect(SleepRules.forNewNights.hourLength == 3600 && SleepRules.forNewNights.pauseLength == 600)
    }

    @Test func eightMinutesAreSevenHours() {
        let l = scaledLog([])
        #expect(CalmHours.hours(of: l, rules: rules).count == 7)
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 7, total: 7))
        // the same window with real hours has none
        #expect(CalmHours.count(log: l, rules: realRules) == .init(calm: 0, total: 0))
    }

    @Test func aTripSpoilsOneHour() {
        // 200 s – 220 s lies in the hour [195, 255) only
        let l = scaledLog([(200, .leftApp), (220, .returned)])
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 6, total: 7))
    }

    @Test func aTripAcrossTheBoundarySpoilsTwoHours() {
        // the hours start at 15 s + n × 60 s: the boundary 255 lies inside 245 – 265
        let l = scaledLog([(245, .leftApp), (265, .returned)])
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 5, total: 7))
    }

    @Test func aPauseLastsTenSecondsAndSpoilsItsHours() {
        let inside = scaledLog([(120, .pauseStarted)])
        #expect(inside.pauseIntervals(length: rules.pauseLength).map { $0.1.timeIntervalSince($0.0) } == [10])
        #expect(CalmHours.count(log: inside, rules: rules) == .init(calm: 6, total: 7))          // [75, 135) only
        let across = scaledLog([(130, .pauseStarted)])                                           // 130 – 140 crosses 135
        #expect(CalmHours.count(log: across, rules: rules) == .init(calm: 5, total: 7))
        // the 10-minute pause of a real night would cover all the rest of the short night
        #expect(CalmHours.count(log: across, rules: realRules).calm == 0)
    }

    @Test func thePauseIsActiveForTenSecondsOnly() {
        let l = scaledLog([(120, .pauseStarted)])
        #expect(PausePolicy.activeUntil(l, rules: rules, at: bedtime + 125) == bedtime + 130)
        #expect(PausePolicy.activeUntil(l, rules: rules, at: bedtime + 130) == nil)
        // with the default rules the same log still has its pause running at 130
        #expect(PausePolicy.activeUntil(l, at: bedtime + 130) == bedtime + 720)
    }

    @Test func tooLateUsesTheNightsPauseLength() {
        let l = scaledLog([])
        let opens = l.window.confirmOpens                                                        // wake - 30 s
        #expect(PausePolicy.block(l, rules: rules, at: opens - 10, coins: 0) == nil)
        #expect(PausePolicy.block(l, rules: rules, at: opens - 9, coins: 0) == .tooLate(opens: opens))
        #expect(PausePolicy.block(l, rules: realRules, at: opens - 10, coins: 0) == .tooLate(opens: opens))
    }

    @Test func aTripInsideTheScaledPauseIsFree() {
        // leaving the app at 125 s inside the 10 s pause that began at 120 s is no trip; after 130 s it would be
        let inPause = scaledLog([(120, .pauseStarted), (125, .leftApp), (128, .returned)])
        #expect(NightEvaluator.awaySeconds(inPause, rules: rules) == 0)
        let after = scaledLog([(120, .pauseStarted), (125, .leftApp), (135, .returned)])
        #expect(NightEvaluator.awaySeconds(after, rules: rules) == 5)
        #expect(NightReport(log: inPause, rules: rules).nightTrips.first?.duringPause == true)
    }
}
