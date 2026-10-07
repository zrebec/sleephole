import Foundation
import Testing
@testable import SleepCore

@Suite struct PickerTests {
    let catalog = try! loadRealCatalog()

    @Test func onlyUnlockedLevels() {
        var rng = SeededGenerator(seed: 1)
        for _ in 0..<200 {
            let e = BuildingPicker.pick(maxLevel: 1, catalog: catalog, history: [], canUpgradeStreets: true, rng: &rng)
            #expect(e.level == 1)
        }
    }

    @Test func levelsAreRoughlyUniform() {
        var rng = SeededGenerator(seed: 2)
        var counts = [Int: Int]()
        for _ in 0..<4000 {
            let e = BuildingPicker.pick(maxLevel: 4, catalog: catalog, history: [], canUpgradeStreets: true, rng: &rng)
            counts[e.level, default: 0] += 1
        }
        for level in 1...4 { #expect((850...1150).contains(counts[level] ?? 0), "level \(level): \(counts)") }
    }

    @Test func neverRepeatsTheLastThree() {
        var rng = SeededGenerator(seed: 3)
        var history: [String] = []
        for _ in 0..<300 {
            let e = BuildingPicker.pick(maxLevel: 3, catalog: catalog, history: history, canUpgradeStreets: true, rng: &rng)
            #expect(!history.suffix(3).contains(e.id))
            history.append(e.id)
        }
    }

    @Test func prefersBuildingsNotYetInTown() {
        var rng = SeededGenerator(seed: 4)
        var history: [String] = []
        let l3 = catalog.buildable(level: 3).count
        for _ in 0..<l3 {
            history.append(BuildingPicker.pick(maxLevel: 3, catalog: catalog, history: history,
                                               canUpgradeStreets: false, rng: &rng).id)
        }
        let l3Picks = history.filter { $0.hasPrefix("l3-") }
        #expect(Set(l3Picks).count == l3Picks.count)             // no L3 duplicate before all were built
    }

    @Test func litStreetsAreOneItemAndOnlyWhenPossible() {
        let c2 = BuildingPicker.candidates(level: 2, catalog: catalog, canUpgradeStreets: true)
        #expect(c2.filter { $0.kind == .roadLit }.count == 1)
        #expect(c2.count == 9)
        let none = BuildingPicker.candidates(level: 2, catalog: catalog, canUpgradeStreets: false)
        #expect(none.allSatisfy { $0.kind != .roadLit })
    }
}

@Suite struct TownLayoutTests {
    let catalog = try! loadRealCatalog()

    func grownTown(nights: Int, seed: UInt64 = 5) -> TownLayout {
        var town = TownLayout()
        var rng = SeededGenerator(seed: seed)
        var history: [String] = []
        for n in 0..<nights {
            let maxLevel = Progression.unlockedMaxLevel(builtBefore: n)
            let e = BuildingPicker.pick(maxLevel: maxLevel, catalog: catalog, history: history,
                                        canUpgradeStreets: town.canUpgradeStreets, rng: &rng)
            if e.kind == .roadLit { town.upgradeStreets() } else { town.place(e) }
            history.append(e.id)
        }
        return town
    }

    @Test func roadGrid() {
        #expect(TownLayout.isRoad(Cell(0, 7)) && TownLayout.isRoad(Cell(3, -5)) && TownLayout.isRoad(Cell(-10, 1)))
        #expect(!TownLayout.isRoad(Cell(1, 1)) && !TownLayout.isRoad(Cell(-1, -4)) && !TownLayout.isRoad(Cell(4, 4)))
    }

    @Test func firstBuildingsHugTheCentre() {
        var town = TownLayout()
        let house = catalog["l1-house-a-0"]!
        let first = (0..<16).map { _ in town.place(house).origin }
        #expect(Set(first.map(TownLayout.block)).count == 1)          // one central block fills up first
        #expect(first.allSatisfy { max(abs($0.col), abs($0.row)) <= 4 })
    }

    @Test func noOverlapsNoRoadsAndTwoByTwoInsideOneBlock() {
        let town = grownTown(nights: 120)
        var seen = Set<Cell>()
        for p in town.placements {
            for c in p.cells {
                #expect(!TownLayout.isRoad(c), "\(p.catalogId) on road \(c)")
                #expect(seen.insert(c).inserted, "overlap at \(c)")
            }
            #expect(Set(p.cells.map(TownLayout.block)).count == 1, "\(p.catalogId) straddles blocks")
        }
    }

    @Test func deterministic() {
        #expect(grownTown(nights: 60, seed: 9) == grownTown(nights: 60, seed: 9))
    }

    @Test func townStaysCompact() {
        let town = grownTown(nights: 100)
        let radius = town.occupied.map { max(abs($0.col), abs($0.row)) }.max()!
        // 100 nights ≈ 300+ cells (most L2–L4 buildings are 2×2) ≈ 20 blocks → the 3rd block ring,
        // whose outermost cells are 14 from the centre
        #expect(radius <= 14, "radius \(radius)")
    }

    @Test func everyDrawnRoadHasASprite() {
        let town = grownTown(nights: 80)
        let roads = town.drawnRoads
        #expect(!town.litRoads.isEmpty)
        for cell in roads {
            let id = RoadTiles.spriteId(at: cell, roads: roads, lit: town.litRoads, catalog: catalog)
            #expect(catalog[id] != nil, "missing sprite \(id)")
        }
    }

    // MARK: roads first (streets are drawn one block ahead of the houses)

    @Test func emptyTownDrawsTheFirstBlocksRing() {
        let town = TownLayout()
        let ring = TownLayout.ring(of: TownLayout.blocks(ring: 1)[0])
        #expect(TownLayout.blocks(ring: 1)[0] == Cell(-1, -1))
        #expect(ring.count == 20)
        #expect(town.drawnRoads == ring)
        #expect(town.builtRoads.isEmpty)
        #expect(ring.allSatisfy { TownLayout.isRoad($0) })
    }

    @Test func oneHouseOutlinesItsBlockAndTheNextOne() {
        var town = TownLayout()
        town.place(catalog["l1-house-a-0"]!)
        let spiral = TownLayout.blocks(ring: 1)
        let roads = town.drawnRoads
        #expect(roads == TownLayout.ring(of: spiral[0]).union(TownLayout.ring(of: spiral[1])))
        #expect(town.builtRoads.isSubset(of: roads))
    }

    @Test func frontierMovesOnWhenABlockIsFull() {
        var town = TownLayout()
        for _ in 0..<6 { town.place(catalog["l1-house-a-0"]!) }
        for _ in 0..<2 { town.place(catalog["l3-police"]!) }
        let spiral = TownLayout.blocks(ring: 1)
        #expect(town.placements.allSatisfy { TownLayout.block($0.origin) == Cell(-1, -1) })
        #expect(town.drawnRoads == TownLayout.ring(of: spiral[0]).union(TownLayout.ring(of: Cell(0, -1))))
        let p = town.place(catalog["l3-police"]!)
        #expect(TownLayout.block(p.origin) == Cell(0, -1))
        #expect(town.drawnRoads == TownLayout.ring(of: spiral[0]).union(TownLayout.ring(of: Cell(0, -1)))
            .union(TownLayout.ring(of: Cell(0, 0))))
    }

    @Test func drawnRoadsOnlyGrowAndCoverBuiltRoads() {
        var town = TownLayout()
        var rng = SeededGenerator(seed: 5)
        var history: [String] = []
        var previous = town.drawnRoads
        for n in 0..<60 {
            let e = BuildingPicker.pick(maxLevel: Progression.unlockedMaxLevel(builtBefore: n), catalog: catalog,
                                        history: history, canUpgradeStreets: town.canUpgradeStreets, rng: &rng)
            if e.kind == .roadLit { town.upgradeStreets() } else { town.place(e) }
            history.append(e.id)
            let now = town.drawnRoads
            #expect(previous.isSubset(of: now), "a ring disappeared at night \(n)")
            #expect(town.builtRoads.isSubset(of: now))
            previous = now
        }
    }

    @Test func lightsStayNextToHousesOnStraightStreets() {
        var town = grownTown(nights: 40)
        let taken = town.occupied
        for _ in 0..<30 { town.upgradeStreets() }
        let roads = town.drawnRoads
        #expect(!town.litRoads.isEmpty)
        for cell in town.litRoads {
            let touches = (-1...1).contains { dc in (-1...1).contains { dr in taken.contains(cell.offset(dc, dr)) } }
            let mask = RoadTiles.mask(at: cell, roads: roads)
            #expect(touches, "lit \(cell) touches no house")
            #expect(mask == "EW" || mask == "NS", "lit \(cell) is \(mask)")
        }
    }

    @Test func roadMasks() {
        let roads: Set<Cell> = [Cell(0, 0), Cell(1, 0), Cell(2, 0), Cell(0, 1)]
        #expect(RoadTiles.mask(at: Cell(1, 0), roads: roads) == "EW")
        #expect(RoadTiles.mask(at: Cell(0, 0), roads: roads) == "ES")
        #expect(RoadTiles.spriteId(at: Cell(1, 0), roads: roads, lit: [], catalog: catalog) == "t-road-straight-ew")
        #expect(RoadTiles.spriteId(at: Cell(1, 0), roads: roads, lit: [Cell(1, 0)], catalog: catalog) == "l2-road-lit-we")
        #expect(RoadTiles.spriteId(at: Cell(2, 0), roads: roads, lit: [], catalog: catalog) == "t-road-end-w")
    }

    @Test func bigBuildingsStillFitWhenSmallOnesCameFirst() {
        var town = TownLayout()
        for _ in 0..<12 { town.place(catalog["l1-house-a-0"]!) }
        let big = town.place(catalog["l3-police"]!)
        #expect(TownLayout.block(big.origin) == TownLayout.block(town.placements[0].origin))
    }

    @Test func streetUpgradeLightsFourStraights() {
        var town = grownTown(nights: 20)
        let before = town.litRoads.count
        let lit = town.upgradeStreets()
        #expect(lit.count == 4 && town.litRoads.count == before + 4)
    }
}

/// Dev aid: `DUMP_TOWN=/path/town.json swift test --filter dumpTown` writes a simulated town
/// (placements + drawn roads with sprite ids) for `tools/render/layout_preview.py`.
@Test func dumpTown() throws {
    guard let path = ProcessInfo.processInfo.environment["DUMP_TOWN"] else { return }
    let nights = Int(ProcessInfo.processInfo.environment["DUMP_NIGHTS"] ?? "") ?? 60
    let catalog = try loadRealCatalog()
    var town = TownLayout()
    var rng = SeededGenerator(seed: 11)
    var history: [String] = []
    for n in 0..<nights {
        let e = BuildingPicker.pick(maxLevel: Progression.unlockedMaxLevel(builtBefore: n), catalog: catalog,
                                    history: history, canUpgradeStreets: town.canUpgradeStreets, rng: &rng)
        if e.kind == .roadLit { town.upgradeStreets() } else { town.place(e) }
        history.append(e.id)
    }
    let roads = town.drawnRoads
    var items: [[String: Any]] = town.placements.map {
        ["id": $0.catalogId, "col": $0.origin.col, "row": $0.origin.row, "size": $0.size]
    }
    items += roads.map { ["id": RoadTiles.spriteId(at: $0, roads: roads, lit: town.litRoads, catalog: catalog),
                          "col": $0.col, "row": $0.row, "size": 1] }
    try JSONSerialization.data(withJSONObject: items).write(to: URL(fileURLWithPath: path))
}
