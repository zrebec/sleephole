import Foundation

/// Calm hours (phase CARE-2a, owner 2026-10-15): every whole hour of the night in which the owner stayed with the app
/// pays `Economy.calmHourBonus`. Hours run from `anchor = max(bedtime + normal setup, end of the setup)` to the wake time; a
/// last partial hour does not count, and an early start never earns more than a normal one (the anchor is never before
/// bedtime + `rules.setupGrace`, so an early and a normal start with the same bedtime count the same hours).
public enum CalmHours {
    /// Marker stored on a night that starts under this rule (`NightRecord.calmHoursRule`). nil = an older night → no calm hours.
    public static let currentRule = 1

    public struct Count: Equatable, Sendable {
        public let calm: Int
        public let total: Int
        public init(calm: Int, total: Int) { self.calm = calm; self.total = total }
    }

    /// The whole hours of the night as `[start, end)` pairs, from `max(bedtime + rules.setupGrace, setup end)`.
    public static func hours(of log: NightLog, rules: SleepRules = SleepRules()) -> [(Date, Date)] {
        guard let start = log.startedAt else { return [] }
        let anchor = max(log.window.bedtime + rules.setupGrace, log.window.setupEnds(start: start, rules: rules))
        var out: [(Date, Date)] = []
        var n = 0.0
        while anchor + (n + 1) * 3600 <= log.window.wake {
            out.append((anchor + n * 3600, anchor + (n + 1) * 3600))
            n += 1
        }
        return out
    }

    /// An hour is spoiled by: a trip out of the app (the evaluator's away intervals – calls are excused there, a closed
    /// app counts until it is opened again), a `.usedLockScreen` event inside it (also in gentle mode), or a pause
    /// overlapping it. A glance with Face ID, the screen lighting up and a call spoil nothing.
    public static func count(log: NightLog, rules: SleepRules = SleepRules()) -> Count {
        let hours = hours(of: log, rules: rules)
        var spoilers = NightEvaluator.awayIntervals(log, rules: rules) + log.pauseIntervals
        let lockUse = log.sortedEvents.filter { $0.kind == .usedLockScreen }.map(\.at)
        spoilers = spoilers.filter { $0.0 < $0.1 }
        let calm = hours.filter { h in
            !spoilers.contains { $0.0 < h.1 && $0.1 > h.0 } && !lockUse.contains { $0 >= h.0 && $0 < h.1 }
        }.count
        return Count(calm: calm, total: hours.count)
    }
}
