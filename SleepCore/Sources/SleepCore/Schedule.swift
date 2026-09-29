import Foundation

/// A local wall-clock time ("22:30").
public struct TimeOfDay: Codable, Hashable, Sendable, CustomStringConvertible {
    public var hour: Int
    public var minute: Int
    public init(_ hour: Int, _ minute: Int) {
        precondition((0..<24).contains(hour) && (0..<60).contains(minute))
        self.hour = hour
        self.minute = minute
    }
    public var description: String { String(format: "%d:%02d", hour, minute) }
    var components: DateComponents { DateComponents(hour: hour, minute: minute) }
}

/// Identity of a night = the calendar date of its MORNING (the night 28→29 Sep is "2026-09-29").
public struct NightKey: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int, month: Int, day: Int
    public init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }

    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// "2026-09-29" – also the persisted form.
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public init?(_ string: String) {
        let p = string.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        self.init(year: p[0], month: p[1], day: p[2])
    }

    public static func < (a: NightKey, b: NightKey) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// Noon of that day – a DST-safe anchor for day arithmetic.
    func noon(_ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public func adding(days: Int, calendar: Calendar) -> NightKey {
        NightKey(date: calendar.date(byAdding: .day, value: days, to: noon(calendar))!, calendar: calendar)
    }
}

/// The owner's fixed daily schedule (decision D8).
public struct Schedule: Codable, Equatable, Sendable {
    public var bedtime: TimeOfDay
    public var wake: TimeOfDay
    /// Minutes before bedtime at which a reminder notification fires.
    public var reminderOffsets: [Int]

    public init(bedtime: TimeOfDay = TimeOfDay(22, 30), wake: TimeOfDay = TimeOfDay(6, 30),
                reminderOffsets: [Int] = [30]) {
        self.bedtime = bedtime
        self.wake = wake
        self.reminderOffsets = reminderOffsets
    }

    /// The night the owner is in, or heading into, at `t`.
    /// A night "belongs" to `t` until one hour after its wake time (the late-confirm window).
    public func window(containing t: Date, calendar: Calendar) -> NightWindow {
        let wakeDate = calendar.nextDate(after: t - NightWindow.lateConfirm, matching: wake.components,
                                         matchingPolicy: .nextTime, direction: .forward)!
        let bedDate = calendar.nextDate(after: wakeDate, matching: bedtime.components,
                                        matchingPolicy: .nextTime, direction: .backward)!
        return NightWindow(key: NightKey(date: wakeDate, calendar: calendar), bedtime: bedDate, wake: wakeDate)
    }

    /// The window of a specific night.
    public func window(for key: NightKey, calendar: Calendar) -> NightWindow {
        let dayStart = calendar.startOfDay(for: key.noon(calendar))
        return window(containing: dayStart, calendar: calendar)
    }
}

/// A concrete night with its derived time windows.
public struct NightWindow: Codable, Equatable, Sendable {
    public static let startLead: TimeInterval = 10 * 60           // "Začať stavbu" from bedtime − 10 min (owner, critical)
    public static let earlyConfirm: TimeInterval = 30 * 60        // "Vstal som" from wake − 30 min
    public static let onTimeConfirm: TimeInterval = 2 * 60        // on time only while the alarm rings (owner, = alarmDuration)
    public static let lateConfirm: TimeInterval = 60 * 60         // night is over at wake + 60 min

    public let key: NightKey
    public let bedtime: Date
    public let wake: Date

    public init(key: NightKey, bedtime: Date, wake: Date) {
        self.key = key
        self.bedtime = bedtime
        self.wake = wake
    }

    public var startOpens: Date { bedtime - Self.startLead }
    public var confirmOpens: Date { wake - Self.earlyConfirm }
    public var confirmOnTimeUntil: Date { wake + Self.onTimeConfirm }
    public var confirmLateUntil: Date { wake + Self.lateConfirm }
    public var duration: TimeInterval { wake.timeIntervalSince(bedtime) }
}
