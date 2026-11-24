import Observation
import SleepCore
import SpriteKit
import UIKit

/// Loads `sprites/catalog.json` from the app bundle and hands out sprite images.
@Observable
final class SpriteLibrary: @unchecked Sendable {     // the caches are guarded by `lock` (13p: filled off the main thread)
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
    @ObservationIgnored private var textureCache: [String: SKTexture] = [:]
    @ObservationIgnored private let lock = NSLock()

    /// The sprite in the current UI language (buildings with a painted sign have an English variant).
    func image(for id: String) -> UIImage? { image(for: id, language: Lang.current) }

    func image(for id: String, language: AppLanguage) -> UIImage? {
        guard let entry = catalog?[id], let folder else { return nil }
        let file = entry.file(language.rawValue)
        if let cached = locked({ cache[file] }) { return cached }
        guard let image = UIImage(contentsOfFile: folder.appendingPathComponent(file).path) else { return nil }
        locked { cache[file] = image }
        return image
    }

    /// The texture prepared by `prepare` – nil when it is not ready yet (the caller then builds it from `image(for:)`).
    func texture(for id: String) -> SKTexture? { texture(for: id, language: Lang.current) }

    func texture(for id: String, language: AppLanguage) -> SKTexture? {
        guard let file = catalog?[id]?.file(language.rawValue) else { return nil }
        return locked { textureCache[file] }
    }

    /// Decodes the sprites' files and builds their textures (13p). Meant for a background thread: the first visit of the
    /// Town or Stats then finds everything ready instead of decoding PNGs on the main thread. Safe to call repeatedly.
    func prepare(ids: [String], language: AppLanguage) {
        guard let folder else { return }
        var fresh: [SKTexture] = []
        for id in ids {
            guard let file = catalog?[id]?.file(language.rawValue) else { continue }
            if locked({ textureCache[file] != nil }) { continue }
            let loaded = locked { cache[file] }
            guard let raw = loaded ?? UIImage(contentsOfFile: folder.appendingPathComponent(file).path) else { continue }
            let image = raw.preparingForDisplay() ?? raw          // forces the PNG decode here, not on first draw
            let texture = SKTexture(image: image)
            locked { cache[file] = image; textureCache[file] = texture }
            fresh.append(texture)
        }
        if !fresh.isEmpty { SKTexture.preload(fresh) {} }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
