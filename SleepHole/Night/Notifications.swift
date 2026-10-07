import Foundation
import SleepCore
import UserNotifications

/// All local notifications (plan §6.4).
enum Notifications {
    private static var center: UNUserNotificationCenter { .current() }

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Daily reminders before bedtime (time sensitive: owner 2026-10-04 – they should reach him in a Focus too).
    static func scheduleReminders(_ schedule: Schedule) {
        let ids = (0..<10).map(reminderId)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        for (i, offset) in schedule.reminderOffsets.enumerated() where offset > 0 {
            let total = (schedule.bedtime.hour * 60 + schedule.bedtime.minute - offset + 24 * 60) % (24 * 60)
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: total / 60, minute: total % 60),
                                                        repeats: true)
            let content = reminderContent(i, bedtime: schedule.bedtime, offset: offset)
            center.add(UNNotificationRequest(identifier: reminderId(i), content: content, trigger: trigger))
        }
        scheduleMonthlyCheck(wake: schedule.wake)
    }

    static let reminderPrefix = "reminder-"
    static func reminderId(_ index: Int) -> String { reminderPrefix + String(index) }

    static func reminderContent(_ index: Int, bedtime: TimeOfDay, offset: Int) -> UNMutableNotificationContent {
        content(title: L("Bedtime at \(Fmt.time(bedtime))"), body: L("Bedtime in \(offset) minutes. Time to get ready 🌙"),
                sound: .default, urgent: isTimeSensitive(reminderId(index)))
    }

    /// On the 1st of every month, an hour after wake-up: the free window to change the schedule (days 1–3).
    static func scheduleMonthlyCheck(wake: TimeOfDay) {
        let total = (wake.hour * 60 + wake.minute + 60) % (24 * 60)
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(day: 1, hour: total / 60, minute: total % 60),
                                                    repeats: true)
        center.add(UNNotificationRequest(identifier: monthlyCheckId, content: monthlyCheckContent(), trigger: trigger))
    }

    static let monthlyCheckId = "schedule-month"

    static func monthlyCheckContent() -> UNMutableNotificationContent {
        content(title: L("New month 🌙"), body: L("Does your bedtime still fit you? Until the 3rd you can change it for free."),
                sound: .default, urgent: isTimeSensitive(monthlyCheckId))
    }

    /// Scheduled when a night starts: end-of-setup warning + backup alarm (only matters if the app dies). The five
    /// backup notifications are ALWAYS scheduled – also next to the system alarm (AlarmKit, phase F6b), which must
    /// not be the only thing between the owner and a missed morning until it has proven itself on the phone.
    static func scheduleNight(setupEnds: Date, wake: Date, alarmFile: String) {
        // owner 2026-09-30: warn 15 s before the setup time runs out
        schedule("grace-end", at: setupEnds - 15, title: L("⏳ 15 s of setup left"),
                 body: L("Come back to SleepHole and lock your phone 🌙"), sound: .default)
        // One notification sounds for at most 30 s and only once – if the app died at night that was the whole
        // alarm. A chain keeps ringing for ~2.5 min (audit 2026-10-03, B3). The app cancels them all as soon as
        // its own alarm really rings.
        for (i, offset) in backupAlarmOffsets.enumerated() {
            schedule(backupAlarmIds[i], at: wake + offset, title: L("Good morning ☀️"),
                     body: L("Open SleepHole and confirm you're up."),
                     sound: UNNotificationSound(named: UNNotificationSoundName(alarmFile)))
        }
    }

    static let backupAlarmOffsets: [TimeInterval] = [30, 60, 90, 120, 150]
    static let backupAlarmIds = ["alarm-backup"] + (2...backupAlarmOffsets.count).map { "alarm-backup-\($0)" }

    /// Leaving the app during a pause (D17) is free until `end`: remind a minute before and when it is over.
    static func pauseEnding(at end: Date) {
        if end.timeIntervalSinceNow > 75 {
            schedule("pause-soon", at: end - 60, title: L("⏳ The pause ends in a minute"),
                     body: L("Come back to SleepHole and lock your phone 🌙"), sound: .default)
        }
        schedule("pause-over", at: end, title: L("⚠️ The pause is over – come back!"),
                 body: L("Come back to SleepHole now, or the building collapses 🏗️"), sound: .default)
    }

    static func cancelPauseNotices() { cancel(["pause-soon", "pause-over"]) }

    /// The expiry warnings' text; the date always carries its year.
    static func expiryBody(_ expiry: Date) -> String {
        L("SleepHole's signature ends on \(Fmt.dateTimeWithYear(expiry)). Connect your iPhone to the Mac and install SleepHole again – your town, nights and coins stay.")
    }

    /// The app stops launching when its provisioning profile runs out (`AppExpiry`).
    /// Warn a day and three hours before (audit 2026-10-03, B2).
    static func scheduleExpiry(_ expiry: Date?) {
        center.removePendingNotificationRequests(withIdentifiers: ["expiry-1", "expiry-2"])
        guard let expiry else { return }
        let body = expiryBody(expiry)
        for (id, lead, title) in [("expiry-1", 24.0, L("SleepHole stops working tomorrow")),
                                  ("expiry-2", 3.0, L("SleepHole stops working in 3 hours"))] {
            let at = expiry - lead * 3600
            guard at > Date() else { continue }
            schedule(id, at: at, title: title, body: body, sound: .default)
        }
    }

    /// Sent the moment leaving the app is detected; the owner then has `tolerance` seconds (D15).
    /// Apps cannot vibrate in the background – the notification's sound is what vibrates the phone, so it is
    /// sent twice. `.default`, not `.defaultCritical`: critical sounds need an Apple entitlement and stay silent
    /// without it (owner 2026-09-30: the warning only popped up, no vibration).
    static func nudge(tolerance: TimeInterval) {
        let title = L("⚠️ Come back to SleepHole!")
        schedule("nudge", at: Date() + 0.2, title: title,
                 body: L("You have \(Int(tolerance)) seconds, or the building collapses 🏗️"), sound: .default)
        // the second one only when there is time for it (the night's budget may leave just a few seconds)
        if tolerance > 6 {
            schedule("nudge-2", at: Date() + 5, title: title,
                     body: L("Only a few seconds left – come back now 🏗️"), sound: .default)
        }
    }

    /// Sent the moment iOS says SleepHole is being closed during a night or nap (R4, owner 2026-10-04: swiping the app
    /// away counts as leaving it): the owner has `tolerance` seconds to open it again. Like `nudge`, twice. Scheduled in
    /// the last moments of the process – the notification centre keeps it, so it still arrives. A restart of the phone
    /// sends the same notice; the relaunch cancels these and recognises the restart by the boot time.
    static func closed(tolerance: TimeInterval) {
        let title = L("⚠️ SleepHole was closed")
        schedule("closed", at: Date() + 0.2, title: title,
                 body: L("Open it within \(Int(tolerance)) seconds, or the building collapses 🏗️"), sound: .default)
        if tolerance > 6 {
            schedule("closed-2", at: Date() + 5, title: title,
                     body: L("Only a few seconds left – come back now 🏗️"), sound: .default)
        }
    }

    /// At the alarm: a silent, time-sensitive notification lights up the lock screen
    /// (apps cannot switch the screen on themselves). The sound comes from the app.
    static func alarmScreen() {
        schedule("alarm-screen", at: Date() + 0.2, title: L("⏰ Good morning!"),
                 body: L("Shake your phone or enter your code in SleepHole."), sound: nil)
    }

    static func cancelNudge() { cancel(["nudge", "nudge-2"]) }
    static func cancelClosed() { cancel(["closed", "closed-2"]) }
    static func cancelBackupAlarm() { cancel(backupAlarmIds) }
    static func cancelNight() { cancel(nightIds) }

    /// "allowed" / "denied" / "not allowed yet" for the Settings screen.
    static func statusText() async -> String {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: L("allowed ✓")
        case .denied: L("denied ✗")
        default: L("not allowed yet")
        }
    }

    private static func cancel(_ ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: Time-sensitive rule (phase F6a, entitlement `com.apple.developer.usernotifications.time-sensitive`)

    /// The ids of the night's notifications: the end-of-setup warning, "Come back!", "SleepHole was closed", the pause
    /// notices, the screen light-up and the backup alarm chain.
    static let nightIds = ["grace-end", "nudge", "nudge-2", "closed", "closed-2", "alarm-screen", "pause-soon", "pause-over"]
        + backupAlarmIds

    /// Time sensitive = breaks through a Focus (Sleep, Do Not Disturb): everything of the night, plus the bedtime
    /// reminders. The monthly check and the app-expiry warnings stay normal.
    static func isTimeSensitive(_ id: String) -> Bool {
        nightIds.contains(id) || id.hasPrefix(reminderPrefix)
    }

    /// The content of every notification; `urgent` ones are time sensitive, the rest keep the default `.active`.
    static func content(title: String, body: String, sound: UNNotificationSound?, urgent: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        // time-sensitive notifications break through a Focus (phase F6a)
        if urgent { content.interruptionLevel = .timeSensitive }
        return content
    }

    private static func schedule(_ id: String, at date: Date, title: String, body: String, sound: UNNotificationSound?) {
        let note = content(title: title, body: body, sound: sound, urgent: isTimeSensitive(id))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.5, date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: note, trigger: trigger))
    }
}
