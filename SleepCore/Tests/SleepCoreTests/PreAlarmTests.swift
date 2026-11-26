import Foundation
import Testing
@testable import SleepCore

/// W7 (build 14b1): the silent pre-alarm that lets the Apple Watch buzz shortly before the alarm.
@Suite struct PreAlarmTests {
    let wake = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theLeadIsThirtySecondsAndTheMinimumAheadThree() {
        #expect(PreAlarmPlan.lead == 30)
        #expect(PreAlarmPlan.minimumAhead == 3)
    }

    @Test func aNormalNightFiresThirtySecondsBeforeTheWake() {
        let now = wake - 8 * 3600
        #expect(PreAlarmPlan.fireDate(wake: wake, now: now, isNap: false, enabled: true) == wake - 30)
    }

    @Test func aNapNeverGetsOne() {
        #expect(PreAlarmPlan.fireDate(wake: wake, now: wake - 3600, isNap: true, enabled: true) == nil)
    }

    @Test func switchedOffNothingFires() {
        #expect(PreAlarmPlan.fireDate(wake: wake, now: wake - 3600, isNap: false, enabled: false) == nil)
    }

    @Test func aQuickNightOfEightMinutesFiresThirtySecondsBeforeItsWake() {
        let start = wake - 8 * 60
        #expect(PreAlarmPlan.fireDate(wake: wake, now: start, isNap: false, enabled: true) == wake - 30)
    }

    @Test func aQuickNightOfFourMinutesFiresThirtySecondsBeforeItsWake() {
        let start = wake - 4 * 60
        #expect(PreAlarmPlan.fireDate(wake: wake, now: start, isNap: false, enabled: true) == wake - 30)
    }

    @Test func tooCloseOrPastNothingFires() {
        // wake - 30 must lie MORE than minimumAhead (3 s) after now
        let boundary = wake - PreAlarmPlan.lead - PreAlarmPlan.minimumAhead          // wake - 33 s: exactly 3 s ahead
        #expect(PreAlarmPlan.fireDate(wake: wake, now: boundary, isNap: false, enabled: true) == nil)
        #expect(PreAlarmPlan.fireDate(wake: wake, now: boundary - 0.5, isNap: false, enabled: true) == wake - 30)
        #expect(PreAlarmPlan.fireDate(wake: wake, now: boundary + 0.5, isNap: false, enabled: true) == nil)
        #expect(PreAlarmPlan.fireDate(wake: wake, now: wake - 30, isNap: false, enabled: true) == nil)
        #expect(PreAlarmPlan.fireDate(wake: wake, now: wake + 5, isNap: false, enabled: true) == nil)
    }

    @Test func aNightShorterThanTheLeadPlusTheMinimumHasNone() {
        let start = wake - 32
        #expect(PreAlarmPlan.fireDate(wake: wake, now: start, isNap: false, enabled: true) == nil)
    }

    @Test func itEndsAtTheWakeTime() {
        #expect(PreAlarmPlan.shouldEnd(now: wake - 1, wake: wake) == false)
        #expect(PreAlarmPlan.shouldEnd(now: wake, wake: wake))
        #expect(PreAlarmPlan.shouldEnd(now: wake + 1, wake: wake))
    }

    @Test func theKeepAliveStartsThreeSecondsBeforeTheFire() {
        #expect(PreAlarmPlan.keepAliveFrom(wake: wake) == wake - 33)
    }
}
