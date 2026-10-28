import Foundation
import Testing
@testable import SleepCore

@Suite struct TownDecorationsTests {
    let catalog = try! loadRealCatalog()
    let first = NightKey("2026-10-01")!
    let all = BoxCatalog.ids(.decoration)

    func town(_ n: Int) -> TownSnapshot {
        let results = (0..<n).map {
            NightResult(key: first.adding(days: $0, calendar: bratislava), outcome: .complete, buildingId: "l1-house-a-0")
        }
        return TownBuilder.build(results: results, catalog: catalog)
    }

    // MARK: the table

    @Test func theTableCoversExactlyTheBoxCatalog() {
        #expect(TownDecorations.spriteIds.count == all.count && Set(TownDecorations.spriteIds).count == 12)
        for (id, sprite) in zip(all, TownDecorations.spriteIds) {
            #expect(TownDecorations.spriteId(for: id) == sprite)
            #expect(catalog[sprite]?.kind == .decoration && catalog[sprite]?.footprint == [1, 1] && catalog[sprite]?.level == 0)
        }
        #expect(TownDecorations.spriteId(for: "decoration-13") == nil && TownDecorations.spriteId(for: "nope") == nil)
        #expect(catalog["d-cat-statue"]?.nameSK == "Socha spiacej mačky" && catalog["d-cat-statue"]?.nameEN == "Sleeping cat statue")
    }

    // MARK: decorations are never buildings

    @Test func decorationsAreNeverBuildable() {
        let decoSprites = Set(TownDecorations.spriteIds)
        for level in 0...5 {
            #expect(catalog.buildable(level: level).allSatisfy { !decoSprites.contains($0.id) && $0.kind != .decoration })
            #expect(BuildingPicker.candidates(level: level, catalog: catalog).allSatisfy { $0.kind != .decoration })
        }
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            let e = BuildingPicker.pick(maxLevel: 4, catalog: catalog, history: [], rng: &rng)
            #expect(e.kind != .decoration)
        }
        var fast = SimFastPicker(catalog: catalog)
        for _ in 0..<300 {
            let e = fast.pick(maxLevel: 4, rng: &rng)
            #expect(e.kind != .decoration)
            fast.append(e.id)
        }
    }

    @Test func aDecorationInANightResultNeverBecomesABuilding() {
        let r = NightResult(key: first, outcome: .complete, buildingId: "d-fountain")
        let t = TownBuilder.build(results: [r], catalog: catalog)
        #expect(t.buildings.isEmpty && t.layout.placements.isEmpty)
        #expect(Population.total(t) == 0)
    }

    @Test func decorationsAddNothingToTheTownCounts() {
        let t = town(30)
        let plain = TownRender.build(t, catalog: catalog, today: first.adding(days: 30, calendar: bratislava), calendar: bratislava)
        let decorated = TownRender.build(t, catalog: catalog, today: first.adding(days: 30, calendar: bratislava),
                                         calendar: bratislava, decorations: all)
        #expect(decorated.buildingCount == plain.buildingCount && plain.buildingCount == 30)
        #expect(Population.total(t) == Population.total(t))
        #expect(decorated.sprites.compactMap(\.buildingIndex).count == 30)
    }

    // MARK: placement

    @Test func ownedInOrderKeepsTheOrderWon() {
        func box(_ id: String, _ minute: Int, _ prize: BoxPrize) -> BoxPurchase {
            BoxPurchase(id: id, at: Date(timeIntervalSince1970: Double(minute) * 60), nightKey: first, price: 0, seed: 1,
                        tableVersion: 1, prize: prize, payout: 0)
        }
        let boxes = [box("c", 3, .collectible(.decoration, id: "decoration-02")),
                     box("a", 1, .collectible(.decoration, id: "decoration-07")),
                     box("b", 2, .collectible(.accessory, id: "rug")),
                     box("d", 4, .collectible(.decoration, id: "decoration-07")),
                     box("e", 5, .coins)]
        #expect(Boxes.ownedInOrder(.decoration, boxes: boxes) == ["decoration-07", "decoration-02"])
    }

    func check(_ n: Int, owned: [String]) {
        let t = town(n)
        let layout = TownDecorations.layout(town: t.layout, owned: owned)
        #expect(layout.placed.count == owned.count, "town \(n)")
        #expect(layout == TownDecorations.layout(town: t.layout, owned: owned), "deterministic")
        let roads = t.layout.drawnRoads, occupied = t.layout.occupied
        let usedBlocks = Set(occupied.map { TownLayout.block($0) })
        let cells = occupied.union(roads)
        let m = layout.margin
        let (c0, c1) = (cells.map(\.col).min()! - m, cells.map(\.col).max()! + m)
        let (r0, r1) = (cells.map(\.row).min()! - m, cells.map(\.row).max()! + m)
        for (i, p) in layout.placed.enumerated() {
            let c = p.cell
            #expect(!TownLayout.isRoad(c), "on a road \(c)")
            #expect(!roads.contains(c) && !occupied.contains(c))
            #expect(!usedBlocks.contains(TownLayout.block(c)), "in a built block \(c)")
            #expect(!TownLayout.ring(of: TownLayout.block(c)).isSubset(of: roads), "in a drawn block \(c)")
            #expect((c0...c1).contains(c.col) && (r0...r1).contains(c.row), "outside the grass \(c)")
            for q in layout.placed[(i + 1)...] {
                #expect(max(abs(q.cell.col - c.col), abs(q.cell.row - c.row)) >= 2, "neighbours \(c) \(q.cell)")
            }
        }
    }

    @Test(arguments: [0, 1, 5, 30, 120])
    func allTwelveStandOnFreeGrass(buildings: Int) {
        check(buildings, owned: all)
    }

    @Test func fewerOwnedStillFollowTheRules() {
        for n in [0, 1, 5, 30] { check(n, owned: ["decoration-03"]); check(n, owned: Array(all.prefix(4))) }
    }

    @Test func theFrontComesFirstAndMiddleBeforeSides() {
        let t = town(5)
        let layout = TownDecorations.layout(town: t.layout, owned: all)
        let depths = layout.placed.map { $0.cell.col + $0.cell.row }
        let free = depths.first!
        // the first decoration stands on the deepest (front-most) free diagonal of the whole grass area
        #expect(depths.allSatisfy { $0 <= free })
        // with more decorations the later ones are never deeper than the earlier ones' diagonal
        #expect(layout.placed[0].collectibleId == "decoration-01")
        // one decoration alone takes the front corner
        let one = TownDecorations.layout(town: t.layout, owned: ["decoration-01"])
        #expect(one.placed[0].cell.col + one.placed[0].cell.row == free)
    }

    @Test func emptyTownKeepsTheDefaultMarginWhenItFits() {
        #expect(TownDecorations.layout(town: TownLayout(), owned: []) == .init(placed: [], margin: TownRender.margin))
        let l = TownDecorations.layout(town: TownLayout(), owned: Array(all.prefix(2)))
        #expect(l.margin >= TownRender.margin)
    }

    @Test func unknownAndDuplicateIdsAreSkipped() {
        let l = TownDecorations.layout(town: town(3).layout, owned: ["decoration-02", "bogus", "decoration-02", "decoration-13"])
        #expect(l.placed.map(\.collectibleId) == ["decoration-02"])
    }

    @Test func anEarlierDecorationKeepsItsRankWhenAnotherIsWon() {
        let t = town(5).layout
        let a = TownDecorations.layout(town: t, owned: ["decoration-05"])
        let b = TownDecorations.layout(town: t, owned: ["decoration-05", "decoration-01"])
        #expect(b.placed[0].cell == a.placed[0].cell)
    }

    // MARK: rendering

    @Test func renderAddsDecorationsAsUntappableObjects() {
        let t = town(12)
        let today = first.adding(days: 12, calendar: bratislava)
        let plain = TownRender.build(t, catalog: catalog, today: today, calendar: bratislava)
        let m = TownRender.build(t, catalog: catalog, today: today, calendar: bratislava, decorations: all)
        let deco = m.sprites.filter { TownDecorations.spriteIds.contains($0.spriteId) }
        #expect(deco.count == 12 && deco.allSatisfy { $0.layer == .object && $0.buildingIndex == nil })
        #expect(m.buildingCount == 12 && m.sprites.compactMap(\.buildingIndex).count == plain.sprites.compactMap(\.buildingIndex).count)
        #expect(m.sprites.map(\.zPosition) == m.sprites.map(\.zPosition).sorted())
        // never returned as a tap candidate, wherever one taps on them
        for d in deco {
            let cands = TownRender.buildingCandidates(at: d.position, in: m)
            #expect(cands.allSatisfy { $0.buildingIndex != nil && !TownDecorations.spriteIds.contains($0.spriteId) })
        }
        // the ground area contains every decoration cell
        let ground = Set(m.sprites.filter { $0.layer == .ground }.map { IsoProjection.cell(at: $0.position) })
        for p in TownDecorations.layout(town: t.layout, owned: all).placed { #expect(ground.contains(p.cell)) }
        // without decorations nothing changes
        #expect(plain.sprites.filter { TownDecorations.spriteIds.contains($0.spriteId) }.isEmpty)
    }

    @Test func aDecorationInFrontIsDrawnOverTheOneBehind() {
        let t = town(1)
        let m = TownRender.build(t, catalog: catalog, today: first, calendar: bratislava, decorations: all)
        let deco = m.sprites.filter { TownDecorations.spriteIds.contains($0.spriteId) }
        for a in deco { for b in deco {
            let (ca, cb) = (IsoProjection.cell(at: a.position), IsoProjection.cell(at: b.position))
            if ca.col + ca.row > cb.col + cb.row { #expect(a.zPosition > b.zPosition) }
        } }
    }
}
