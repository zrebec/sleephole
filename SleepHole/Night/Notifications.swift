import Foundation
import SleepCore
import UserNotifications

/// All local notifications (plan §6.4).
enum Notifications {
    private static var center: UNUserNotificationCenter { .current() }

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - the Time Sensitive switch

    /// True only when notifications are allowed but iOS's "Time Sensitive Notifications" switch for the app is off.
    /// Denied / not asked is covered by the Notifications row, so no second warning is stacked on it.
    static func timeSensitiveOff(authorization: UNAuthorizationStatus, setting: UNNotificationSetting) -> Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return setting == .disabled
        default: return false
        }
    }

    /// Asks the system for the app's own switch (each Focus has another one that no app can read).
    static func readTimeSensitiveOff() async -> Bool {
        let s = await center.notificationSettings()
        return timeSensitiveOff(authorization: s.authorizationStatus, setting: s.timeSensitiveSetting)
    }

    /// The check for this launch: under test it never touches the system; in the simulator `-timeSensitive off|on`
    /// pretends the answer (dev aid for screenshots); otherwise the real reader.
    @MainActor
    static func timeSensitiveCheckForLaunch(args: [String] = ProcessInfo.processInfo.arguments,
                                            underTest: Bool = SystemAlarms.isRunningTests) -> @MainActor () async -> Bool {
        if underTest { return { false } }
        #if targetEnvironment(simulator)
        if let i = args.firstIndex(of: "-timeSensitive"), args.indices.contains(i + 1) {
            let answer = args[i + 1] == "off"
            return { answer }
        }
        #endif
        return { await readTimeSensitiveOff() }
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
                 body: L("Come back to SleepHole and switch the screen off 🌙"), sound: .default)
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
                     body: L("Come back to SleepHole and switch the screen off 🌙"), sound: .default)
        }
        schedule("pause-over", at: end, title: L("⚠️ The pause is over – come back!"),
                 body: L("Come back to SleepHole so the building goes on 🏗️"), sound: .default)
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
    /// Exactly ONE notification per trip (owner 2026-10-09: "each one must have its meaning"). Apps cannot vibrate in
    /// the background – the notification's sound is what vibrates the phone. `.default`, not `.defaultCritical`:
    /// critical sounds need an Apple entitlement and stay silent without it (owner 2026-09-30).
    static func nudge(tolerance: TimeInterval) {
        schedule("nudge", at: Date() + 0.2, title: L("⚠️ Heads up! SleepHole must stay open"),
                 body: L("Come back within \(Int(tolerance)) seconds so tonight's building goes on 🏗️"), sound: .default)
    }

    /// The lock-screen variant of `nudge` (same identifier): "come back" would be wrong advice there – unlocking
    /// needs Face ID or the passcode – the fast, correct reaction is to switch the screen off. One notification only.
    static func lockScreenNudge(tolerance: TimeInterval) {
        schedule("nudge", at: Date() + 0.2, title: L("💤 Your phone is off duty now"),
                 body: L("Switch the screen off within \(Int(tolerance)) seconds so tonight's building goes on 🏗️"), sound: .default)
    }

    /// Gentle mode (owner 2026-10-09, "care instead of enforcement"): the one calm reminder for using the phone on the
    /// lock screen. No seconds, no building at stake – the building stays.
    static func lockScreenReminder() {
        schedule(lockReminderId, at: Date() + 0.2, title: L("💤 Your phone is off duty now"),
                 body: L("Switch the screen off and the calm night goes on."), sound: .default)
    }

    static let lockReminderId = "lock-reminder"

    /// Every warning schedules exactly these identifiers (pure, so it can be tested without the notification centre).
    static let warningIDs = ["nudge"]
    static let closedWarningIDs = ["closed"]

    /// Sent the moment iOS says SleepHole is being closed during a night or nap (R4, owner 2026-10-04: swiping the app
    /// away counts as leaving it): the owner has `tolerance` seconds to open it again. One notification. Scheduled in
    /// the last moments of the process – the notification centre keeps it, so it still arrives. A restart of the phone
    /// sends the same notice; the relaunch cancels these and recognises the restart by the boot time.
    static func closed(tolerance: TimeInterval) {
        schedule("closed", at: Date() + 0.2, title: L("⚠️ Heads up! SleepHole was closed"),
                 body: L("Open it within \(Int(tolerance)) seconds so tonight's building goes on 🏗️"), sound: .default)
    }

    /// "The building collapsed" (owner 2026-10-09: ALWAYS a notice). Scheduled IN ADVANCE when a trip starts, for the moment
    /// it would exceed its allowance – at that moment the app may be suspended or swiped away. Cancelled (pending only,
    /// a delivered notice stays) when the trip ends in time or is excused.
    static func collapsed(isNap: Bool, at date: Date) {
        let title = isNap ? L("😕 Your nap was interrupted") : L("😢 Tonight's building came down")
        let body = isNap ? L("It's all right – try again tomorrow 🌙")
                         : L("Nothing terrible happened. Everything can be repaired – we'll try again tomorrow.")
        schedule(collapsedId, at: max(date, Date() + 0.2), title: title, body: body, sound: .default)
    }

    static let collapsedId = "collapsed"

    /// When the collapse notice of a trip starting at `date` should fire, or nil when no trip can collapse the night
    /// then: inside the setup time, inside a pause, at / after the wake time, after a collapse, or when the trip's
    /// allowance reaches the wake time (away time is clipped there). With the budget used up the allowance is 0 → `date`.
    static func collapseNoticeTime(log: NightLog, rules: SleepRules, at date: Date, alreadyCollapsed: Bool) -> Date? {
        guard !alreadyCollapsed, let start = log.startedAt,
              date >= log.window.setupEnds(start: start, rules: rules), date < log.window.wake,
              PausePolicy.activeUntil(log, at: date) == nil else { return nil }
        let fire = date + NightEvaluator.allowance(log, rules: rules, at: date)
        return fire < log.window.wake ? fire : nil
    }

    /// At the alarm: a silent, time-sensitive notification lights up the lock screen
    /// (apps cannot switch the screen on themselves). The sound comes from the app.
    static func alarmScreen() {
        schedule("alarm-screen", at: Date() + 0.2, title: L("⏰ Good morning!"),
                 body: L("Shake your phone or enter your code in SleepHole."), sound: nil)
    }

    // the "-2" ids are no longer scheduled; they are still cancelled for a notification a previous build left pending
    static func cancelNudge() { cancel(["nudge", "nudge-2", lockReminderId]) }
    static func cancelClosed() { cancel(["closed", "closed-2"]) }
    /// Pending only: a collapse notice that was already delivered must stay for the owner to read.
    static func cancelCollapsed() { center.removePendingNotificationRequests(withIdentifiers: [collapsedId]) }
    static func cancelBackupAlarm() { cancel(backupAlarmIds) }
    static func cancelNight() {
        cancel(nightIds.filter { $0 != collapsedId })
        cancelCollapsed()
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

    // MARK: Time-sensitive rule (phase F6a, entitlement `com.apple.developer.usernotifications.time-sensitive`)

    /// The ids of the night's notifications: the end-of-setup warning, "Come back!", "SleepHole was closed", the pause
    /// notices, the collapse notice, the screen light-up and the backup alarm chain.
    static let nightIds = ["grace-end", "nudge", "nudge-2", "closed", "closed-2", "alarm-screen", "pause-soon", "pause-over", collapsedId,
                          lockReminderId] + backupAlarmIds

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
