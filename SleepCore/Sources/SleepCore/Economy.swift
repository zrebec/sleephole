import Foundation

/// Coins 🪙 (owner, 2026-09-30). Earned by nights; spent on buildings later (prices per level).
/// Like the town, the balance is not stored – it is replayed from the finalized real nights.
public enum Economy {
    /// Coins for a night by outcome.
    public static func reward(_ outcome: Outcome) -> Int {
        switch outcome {
        case .complete: 100
        case .unfinished: 50
        case .ruins, .missed: 0
        }
    }

    /// Every 7th complete night in a row adds a bonus.
    public static let streakBonusEvery = 7
    public static let streakBonus = 200

    /// Building prices by level (for the upcoming shop): a house 100, L2 200, L3 400, L4 1000.
    public static func price(level: Int) -> Int {
        switch level {
        case ...1: 100
        case 2: 200
        case 3: 400
        default: 1000
        }
    }

    public struct Entry: Equatable, Sendable {
        public let key: NightKey
        public let outcome: Outcome
        public let coins: Int          // reward + bonus
        public let streakBonus: Int
    }

    /// One entry per result in chronological order, with the streak bonus where it was earned.
    /// Streak semantics as in `Progression`: complete +1, unfinished neutral, ruins/missed/gaps break.
    /// `breaks`: nights that start a new streak (a paid schedule change).
    public static func ledger(_ results: [NightResult], calendar: Calendar, breaks: [NightKey] = []) -> [Entry] {
        var out: [Entry] = []
        var run = 0
        var prev: NightKey?
        for r in results.sorted(by: { $0.key < $1.key }) {
            if let p = prev, r.key != p, r.key != p.adding(days: 1, calendar: calendar) { run = 0 }   // a gap
            if let p = prev, breaks.contains(where: { p < $0 && $0 <= r.key }) { run = 0 }         // a schedule change
            var bonus = 0
            switch r.outcome {
            case .complete:
                run += 1
                if run % streakBonusEvery == 0 { bonus = streakBonus }
            case .unfinished: break
            case .ruins, .missed: run = 0
            }
            out.append(Entry(key: r.key, outcome: r.outcome, coins: reward(r.outcome) + bonus, streakBonus: bonus))
            prev = r.key
        }
        return out
    }

    public static func earned(_ results: [NightResult], calendar: Calendar, breaks: [NightKey] = []) -> Int {
        ledger(results, calendar: calendar, breaks: breaks).reduce(0) { $0 + $1.coins }
    }
}
