import Foundation

/// Jokers 🛡️ (owner 2026-10-02): protect the 🔥 streak when you are ill or on holiday. Each kind (bronze, silver, gold)
/// once per calendar month, independently of the others. A protected night that was missed or ruined becomes `.excused` – the streak neither grows nor
/// breaks, no building, no coins. A good night inside a joker still counts normally.
public enum JokerTier: String, Codable, CaseIterable, Sendable {
    case bronze, silver, gold

    public var nights: Int {
        switch self {
        case .bronze: 1
        case .silver: 3
        case .gold: 7
        }
    }

    public var price: Int {
        switch self {
        case .bronze: 0
        case .silver: 1000
        case .gold: 5000
        }
    }
}

public struct JokerUse: Equatable, Sendable {
    public let tier: JokerTier
    public let firstNight: NightKey
    /// The bronze joker is used by itself on the first missed night of a month that would break a streak
    /// (like Duolingo's streak freeze) – a sick person should not have to remember it.
    public let automatic: Bool

    public init(tier: JokerTier, firstNight: NightKey, automatic: Bool = false) {
        self.tier = tier
        self.firstNight = firstNight
        self.automatic = automatic
    }

    public func lastNight(calendar: Calendar) -> NightKey { firstNight.adding(days: tier.nights - 1, calendar: calendar) }

    public func covers(_ key: NightKey, calendar: Calendar) -> Bool {
        key >= firstNight && key <= lastNight(calendar: calendar)
    }

    /// The calendar month the joker belongs to (the month of its first night).
    public var month: Month { Month(year: firstNight.year, month: firstNight.month) }
}

public struct Month: Hashable, Sendable {
    public let year: Int, month: Int
    public init(year: Int, month: Int) { self.year = year; self.month = month }
    public init(_ key: NightKey) { self.init(year: key.year, month: key.month) }
}

public enum Jokers {
    /// The results with every protected night turned into `.excused`, and all jokers in effect (the manual ones
    /// + the automatic bronze ones), oldest first.
    /// - Parameters:
    ///   - manual: jokers the owner switched on (silver / gold, or a bronze chosen by hand)
    ///   - lastNight: the most recent night that is over – later nights are never touched
    ///   - breaks: nights that start a new streak (paid schedule changes) – as in `Progression`
    public static func apply(results: [NightResult], manual: [JokerUse], lastNight: NightKey, calendar: Calendar,
                             breaks: [NightKey] = []) -> (results: [NightResult], uses: [JokerUse]) {
        // several results may share a key (a counted test night) – they are all kept; a key is "bad" when none of
        // its results built anything
        var out = results
        var excused = Set<NightKey>()
        let good = Set(results.filter { $0.outcome.isBuildNight }.map(\.key))
        func isBad(_ key: NightKey) -> Bool { !good.contains(key) && !excused.contains(key) }
        func excuse(_ key: NightKey) {
            out.removeAll { $0.key == key }
            out.append(NightResult(key: key, outcome: .excused, buildingId: nil))
            excused.insert(key)
        }
        func outcome(_ key: NightKey) -> Outcome? {
            if good.contains(key) {
                return results.contains { $0.key == key && $0.outcome == .complete } ? .complete : .unfinished
            }
            return excused.contains(key) ? .excused : nil
        }

        var uses = manual
        // only a BRONZE (by hand or automatic) uses up the month's automatic bronze – silver / gold do not
        var usedMonths = Set(manual.filter { $0.tier == .bronze }.map(\.month))
        for use in manual {
            var key = use.firstNight
            while key <= min(use.lastNight(calendar: calendar), lastNight) {
                if isBad(key) { excuse(key) }
                key = key.adding(days: 1, calendar: calendar)
            }
        }

        // automatic bronze: the first missed night of a month (without a bronze yet) that would break a streak
        if let first = results.map(\.key).min() {
            let breakSet = Set(breaks)
            var run = 0
            var key = first
            while key <= lastNight {
                if breakSet.contains(key) { run = 0 }
                switch outcome(key) {
                case .complete: run += 1
                case .unfinished, .excused: break
                default:
                    if run > 0, !usedMonths.contains(Month(key)) {
                        uses.append(JokerUse(tier: .bronze, firstNight: key, automatic: true))
                        usedMonths.insert(Month(key))
                        excuse(key)
                    } else {
                        run = 0
                    }
                }
                key = key.adding(days: 1, calendar: calendar)
            }
        }
        return (out.sorted { $0.key < $1.key }, uses.sorted { $0.firstNight < $1.firstNight })
    }

    /// Why a joker can't be switched on for `firstNight` now, or nil when it can.
    public enum Block: Equatable, Sendable {
        case alreadyUsedThisMonth
        case notEnoughCoins(missing: Int)
    }

    /// Each kind may be used once per calendar month (the month of its first night), independently of the others.
    /// A manual joker is applied before the automatic bronze, so one that starts on the night the automatic bronze
    /// saved covers that night itself and the month's bronze stays free for a later missed night.
    public static func block(_ tier: JokerTier, firstNight: NightKey, uses: [JokerUse], coins: Int) -> Block? {
        let taken = uses.contains { $0.tier == tier && $0.month == Month(firstNight) }
        if taken { return .alreadyUsedThisMonth }
        if coins < tier.price { return .notEnoughCoins(missing: tier.price - coins) }
        return nil
    }

    /// The night a joker switched on now starts with: last night if it was missed / ruined and is not protected
    /// yet (the morning after – "repair"), otherwise tonight.
    public static func firstNight(tonight: NightKey, lastNightResult: NightResult?, calendar: Calendar) -> NightKey {
        let last = tonight.adding(days: -1, calendar: calendar)
        switch lastNightResult?.outcome {
        case .complete?, .unfinished?, .excused?: return tonight
        default: return last
        }
    }
}
