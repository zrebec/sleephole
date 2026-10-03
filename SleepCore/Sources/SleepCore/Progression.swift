import Foundation

/// Level unlocks (owner decision D13) and streaks (plan §5.5).
public enum Progression {
    /// (built nights needed BEFORE tonight, highest unlocked level)
    /// nights 1–5 → L1 · 6–15 → L1–2 · 16–30 → L1–3 · 31+ → L1–4 (everything)
    public static let thresholds: [(minBuilt: Int, maxLevel: Int)] = [(0, 1), (5, 2), (15, 3), (30, 4)]

    public static func builtNights(_ results: [NightResult]) -> Int {
        results.filter { $0.outcome.isBuildNight }.count
    }

    /// Highest level that can be built tonight, given how many build nights happened before it.
    public static func unlockedMaxLevel(builtBefore n: Int) -> Int {
        thresholds.last { n >= $0.minBuilt }!.maxLevel
    }

    /// Build nights still needed to unlock the next level, nil when everything is unlocked.
    public static func nightsToNextLevel(built n: Int) -> (level: Int, nights: Int)? {
        thresholds.first { $0.minBuilt > n }.map { ($0.maxLevel, $0.minBuilt - n) }
    }

    /// The level unlocked by going from `before` to `after` build nights, if any (→ level-up banner).
    public static func levelUp(builtBefore before: Int, builtAfter after: Int) -> Int? {
        let a = unlockedMaxLevel(builtBefore: before), b = unlockedMaxLevel(builtBefore: after)
        return b > a ? b : nil
    }

    /// Consecutive nights ending `.complete`, counted backwards from `lastNight`.
    /// `.unfinished` neither extends nor breaks the streak (gentle); `.ruins`, `.missed` and nights
    /// without any result break it. `breaks`: nights that start a new streak (a paid schedule change,
    /// `SchedulePolicy.streakBreak`) – older nights don't count.
    public static func currentStreak(_ results: [NightResult], lastNight: NightKey, calendar: Calendar,
                                     breaks: [NightKey] = []) -> Int {
        let byKey = Dictionary(results.map { ($0.key, $0.outcome) }, uniquingKeysWith: { _, b in b })
        var streak = 0
        var key = lastNight
        let first = results.map(\.key).min() ?? lastNight
        // a break for tonight (a change made after the last night) shows 0 at once, not only tomorrow
        let horizon = lastNight.adding(days: 1, calendar: calendar)
        let earliest = max(first, breaks.filter { $0 <= horizon }.max() ?? first)
        while key >= earliest {
            switch byKey[key] {
            case .complete: streak += 1
            case .unfinished, .excused: break
            default: return streak
            }
            key = key.adding(days: -1, calendar: calendar)
        }
        return streak
    }

    public static func bestStreak(_ results: [NightResult], calendar: Calendar, breaks: [NightKey] = []) -> Int {
        guard let first = results.map(\.key).min(), let last = results.map(\.key).max() else { return 0 }
        let byKey = Dictionary(results.map { ($0.key, $0.outcome) }, uniquingKeysWith: { _, b in b })
        let breakSet = Set(breaks)
        var best = 0, run = 0
        var key = first
        while key <= last {
            if breakSet.contains(key) { run = 0 }
            switch byKey[key] {
            case .complete: run += 1; best = max(best, run)
            case .unfinished, .excused: break
            default: run = 0
            }
            key = key.adding(days: 1, calendar: calendar)
        }
        return best
    }
}
