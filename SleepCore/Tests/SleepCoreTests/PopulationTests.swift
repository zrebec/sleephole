import Foundation
import Testing
@testable import SleepCore

@Suite struct PopulationTests {
    private func key(_ i: Int) -> NightKey { NightKey(year: 2026 + i / 372, month: i / 31 % 12 + 1, day: i % 31 + 1) }
    private func sample(_ id: String, _ n: Int = 2000) -> [Int] {
        (0..<n).map { Population.residents(buildingId: id, nightKey: key($0)) }
    }

    @Test(arguments: [("l1-house-a", 2, 14), ("l1-block-b", 24, 96), ("l1-bigblock-c", 180, 540),
                      ("l4-tower-d", 600, 1_400), ("l4-sky-e", 1_500, 4_000)])
    func rangesHold(id: String, lo: Int, hi: Int) {
        let s = sample(id)
        #expect(s.allSatisfy { (lo...hi).contains($0) })
        #expect(s.min()! < lo + (hi - lo) / 4 + 2 && s.max()! > hi - (hi - lo) / 4 - 2)   // really spread
    }

    @Test func bigBlockIsNotABlock() {
        #expect(sample("l1-bigblock-x", 200).allSatisfy { $0 >= 180 })
    }

    @Test(arguments: ["l1-park-1", "l2-library", "l2-museum", "l2-school", "l3-hospital", "l3-townhall",
                      "o-ruin-1", "o-road-lit", "l2-police", "l2-firestation"])
    func nobodyLivesThere(id: String) {
        #expect(Population.residents(buildingId: id, nightKey: key(1)) == 0)
    }

    @Test func houseDistributionIsRoughly70_25_5() {
        let s = sample("l1-house-a", 4000)
        let low = Double(s.filter { $0 <= 5 }.count) / 4000
        let mid = Double(s.filter { (6...9).contains($0) }.count) / 4000
        let high = Double(s.filter { $0 >= 10 }.count) / 4000
        #expect(abs(low - 0.70) < 0.04)
        #expect(abs(mid - 0.25) < 0.04)
        #expect(abs(high - 0.05) < 0.03)
    }

    @Test func deterministic() {
        let k = NightKey(year: 2026, month: 10, day: 3)
        #expect(Population.residents(buildingId: "l1-block-a", nightKey: k)
                == Population.residents(buildingId: "l1-block-a", nightKey: k))
        // Pinned values: a change of the hash or the draw order would renumber every town.
        #expect(Population.fnv1a64("a") == 0xaf63dc4c8601ec8c)
        #expect(Population.residents(buildingId: "l1-block-a", nightKey: k) == PopulationTests.pinnedBlock)
    }
    static let pinnedBlock = 41

    @Test func statesCountAsBefore() {
        let k = NightKey(year: 2026, month: 10, day: 3)
        let p = Placement(catalogId: "l1-block-a", origin: Cell(0, 0), size: 1)
        func b(_ s: BuildingState) -> TownBuilding {
            TownBuilding(placement: p, nightKey: k, buildingId: "l1-block-a", state: s)
        }
        let full = Population.residents(of: b(.complete))
        #expect(full > 0)
        #expect(Population.residents(of: b(.unfinished)) == full / 2)
        #expect(Population.residents(of: b(.ruins)) == 0)
    }

    @Test(arguments: [(0, TownSize.hamlet), (99, .hamlet), (100, .village), (999, .village), (1_000, .smallTown),
                      (4_999, .smallTown), (5_000, .town), (19_999, .town), (20_000, .city), (99_999, .city),
                      (100_000, .bigCity), (499_999, .bigCity), (500_000, .metropolis)])
    func sizeNames(n: Int, expected: TownSize) {
        #expect(TownSize.of(residents: n) == expected)
    }
}
