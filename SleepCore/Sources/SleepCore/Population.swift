import Foundation

/// Town size names (a pure function of the total number of residents).
public enum TownSize: String, Sendable, CaseIterable {
    case hamlet, village, smallTown, town, city, bigCity, metropolis

    public static func of(residents: Int) -> TownSize {
        switch residents {
        case ..<100: .hamlet
        case ..<1_000: .village
        case ..<5_000: .smallTown
        case ..<20_000: .town
        case ..<100_000: .city
        case ..<500_000: .bigCity
        default: .metropolis
        }
    }
}

/// Residents of the buildings (owner POP, 2026-10-12). Deterministic: the number of one building depends only on
/// its stable identity (night key + building id), so it is the same in every process, after a restore from
/// backup and after an iCloud sync.
public enum Population {
    /// Residents of a complete building of this kind, or 0 where nobody lives.
    public static func residents(buildingId id: String, nightKey: NightKey) -> Int {
        var rng = SeededGenerator(seed: fnv1a64("\(nightKey.description)|\(id)"))
        if id.hasPrefix("l1-house") {
            let roll = draw(0...99, &rng)
            if roll < 70 { return draw(2...5, &rng) }
            if roll < 95 { return draw(6...9, &rng) }
            return draw(10...14, &rng)
        }
        // `l1-bigblock` does not start with `l1-block`, so the order of these checks does not matter.
        if id.hasPrefix("l1-bigblock") { return draw(180...540, &rng) }
        if id.hasPrefix("l1-block") { return draw(24...96, &rng) }
        if id.hasPrefix("l4-tower") { return draw(600...1_400, &rng) }
        if id.hasPrefix("l4-sky") { return draw(1_500...4_000, &rng) }
        return 0
    }

    /// Residents counted for a building in its current state: unfinished half, ruins nobody, repaired full.
    public static func residents(of b: TownBuilding) -> Int {
        guard b.state != .ruins else { return 0 }
        let full = residents(buildingId: b.buildingId, nightKey: b.nightKey)
        return b.state == .unfinished ? full / 2 : full
    }

    public static func total(_ town: TownSnapshot) -> Int {
        town.buildings.reduce(0) { $0 + residents(of: $1) }
    }

    /// Own mapping instead of `Int.random(in:using:)`: its algorithm is the standard library's to change, and the
    /// numbers must agree between devices running different iOS versions.
    private static func draw(_ r: ClosedRange<Int>, _ rng: inout SeededGenerator) -> Int {
        r.lowerBound + Int(rng.next() % UInt64(r.count))
    }

    /// FNV-1a, 64 bit (never Swift's `Hasher`, which is randomly seeded per process).
    static func fnv1a64(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return h
    }
}
