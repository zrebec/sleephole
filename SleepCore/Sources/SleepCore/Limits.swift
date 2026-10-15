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

/// Changing the sleep schedule (bedtime + wake) – the "change week" (owner 2026-10-15, build 8; it replaced the free
/// days 1–3 of a month and the streak reset of 2026-09-30).
///
/// * `open` – nothing is running; the next change OPENS a change week (the app asks first).
/// * `changeWeek` – 7 calendar days, the day of the first change is day 1; any number of changes, free.
/// * `locked` – from the day after the week for one calendar month; the schedule stays. A paid early unlock
///   (`unlockPrice`) opens a new change week today. From `freeFrom` on the state is `open` again – nothing opens by
///   itself.
///
/// The state is derived from ONE stored date (when the last change week was opened) – no timers. A change never
/// touches the 🔥 streak any more. Only bedtime and wake follow this; the reminder, the nap window, the sounds stay free.
public enum SchedulePolicy {
    public static let weekDays = 7
    public static let unlockPrice = 2000

    public enum State: Equatable, Sendable {
        case open
        /// `lastDay`: the last day of the week (inclusive).
        case changeWeek(lastDay: NightKey)
        /// `lastDay`: the last day the schedule is locked (the day before `freeFrom`).
        case locked(lastDay: NightKey, freeFrom: NightKey)
    }

    /// The days of a change week opened on `day`.
    public struct Plan: Equatable, Sendable {
        public let lastDay: NightKey        // the last day of the change week
        public let lockLastDay: NightKey    // the last day of the lock that follows
        public let freeFrom: NightKey       // the first day a new change week can be opened for free
    }

    /// 16 Dec → week until 22 Dec, locked 23 Dec – 22 Jan, free from 23 Jan. The month is added to the first day of the
    /// lock and clamped by the calendar (a lock starting 31 Jan is free from 28 / 29 Feb).
    public static func plan(opening day: Date, calendar: Calendar) -> Plan {
        let first = NightKey(date: day, calendar: calendar)
        let last = first.adding(days: weekDays - 1, calendar: calendar)
        let lockFirst = last.adding(days: 1, calendar: calendar)
        let free = NightKey(date: calendar.date(byAdding: .month, value: 1, to: lockFirst.noon(calendar))!, calendar: calendar)
        return Plan(lastDay: last, lockLastDay: free.adding(days: -1, calendar: calendar), freeFrom: free)
    }

    /// - Parameter weekStart: when the last change week was opened; nil = never (everyone starts `open`; a week opened
    ///   under the old rule is not stored in this field).
    public static func state(at now: Date, weekStart: Date?, calendar: Calendar) -> State {
        guard let weekStart else { return .open }
        let plan = plan(opening: weekStart, calendar: calendar)
        let today = NightKey(date: now, calendar: calendar)
        if today <= plan.lastDay { return .changeWeek(lastDay: plan.lastDay) }
        if today < plan.freeFrom { return .locked(lastDay: plan.lockLastDay, freeFrom: plan.freeFrom) }
        return .open
    }

    /// May the bedtime / wake be changed in this state? (`open` opens a week, `changeWeek` is free, `locked` refuses.)
    public static func allowsChange(_ state: State) -> Bool {
        if case .locked = state { return false }
        return true
    }

    /// The paid early unlock: only while locked, only with enough coins (coins never go negative).
    public enum Unlock: Equatable, Sendable {
        case notLocked
        case notEnoughCoins(missing: Int)
        case ok
    }

    public static func unlock(state: State, coins: Int) -> Unlock {
        guard case .locked = state else { return .notLocked }
        return coins >= unlockPrice ? .ok : .notEnoughCoins(missing: unlockPrice - coins)
    }

    /// The first day after a lock that has ended (state `open` while a week start is stored): the day of the
    /// "you can open a change week again" card and its notification. nil while a week or a lock is running or when
    /// no week was ever opened.
    public static func lockEnded(at now: Date, weekStart: Date?, calendar: Calendar) -> NightKey? {
        guard let weekStart, state(at: now, weekStart: weekStart, calendar: calendar) == .open else { return nil }
        return plan(opening: weekStart, calendar: calendar).freeFrom
    }

    // MARK: the evening rule

    /// A change of the bedtime / wake saved at `now`: nil = it applies at once; a night key = it applies from that
    /// night on (the tonight's building may already be started, so tonight keeps the schedule in effect).
    /// "Tonight's night" is the night `current` puts `now` in (`Schedule.window(containing:)`: the coming one in the
    /// evening and during the day, the one in progress after midnight until one hour after its wake time). It can be
    /// started from `earlyStartOpens` (bedtime − 3 h) – under the current OR the new times, whichever is earlier; from
    /// then on the new times wait for the night after it. After midnight (before the morning is over) tonight's night
    /// is the one that began the evening before, so the new times apply from the night after it, i.e. from the
    /// coming evening.
    public static func startsFrom(changedAt now: Date, current: Schedule, new: Schedule, calendar: Calendar) -> NightKey? {
        let key = current.window(containing: now, calendar: calendar).key
        let earliest = min(current.window(for: key, calendar: calendar).earlyStartOpens,
                           new.window(for: key, calendar: calendar).earlyStartOpens)
        return now >= earliest ? key.adding(days: 1, calendar: calendar) : nil
    }
}

/// New bedtime / wake times that wait for a night (the evening rule of `SchedulePolicy.startsFrom`).
public struct PendingSchedule: Codable, Equatable, Sendable {
    public var schedule: Schedule
    /// The first night that uses `schedule`.
    public var fromNight: NightKey

    public init(schedule: Schedule, fromNight: NightKey) {
        self.schedule = schedule
        self.fromNight = fromNight
    }

    /// The night `current` puts `now` in has reached `fromNight`: the new times are in effect from now on.
    public func isDue(at now: Date, current: Schedule, calendar: Calendar) -> Bool {
        current.window(containing: now, calendar: calendar).key >= fromNight
    }
}
