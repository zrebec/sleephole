import Foundation
import SleepCore
import Testing
import UserNotifications
@testable import SleepHole

/// Phase F6a: which notifications are time sensitive (break through a Focus) and which stay normal.
/// Pure functions only – nothing is scheduled and the authorization is never requested (its alert would block the run).
struct NotificationsTests {
    @Test func contentLevelFollowsUrgency() {
        let urgent = Notifications.content(title: "t", body: "b", sound: .default, urgent: true)
        #expect(urgent.interruptionLevel == .timeSensitive)
        #expect(urgent.title == "t" && urgent.body == "b" && urgent.sound != nil)
        let normal = Notifications.content(title: "t", body: "b", sound: nil, urgent: false)
        #expect(normal.interruptionLevel == .active)
        #expect(normal.sound == nil)
    }

    @Test func nightNoticesAreTimeSensitive() {
        for id in ["grace-end", "nudge", "nudge-2", "closed", "closed-2", "pause-soon", "pause-over", "alarm-screen", "collapsed", "lock-reminder"] {
            #expect(Notifications.isTimeSensitive(id), "\(id)")
        }
    }

    @Test func everyBackupAlarmIsTimeSensitive() {
        #expect(Notifications.backupAlarmIds.count == Notifications.backupAlarmOffsets.count)
        #expect(Set(Notifications.backupAlarmIds).count == Notifications.backupAlarmIds.count)
        for id in Notifications.backupAlarmIds {
            #expect(Notifications.isTimeSensitive(id), "\(id)")
        }
    }

    @Test func nightIdsAreExactlyTheTimeSensitiveNightNotices() {
        let expected = Set(["grace-end", "nudge", "nudge-2", "closed", "closed-2", "pause-soon", "pause-over", "alarm-screen", "collapsed", "lock-reminder"]
                           + Notifications.backupAlarmIds)
        #expect(Set(Notifications.nightIds) == expected)   // cancelNight() cancels all of them, nothing else
        #expect(Notifications.nightIds.count == expected.count)
    }

    @Test func bedtimeRemindersAreTimeSensitive() {
        for i in 0..<10 {
            #expect(Notifications.isTimeSensitive(Notifications.reminderId(i)), "reminder \(i)")
        }
        let content = Notifications.reminderContent(0, bedtime: TimeOfDay(22, 30), offset: 30)
        #expect(content.interruptionLevel == .timeSensitive)
        #expect(content.sound != nil)
        #expect(!content.title.isEmpty && !content.body.isEmpty)
    }

    @Test func monthlyCheckAndExpiryWarningsStayNormal() {
        #expect(!Notifications.isTimeSensitive(Notifications.monthlyCheckId))
        #expect(Notifications.monthlyCheckContent().interruptionLevel == .active)
        for id in ["expiry-1", "expiry-2"] {
            #expect(!Notifications.isTimeSensitive(id), "\(id)")
        }
        #expect(!Notifications.isTimeSensitive("anything-else"))
    }
}
