import Foundation
import SleepCore
import SpriteKit
import Testing
import UIKit
@testable import SleepHole

@MainActor
struct TownAccessibilityTests {
    let sprites = SpriteLibrary.loadFromBundle()

    func snapshot() -> TownSnapshot {
        let k = NightKey("2026-10-01")!
        let outcomes: [Outcome] = [.complete, .complete, .ruins, .unfinished]
        let results = outcomes.enumerated().map { i, o in
            NightResult(key: k.adding(days: i, calendar: .current), outcome: o, buildingId: "l1-house-a-0")
        }
        return TownBuilder.build(results: results, catalog: sprites.catalog!)
    }

    @Test func oneEntryPerBuildingInTheOrderTheyWereBuilt() {
        let before = Lang.current
        defer { Lang.current = before }
        let town = snapshot()
        Lang.current = .en
        let en = TownAccessibility.entries(town) { _ in "House" }
        #expect(en.map(\.index) == Array(town.buildings.indices))
        #expect(en.count == town.buildings.count)
        #expect(en.map(\.label) == ["House", "House", "House, in ruins", "House, unfinished"])
        Lang.current = .cs
        #expect(TownAccessibility.entries(town) { _ in "Dům" }.map(\.label) == ["Dům", "Dům", "Dům, v ruinách", "Dům, nedokončená stavba"])
        Lang.current = .sk
        let sk = TownAccessibility.entries(town) { _ in "Dom" }
        #expect(sk.map(\.label) == ["Dom", "Dom", "Dom, v ruinách", "Dom, rozostavaná stavba"])
    }

    @Test func summaryHasRealPlurals() {
        let before = Lang.current
        defer { Lang.current = before }
        Lang.current = .en
        #expect(TownAccessibility.summary(buildings: 1) == "Your town: 1 building")
        #expect(TownAccessibility.summary(buildings: 4) == "Your town: 4 buildings")
        Lang.current = .sk
        #expect(TownAccessibility.summary(buildings: 1) == "Tvoje mesto: 1 budova")
        #expect(TownAccessibility.summary(buildings: 2) == "Tvoje mesto: 2 budovy")
        #expect(TownAccessibility.summary(buildings: 5) == "Tvoje mesto: 5 budov")
        Lang.current = .cs
        #expect(TownAccessibility.summary(buildings: 2) == "Tvoje město: 2 budovy")
        #expect(TownAccessibility.summary(buildings: 5) == "Tvoje město: 5 budov")
    }

    /// Every building element has a point inside its frame that a sighted tap would also hit (buildings overlap, so not every point).
    @Test func framesLineUpWithWhatATapHits() {
        let ids = ["l1-block-a-0", "l1-bigblock-e", "l2-library-a", "l3-firestation", "l4-sky-a-0", "l1-house-a-0", "l2-library-a"]
        let k = NightKey("2026-10-01")!
        let results = ids.enumerated().map { i, id in
            NightResult(key: k.adding(days: i, calendar: .current), outcome: i == 5 ? .unfinished : .complete, buildingId: id)
        }
        let town = TownBuilder.build(results: results, catalog: sprites.catalog!)
        let model = TownRender.build(town, catalog: sprites.catalog!, today: NightKey("2026-10-20")!, calendar: .current)
        let view = TownSKView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let scene = TownScene(size: view.bounds.size)
        scene.imageProvider = { sprites.image(for: $0) }
        scene.cameraDefaults = UserDefaults(suiteName: "TownAccessibilityTests-\(UUID().uuidString)")!
        view.presentScene(scene)
        scene.show(model, focus: nil)
        view.entries = TownAccessibility.entries(town) { _ in "B" }
        view.summary = "S"
        func hits() -> (passed: Int, total: Int) {
            let els = (view.accessibilityElements ?? []).compactMap { $0 as? TownAccessibilityElement }.filter { $0.buildingIndex != nil }
            var passed = 0
            for e in els {
                let f = e.accessibilityFrameInContainerSpace
                var ok = false
                for i in 0..<9 { for j in 0..<9 where !ok {
                    let p = CGPoint(x: f.minX + f.width * (CGFloat(i) + 0.5) / 9, y: f.minY + f.height * (CGFloat(j) + 0.5) / 9)
                    if scene.building(atView: p) == e.buildingIndex { ok = true }
                } }
                if ok { passed += 1 }
                #expect(ok, "building \(e.buildingIndex ?? -1)")
            }
            return (passed, els.count)
        }
        let before = hits()
        #expect(before.total == ids.count)
        scene.pan(by: CGPoint(x: 60, y: -40))
        let after = hits()
        #expect(before.passed == before.total && after.passed == after.total && after.total == ids.count)
    }

    @Test func elementsFollowTheSpritesAndActivate() {
        let town = snapshot()
        let catalog = sprites.catalog!
        let model = TownRender.build(town, catalog: catalog, today: NightKey("2026-10-10")!, calendar: .current)
        let view = TownSKView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let scene = TownScene(size: view.bounds.size)
        scene.imageProvider = { sprites.image(for: $0) }
        scene.cameraDefaults = UserDefaults(suiteName: "TownAccessibilityTests-\(UUID().uuidString)")!
        view.presentScene(scene)
        scene.show(model, focus: nil)
        view.entries = TownAccessibility.entries(town) { _ in "House" }
        view.summary = "Summary"
        var opened: Int?
        view.onActivate = { opened = $0 }
        let elements = (view.accessibilityElements ?? []).compactMap { $0 as? TownAccessibilityElement }
        #expect(elements.count == town.buildings.count + 1)
        #expect(elements.first?.accessibilityLabel == "Summary")
        for e in elements.dropFirst() {
            #expect(e.accessibilityFrameInContainerSpace.width > 0 && e.accessibilityFrameInContainerSpace.height > 0)
        }
        #expect(elements[3].accessibilityActivate())
        #expect(opened == 2)
        // the frame follows the camera
        let f0 = elements[1].accessibilityFrameInContainerSpace
        scene.pan(by: CGPoint(x: 50, y: 0))
        let moved = (view.accessibilityElements ?? []).compactMap { $0 as? TownAccessibilityElement }
        #expect(moved[1].accessibilityFrameInContainerSpace.minX != f0.minX)
    }
}
