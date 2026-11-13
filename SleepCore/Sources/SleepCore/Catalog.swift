import Foundation

/// One sprite from `assets/sprites/catalog.json` (schema: IMPLEMENTATION_PLAN.md §3.2).
public struct CatalogEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case building, park, road, terrain, overlay, vehicle
        /// A town decoration won from a mystery box (build 11b5c): never a night's building, never counted.
        case decoration
        case roadLit = "road-lit"
    }

    public let id: String
    public let level: Int
    public let kind: Kind
    public let nameSK: String
    /// English name; optional so older catalogs still decode.
    public let nameEN: String?
    /// Czech name (build 13b); optional – Czech falls back to the Slovak name.
    public let nameCS: String?
    public let footprint: [Int]
    public let file: String
    /// Variant with an English sign painted on it (e.g. "L3/l3-police.en.png"); nil = no text on the sprite.
    public let fileEN: String?
    /// Variant with a Czech sign (build 13b2), only where the Czech word differs from the Slovak one; nil = use `file`.
    public let fileCS: String?
    public let size: [Int]
    public let anchor: [Double]
    public let connects: String?

    /// Display name for a language code ("sk", "cs", "en", …); Czech falls back to Slovak, unknown languages to English,
    /// then Slovak.
    public func name(_ lang: String) -> String {
        switch lang {
        case "sk": nameSK
        case "cs": nameCS ?? nameSK
        default: nameEN ?? nameSK
        }
    }

    /// Sprite file for a language: the signs painted on the sprites are Slovak for "sk", Czech for "cs" (the Slovak
    /// file where the Czech word is the same), English for every other language, if there is a variant.
    public func file(_ lang: String) -> String {
        switch lang {
        case "sk": file
        case "cs": fileCS ?? file
        default: fileEN ?? file
        }
    }
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
        entries.filter { $0.level == level && $0.kind != .terrain && $0.kind != .overlay
            && $0.kind != .vehicle && $0.kind != .decoration }
    }
}
