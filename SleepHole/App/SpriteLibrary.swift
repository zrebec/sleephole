import Observation
import SleepCore
import UIKit

/// Loads `sprites/catalog.json` from the app bundle and hands out sprite images.
@Observable
final class SpriteLibrary {
    let catalog: Catalog?
    let loadError: String?
    private let folder: URL?

    init(catalog: Catalog?, folder: URL?, loadError: String?) {
        self.catalog = catalog
        self.folder = folder
        self.loadError = loadError
    }

    static func loadFromBundle(_ bundle: Bundle = .main) -> SpriteLibrary {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "sprites") else {
            return SpriteLibrary(catalog: nil, folder: nil, loadError: "sprites/catalog.json chýba v balíku appky")
        }
        do {
            let catalog = try Catalog(jsonData: Data(contentsOf: url))
            return SpriteLibrary(catalog: catalog, folder: url.deletingLastPathComponent(), loadError: nil)
        } catch {
            return SpriteLibrary(catalog: nil, folder: nil, loadError: "Katalóg sa nedá načítať: \(error)")
        }
    }

    @ObservationIgnored private var cache: [String: UIImage] = [:]

    func image(for id: String) -> UIImage? {
        if let cached = cache[id] { return cached }
        guard let entry = catalog?[id], let folder,
              let image = UIImage(contentsOfFile: folder.appendingPathComponent(entry.file).path) else { return nil }
        cache[id] = image
        return image
    }
}
