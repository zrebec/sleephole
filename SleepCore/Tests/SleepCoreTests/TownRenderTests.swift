import Foundation
import Testing
@testable import SleepCore

@Suite struct TownRenderTests {
    let catalog = try! loadRealCatalog()
    let first = NightKey("2026-10-01")!

    func results(_ items: [(String, Outcome)]) -> [NightResult] {
        items.enumerated().map { i, it in
            NightResult(key: first.adding(days: i, calendar: bratislava), outcome: it.1, buildingId: it.0)
        }
    }

    // MARK: projection

    @Test func projectionMatchesTheRendererContract() {
        #expect(IsoProjection.scenePoint(x: 0, z: 0) == ScenePoint(x: 0, y: 0))
        #expect(IsoProjection.scenePoint(x: 1, z: 0) == ScenePoint(x: 128, y: -64))    // east = down-right
        #expect(IsoProjection.scenePoint(x: 0, z: 1) == ScenePoint(x: -128, y: -64))   // south = down-left
        #expect(IsoProjection.scenePoint(x: 0.5, z: 0.5) == ScenePoint(x: 0, y: -64))
    }

    @Test(arguments: [(0, 0), (3, -2), (-7, 4), (12, 12), (-5, -9)])
    func cellRoundTrip(col: Int, row: Int) {
        let p = IsoProjection.scenePoint(x: Double(col), z: Double(row))
        #expect(IsoProjection.cell(at: ScenePoint(x: p.x + 20, y: p.y - 10)) == Cell(col, row))
    }

    // MARK: builder

    @Test func missedNightsLeaveNoTrace() {
        let t = TownBuilder.build(results: results([("l1-house-a-0", .missed), ("l1-house-b-0", .complete)]),
                                  catalog: catalog)
        #expect(t.buildings.map(\.buildingId) == ["l1-house-b-0"])
    }

    @Test func statesFollowOutcomes() {
        let t = TownBuilder.build(results: results([("l1-house-a-0", .complete), ("l1-house-b-0", .ruins),
                                                    ("l3-police", .unfinished)]), catalog: catalog)
        #expect(t.buildings.map(\.state) == [.complete, .ruins, .unfinished])
        #expect(t.buildings[2].placement.size == 2)
    }

    @Test func aGoodNightFinishesTheOldestUnfinished() {
        let t = TownBuilder.build(results: results([("l1-house-a-0", .unfinished), ("l1-house-b-0", .unfinished),
                                                    ("l1-house-c-0", .complete)]), catalog: catalog)
        #expect(t.buildings[0].state == .complete && t.buildings[0].completedLater)
        #expect(t.buildings[1].state == .unfinished)
    }

    @Test func aGoodNightRepairsTheOldestRuinWhenNothingIsUnfinished() {
        let t = TownBuilder.build(results: results([("l1-house-a-0", .ruins), ("l1-house-b-0", .ruins),
                                                    ("l1-house-c-0", .complete)]), catalog: catalog)
        #expect(t.buildings[0].state == .complete && t.buildings[0].repairedLater)
        #expect(t.buildings[1].state == .ruins)
        // unfinished first, ruins second – one per good night
        let u = TownBuilder.build(results: results([("l1-house-a-0", .ruins), ("l1-house-b-0", .unfinished),
                                                    ("l1-house-c-0", .complete)]), catalog: catalog)
        #expect(u.buildings[0].state == .ruins && u.buildings[1].completedLater)
        // lit-street ruins stay ruins (nothing to rebuild)
        let lit = TownBuilder.build(results: results([("l2-road-lit-we", .ruins), ("l1-house-c-0", .complete)]),
                                    catalog: catalog)
        #expect(lit.buildings[0].state == .ruins)
    }

    @Test func litStreetsUpgradeRoadsOrBecomeARuin() {
        var items: [(String, Outcome)] = (0..<6).map { _ in ("l1-house-a-0", .complete) }
        items.append(("l2-road-lit-we", .complete))
        let t = TownBuilder.build(results: results(items), catalog: catalog)
        #expect(t.layout.litRoads.count == 4 && t.buildings.count == 6)
        let ruined = TownBuilder.build(results: results([("l2-road-lit-we", .ruins)]), catalog: catalog)
        #expect(ruined.buildings.first?.placement.catalogId == "o-ruin-1")
    }

    @Test func unknownIdsAreSkipped() {
        let t = TownBuilder.build(results: [NightResult(key: first, outcome: .complete, buildingId: "nope")],
                                  catalog: catalog)
        #expect(t.buildings.isEmpty)
    }

    // MARK: render model

    func model(_ items: [(String, Outcome)], today: NightKey? = nil) -> (TownSnapshot, TownRenderModel) {
        let t = TownBuilder.build(results: results(items), catalog: catalog)
        return (t, TownRender.build(t, catalog: catalog, today: today ?? first.adding(days: items.count, calendar: bratislava),
                                    calendar: bratislava))
    }

    @Test func emptyTownIsAGrassPatch() {
        let (_, m) = model([])
        #expect(m.buildingCount == 0)
        #expect(m.sprites.allSatisfy { $0.layer == .ground })
        #expect(m.sprites.count == 25)                               // 5×5 around the origin
    }

    @Test func layersAreOrderedGroundRoadObject() {
        let (_, m) = model([("l1-house-a-0", .complete), ("l3-police", .complete)])
        let layers = m.sprites.map(\.layer.rawValue)
        #expect(layers == layers.sorted())
        #expect(m.sprites.contains { $0.layer == .road })
        #expect(m.sprites.filter { $0.layer == .object }.count == 2)
    }

    @Test func noGrassUnderRoads() {
        let (t, m) = model([("l1-house-a-0", .complete)])
        let roadCells = t.layout.drawnRoads
        for s in m.sprites where s.layer == .ground {
            let cell = IsoProjection.cell(at: s.position)
            #expect(!roadCells.contains(cell))
        }
    }

    @Test func unfinishedGetsScaffoldAndPartialReveal() {
        let (_, m) = model([("l1-house-a-0", .unfinished)])
        let objs = m.sprites.filter { $0.layer == .object }
        #expect(objs.map(\.spriteId) == ["l1-house-a-0", "o-scaffold-1"])
        #expect(objs[0].reveal == TownRender.unfinishedReveal && objs[1].buildingIndex == nil)
    }

    @Test func ruinsBloomAfterAWeek() {
        let items: [(String, Outcome)] = [("l3-police", .ruins)]      // no later good night → stays a ruin
        #expect(model(items, today: first.adding(days: 6, calendar: bratislava)).1.sprites.contains { $0.spriteId == "o-ruin-2" })
        #expect(model(items, today: first.adding(days: 7, calendar: bratislava)).1.sprites.contains { $0.spriteId == "o-ruin-flowers-2" })
    }

    @Test func tapFindsTheFrontMostBuilding() {
        let (t, m) = model([("l1-house-a-0", .complete), ("l1-house-b-0", .complete)])
        for (i, b) in t.buildings.enumerated() {
            let (x, z) = b.placement.centre
            let p = IsoProjection.scenePoint(x: x, z: z)
            let tap = ScenePoint(x: p.x, y: p.y + 30)
            let candidates = TownRender.buildingCandidates(at: tap, in: m)
            #expect(candidates.contains { $0.buildingIndex == i })
            let c = candidates.first { $0.buildingIndex == i }!
            let px = TownRender.pixel(of: tap, in: c)
            #expect(px.x >= 0 && px.x < Int(c.size[0]) && px.y >= 0 && px.y < Int(c.size[1]))
        }
        #expect(TownRender.buildingCandidates(at: ScenePoint(x: 99_999, y: 0), in: m).isEmpty)
        // front-most first
        let zs = TownRender.buildingCandidates(at: ScenePoint(x: 0, y: -100), in: m).map(\.zPosition)
        #expect(zs == zs.sorted(by: >))
    }

    @Test func boundsContainEverySpriteAndClampWorks() {
        let (_, m) = model((0..<20).map { _ in ("l1-house-a-0", .complete) })
        for s in m.sprites { #expect(m.bounds.union(s.frame) == m.bounds) }
        let far = TownRender.clamp(ScenePoint(x: 1e6, y: -1e6), to: m.bounds)
        #expect(far == ScenePoint(x: m.bounds.maxX, y: m.bounds.minY))
        #expect(TownRender.clamp(m.bounds.mid, to: m.bounds) == m.bounds.mid)
        #expect(m.bounds.width > 0 && m.bounds.height > 0)
    }

    @Test func bigTownPerformance() {
        let items: [(String, Outcome)] = (0..<150).map { i in (i % 3 == 0 ? "l4-sky-a-0" : "l1-house-a-0", .complete) }
        let (_, m) = model(items)
        #expect(m.buildingCount == 150)
        #expect(m.sprites.count < 3000)
    }
}
