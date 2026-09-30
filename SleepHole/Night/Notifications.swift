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
    }

    /// Scheduled when a night starts: end-of-setup warning + backup alarm (only matters if the app dies).
    static func scheduleNight(setupEnds: Date, wake: Date, alarmFile: String) {
        // owner 2026-09-30: warn 15 s before the setup time runs out
        schedule("grace-end", at: setupEnds - 15, title: L("⏳ 15 s of setup left"),
                 body: L("Come back to SleepHole and lock your phone 🌙"), sound: .default, urgent: true)
        schedule("alarm-backup", at: wake + 30, title: L("Good morning ☀️"),
                 body: L("Open SleepHole and confirm you're up."),
                 sound: UNNotificationSound(named: UNNotificationSoundName(alarmFile)), urgent: true)
    }

    /// Sent the moment leaving the app is detected; the owner then has `tolerance` seconds (D15).
    static func nudge(tolerance: TimeInterval) {
        schedule("nudge", at: Date() + 0.2, title: L("⚠️ Come back to SleepHole!"),
                 body: L("You have \(Int(tolerance)) seconds, or the building collapses 🏗️"), sound: .defaultCritical,
                 urgent: true)
    }

    /// At the alarm: a silent, time-sensitive notification lights up the lock screen
    /// (apps cannot switch the screen on themselves). The sound comes from the app.
    static func alarmScreen() {
        schedule("alarm-screen", at: Date() + 0.2, title: L("⏰ Good morning!"),
                 body: L("Shake your phone or enter your code in SleepHole."), sound: nil, urgent: true)
    }

    static func cancelNudge() { cancel(["nudge"]) }
    static func cancelBackupAlarm() { cancel(["alarm-backup"]) }
    static func cancelNight() { cancel(["grace-end", "alarm-backup", "nudge", "alarm-screen"]) }

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
