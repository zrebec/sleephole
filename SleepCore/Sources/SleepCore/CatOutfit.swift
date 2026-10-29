import Foundation

/// What the sleep buddy wears (step 11b5b): at most ONE accessory per slot – head, face and by the bed. The slot table
/// covers exactly `BoxCatalog.ids(.accessory)` (ids are persisted – never rename one, only add). Choosing the outfit is
/// a later step; this is only the value the cat's view can show.
public enum AccessorySlot: String, CaseIterable, Codable, Sendable {
    case head, face, bed

    /// The slot of an accessory id; nil for an unknown id (or an id of another collectible kind).
    public static func of(_ id: String) -> AccessorySlot? {
        switch id {
        case "nightcap", "top-hat", "builder-helmet": .head
        case "sunglasses": .face
        case "fish-bowl", "rug": .bed
        default: nil
        }
    }
}

public struct CatOutfit: Equatable, Codable, Sendable {
    public var head: String?
    public var face: String?
    public var bed: String?

    public static let none = CatOutfit()

    public init(head: String? = nil, face: String? = nil, bed: String? = nil) {
        self.head = AccessorySlot.of(head ?? "") == .head ? head : nil
        self.face = AccessorySlot.of(face ?? "") == .face ? face : nil
        self.bed = AccessorySlot.of(bed ?? "") == .bed ? bed : nil
    }

    /// Keeps the FIRST valid id of each slot; unknown ids are ignored.
    public init(ids: [String]) {
        var o = CatOutfit()
        for id in ids {
            switch AccessorySlot.of(id) {
            case .head where o.head == nil: o.head = id
            case .face where o.face == nil: o.face = id
            case .bed where o.bed == nil: o.bed = id
            default: break
            }
        }
        self = o
    }

    public var isEmpty: Bool { head == nil && face == nil && bed == nil }

    /// The ids to draw, back to front: by the bed first, then the face, then the head (a hat sits over the glasses' frame).
    public var layers: [String] { [bed, face, head].compactMap { $0 } }
}
