import Foundation

/// The "⏳ 15s of setup left" reminder (owner 2026-09-30) exists only to call back a user who is in ANOTHER app while
/// the setup runs. With SleepHole in front – or the phone locked from inside it – it must not be pending at all
/// (owner 2026-10-15: it lit the lock screen and sounded in a night it was meant to protect).
public enum SetupReminder {
    /// The reminder comes this long before the setup runs out.
    public static let lead: TimeInterval = 15

    /// When the reminder should fire, or nil when none is needed: the user is outside SleepHole and the moment
    /// `setupEnds − lead` is still ahead.
    public static func fireDate(setupEnds: Date, now: Date, outsideApp: Bool) -> Date? {
        guard outsideApp else { return nil }
        let fire = setupEnds - lead
        return fire > now ? fire : nil
    }

    /// Is the user outside SleepHole after this event? Leaving the app, using the phone outside it and closing the app
    /// say yes; coming back, a relaunch, the start of a night and the confirmation say no. A lock changes nothing:
    /// locked from inside the app he stays inside, locked with another app in front he stays outside.
    public static func outsideApp(after kind: NightEventKind, wasOutside: Bool) -> Bool {
        switch kind {
        case .leftApp, .usedLockScreen, .closedByOwner: true
        case .returned, .appLaunched, .started, .confirmed, .forgiven, .restartExcused: false
        default: wasOutside
        }
    }
}
