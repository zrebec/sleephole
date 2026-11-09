import SleepCore
import SpriteKit
import UIKit

/// The town for VoiceOver (13e3). The SKView draws everything itself, so each building is exposed as an accessibility element.
enum TownAccessibility {
    struct Entry: Equatable {
        let label: String       // the building's name
        var value: String = ""  // the rest of the building card, read after the label (13y)
        let index: Int          // index into `TownSnapshot.buildings`
    }

    /// One entry per building, in the order the buildings were built (the snapshot's order). Roads and decorations are not buildings.
    /// The label is the name; the value is what the building sheet shows – state, night, level, residents (13y). Computed once here,
    /// never per accessibility query (13p).
    static func entries(_ town: TownSnapshot, name: (String) -> String?, level: (String) -> Int? = { _ in nil }) -> [Entry] {
        town.buildings.enumerated().map { i, b in
            let state: String
            switch b.state {
            case .complete: state = b.repairedLater ? L("Repaired") : b.completedLater ? L("Finished later") : L("Complete")
            case .unfinished: state = L("Unfinished")
            case .ruins: state = L("In ruins")
            }
            var parts = [state, L("Night of \(Fmt.fullDate(b.nightKey))")]
            if let lv = level(b.buildingId) { parts.append(L("Level \(lv)")) }
            let residents = Population.residents(of: b)
            if residents > 0 { parts.append(L("\(residents) people live here")) }
            return Entry(label: name(b.buildingId) ?? L("Building"), value: parts.joined(separator: ", "), index: i)
        }
    }

    /// The town's summary, read first.
    static func summary(buildings: Int) -> String { L("Your town: \(buildings) buildings") }
}

/// A building (or the summary) as seen by VoiceOver; the frame is recomputed on every query so it follows the camera.
final class TownAccessibilityElement: UIAccessibilityElement {
    let buildingIndex: Int?
    var onActivate: ((Int) -> Void)?
    var onFocus: ((Int) -> Void)?

    init(container: Any, label: String, value: String = "", buildingIndex: Int?) {
        self.buildingIndex = buildingIndex
        super.init(accessibilityContainer: container)
        accessibilityLabel = label
        if !value.isEmpty { accessibilityValue = value }
        accessibilityTraits = buildingIndex == nil ? .staticText : .button
    }

    override func accessibilityElementDidBecomeFocused() {
        if let buildingIndex { onFocus?(buildingIndex) }
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
            guard let scene = scene as? TownScene, scene.model != nil else { return [] }
            let wanted = [TownAccessibility.Entry(label: summary, value: "", index: -1)] + entries
            if elements.map({ $0.accessibilityLabel }) != wanted.map({ $0.label })
                || elements.map({ $0.accessibilityValue ?? "" }) != wanted.map({ $0.value })
                || elements.map({ $0.buildingIndex ?? -1 }) != wanted.map(\.index) {
                elements = wanted.map {
                    TownAccessibilityElement(container: self, label: $0.label, value: $0.value, buildingIndex: $0.index < 0 ? nil : $0.index)
                }
            }
            for e in elements {
                e.onActivate = onActivate
                e.onFocus = { [weak self] i in self?.bringIntoViewIfNeeded(building: i) }
                if let i = e.buildingIndex {
                    e.accessibilityFrameInContainerSpace = Self.viewFrame(ofBuilding: i, scene: scene) ?? .zero
                } else {
                    e.accessibilityFrameInContainerSpace = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1)
                }
            }
            return elements
        }
        set {}
    }

    /// VoiceOver moved to a building that is not fully inside the view: the camera brings it in.
    func bringIntoViewIfNeeded(building index: Int) {
        guard let scene = scene as? TownScene,
              let frame = Self.viewFrame(ofBuilding: index, scene: scene), !bounds.contains(frame) else { return }
        scene.bringIntoView(viewFrame: frame)
    }

    /// A three-finger swipe moves the camera by about 80 % of the view, as a finger drag in that direction would.
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        guard let scene = scene as? TownScene else { return false }
        let w = bounds.width * 0.8, h = bounds.height * 0.8
        let translation: CGPoint
        switch direction {
        case .left: translation = CGPoint(x: -w, y: 0)
        case .right: translation = CGPoint(x: w, y: 0)
        case .up: translation = CGPoint(x: 0, y: -h)
        case .down: translation = CGPoint(x: 0, y: h)
        default: return false
        }
        guard scene.scrollForAccessibility(by: translation) else { return false }
        UIAccessibility.post(notification: .pageScrolled, argument: summary)
        return true
    }

    /// The building's sprites (all pieces with its index, the unfinished ones only as high as they are shown) in view space.
    /// The scene rect comes from the scene's per-building cache (built once per `show`), so a query is O(1) per building (13p).
    static func viewFrame(ofBuilding index: Int, scene: TownScene) -> CGRect? {
        scene.sceneRect(ofBuilding: index).map { viewRect($0, scene: scene) }
    }

    /// The same frame by scanning every sprite of `model` – the reference the cache must equal.
    static func viewFrame(ofBuilding index: Int, in model: TownRenderModel, scene: SKScene) -> CGRect? {
        TownScene.sceneRectByScan(ofBuilding: index, in: model).map { viewRect($0, scene: scene) }
    }

    private static func viewRect(_ rect: SceneRect, scene: SKScene) -> CGRect {
        let a = scene.convertPoint(toView: CGPoint(x: rect.minX, y: rect.minY))
        let b = scene.convertPoint(toView: CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
