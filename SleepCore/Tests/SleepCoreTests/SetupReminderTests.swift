import Foundation
import Testing
@testable import SleepCore

@Suite struct SetupReminderTests {
    let ends = Date(timeIntervalSince1970: 10_000)

    @Test func insideTheAppNeverNeedsIt() {
        #expect(SetupReminder.fireDate(setupEnds: ends, now: ends - 200, outsideApp: false) == nil)
    }

    @Test func outsideWithTimeLeftFiresFifteenSecondsBeforeTheEnd() {
        #expect(SetupReminder.fireDate(setupEnds: ends, now: ends - 200, outsideApp: true) == ends - 15)
    }

    @Test func outsideTooLateIsNotScheduled() {
        #expect(SetupReminder.fireDate(setupEnds: ends, now: ends - 15, outsideApp: true) == nil)
        #expect(SetupReminder.fireDate(setupEnds: ends, now: ends - 5, outsideApp: true) == nil)
    }

    @Test func eventsMoveTheUserInAndOut() {
        #expect(SetupReminder.outsideApp(after: .leftApp, wasOutside: false))
        #expect(SetupReminder.outsideApp(after: .usedLockScreen, wasOutside: false))
        #expect(SetupReminder.outsideApp(after: .closedByOwner, wasOutside: false))
        #expect(!SetupReminder.outsideApp(after: .returned, wasOutside: true))
        #expect(!SetupReminder.outsideApp(after: .appLaunched, wasOutside: true))
        #expect(!SetupReminder.outsideApp(after: .started, wasOutside: true))
    }

    @Test func aLockChangesNothing() {
        #expect(!SetupReminder.outsideApp(after: .locked, wasOutside: false))   // locked from inside SleepHole
        #expect(SetupReminder.outsideApp(after: .locked, wasOutside: true))     // locked with another app in front
        #expect(!SetupReminder.outsideApp(after: .dataLocked, wasOutside: false))
    }
}
