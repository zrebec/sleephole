import SleepCore
import SpriteKit
import UIKit

/// The town for VoiceOver (13e3). The SKView draws everything itself, so each building is exposed as an accessibility element.
enum TownAccessibility {
    struct Entry: Equatable {
        let label: String
        let index: Int          // index into `TownSnapshot.buildings`
    }

    /// One entry per building, in the order the buildings were built (the snapshot's order). Roads and decorations are not buildings.
    static func entries(_ town: TownSnapshot, name: (String) -> String?) -> [Entry] {
        town.buildings.enumerated().map { i, b in
            let n = name(b.buildingId) ?? L("Building")
            switch b.state {
            case .complete: return Entry(label: n, index: i)
            case .unfinished: return Entry(label: L("\(n), unfinished"), index: i)
            case .ruins: return Entry(label: L("\(n), in ruins"), index: i)
            }
        }
    }

    /// The town's summary, read first.
    static func summary(buildings: Int) -> String { L("Your town: \(buildings) buildings") }
}

/// A building (or the summary) as seen by VoiceOver; the frame is recomputed on every query so it follows the camera.
final class TownAccessibilityElement: UIAccessibilityElement {
    let buildingIndex: Int?
    var onActivate: ((Int) -> Void)?

    init(container: Any, label: String, buildingIndex: Int?) {
        self.buildingIndex = buildingIndex
        super.init(accessibilityContainer: container)
        accessibilityLabel = label
        accessibilityTraits = buildingIndex == nil ? .staticText : .button
    }

    override func accessibilityActivate() -> Bool {
        guard let buildingIndex, let onActivate else { return false }
        onActivate(buildingIndex)
        return true
    }
}

/// SKView that publishes the town's buildings to VoiceOver.
final class TownSKView: SKView {
    var entries: [TownAccessibility.Entry] = []
    var summary = ""
    var onActivate: ((Int) -> Void)?
    private var elements: [TownAccessibilityElement] = []

    override var isAccessibilityElement: Bool { get { false } set {} }

    override var accessibilityElements: [Any]? {
        get {
            guard let scene = scene as? TownScene, let model = scene.model else { return [] }
            let wanted = [TownAccessibility.Entry(label: summary, index: -1)] + entries
            if elements.map({ $0.accessibilityLabel }) != wanted.map({ $0.label })
                || elements.map({ $0.buildingIndex ?? -1 }) != wanted.map(\.index) {
                elements = wanted.map {
                    TownAccessibilityElement(container: self, label: $0.label, buildingIndex: $0.index < 0 ? nil : $0.index)
                }
            }
            for e in elements {
                e.onActivate = onActivate
                if let i = e.buildingIndex {
                    e.accessibilityFrameInContainerSpace = Self.viewFrame(ofBuilding: i, in: model, scene: scene) ?? .zero
                } else {
                    e.accessibilityFrameInContainerSpace = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1)
                }
            }
            return elements
        }
        set {}
    }

    /// The building's sprites (all pieces with its index, the unfinished ones only as high as they are shown) in view space.
    static func viewFrame(ofBuilding index: Int, in model: TownRenderModel, scene: SKScene) -> CGRect? {
        var rect: SceneRect?
        for s in model.sprites where s.buildingIndex == index {
            var f = s.frame
            if s.reveal < 1 { f.maxY = f.minY + (f.maxY - f.minY) * s.reveal }
            rect = rect.map { $0.union(f) } ?? f
        }
        guard let rect else { return nil }
        let a = scene.convertPoint(toView: CGPoint(x: rect.minX, y: rect.minY))
        let b = scene.convertPoint(toView: CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
