import SleepCore
import SpriteKit
import UIKit

/// SpriteKit town (plan §7.2). Pure view of a `TownRenderModel`; camera with SimCity-style smooth
/// scrolling (pan with inertia, pinch zoom around the fingers, double-tap zoom), clamped to the town.
final class TownScene: SKScene {
    private(set) var model: TownRenderModel?
    private let cameraNode = SKCameraNode()
    private var textures: [String: SKTexture] = [:]
    private var velocity = CGVector.zero
    private var lastUpdate: TimeInterval = 0
    var imageProvider: ((String) -> UIImage?)?

    static let minScale: CGFloat = 0.6      // camera scale: smaller = closer
    static let maxScale: CGFloat = 10
    private var needsFit = true

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = UIColor(red: 0.42, green: 0.64, blue: 0.36, alpha: 1)     // meadow beyond the map
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.setScale(2.2)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: content

    func show(_ model: TownRenderModel, focus: ScenePoint?) {
        let firstShow = self.model == nil
        self.model = model
        children.filter { $0 !== cameraNode }.forEach { $0.removeFromParent() }
        for s in model.sprites {
            guard let texture = texture(for: s.spriteId) else { continue }
            let node: SKNode
            let sprite = SKSpriteNode(texture: texture, size: CGSize(width: s.size[0], height: s.size[1]))
            sprite.anchorPoint = CGPoint(x: s.anchor[0], y: s.anchor[1])
            if s.reveal < 1 {
                // unfinished: show only the lowest part of the building
                let crop = SKCropNode()
                let mask = SKSpriteNode(color: .white, size: CGSize(width: s.size[0], height: s.size[1] * s.reveal))
                mask.anchorPoint = CGPoint(x: s.anchor[0], y: (s.anchor[1] * s.size[1]) / (s.size[1] * s.reveal))
                crop.maskNode = mask
                crop.addChild(sprite)
                node = crop
            } else {
                node = sprite
            }
            node.position = CGPoint(x: s.position.x, y: s.position.y)
            node.zPosition = CGFloat(s.zPosition)
            addChild(node)
        }
        if firstShow {
            needsFit = true
            fitIfPossible()
        } else if let focus {
            cameraNode.run(.move(to: CGPoint(x: focus.x, y: focus.y + 120), duration: 0.6)) { [weak self] in
                self?.clampCamera()
            }
        }
        clampCamera()
    }

    /// First look: the whole town fits on screen (capped so a big town is not microscopic).
    private func fitIfPossible() {
        guard needsFit, let model, size.width > 10, size.height > 10 else { return }
        needsFit = false
        let fit = max(model.bounds.width / size.width, model.bounds.height / (size.height * 0.8)) * 1.05
        cameraNode.setScale(min(max(fit, 1.4), 4.5))
        cameraNode.position = CGPoint(x: model.bounds.mid.x, y: model.bounds.mid.y)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        fitIfPossible()
    }

    private func texture(for id: String) -> SKTexture? {
        if let t = textures[id] { return t }
        guard let image = imageProvider?(id) else { return nil }
        let t = SKTexture(image: image)
        textures[id] = t
        return t
    }

    // MARK: camera

    func pan(by translation: CGPoint) {
        velocity = .zero
        cameraNode.position.x -= translation.x * cameraNode.xScale
        cameraNode.position.y += translation.y * cameraNode.yScale
        clampCamera()
    }

    func fling(velocity v: CGPoint) {
        velocity = CGVector(dx: -v.x * cameraNode.xScale, dy: v.y * cameraNode.yScale)
    }

    /// Zoom by `factor` keeping the scene point under `viewPoint` fixed.
    func zoom(by factor: CGFloat, at viewPoint: CGPoint, in view: SKView) {
        let before = convertPoint(fromView: viewPoint)
        let newScale = min(Self.maxScale, max(Self.minScale, cameraNode.xScale / factor))
        cameraNode.setScale(newScale)
        let after = convertPoint(fromView: viewPoint)
        cameraNode.position.x += before.x - after.x
        cameraNode.position.y += before.y - after.y
        clampCamera()
    }

    func animateZoom(in viewPoint: CGPoint, view: SKView) {
        let target = cameraNode.xScale > 1.2 ? cameraNode.xScale / 2 : 2.2
        let p = convertPoint(fromView: viewPoint)
        cameraNode.run(.group([.scale(to: target, duration: 0.3), .move(to: p, duration: 0.3)])) { [weak self] in
            self?.clampCamera()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(0.05, currentTime - lastUpdate)
        lastUpdate = currentTime
        guard abs(velocity.dx) + abs(velocity.dy) > 5 else { velocity = .zero; return }
        cameraNode.position.x += velocity.dx * dt
        cameraNode.position.y += velocity.dy * dt
        let decay = pow(0.04, dt)                  // smooth deceleration (≈ 1 s)
        velocity.dx *= decay
        velocity.dy *= decay
        clampCamera()
    }

    private func clampCamera() {
        guard let b = model?.bounds else { return }
        let p = TownRender.clamp(ScenePoint(x: cameraNode.position.x, y: cameraNode.position.y), to: b)
        if p.x != cameraNode.position.x { velocity.dx = 0 }
        if p.y != cameraNode.position.y { velocity.dy = 0 }
        cameraNode.position = CGPoint(x: p.x, y: p.y)
    }

    // MARK: tap

    /// The building index at a view point, using the sprite's alpha channel for precision.
    func building(atView viewPoint: CGPoint) -> Int? {
        guard let model else { return nil }
        let p = convertPoint(fromView: viewPoint)
        let sp = ScenePoint(x: p.x, y: p.y)
        for c in TownRender.buildingCandidates(at: sp, in: model) {
            guard let image = imageProvider?(c.spriteId) else { continue }
            let px = TownRender.pixel(of: sp, in: c)
            if image.alpha(atX: px.x, y: px.y) > 0.1 { return c.buildingIndex }
        }
        return nil
    }
}

extension UIImage {
    /// Alpha (0…1) of the pixel at (x, y) from the top-left, 0 when outside.
    func alpha(atX x: Int, y: Int) -> CGFloat {
        guard let cg = cgImage, x >= 0, y >= 0, x < cg.width, y < cg.height else { return 0 }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: -x, y: y - cg.height + 1, width: cg.width, height: cg.height))
        return CGFloat(pixel[3]) / 255
    }
}
