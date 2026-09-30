import Foundation

/// Afternoon rest ("Odpočinok", owner 2026-09-30). One per day, only inside the nap window, 30 or 60 min.
/// Same detection rules as a night (stay in the app, lock the phone), a short setup, an alarm at the end.
/// Pays a few coins; it never builds, never touches streaks or levels.
public struct NapPlan: Codable, Equatable, Sendable {
    public static let allowedMinutes = [30, 60]

    public var minutes: Int
    public var windowStart: TimeOfDay
    public var windowEnd: TimeOfDay

    public init(minutes: Int = 30, windowStart: TimeOfDay = TimeOfDay(13, 0), windowEnd: TimeOfDay = TimeOfDay(15, 0)) {
        self.minutes = NapPlan.allowedMinutes.contains(minutes) ? minutes : 30
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }

    public static let `default` = NapPlan()

    /// Detection rules for a nap: only 2 min to set up a story / sound.
    public static let rules: SleepRules = { var r = SleepRules(); r.setupGrace = 2 * 60; return r }()

    /// Today's window [start, end] around `t` (inclusive: starting exactly at the end is allowed).
    public func window(on t: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let day = calendar.startOfDay(for: t)
        func at(_ tod: TimeOfDay) -> Date {
            calendar.date(bySettingHour: tod.hour, minute: tod.minute, second: 0, of: day)!
        }
        return (at(windowStart), at(windowEnd))
    }

    public func canStart(at t: Date, calendar: Calendar) -> Bool {
        let w = window(on: t, calendar: calendar)
        return t >= w.start && t <= w.end
    }

    /// The nap as a session window: "bedtime" = start, "wake" = start + minutes; confirm only at the end.
    public func session(startingAt start: Date, calendar: Calendar) -> NightWindow {
        NightWindow(key: NightKey(date: start, calendar: calendar), bedtime: start,
                    wake: start + Double(minutes) * 60, earlyConfirmOverride: 0)
    }

    /// Coins for a nap (owner 2026-09-30: complete +50, cut short +25).
    public static func reward(_ outcome: Outcome) -> Int {
        switch outcome {
        case .complete: 50
        case .unfinished: 25
        case .ruins, .missed: 0
        }
    }
}
