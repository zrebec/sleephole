import Foundation
import SleepCore

/// The localized names of the collectibles (box prizes). Step 11b5b: the six cat accessories; later steps add the town
/// decorations and the night skies here. Every name is a literal `L("…")` so the i18n tool finds it.
enum CollectibleText {
    /// The English keys, exactly as they stand in the String Catalog.
    static let keys: [String] = ["Nightcap", "Top hat", "Builder's helmet", "Sunglasses", "Bowl with a fish", "Rug"]

    /// The name of an accessory id (`BoxCatalog.ids(.accessory)`); the id itself for an unknown one.
    static func accessoryName(_ id: String) -> String {
        switch id {
        case "nightcap": L("Nightcap")
        case "top-hat": L("Top hat")
        case "builder-helmet": L("Builder's helmet")
        case "sunglasses": L("Sunglasses")
        case "fish-bowl": L("Bowl with a fish")
        case "rug": L("Rug")
        default: id
        }
    }

    /// "Wearing: nightcap, rug" for the cat's accessibility label; "" when nothing is worn.
    static func wearing(_ outfit: CatOutfit) -> String {
        let names = outfit.layers.reversed().map(accessoryName)       // head, face, bed – what people see first
        return names.isEmpty ? "" : L("Wearing: \(names.joined(separator: ", "))")
    }
}
