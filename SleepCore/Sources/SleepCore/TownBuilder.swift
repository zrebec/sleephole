import Foundation

/// State of one building in the town.
public enum BuildingState: String, Codable, Sendable {
    case complete, unfinished, ruins
}

/// A building placed in the town, with the night that produced it.
public struct TownBuilding: Equatable, Sendable {
    public let placement: Placement
    public let nightKey: NightKey
    /// The catalog id that was built (for ruins still the original building).
    public let buildingId: String
    public var state: BuildingState
    /// An unfinished building completed by a later good night ("dostavaná", plan §8).
    public var completedLater: Bool = false
    /// A ruin rebuilt by a later good night ("opravená", owner 2026-09-30).
    public var repairedLater: Bool = false
}

/// The whole town derived from the finalized nights. Nothing about the town is stored: it is replayed
/// from the results in chronological order – placement is deterministic (plan §7, §8).
public struct TownSnapshot: Equatable, Sendable {
    public var layout = TownLayout()
    public var buildings: [TownBuilding] = []
    /// Nights whose complete result repaired an older ruin, in order (→ achievement "Repair").
    public var repairs: [NightKey] = []
    public init() {}
}

public enum TownBuilder {
    /// - Parameter results: finalized REAL nights (debug nights excluded by the caller), any order.
    public static func build(results: [NightResult], catalog: Catalog) -> TownSnapshot {
        var town = TownSnapshot()
        for r in results.sorted(by: { $0.key < $1.key }) {
            guard r.outcome != .missed, r.outcome != .excused, let id = r.buildingId, let entry = catalog[id] else { continue }
            switch (entry.kind, r.outcome) {
            case (.roadLit, .complete), (.roadLit, .unfinished):
                town.layout.upgradeStreets()                       // "Osvetlená ulica" lights streets
            case (.roadLit, _):
                guard let ruin = catalog["o-ruin-1"] else { continue }
                append(&town, entry: ruin, buildingId: id, key: r.key, state: .ruins)
            default:
                let state: BuildingState = r.outcome == .complete ? .complete
                    : r.outcome == .unfinished ? .unfinished : .ruins
                append(&town, entry: entry, buildingId: id, key: r.key, state: state)
            }
            // A complete night also helps ONE older building (gentle bonus): first it finishes the oldest
            // unfinished building, otherwise it repairs the oldest ruin (not lit-street ruins – nothing to rebuild).
            if r.outcome == .complete {
                if let i = town.buildings.firstIndex(where: { $0.state == .unfinished && $0.nightKey < r.key }) {
                    town.buildings[i].state = .complete
                    town.buildings[i].completedLater = true
                } else if let i = town.buildings.firstIndex(where: {
                    $0.state == .ruins && $0.nightKey < r.key && $0.placement.catalogId == $0.buildingId
                }) {
                    town.buildings[i].state = .complete
                    town.buildings[i].repairedLater = true
                    town.repairs.append(r.key)
                }
            }
        }
        return town
    }

    private static func append(_ town: inout TownSnapshot, entry: CatalogEntry, buildingId: String,
                               key: NightKey, state: BuildingState) {
        let p = town.layout.place(entry)
        town.buildings.append(TownBuilding(placement: p, nightKey: key, buildingId: buildingId, state: state))
    }
}
