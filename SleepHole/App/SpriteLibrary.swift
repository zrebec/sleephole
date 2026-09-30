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
            return SpriteLibrary(catalog: nil, folder: nil, loadError: L("sprites/catalog.json is missing from the app bundle"))
        }
        do {
            let catalog = try Catalog(jsonData: Data(contentsOf: url))
            return SpriteLibrary(catalog: catalog, folder: url.deletingLastPathComponent(), loadError: nil)
        } catch {
            return SpriteLibrary(catalog: nil, folder: nil, loadError: L("The catalog can't be loaded: \(String(describing: error))"))
        }
    }

    @ObservationIgnored private var cache: [String: UIImage] = [:]

    /// The sprite in the current UI language (buildings with a painted sign have an English variant).
    func image(for id: String) -> UIImage? { image(for: id, language: Lang.current) }

    func image(for id: String, language: AppLanguage) -> UIImage? {
        guard let entry = catalog?[id], let folder else { return nil }
        let file = entry.file(language.rawValue)
        if let cached = cache[file] { return cached }
        guard let image = UIImage(contentsOfFile: folder.appendingPathComponent(file).path) else { return nil }
        cache[file] = image
        return image
    }
}
