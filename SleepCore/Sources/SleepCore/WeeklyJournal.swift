import Foundation

/// One week (Monday–Sunday evenings) of the "town journal" (owner 2026-09-30, idea M).
/// A night belongs to the week of its EVENING (key − 1 day), so the night Sunday → Monday closes the week and
/// Monday morning's "I'm up" can show the finished week. Naps belong to their own day.
public struct WeekSummary: Equatable, Sendable {
    /// The Monday the week starts on (an evening date).
    public let monday: NightKey
    public let complete: Int
    public let unfinished: Int
    public let ruins: Int
    /// Buildings added this week (complete + unfinished nights), in order.
    public let buildingIds: [String]
    /// Coins from this week's nights (incl. streak bonuses) and naps.
    public let coins: Int
    public let averageStart: TimeOfDay?
    public let averageWake: TimeOfDay?
    /// Longest run of complete nights inside the week.
    public let bestStreak: Int
    public let completeNaps: Int

    public var nights: Int { complete + unfinished + ruins }
    public var built: Int { complete + unfinished }
    public var sunday: NightKey { monday.adding(days: 6, calendar: Calendar(identifier: .gregorian)) }
}

public enum WeeklyJournal {
    /// The evening a night started on.
    public static func evening(of key: NightKey, calendar: Calendar) -> NightKey { key.adding(days: -1, calendar: calendar) }

    /// Monday of the week that contains `day`.
    public static func monday(of day: NightKey, calendar: Calendar) -> NightKey {
        let weekday = calendar.component(.weekday, from: day.noon(calendar))       // 1 = Sunday … 7 = Saturday
        return day.adding(days: -((weekday + 5) % 7), calendar: calendar)
    }

    /// All weeks with at least one night or nap, newest first.
    public static func weeks(results: [NightResult], naps: [NightResult] = [], calendar: Calendar) -> [WeekSummary] {
        let ledger = Economy.ledger(results, calendar: calendar)
        var mondays = Set(results.map { monday(of: evening(of: $0.key, calendar: calendar), calendar: calendar) })
        mondays.formUnion(naps.map { monday(of: $0.key, calendar: calendar) })
        return mondays.sorted(by: >).map { m in
            summary(monday: m, results: results, ledger: ledger, naps: naps, calendar: calendar)
        }
    }

    /// One week (may be empty).
    public static func week(monday: NightKey, results: [NightResult], naps: [NightResult] = [],
                            calendar: Calendar) -> WeekSummary {
        summary(monday: monday, results: results, ledger: Economy.ledger(results, calendar: calendar), naps: naps,
                calendar: calendar)
    }

    private static func summary(monday m: NightKey, results: [NightResult], ledger: [Economy.Entry],
                                naps: [NightResult], calendar: Calendar) -> WeekSummary {
        let sunday = m.adding(days: 6, calendar: calendar)
        let inWeek = { (key: NightKey) in key >= m && key <= sunday }
        let nights = results.filter { inWeek(evening(of: $0.key, calendar: calendar)) }.sorted { $0.key < $1.key }
        let weekNaps = naps.filter { inWeek($0.key) }
        let keys = Set(nights.map(\.key))
        var best = 0, run = 0
        var prev: NightKey?
        for r in nights {
            if let p = prev, r.key != p.adding(days: 1, calendar: calendar) { run = 0 }
            prev = r.key
            switch r.outcome {
            case .complete: run += 1; best = max(best, run)
            case .unfinished: break
            case .ruins, .missed: run = 0
            }
        }
        let starts = nights.compactMap { $0.startedAt.map { Stats.minutesOfDay($0, calendar) } }
        let wakes = nights.compactMap { $0.confirmedAt.map { Stats.minutesOfDay($0, calendar) } }
        return WeekSummary(
            monday: m,
            complete: nights.filter { $0.outcome == .complete }.count,
            unfinished: nights.filter { $0.outcome == .unfinished }.count,
            ruins: nights.filter { $0.outcome == .ruins || $0.outcome == .missed }.count,
            buildingIds: nights.filter { $0.outcome.isBuildNight }.compactMap(\.buildingId),
            coins: ledger.filter { keys.contains($0.key) }.reduce(0) { $0 + $1.coins }
                + weekNaps.reduce(0) { $0 + NapPlan.reward($1.outcome) },
            averageStart: Stats.circularMean(starts).map(Stats.timeOfDay),
            averageWake: Stats.circularMean(wakes).map(Stats.timeOfDay),
            bestStreak: best,
            completeNaps: weekNaps.filter { $0.outcome == .complete }.count)
    }

    /// The finished week to celebrate on the result screen of the night `key`, if this is the first result
    /// after that week ended: the night Sunday → Monday shows its own week; if that night was skipped, the
    /// next result shows the week before. `previous` = the key of the real night finalized before this one.
    public static func finishedWeek(after key: NightKey, previous: NightKey?, calendar: Calendar) -> NightKey? {
        let eve = evening(of: key, calendar: calendar)
        let thisMonday = monday(of: eve, calendar: calendar)
        let isSunday = eve == thisMonday.adding(days: 6, calendar: calendar)
        let finished = isSunday ? thisMonday : thisMonday.adding(days: -7, calendar: calendar)
        guard let previous else { return isSunday ? finished : nil }
        // the first result on or after that Sunday evening (the week was not shown yet)
        return evening(of: previous, calendar: calendar) < finished.adding(days: 6, calendar: calendar) ? finished : nil
    }
}
