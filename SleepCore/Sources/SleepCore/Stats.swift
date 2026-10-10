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
    /// Average time of falling asleep (Apple Health; circular mean over the same nights, only those with a value).
    public let averageFellAsleep: TimeOfDay?
    /// Average minutes from the build start to falling asleep (nights with both values; negative counts as 0).
    public let averageMinutesToSleep: Double?
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
    public let asleepMinutes: Double?    // fell asleep, on the same axis as `startMinutes` (minutes after 12:00)
    public let outcome: Outcome

    public init(key: NightKey, startMinutes: Double?, wakeMinutes: Double?, asleepMinutes: Double?, outcome: Outcome) {
        self.key = key
        self.startMinutes = startMinutes
        self.wakeMinutes = wakeMinutes
        self.asleepMinutes = asleepMinutes
        self.outcome = outcome
    }
}

public enum Stats {
    public static func summary(_ results: [NightResult], today: NightKey, calendar: Calendar,
                               window: Int = 14, calendarDays: Int = 35, breaks: [NightKey] = [],
                               catalog: Catalog? = nil) -> StatsSummary {
        let sorted = results.sorted { $0.key < $1.key }
        let lastPossible = today.adding(days: -1, calendar: calendar)
        let last = max(sorted.last?.key ?? lastPossible, lastPossible)
        let built = Progression.builtNights(sorted)
        let recent = Array(sorted.suffix(window))
        let starts = recent.compactMap { $0.startedAt.map { minutesOfDay($0, calendar) } }
        let wakes = recent.compactMap { $0.confirmedAt.map { minutesOfDay($0, calendar) } }
        let fells = recent.compactMap { $0.fellAsleepAt.map { minutesOfDay($0, calendar) } }
        let toSleep = recent.compactMap { r in
            r.fellAsleepAt.flatMap { f in r.startedAt.map { max(0, f.timeIntervalSince($0) / 60) } }
        }
        let byKey = Dictionary(sorted.map { ($0.key, $0.outcome) }, uniquingKeysWith: { _, b in b })
        let days = (0..<calendarDays).reversed().map { back -> CalendarDay in
            let k = last.adding(days: -back, calendar: calendar)
            return CalendarDay(key: k, outcome: byKey[k])
        }
        let series = sorted.suffix(30).map { r in
            NightPoint(key: r.key,
                       startMinutes: r.startedAt.map { (minutesOfDay($0, calendar) + 720).truncatingRemainder(dividingBy: 1440) },
                       wakeMinutes: r.confirmedAt.map { minutesOfDay($0, calendar) },
                       asleepMinutes: r.fellAsleepAt.map { (minutesOfDay($0, calendar) + 720).truncatingRemainder(dividingBy: 1440) },
                       outcome: r.outcome)
        }
        return StatsSummary(
            currentStreak: Progression.currentStreak(sorted, lastNight: last, calendar: calendar, breaks: breaks),
            bestStreak: Progression.bestStreak(sorted, calendar: calendar, breaks: breaks),
            builtNights: built,
            completeNights: sorted.filter { $0.outcome == .complete }.count,
            coins: Economy.earned(sorted, calendar: calendar, breaks: breaks, catalog: catalog),
            maxLevel: Progression.unlockedMaxLevel(builtBefore: built),
            averageStart: circularMean(starts).map(timeOfDay),
            averageWake: circularMean(wakes).map(timeOfDay),
            regularityMinutes: regularity(recent, calendar: calendar),
            averageFellAsleep: circularMean(fells).map(timeOfDay),
            averageMinutesToSleep: toSleep.isEmpty ? nil : toSleep.reduce(0, +) / Double(toSleep.count),
            calendar: days,
            series: Array(series))
    }

    /// How regular the build starts are: the standard deviation, in minutes, of "start − that night's bedtime"
    /// (2026-10-03: moving the bedtime by half an hour looked like ±13 min although every start was
    /// within 3 min of its bedtime). Nights without a stored bedtime fall back to the spread of clock times.
    static func regularity(_ results: [NightResult], calendar: Calendar) -> Double? {
        let offsets = results.compactMap { r in
            r.startedAt.flatMap { start in r.bedtime.map { start.timeIntervalSince($0) / 60 } }
        }
        let started = results.filter { $0.startedAt != nil }.count
        guard offsets.count == started else {
            return circularStd(results.compactMap { $0.startedAt.map { minutesOfDay($0, calendar) } })
        }
        guard offsets.count >= 2 else { return nil }
        let mean = offsets.reduce(0, +) / Double(offsets.count)
        return (offsets.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(offsets.count)).squareRoot()
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
