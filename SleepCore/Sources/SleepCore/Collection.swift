import Foundation

/// The collection (step 11b4c): what the cat wears and which night sky is shown are CHOICES stored on the profile as
/// plain strings; this file turns a stored choice plus the dated box records into what is really shown. Nothing here is
/// a counter – the owned items always come from the box records.
///
/// Stored forms:
/// * outfit – `nil` = never chosen; otherwise the comma-separated accessory ids worn (`""` = explicitly nothing);
/// * sky – `nil` = never chosen; `"none"` = the plain sky chosen; otherwise a sky id.
public enum Collection {
    /// The stored sky choice that means "the plain sky, on purpose".
    public static let plainSky = "none"

    /// The box that first gave each collectible of that kind, oldest first (a repeat adds nothing) – the list of the
    /// collection and the date an item was won.
    public static func firstWins(_ kind: CollectibleKind, boxes: [BoxPurchase]) -> [(id: String, box: BoxPurchase)] {
        var seen = Set<String>(), out: [(id: String, box: BoxPurchase)] = []
        for b in boxes.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            if case .collectible(kind, let id) = b.prize, seen.insert(id).inserted { out.append((id, b)) }
        }
        return out
    }

    /// What the cat wears. Never chosen → in each slot the NEWEST owned accessory (a first win shows at once). A choice →
    /// the chosen ids that are owned (an unknown or not owned id – e.g. a sync that arrived before its box – is dropped).
    public static func effectiveOutfit(choice: String?, boxes: [BoxPurchase]) -> CatOutfit {
        let owned = Boxes.ownedInOrder(.accessory, boxes: boxes)
        guard let choice else {
            return CatOutfit(ids: owned.reversed())            // newest first → the first valid id per slot is the newest
        }
        let ownedSet = Set(owned)
        return CatOutfit(ids: choice.split(separator: ",").map(String.init).filter { ownedSet.contains($0) })
    }

    /// The sky shown: nil = the plain sky. Never chosen → the newest owned sky; `"none"` → plain; an owned id → that id; an
    /// id that is not owned behaves like never chosen.
    public static func effectiveSky(choice: String?, boxes: [BoxPurchase]) -> String? {
        let owned = Boxes.ownedInOrder(.sky, boxes: boxes)
        if choice == plainSky { return nil }
        if let choice, owned.contains(choice) { return choice }
        return owned.last
    }

    /// The new stored outfit when ONE slot changes (`id` nil = nothing in that slot), starting from what is worn now, so
    /// that choosing a hat keeps the glasses that were worn automatically. Ids in the order head, face, bed.
    public static func storedOutfit(changing slot: AccessorySlot, to id: String?, current: CatOutfit) -> String {
        var o = current
        switch slot {
        case .head: o.head = id
        case .face: o.face = id
        case .bed: o.bed = id
        }
        return [o.head, o.face, o.bed].compactMap { $0 }.joined(separator: ",")
    }

    /// The stored sky choice for "show this sky" (`id` nil = the plain sky).
    public static func storedSky(_ id: String?) -> String { id ?? plainSky }
}
