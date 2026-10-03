import Foundation

/// Achievements (owner 2026-09-30, idea S). Like coins and the town they are not stored: they are replayed from
/// the finalized real nights, so old nights count too. Each one pays a small coin bonus once.
public enum Achievement: String, CaseIterable, Codable, Sendable, Identifiable {
    case firstBuilding
    case streak3, streak7, streak30
    case built10, built50, built100
    case firstLevel2, firstLevel3, firstSkyscraper
    case firstNap
    case firstRepair

    public var id: String { rawValue }

    /// The big ones pay more.
    public var reward: Int {
        switch self {
        case .streak30, .built100, .firstSkyscraper: 200
        default: 50
        }
    }
}

public enum Achievements {
    public struct Unlocked: Equatable, Sendable {
        public let achievement: Achievement
        /// The night (or nap day) that earned it.
        public let key: NightKey
    }

    /// - Parameters:
    ///   - results: finalized REAL nights (no naps, no debug nights), any order
    ///   - naps: finalized real naps (their key = the nap's day)
    ///   - repairs: nights that repaired a ruin (`TownSnapshot.repairs`)
    /// - Returns: every unlocked achievement with the night that earned it, oldest first.
    public static func unlocked(results: [NightResult], naps: [NightResult] = [], repairs: [NightKey] = [],
                                catalog: Catalog?, calendar: Calendar, breaks: [NightKey] = []) -> [Unlocked] {
        var found: [Achievement: NightKey] = [:]
        func unlock(_ a: Achievement, _ key: NightKey) { if found[a] == nil { found[a] = key } }

        // streak semantics exactly as the coin ledger: complete +1, unfinished neutral, ruins/missed/gaps break
        var run = 0, built = 0
        var prev: NightKey?
        for r in results.sorted(by: { $0.key < $1.key }) {
            if let p = prev, r.key != p, r.key != p.adding(days: 1, calendar: calendar) { run = 0 }
            if let p = prev, breaks.contains(where: { p < $0 && $0 <= r.key }) { run = 0 }
            prev = r.key
            switch r.outcome {
            case .complete: run += 1
            case .unfinished, .excused: break
            case .ruins, .missed: run = 0
            }
            for (n, a) in [(3, Achievement.streak3), (7, .streak7), (30, .streak30)] where run >= n { unlock(a, r.key) }
            guard r.outcome.isBuildNight else { continue }
            built += 1
            unlock(.firstBuilding, r.key)
            for (n, a) in [(10, Achievement.built10), (50, .built50), (100, .built100)] where built >= n {
                unlock(a, r.key)
            }
            if let entry = r.buildingId.flatMap({ catalog?[$0] }), entry.kind != .roadLit {
                switch entry.level {
                case 2: unlock(.firstLevel2, r.key)
                case 3: unlock(.firstLevel3, r.key)
                case 4: unlock(.firstSkyscraper, r.key)
                default: break
                }
            }
        }
        if let nap = naps.filter({ $0.outcome == .complete }).map(\.key).min() { unlock(.firstNap, nap) }
        if let repair = repairs.min() { unlock(.firstRepair, repair) }
        return found.map { Unlocked(achievement: $0.key, key: $0.value) }
            .sorted { ($0.key, Achievement.allCases.firstIndex(of: $0.achievement)!)
                    < ($1.key, Achievement.allCases.firstIndex(of: $1.achievement)!) }
    }

    /// Coins from all unlocked achievements.
    public static func coins(_ unlocked: [Unlocked]) -> Int { unlocked.reduce(0) { $0 + $1.achievement.reward } }
}
