import Foundation

/// Chooses tonight's building (plan §5.6).
public enum BuildingPicker {
    /// - Parameters:
    ///   - history: catalog ids built so far, oldest first (includes ruins/unfinished).
    /// "road-lit" is never drawn (owner 2026-10-14: a lit street is neither a building nor a park); stored nights keep working.
    /// `excluding`: ids that must not come up (the buildings already drawn tonight, see `Reroll`); filtered like `recent`.
    /// Level first (uniform over unlocked levels), then an item inside the level: never one of the last
    /// 3 picks, preferring ids not yet in the town, then the least recently used.
    public static func pick<G: RandomNumberGenerator>(maxLevel: Int, catalog: Catalog, history: [String],
                                                      excluding: Set<String> = [], rng: inout G) -> CatalogEntry {
        let recent = Set(history.suffix(3)).union(excluding)
        var levels = Array(1...max(1, min(4, maxLevel)))
        levels.shuffle(using: &rng)
        for level in levels {
            let candidates = candidates(level: level, catalog: catalog)
                .filter { !recent.contains($0.id) }
            guard !candidates.isEmpty else { continue }
            let fresh = candidates.filter { isNew($0.id, history: history) }
            if !fresh.isEmpty { return fresh.randomElement(using: &rng)! }
            // all used already: least recently used = smallest last index in history
            let lastUse = Dictionary(history.enumerated().map { ($1, $0) }, uniquingKeysWith: { _, b in b })
            let oldest = candidates.map { lastUse[$0.id] ?? -1 }.min()!
            return candidates.filter { (lastUse[$0.id] ?? -1) == oldest }.randomElement(using: &rng)!
        }
        // Everything was filtered out (tiny catalog in tests) – fall back to any L1 building.
        let l1 = catalog.buildable(level: 1)
        return (l1.filter { !excluding.contains($0.id) }.randomElement(using: &rng)) ?? l1.randomElement(using: &rng)!
    }

    /// "New in town": the id is not among the buildings of the finished nights (`history`, ruins and unfinished
    /// included). The one notion of *fresh* shared by `pick` and the "New in town" label of the setup (11b6b).
    public static func isNew(_ id: String, history: [String]) -> Bool {
        !history.contains(id)
    }

    /// Buildable entries of a level, without the lit-street sprites (they are never drawn any more).
    static func candidates(level: Int, catalog: Catalog) -> [CatalogEntry] {
        catalog.buildable(level: level).filter { $0.kind != .roadLit }
    }
}
