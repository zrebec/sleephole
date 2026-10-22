import Foundation
import SleepCore
import SpriteKit
import SwiftData
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

    /// An empty `UserDefaults` suite per test – the remembered camera never leaks between tests or into the app.
    func suite() -> UserDefaults {
        let d = UserDefaults(suiteName: "TownSceneTests-\(UUID().uuidString)")!
        return d
    }

    func presented(_ model: TownRenderModel, defaults: UserDefaults? = nil, focus: ScenePoint? = nil,
                   newest: String? = nil) -> (SKView, TownScene) {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let scene = TownScene(size: view.bounds.size)
        scene.imageProvider = { sprites.image(for: $0) }
        scene.cameraDefaults = defaults ?? suite()
        view.presentScene(scene)
        scene.show(model, focus: focus, newest: newest)
        return (view, scene)
    }

    @Test func everySpriteBecomesANode() {
        let (_, m) = town(10)          // the 10th night is unfinished and nothing finishes it later
        let (_, scene) = presented(m)
        let nodes = scene.children.filter { !($0 is SKCameraNode) && !($0 is SKShapeNode) }
        #expect(nodes.count == m.sprites.count)
        #expect(scene.children.filter { $0 is SKShapeNode }.count == 3)        // meadow + two soil faces (island)
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

    // MARK: remembered camera (B30)

    @Test func theCameraIsSavedAndRestoredOnTheNextLaunch() throws {
        let (_, m) = town(20)
        let d = suite()
        let (_, first) = presented(m, defaults: d, newest: "2026-10-20")
        first.pan(by: CGPoint(x: 300, y: -200))
        first.saveCamera()
        let moved = try #require(first.camera).position
        let scale = try #require(first.camera).xScale
        let (_, second) = presented(m, defaults: d, newest: "2026-10-20")
        let cam = try #require(second.camera)
        #expect(abs(cam.position.x - moved.x) < 1 && abs(cam.position.y - moved.y) < 1)
        #expect(abs(cam.xScale - scale) < 0.001)
    }

    @Test func aRestoredCameraIsClampedToTheTown() throws {
        let (_, m) = town(6)
        let d = suite()
        d.set(try JSONEncoder().encode(TownCamera(scale: 500, x: 1e7, y: -1e7)), forKey: TownScene.cameraKey)
        let (_, scene) = presented(m, defaults: d)
        let cam = try #require(scene.camera)
        #expect(inside(cam.position, m.bounds))
        #expect(abs(cam.xScale - TownScene.maxScale) < 0.001)
    }

    @Test func aNewBuildingMakesTheCameraGlideAndOnlyOnce() throws {
        let (_, m) = town(6)
        let d = suite()
        d.set(try JSONEncoder().encode(TownCamera(scale: 2, x: m.bounds.mid.x, y: m.bounds.mid.y, seenBuilding: "2026-10-01")),
              forKey: TownScene.cameraKey)
        let focus = ScenePoint(x: m.bounds.minX + 50, y: m.bounds.mid.y)
        let (_, scene) = presented(m, defaults: d, focus: focus, newest: "2026-10-06")
        let cam = try #require(scene.camera)
        #expect(cam.hasActions())                                       // gliding
        #expect(cam.action(forKey: "glide") != nil)
        scene.pan(by: CGPoint(x: 1, y: 1))                              // a touch takes the camera back
        #expect(cam.action(forKey: "glide") == nil)
        let saved = try JSONDecoder().decode(TownCamera.self, from: try #require(d.data(forKey: TownScene.cameraKey)))
        #expect(saved.seenBuilding == "2026-10-06")
        let (_, again) = presented(m, defaults: d, focus: focus, newest: "2026-10-06")
        #expect(again.camera?.action(forKey: "glide") == nil)           // already seen → no glide
    }

    @Test func noRememberedBuildingMeansNoGlide() throws {
        let (_, m) = town(6)
        let (_, scene) = presented(m, focus: ScenePoint(x: 0, y: 0), newest: "2026-10-06")
        #expect(scene.camera?.action(forKey: "glide") == nil)
    }

    @Test func theCameraIsNotInTheBackupOrTheSyncFile() throws {
        let (_, m) = town(6)
        let d = suite()
        let (_, scene) = presented(m, defaults: d, newest: "x")
        scene.saveCamera()
        #expect(d.data(forKey: TownScene.cameraKey) != nil)
        let container = try ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                           JokerRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let model = AppModel(context: container.mainContext, catalog: sprites.catalog, servicesEnabled: false)
        let json = String(decoding: try model.makeBackup().encoded(), as: UTF8.self)
        #expect(!json.contains("townCamera") && !json.contains("seenBuilding"))
        let src = try String(contentsOfFile: #filePath.replacingOccurrences(of: "SleepHoleTests/TownSceneTests.swift", with: "SleepHole/Persistence/SyncEngine.swift"), encoding: .utf8)
        #expect(!src.contains("townCamera"))
    }
}
