import Foundation
import SleepCore
import UserNotifications

/// All local notifications (plan §6.4).
enum Notifications {
    private static var center: UNUserNotificationCenter { .current() }

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Daily reminders before bedtime.
    static func scheduleReminders(_ schedule: Schedule) {
        let ids = (0..<10).map { "reminder-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        for (i, offset) in schedule.reminderOffsets.enumerated() where offset > 0 {
            let total = (schedule.bedtime.hour * 60 + schedule.bedtime.minute - offset + 24 * 60) % (24 * 60)
            let content = UNMutableNotificationContent()
            content.title = L("Bedtime at \(Fmt.time(schedule.bedtime))")
            content.body = L("Bedtime in \(offset) minutes. Time to get ready 🌙")
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: total / 60, minute: total % 60),
                                                        repeats: true)
            center.add(UNNotificationRequest(identifier: "reminder-\(i)", content: content, trigger: trigger))
        }
        scheduleMonthlyCheck(wake: schedule.wake)
    }

    /// On the 1st of every month, an hour after wake-up: the free window to change the schedule (days 1–3).
    static func scheduleMonthlyCheck(wake: TimeOfDay) {
        let total = (wake.hour * 60 + wake.minute + 60) % (24 * 60)
        let content = UNMutableNotificationContent()
        content.title = L("New month 🌙")
        content.body = L("Does your bedtime still fit you? Until the 3rd you can change it for free.")
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(day: 1, hour: total / 60, minute: total % 60),
                                                    repeats: true)
        center.add(UNNotificationRequest(identifier: "schedule-month", content: content, trigger: trigger))
    }

    /// Scheduled when a night starts: end-of-setup warning + backup alarm (only matters if the app dies).
    static func scheduleNight(setupEnds: Date, wake: Date, alarmFile: String) {
        // owner 2026-09-30: warn 15 s before the setup time runs out
        schedule("grace-end", at: setupEnds - 15, title: L("⏳ 15 s of setup left"),
                 body: L("Come back to SleepHole and lock your phone 🌙"), sound: .default, urgent: true)
        // One notification sounds for at most 30 s and only once – if the app died at night that was the whole
        // alarm. A chain keeps ringing for ~2.5 min (audit 2026-10-03, B3). The app cancels them all as soon as
        // its own alarm really rings.
        for (i, offset) in backupAlarmOffsets.enumerated() {
            schedule(backupAlarmIds[i], at: wake + offset, title: L("Good morning ☀️"),
                     body: L("Open SleepHole and confirm you're up."),
                     sound: UNNotificationSound(named: UNNotificationSoundName(alarmFile)), urgent: true)
        }
    }

    static let backupAlarmOffsets: [TimeInterval] = [30, 60, 90, 120, 150]
    static let backupAlarmIds = ["alarm-backup"] + (2...backupAlarmOffsets.count).map { "alarm-backup-\($0)" }

    /// Leaving the app during a pause (D17) is free until `end`: remind a minute before and when it is over.
    static func pauseEnding(at end: Date) {
        if end.timeIntervalSinceNow > 75 {
            schedule("pause-soon", at: end - 60, title: L("⏳ The pause ends in a minute"),
                     body: L("Come back to SleepHole and lock your phone 🌙"), sound: .default, urgent: true)
        }
        schedule("pause-over", at: end, title: L("⚠️ The pause is over – come back!"),
                 body: L("Come back to SleepHole now, or the building collapses 🏗️"), sound: .default, urgent: true)
    }

    static func cancelPauseNotices() { cancel(["pause-soon", "pause-over"]) }

    /// Free Personal Team signing: the app stops launching when its provisioning profile runs out (`AppExpiry`).
    /// Warn a day and three hours before (audit 2026-10-03, B2).
    static func scheduleExpiry(_ expiry: Date?) {
        center.removePendingNotificationRequests(withIdentifiers: ["expiry-1", "expiry-2"])
        guard let expiry else { return }
        let when = L("\(Fmt.dayMonth(NightKey(date: expiry, calendar: .current))) at \(Fmt.time(expiry))")
        let body = L("The free signature ends on \(when). Connect your iPhone to the Mac and run SleepHole from Xcode – your data stays.")
        for (id, lead, title) in [("expiry-1", 24.0, L("SleepHole stops working tomorrow")),
                                  ("expiry-2", 3.0, L("SleepHole stops working in 3 hours"))] {
            let at = expiry - lead * 3600
            guard at > Date() else { continue }
            schedule(id, at: at, title: title, body: body, sound: .default, urgent: true)
        }
    }

    /// Sent the moment leaving the app is detected; the owner then has `tolerance` seconds (D15).
    /// Apps cannot vibrate in the background – the notification's sound is what vibrates the phone, so it is
    /// sent twice. `.default`, not `.defaultCritical`: critical sounds need an Apple entitlement and stay silent
    /// without it (owner 2026-09-30: the warning only popped up, no vibration).
    static func nudge(tolerance: TimeInterval) {
        let title = L("⚠️ Come back to SleepHole!")
        schedule("nudge", at: Date() + 0.2, title: title,
                 body: L("You have \(Int(tolerance)) seconds, or the building collapses 🏗️"), sound: .default, urgent: true)
        // the second one only when there is time for it (the night's budget may leave just a few seconds)
        if tolerance > 6 {
            schedule("nudge-2", at: Date() + 5, title: title,
                     body: L("Only a few seconds left – come back now 🏗️"), sound: .default, urgent: true)
        }
    }

    /// At the alarm: a silent, time-sensitive notification lights up the lock screen
    /// (apps cannot switch the screen on themselves). The sound comes from the app.
    static func alarmScreen() {
        schedule("alarm-screen", at: Date() + 0.2, title: L("⏰ Good morning!"),
                 body: L("Shake your phone or enter your code in SleepHole."), sound: nil, urgent: true)
    }

    static func cancelNudge() { cancel(["nudge", "nudge-2"]) }
    static func cancelBackupAlarm() { cancel(backupAlarmIds) }
    static func cancelNight() {
        cancel(["grace-end", "nudge", "nudge-2", "alarm-screen", "pause-soon", "pause-over"] + backupAlarmIds)
    }

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

    private static func schedule(_ id: String, at date: Date, title: String, body: String, sound: UNNotificationSound?,
                                 urgent: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        // Time-sensitive would break through Focus, but Personal Teams can't get the entitlement
        // (F6, paid account). Until then the owner allows SleepHole in the Focus settings.
        if urgent { content.interruptionLevel = .active }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.5, date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
