import SleepCore
import SwiftUI

/// Today hero (phase UI): a small floating island cut out of the owner's town around the newest building, gently
/// bobbing over the sky. In the evening start window a crane stands on it – tonight something will be built.
struct TownIslandView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpriteLibrary.self) private var sprites
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var crane = false

    static let soilDepth = 70.0          // scene units
    static let craneSize = (w: 471.0, h: 717.0, ax: 0.334, ay: 0.209)

    var body: some View {
        if let render = model.townRender, let town = model.townSnapshot {
            let island = TownRender.island(render, town: town)
            // the crane stands at the back-right edge, behind every building
            let craneAt = ScenePoint(x: (island.top.x + island.right.x) / 2 - 20, y: (island.top.y + island.right.y) / 2 - 40)
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let bob = reduceMotion ? 0 : sin(t * 2 * .pi / (6 * Motion.pace)) * 4
                let frame = Int(t / ConstructionSite.frameDuration) % ConstructionSite.frames
                Canvas { gc, size in
                    draw(&gc, size: size, island: island, crane: crane ? (craneAt, frame) : nil)
                }
                .offset(y: bob)
                .background(alignment: .bottom) {
                    // soft shadow on the "air" below – shrinks when the island floats up
                    Ellipse().fill(.black.opacity(0.12)).frame(width: 170 - bob * 3, height: 16).blur(radius: 8)
                        .offset(y: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(L("Your town"))
            .accessibilityAddTraits(.isButton)
        }
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize, island: TownIsland, crane: (ScenePoint, Int)?) {
        var bounds = island.bounds
        bounds = SceneRect(minX: bounds.minX, minY: bounds.minY - Self.soilDepth, maxX: bounds.maxX, maxY: bounds.maxY)
        let craneFrame = crane.map { c in
            SceneRect(minX: c.0.x - Self.craneSize.ax * Self.craneSize.w, minY: c.0.y - Self.craneSize.ay * Self.craneSize.h,
                      maxX: c.0.x + (1 - Self.craneSize.ax) * Self.craneSize.w, maxY: c.0.y + (1 - Self.craneSize.ay) * Self.craneSize.h)
        }
        if let craneFrame { bounds = bounds.union(craneFrame) }
        let k = min(size.width / bounds.width, size.height / bounds.height)
        let ox = (size.width - bounds.width * k) / 2, oy = (size.height - bounds.height * k) / 2
        func point(_ p: ScenePoint) -> CGPoint { CGPoint(x: ox + (p.x - bounds.minX) * k, y: oy + (bounds.maxY - p.y) * k) }
        func rect(_ f: SceneRect) -> CGRect {
            CGRect(origin: point(ScenePoint(x: f.minX, y: f.maxY)), size: CGSize(width: f.width * k, height: f.height * k))
        }

        let (left, right) = IslandEdge.faces(left: point(island.left), bottom: point(island.bottom), right: point(island.right),
                                             depth: Self.soilDepth * k)
        var top = Path()
        top.addLines([point(island.top), point(island.right), point(island.bottom), point(island.left)])
        gc.fill(top, with: .color(IslandEdge.meadow))
        gc.fill(left, with: .color(IslandEdge.leftSoil))
        gc.fill(right, with: .color(IslandEdge.rightSoil))

        var craneDrawn = crane == nil
        for s in island.sprites {
            if !craneDrawn, s.layer == .object, let crane, let craneFrame {
                drawImage(&gc, String(format: "o-crane-%02d", crane.1), in: rect(craneFrame), reveal: 1)
                craneDrawn = true
            }
            drawImage(&gc, s.spriteId, in: rect(s.frame), reveal: s.reveal)
        }
        if !craneDrawn, let crane, let craneFrame {
            drawImage(&gc, String(format: "o-crane-%02d", crane.1), in: rect(craneFrame), reveal: 1)
        }
    }

    private func drawImage(_ gc: inout GraphicsContext, _ id: String, in r: CGRect, reveal: Double) {
        guard let image = sprites.image(for: id) else { return }
        if reveal < 1 {
            var clipped = gc
            clipped.clip(to: Path(CGRect(x: r.minX, y: r.maxY - r.height * reveal, width: r.width, height: r.height * reveal)))
            clipped.draw(Image(uiImage: image), in: r)
        } else {
            gc.draw(Image(uiImage: image), in: r)
        }
    }
}
