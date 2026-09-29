import Foundation

/// One sprite from `assets/sprites/catalog.json` (schema: IMPLEMENTATION_PLAN.md §3.2).
public struct CatalogEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case building, park, road, terrain, overlay, vehicle
        case roadLit = "road-lit"
    }

    public let id: String
    public let level: Int
    public let kind: Kind
    public let nameSK: String
    public let footprint: [Int]
    public let file: String
    public let size: [Int]
    public let anchor: [Double]
    public let connects: String?
}

/// The whole sprite catalog, with lookups used by the app and the domain logic.
public struct Catalog: Sendable {
    public let entries: [CatalogEntry]
    private let byId: [String: CatalogEntry]

    public init(entries: [CatalogEntry]) {
        self.entries = entries
        self.byId = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    public init(jsonData: Data) throws {
        self.init(entries: try JSONDecoder().decode([CatalogEntry].self, from: jsonData))
    }

    public subscript(id: String) -> CatalogEntry? { byId[id] }

    /// Entries that can be built at night (levels 1…4).
    public func buildable(level: Int) -> [CatalogEntry] {
        entries.filter { $0.level == level && $0.kind != .terrain && $0.kind != .overlay && $0.kind != .vehicle }
    }
}
