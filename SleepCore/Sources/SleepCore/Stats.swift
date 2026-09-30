import Foundation

/// Numbers for the "Štatistiky" tab (plan §9, F4). Pure, derived from finalized real nights.
public struct StatsSummary: Equatable, Sendable {
    public let currentStreak: Int
    public let bestStreak: Int
    public let builtNights: Int
    public let completeNights: Int
    public let coins: Int
    public let maxLevel: Int
    /// Average start time (circular mean over the last `window` nights with a start).
    public let averageStart: TimeOfDay?
    /// Average "Vstal som" time.
    public let averageWake: TimeOfDay?
    /// Regularity = standard deviation of the start time in minutes (lower is better).
    public let regularityMinutes: Double?
    /// Last `calendarDays` nights (oldest first) with their outcome (nil = no record = missed).
    public let calendar: [CalendarDay]
    /// Per-night series for the chart (oldest first).
    public let series: [NightPoint]
}

public struct CalendarDay: Equatable, Sendable {
    public let key: NightKey
    public let outcome: Outcome?
}

public struct NightPoint: Equatable, Sendable {
    public let key: NightKey
    public let startMinutes: Double?     // minutes after 12:00 (so evenings/after-midnight are continuous)
    public let wakeMinutes: Double?      // minutes after 00:00
    public let outcome: Outcome
}

public enum Stats {
    public static func summary(_ results: [NightResult], today: NightKey, calendar: Calendar,
                               window: Int = 14, calendarDays: Int = 35, breaks: [NightKey] = []) -> StatsSummary {
        let sorted = results.sorted { $0.key < $1.key }
        let lastPossible = today.adding(days: -1, calendar: calendar)
        let last = max(sorted.last?.key ?? lastPossible, lastPossible)
        let built = Progression.builtNights(sorted)
        let recent = Array(sorted.suffix(window))
        let starts = recent.compactMap { $0.startedAt.map { minutesOfDay($0, calendar) } }
        let wakes = recent.compactMap { $0.confirmedAt.map { minutesOfDay($0, calendar) } }
        let byKey = Dictionary(sorted.map { ($0.key, $0.outcome) }, uniquingKeysWith: { _, b in b })
        let days = (0..<calendarDays).reversed().map { back -> CalendarDay in
            let k = last.adding(days: -back, calendar: calendar)
            return CalendarDay(key: k, outcome: byKey[k])
        }
        let series = sorted.suffix(30).map { r in
            NightPoint(key: r.key,
                       startMinutes: r.startedAt.map { (minutesOfDay($0, calendar) + 720).truncatingRemainder(dividingBy: 1440) },
                       wakeMinutes: r.confirmedAt.map { minutesOfDay($0, calendar) }, outcome: r.outcome)
        }
        return StatsSummary(
            currentStreak: Progression.currentStreak(sorted, lastNight: last, calendar: calendar, breaks: breaks),
            bestStreak: Progression.bestStreak(sorted, calendar: calendar, breaks: breaks),
            builtNights: built,
            completeNights: sorted.filter { $0.outcome == .complete }.count,
            coins: Economy.earned(sorted, calendar: calendar, breaks: breaks),
            maxLevel: Progression.unlockedMaxLevel(builtBefore: built),
            averageStart: circularMean(starts).map(timeOfDay),
            averageWake: circularMean(wakes).map(timeOfDay),
            regularityMinutes: circularStd(starts),
            calendar: days,
            series: Array(series))
    }

    static func minutesOfDay(_ d: Date, _ calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: d)
        return Double(c.hour! * 60 + c.minute!) + Double(c.second!) / 60
    }

    static func timeOfDay(_ minutes: Double) -> TimeOfDay {
        let m = Int(minutes.rounded()) % 1440
        return TimeOfDay(m / 60, m % 60)
    }

    /// Mean of clock times on the 24 h circle (23:50 and 00:10 average to 00:00, not 12:00).
    static func circularMean(_ minutes: [Double]) -> Double? {
        guard !minutes.isEmpty else { return nil }
        let a = minutes.map { $0 / 1440 * 2 * .pi }
        let s = a.map(sin).reduce(0, +), c = a.map(cos).reduce(0, +)
        let mean = atan2(s, c) / (2 * .pi) * 1440
        return mean < 0 ? mean + 1440 : mean
    }

    /// Standard deviation in minutes around the circular mean (needs ≥ 2 nights).
    static func circularStd(_ minutes: [Double]) -> Double? {
        guard minutes.count >= 2, let mean = circularMean(minutes) else { return nil }
        let d = minutes.map { m -> Double in
            var x = m - mean
            if x > 720 { x -= 1440 } else if x < -720 { x += 1440 }
            return x * x
        }
        return (d.reduce(0, +) / Double(minutes.count)).squareRoot()
    }
}
