import Foundation

/// Chooses tonight's building (plan §5.6).
public enum BuildingPicker {
    /// - Parameters:
    ///   - history: catalog ids built so far, oldest first (includes ruins/unfinished).
    ///   - canUpgradeStreets: false when there is no unlit straight road → "road-lit" is not offered.
    /// Level first (uniform over unlocked levels), then an item inside the level: never one of the last
    /// 3 picks, preferring ids not yet in the town, then the least recently used.
    public static func pick<G: RandomNumberGenerator>(maxLevel: Int, catalog: Catalog, history: [String],
                                                      canUpgradeStreets: Bool, rng: inout G) -> CatalogEntry {
        let recent = Set(history.suffix(3))
        var levels = Array(1...max(1, min(4, maxLevel)))
        levels.shuffle(using: &rng)
        for level in levels {
            let candidates = candidates(level: level, catalog: catalog, canUpgradeStreets: canUpgradeStreets)
                .filter { !recent.contains($0.id) }
            guard !candidates.isEmpty else { continue }
            let built = Set(history)
            let fresh = candidates.filter { !built.contains($0.id) }
            if !fresh.isEmpty { return fresh.randomElement(using: &rng)! }
            // all used already: least recently used = smallest last index in history
            let lastUse = Dictionary(history.enumerated().map { ($1, $0) }, uniquingKeysWith: { _, b in b })
            let oldest = candidates.map { lastUse[$0.id] ?? -1 }.min()!
            return candidates.filter { (lastUse[$0.id] ?? -1) == oldest }.randomElement(using: &rng)!
        }
        // Everything was filtered out (tiny catalog in tests) – fall back to any L1 building.
        return catalog.buildable(level: 1).randomElement(using: &rng)!
    }

    /// Buildable entries of a level; the two lit-street sprites count as ONE item ("Osvetlená ulica").
    static func candidates(level: Int, catalog: Catalog, canUpgradeStreets: Bool) -> [CatalogEntry] {
        var seenLit = false
        return catalog.buildable(level: level).filter { e in
            guard e.kind == .roadLit else { return true }
            defer { seenLit = true }
            return canUpgradeStreets && !seenLit
        }
    }
}
