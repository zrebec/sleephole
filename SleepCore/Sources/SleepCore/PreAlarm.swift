import Foundation

/// W7 (build 14b1): a silent AlarmKit "pre-alarm" shortly before the wake time, so that an Apple Watch buzzes before
/// SleepHole's own alarm. It is a third alarm next to the backup and the lock-screen warning, plays digital silence and
/// is ended the moment our alarm starts. In build 14b1 it exists only in Developer test nights (a measurement).
public enum PreAlarmPlan {
    /// The pre-alarm fires this long before the wake time (owner 2026-11-26: 30 s).
    public static let lead: TimeInterval = 30
    /// AlarmKit refuses dates that are too close: the fire date must lie more than this far ahead of `now`.
    public static let minimumAhead: TimeInterval = 3

    /// When the pre-alarm fires, nil = none (a nap, switched off, or `wake − lead` is not more than `minimumAhead` ahead).
    public static func fireDate(wake: Date, now: Date, isNap: Bool, enabled: Bool) -> Date? {
        guard enabled, !isNap else { return nil }
        let at = wake - lead
        return at > now + minimumAhead ? at : nil
    }

    /// The pre-alarm's job is done at the wake time (our own alarm starts then).
    public static func shouldEnd(now: Date, wake: Date) -> Bool { now >= wake }

    /// A keep-alive background task starts here (shortly before the pre-alarm fires): the alert takes our audio session
    /// away and iOS would suspend the app, so our own alarm at the wake time could come late (B28).
    public static func keepAliveFrom(wake: Date) -> Date { wake - lead - minimumAhead }
}
