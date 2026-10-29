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

    /// Coins for every calm hour of a complete or unfinished night (owner 2026-10-15, phase CARE-2a; `CalmHours`).
    public static let calmHourBonus = 5

    public struct Entry: Equatable, Sendable {
        public let key: NightKey
        public let outcome: Outcome
        public let coins: Int          // reward + bonuses
        public let streakBonus: Int
        /// +30 for a complete night without a pause (only nights played with the pause rules).
        public let undisturbedBonus: Int
        /// Calm hours of the night and their pay (+`calmHourBonus` each); 0 for nights from before build 8.
        public let calmHours: Int
        public let calmBonus: Int
        /// The building's pay alone (full for complete, half for unfinished), its level and the complete-night run
        /// at that night – what the receipt lists (11a).
        public let base: Int
        public let level: Int
        public let run: Int
        /// A lucky night ×2 from a box (11b3): the night's pay once more (base + streak + undisturbed + calm); 0 otherwise.
        public let luckyBonus: Int
    }

    /// The coin receipt of one night (11a): every part of the night's coins on its own line.
    public struct Receipt: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case building(level: Int)
            case unfinishedBuilding(level: Int)
            case withoutPause
            case calmHours(calm: Int, total: Int)
            case streak(run: Int)
            /// The night was doubled by a lucky night from a box (11b3).
            case luckyNight
            /// Coins that came from outside the ledger (achievements) – added by the app so the total adds up.
            case achievements
        }
        public struct Line: Equatable, Sendable {
            public let kind: Kind
            public let amount: Int
            public init(kind: Kind, amount: Int) { self.kind = kind; self.amount = amount }
        }
        public private(set) var lines: [Line]
        public var total: Int { lines.reduce(0) { $0 + $1.amount } }

        /// `calmTotal`: the night's whole hours (`NightResult.calmHoursTotal`). nil when the night paid nothing.
        public init?(_ entry: Entry, calmTotal: Int?) {
            guard entry.outcome == .complete || entry.outcome == .unfinished, entry.base > 0 else { return nil }
            var l: [Line] = [Line(kind: entry.outcome == .complete ? .building(level: entry.level)
                                                                  : .unfinishedBuilding(level: entry.level),
                                  amount: entry.base)]
            if entry.undisturbedBonus > 0 { l.append(Line(kind: .withoutPause, amount: entry.undisturbedBonus)) }
            if entry.calmBonus > 0, entry.calmHours > 0 {
                l.append(Line(kind: .calmHours(calm: entry.calmHours, total: max(calmTotal ?? entry.calmHours, entry.calmHours)),
                              amount: entry.calmBonus))
            }
            if entry.streakBonus > 0 { l.append(Line(kind: .streak(run: entry.run), amount: entry.streakBonus)) }
            if entry.luckyBonus > 0 { l.append(Line(kind: .luckyNight, amount: entry.luckyBonus)) }
            lines = l
        }

        public init(lines: [Line]) { self.lines = lines }

        /// A copy with extra coins from outside the ledger (achievements) as the last line.
        public func addingAchievements(_ amount: Int) -> Receipt {
            var r = self
            if amount > 0 { r.lines.append(Line(kind: .achievements, amount: amount)) }
            return r
        }
    }

    /// One entry per result in chronological order, with the streak bonus where it was earned.
    /// Streak semantics as in `Progression`: complete +1, unfinished neutral, ruins/missed/gaps break.
    /// `breaks`: nights that start a new streak (a paid schedule change).
    public static func ledger(_ results: [NightResult], calendar: Calendar, breaks: [NightKey] = [],
                              catalog: Catalog? = nil, boxes: [BoxPurchase] = []) -> [Entry] {
        var out: [Entry] = []
        // Each lucky night box doubles the first complete night AFTER its own night key that no earlier lucky box has
        // doubled (FIFO); other nights leave it waiting. Derived from the records – no counter is stored.
        let lucky = boxes.filter { $0.prize == .luckyNight }.sorted { ($0.nightKey, $0.at, $0.id) < ($1.nightKey, $1.at, $1.id) }
        var luckyUsed = 0
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
            let calmHours = r.outcome.isBuildNight ? r.calmHours ?? 0 : 0
            let calmBonus = calmHours * calmHourBonus
            let lvl = level(of: r, catalog: catalog)
            let base = reward(r.outcome, level: lvl)
            var lucky2 = 0
            if r.outcome == .complete, luckyUsed < lucky.count, lucky[luckyUsed].nightKey < r.key {
                lucky2 = base + bonus + undisturbed + calmBonus
                luckyUsed += 1
            }
            let coins = base + bonus + undisturbed + calmBonus + lucky2
            out.append(Entry(key: r.key, outcome: r.outcome, coins: coins, streakBonus: bonus,
                             undisturbedBonus: undisturbed, calmHours: calmHours, calmBonus: calmBonus,
                             base: base, level: lvl, run: run, luckyBonus: lucky2))
            prev = r.key
        }
        return out
    }

    public static func earned(_ results: [NightResult], calendar: Calendar, breaks: [NightKey] = [],
                              catalog: Catalog? = nil, boxes: [BoxPurchase] = []) -> Int {
        ledger(results, calendar: calendar, breaks: breaks, catalog: catalog, boxes: boxes).reduce(0) { $0 + $1.coins }
    }
}
