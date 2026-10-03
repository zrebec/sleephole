import Foundation

/// Coins 🪙 (owner, 2026-09-30). Earned by nights; spent on buildings later (prices per level).
/// Like the town, the balance is not stored – it is replayed from the finalized real nights.
public enum Economy {
    /// Coins for a complete night by the level of its building (owner 2026-10-02: higher levels pay more, so
    /// developing them is worth more than spending on night pauses). Unfinished = half.
    public static func completeReward(level: Int) -> Int {
        switch level {
        case ...1: 100
        case 2: 120
        case 3: 150
        default: 200
        }
    }

    /// Coins for a night by outcome and building level.
    public static func reward(_ outcome: Outcome, level: Int = 1) -> Int {
        switch outcome {
        case .complete: completeReward(level: level)
        case .unfinished: completeReward(level: level) / 2
        case .ruins, .missed, .excused: 0
        }
    }

    /// Level of a night's building (lit streets and parks are level 2; unknown → 1).
    public static func level(of result: NightResult, catalog: Catalog?) -> Int {
        result.buildingId.flatMap { catalog?[$0]?.level } ?? 1
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
        public let coins: Int          // reward + bonuses
        public let streakBonus: Int
        /// +30 for a complete night without a pause (only nights played with the pause rules).
        public let undisturbedBonus: Int
    }

    /// One entry per result in chronological order, with the streak bonus where it was earned.
    /// Streak semantics as in `Progression`: complete +1, unfinished neutral, ruins/missed/gaps break.
    /// `breaks`: nights that start a new streak (a paid schedule change).
    public static func ledger(_ results: [NightResult], calendar: Calendar, breaks: [NightKey] = [],
                              catalog: Catalog? = nil) -> [Entry] {
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
            case .unfinished, .excused: break
            case .ruins, .missed: run = 0
            }
            let undisturbed = r.outcome == .complete && r.pauses == 0 ? PausePolicy.undisturbedBonus : 0
            let coins = reward(r.outcome, level: level(of: r, catalog: catalog)) + bonus + undisturbed
            out.append(Entry(key: r.key, outcome: r.outcome, coins: coins, streakBonus: bonus,
                             undisturbedBonus: undisturbed))
            prev = r.key
        }
        return out
    }

    public static func earned(_ results: [NightResult], calendar: Calendar, breaks: [NightKey] = [],
                              catalog: Catalog? = nil) -> Int {
        ledger(results, calendar: calendar, breaks: breaks, catalog: catalog).reduce(0) { $0 + $1.coins }
    }
}
