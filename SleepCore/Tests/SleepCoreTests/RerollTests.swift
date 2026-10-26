import Foundation
import Testing
@testable import SleepCore

@Suite struct RerollTests {
    @Test func priceIs400Then800ThenNone() {
        #expect(Reroll.price(drawsMade: 0) == 400)
        #expect(Reroll.price(drawsMade: 1) == 800)
        #expect(Reroll.price(drawsMade: 2) == nil)
        #expect(Reroll.price(drawsMade: 7) == nil)
        #expect(Reroll.price(drawsMade: -1) == nil)
    }

    @Test func reasonRoundTripIgnoresOtherNightsAndKinds() {
        let a = Reroll.reason(nightKey: "2026-10-26", from: "l1-house-a-0")
        let b = Reroll.reason(nightKey: "2026-10-26", from: "l2-park-small")
        let other = Reroll.reason(nightKey: "2026-10-27", from: "l3-police")
        #expect(a == "reroll-2026-10-26:l1-house-a-0")
        let reasons = [other, "pause-2026-10-26", a, "town-rename", b]
        #expect(Reroll.drawnAway(nightKey: "2026-10-26", reasons: reasons) == ["l1-house-a-0", "l2-park-small"])
        #expect(Reroll.drawnAway(nightKey: "2026-10-27", reasons: reasons) == ["l3-police"])
        #expect(Reroll.drawnAway(nightKey: "2026-10-28", reasons: reasons).isEmpty)
    }

    @Test func pickNeverReturnsAnExcludedIdAndKeepsLevels() throws {
        let catalog = try loadRealCatalog()
        for seed in 1...200 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let first = BuildingPicker.pick(maxLevel: 2, catalog: catalog, history: [], rng: &rng)
            let second = BuildingPicker.pick(maxLevel: 2, catalog: catalog, history: [], excluding: [first.id], rng: &rng)
            #expect(second.id != first.id)
            #expect(second.level <= 2)
            let third = BuildingPicker.pick(maxLevel: 1, catalog: catalog, history: [],
                                            excluding: [first.id, second.id], rng: &rng)
            #expect(third.level == 1 && third.id != first.id && third.id != second.id)
        }
    }
}
