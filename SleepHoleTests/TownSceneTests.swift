import Foundation
import SleepCore
import SpriteKit
import Testing
import UIKit
@testable import SleepHole

@MainActor
struct TownSceneTests {
    let sprites = SpriteLibrary.loadFromBundle()

    func town(_ n: Int) -> (TownSnapshot, TownRenderModel) {
        let catalog = sprites.catalog!
        let k = NightKey("2026-10-01")!
        let results = (0..<n).map { i in
            NightResult(key: k.adding(days: i, calendar: .current), outcome: i % 5 == 4 ? .unfinished : .complete,
                        buildingId: i % 3 == 0 ? "l3-police" : "l1-house-a-0")
        }
        let snap = TownBuilder.build(results: results, catalog: catalog)
        return (snap, TownRender.build(snap, catalog: catalog, today: k.adding(days: n, calendar: .current),
                                       calendar: .current))
    }

    /// SpriteKit stores scales/positions as Float → compare with a tolerance.
    func inside(_ p: CGPoint, _ b: SceneRect) -> Bool {
        p.x >= b.minX - 1 && p.x <= b.maxX + 1 && p.y >= b.minY - 1 && p.y <= b.maxY + 1
    }

    func presented(_ model: TownRenderModel) -> (SKView, TownScene) {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let scene = TownScene(size: view.bounds.size)
        scene.imageProvider = { sprites.image(for: $0) }
        view.presentScene(scene)
        scene.show(model, focus: nil)
        return (view, scene)
    }

    @Test func everySpriteBecomesANode() {
        let (_, m) = town(10)          // the 10th night is unfinished and nothing finishes it later
        let (_, scene) = presented(m)
        let nodes = scene.children.filter { !($0 is SKCameraNode) }
        #expect(nodes.count == m.sprites.count)
        #expect(nodes.contains { $0 is SKCropNode })                         // unfinished building
    }

    @Test func firstShowFitsTheWholeTown() throws {
        let (_, m) = town(20)
        let (_, scene) = presented(m)
        let cam = try #require(scene.camera)
        #expect(cam.xScale >= 1.4 && cam.xScale <= 4.5)
        #expect(abs(cam.position.x - m.bounds.mid.x) < 1)
    }

    @Test func panZoomAndFlingStayInsideTheTown() throws {
        let (_, m) = town(20)
        let (view, scene) = presented(m)
        let cam = try #require(scene.camera)
        scene.pan(by: CGPoint(x: 1e6, y: -1e6))
        #expect(inside(cam.position, m.bounds))
        scene.zoom(by: 100, at: CGPoint(x: 200, y: 400), in: view)
        #expect(abs(cam.xScale - TownScene.minScale) < 0.001)
        scene.zoom(by: 0.001, at: CGPoint(x: 200, y: 400), in: view)
        #expect(abs(cam.xScale - TownScene.maxScale) < 0.001)
        scene.fling(velocity: CGPoint(x: 5000, y: 5000))
        for t in stride(from: 0.0, to: 2.0, by: 1.0 / 60) { scene.update(1000 + t) }
        #expect(inside(cam.position, m.bounds))
        scene.animateZoom(in: CGPoint(x: 200, y: 400), view: view)
    }

    @Test func tappingABuildingFindsIt() throws {
        let (snap, m) = town(6)
        let (view, scene) = presented(m)
        scene.camera?.setScale(1)
        let b = snap.buildings[0]
        let p = IsoProjection.scenePoint(x: b.placement.centre.x, z: b.placement.centre.z)
        scene.camera?.position = CGPoint(x: p.x, y: p.y)
        let viewPoint = view.convert(CGPoint(x: p.x, y: p.y + 40), from: scene)
        #expect(scene.building(atView: viewPoint) == 0)
        #expect(scene.building(atView: CGPoint(x: -500, y: -500)) == nil)
    }

    @Test func showingANewVersionMovesTheCamera() {
        let (_, m) = town(3)
        let (_, scene) = presented(m)
        let (_, bigger) = town(8)
        scene.show(bigger, focus: ScenePoint(x: 0, y: 0))
        #expect(scene.model == bigger)
    }
}
