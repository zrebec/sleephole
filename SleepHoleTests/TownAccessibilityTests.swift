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
        let en = TownAccessibility.entries(town, name: { _ in "House" }, level: { _ in 1 })
        #expect(en.map(\.index) == Array(town.buildings.indices))
        #expect(en.count == town.buildings.count)
        #expect(en.map(\.label) == ["House", "House", "House", "House"])
    }

    @Test func theValueCarriesTheWholeBuildingCard() {
        let before = Lang.current
        defer { Lang.current = before }
        let town = snapshot()
        func values(_ lang: AppLanguage) -> [String] {
            Lang.current = lang
            return TownAccessibility.entries(town, name: { _ in "House" }, level: { _ in 1 }).map(\.value)
        }
        let people = town.buildings.map { Population.residents(of: $0) }
        func expected(_ lang: AppLanguage, _ states: [String], _ night: (Int) -> String, _ level: String, _ live: (Int) -> String) -> [String] {
            Lang.current = lang
            return town.buildings.indices.map { i in
                var p = [states[i], night(i), level]
                if people[i] > 0 { p.append(live(people[i])) }
                return p.joined(separator: ", ")
            }
        }
        // order of the snapshot: complete, complete, ruins, unfinished
        let en = values(.en)
        #expect(en == expected(.en, ["Complete", "Complete", "In ruins", "Unfinished"],
                               { "Night of \(Fmt.fullDate(town.buildings[$0].nightKey))" }, "Level 1", { L("\($0) people live here") }))
        #expect(en.allSatisfy { $0.contains("Night of") && $0.contains("Level 1") })
        #expect(en[3].hasPrefix("Unfinished, ") && en[2].hasPrefix("In ruins, "))
        // residents are read only when there are any
        let sk = values(.sk), cs = values(.cs)
        #expect(sk[0].hasPrefix("Hotová, Noc na ") && sk[0].contains("Level 1"))
        #expect(sk[3].hasPrefix("Rozostavaná, ") && sk[2].hasPrefix("V ruinách, "))
        #expect(cs[0].hasPrefix("Hotová, Noc na ") && cs[0].contains("Úroveň 1"))
        #expect(cs[3].hasPrefix("Nedokončená, ") && cs[2].hasPrefix("V ruinách, "))
        for (l, v) in [("en", en), ("sk", sk), ("cs", cs)] { for x in v { print("13Y \(l): House | \(x)") } }
    }

    @Test func aChangedValueRefreshesTheElements() {
        let town = snapshot()
        let view = TownSKView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let scene = TownScene(size: view.bounds.size)
        scene.imageProvider = { sprites.image(for: $0) }
        scene.cameraDefaults = UserDefaults(suiteName: "TownAccessibilityTests-\(UUID().uuidString)")!
        view.presentScene(scene)
        scene.show(TownRender.build(town, catalog: sprites.catalog!, today: NightKey("2026-10-10")!, calendar: .current), focus: nil)
        view.summary = "S"
        view.entries = TownAccessibility.entries(town, name: { _ in "House" }, level: { _ in 1 })
        let first = (view.accessibilityElements ?? []).compactMap { $0 as? TownAccessibilityElement }
        #expect(first[1].accessibilityValue?.contains("Level 1") == true)
        view.entries = TownAccessibility.entries(town, name: { _ in "House" }, level: { _ in 2 })
        let second = (view.accessibilityElements ?? []).compactMap { $0 as? TownAccessibilityElement }
        #expect(second[1].accessibilityValue?.contains("Level 2") == true)
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

    /// A zoomed-in town on a phone-sized view (camera scale 3, so every building is narrower than the view).
    func zoomedTown() -> (view: TownSKView, scene: TownScene, count: Int) {
        let ids = ["l1-block-a-0", "l1-bigblock-e", "l2-library-a", "l3-firestation", "l4-sky-a-0", "l1-house-a-0", "l2-library-a"]
        let k = NightKey("2026-10-01")!
        let results = ids.enumerated().map { i, id in NightResult(key: k.adding(days: i, calendar: .current), outcome: .complete, buildingId: id) }
        let town = TownBuilder.build(results: results, catalog: sprites.catalog!)
        let model = TownRender.build(town, catalog: sprites.catalog!, today: NightKey("2026-10-20")!, calendar: .current)
        let view = TownSKView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let scene = TownScene(size: view.bounds.size)
        scene.imageProvider = { sprites.image(for: $0) }
        scene.cameraDefaults = UserDefaults(suiteName: "TownAccessibilityTests-\(UUID().uuidString)")!
        scene.reduceMotion = { true }
        view.presentScene(scene)
        scene.show(model, focus: nil)
        view.entries = TownAccessibility.entries(town) { _ in "B" }
        view.summary = "Summary"
        scene.zoom(by: scene.camera!.xScale / 3.0, at: CGPoint(x: 201, y: 437), in: view)
        return (view, scene, ids.count)
    }

    @Test func aThreeFingerSwipeMovesTheCameraAndStopsAtTheEdge() {
        let (view, scene, _) = zoomedTown()
        let start = scene.camera!.position
        #expect(view.accessibilityScroll(.left))                                  // shows what is to the right
        #expect(scene.camera!.position.x > start.x)
        #expect(view.accessibilityScroll(.right))
        #expect(view.accessibilityScroll(.down) || view.accessibilityScroll(.up))
        var guardCount = 0
        while view.accessibilityScroll(.left), guardCount < 100 { guardCount += 1 }   // at the edge: false
        #expect(guardCount < 100 && !view.accessibilityScroll(.left))
    }

    @Test func focusingABuildingOutsideTheViewBringsItIn() {
        let (view, scene, count) = zoomedTown()
        let model = scene.model!
        var tried = 0
        for i in 0..<count {
            scene.pan(by: CGPoint(x: 0, y: 0))
            // look at every building from the far side so that at least one starts outside
            _ = view.accessibilityScroll(i % 2 == 0 ? .left : .right)
            guard let f = TownSKView.viewFrame(ofBuilding: i, in: model, scene: scene), !view.bounds.contains(f) else { continue }
            tried += 1
            let els = (view.accessibilityElements ?? []).compactMap { $0 as? TownAccessibilityElement }
            els.first { $0.buildingIndex == i }?.accessibilityElementDidBecomeFocused()
            let after = TownSKView.viewFrame(ofBuilding: i, in: model, scene: scene)!
            #expect(view.bounds.contains(after), "building \(i)")
        }
        #expect(tried > 0)
    }
}

