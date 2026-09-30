import Foundation

/// Renaming the town (owner 2026-09-30): the first naming is free, a typo can be fixed for free within 10 minutes,
/// one rename every 365 days is free, anything else costs 5 000 🪙.
public enum RenamePolicy {
    public static let price = 5000
    public static let freeEvery: TimeInterval = 365 * 24 * 3600
    public static let typoWindow: TimeInterval = 10 * 60

    public enum Cost: Equatable, Sendable {
        case free(FreeReason)
        case paid(Int)

        public var coins: Int { if case .paid(let c) = self { c } else { 0 } }
    }

    public enum FreeReason: Equatable, Sendable {
        case firstNaming    // from the default name to your own – never counted
        case typoFix        // within 10 min of the last counted rename – does not move the anchor
        case yearly         // the free rename of the year – starts the next 365 days
    }

    /// - Parameters:
    ///   - lastRenameAt: the last counted rename (not a typo fix); nil = never renamed
    ///   - lastFreeRenameAt: the last *yearly* free rename; nil = the yearly one is available
    ///   - hasCustomName: the town already has its own name (older app versions stored it without dates)
    public static func cost(at now: Date, hasCustomName: Bool, lastRenameAt: Date?, lastFreeRenameAt: Date?) -> Cost {
        if !hasCustomName && lastRenameAt == nil { return .free(.firstNaming) }
        if let last = lastRenameAt, now >= last, now < last + typoWindow { return .free(.typoFix) }
        if let free = lastFreeRenameAt, now < free + freeEvery { return .paid(price) }
        return .free(.yearly)
    }

    /// When the yearly free rename is available again (nil = now).
    public static func nextFree(after now: Date, lastFreeRenameAt: Date?) -> Date? {
        guard let free = lastFreeRenameAt, now < free + freeEvery else { return nil }
        return free + freeEvery
    }
}

/// Changing the sleep schedule (bedtime + wake, owner 2026-09-30): free on days 1–3 of every month (the app asks)
/// and during the first 7 days; otherwise the change resets the 🔥 streak (nothing else is taken away).
public enum SchedulePolicy {
    public static let freeDays = 1...3
    public static let calibration: TimeInterval = 7 * 24 * 3600

    public enum Change: Equatable, Sendable {
        case free(FreeReason)
        case resetsStreak
    }

    public enum FreeReason: Equatable, Sendable {
        case monthStart     // days 1–3 of the month
        case calibration    // the first 7 days
    }

    public static func change(at now: Date, calibrationStart: Date?, calendar: Calendar) -> Change {
        if freeDays.contains(calendar.component(.day, from: now)) { return .free(.monthStart) }
        if let start = calibrationStart, now < start + calibration { return .free(.calibration) }
        return .resetsStreak
    }

    /// The end of the free calibration week (nil when it is over).
    public static func calibrationEnds(after now: Date, calibrationStart: Date?) -> Date? {
        guard let start = calibrationStart, now < start + calibration else { return nil }
        return start + calibration
    }

    /// The start of the next free window (day 1 of the next month), or `now` while in a free window.
    public static func nextFreeWindow(after now: Date, calibrationStart: Date?, calendar: Calendar) -> Date {
        if case .free = change(at: now, calibrationStart: calibrationStart, calendar: calendar) { return now }
        let month = calendar.dateInterval(of: .month, for: now)!
        return month.end
    }

    /// The first night that starts a new streak after a streak-resetting change at `date`: tonight's night
    /// (its key is tomorrow's date). Earlier nights stay in the history but no longer count for the streak.
    public static func streakBreak(changedAt date: Date, calendar: Calendar) -> NightKey {
        NightKey(date: date, calendar: calendar).adding(days: 1, calendar: calendar)
    }
}
