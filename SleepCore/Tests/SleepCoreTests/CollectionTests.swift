import Foundation
import Testing
@testable import SleepCore

@Suite struct CollectionTests {
    func box(_ n: Int, _ kind: CollectibleKind, _ id: String) -> BoxPurchase {
        BoxPurchase(id: "b\(n)", at: Date(timeIntervalSince1970: 1_800_000_000 + Double(n) * 86400),
                    nightKey: NightKey(year: 2026, month: 10, day: n), price: 400, seed: 1, tableVersion: 1,
                    prize: .collectible(kind, id: id), payout: 0)
    }

    var boxes: [BoxPurchase] {
        [box(1, .accessory, "nightcap"), box(2, .accessory, "sunglasses"), box(3, .accessory, "top-hat"),
         box(4, .sky, "sky-01"), box(5, .sky, "sky-03")]
    }

    // MARK: outfit

    @Test func neverChosenWearsTheNewestPerSlot() {
        #expect(Collection.effectiveOutfit(choice: nil, boxes: boxes) == CatOutfit(head: "top-hat", face: "sunglasses"))
        #expect(Collection.effectiveOutfit(choice: nil, boxes: []) == .none)
    }

    @Test func explicitNothingIsNothing() {
        #expect(Collection.effectiveOutfit(choice: "", boxes: boxes) == .none)
    }

    @Test func aChoiceKeepsOnlyOwnedIds() {
        #expect(Collection.effectiveOutfit(choice: "nightcap,sunglasses", boxes: boxes)
            == CatOutfit(head: "nightcap", face: "sunglasses"))
        #expect(Collection.effectiveOutfit(choice: "builder-helmet,rug,bogus,sunglasses", boxes: boxes)
            == CatOutfit(face: "sunglasses"))
    }

    @Test func aSlotChangeKeepsTheOthers() {
        let current = Collection.effectiveOutfit(choice: nil, boxes: boxes)            // top-hat + sunglasses, automatically
        let stored = Collection.storedOutfit(changing: .head, to: "nightcap", current: current)
        #expect(stored == "nightcap,sunglasses")
        #expect(Collection.effectiveOutfit(choice: stored, boxes: boxes) == CatOutfit(head: "nightcap", face: "sunglasses"))
        let bare = Collection.storedOutfit(changing: .face, to: nil, current: current)
        #expect(bare == "top-hat")
        #expect(Collection.storedOutfit(changing: .head, to: nil, current: CatOutfit(head: "top-hat")) == "")
        #expect(Collection.effectiveOutfit(choice: "", boxes: boxes) == .none)
    }

    @Test func firstWinsKeepTheFirstBoxOfEachItem() {
        let again = box(9, .accessory, "nightcap")                                       // a later repeat
        let wins = Collection.firstWins(.accessory, boxes: boxes + [again])
        #expect(wins.map(\.id) == ["nightcap", "sunglasses", "top-hat"])
        #expect(wins.first?.box.id == "b1")
        #expect(Collection.firstWins(.postcard, boxes: boxes).isEmpty)
    }

    // MARK: sky

    @Test func skyAutoNonePickedAndUnknown() {
        #expect(Collection.effectiveSky(choice: nil, boxes: boxes) == "sky-03")             // the newest
        #expect(Collection.effectiveSky(choice: nil, boxes: []) == nil)
        #expect(Collection.effectiveSky(choice: "none", boxes: boxes) == nil)
        #expect(Collection.effectiveSky(choice: "sky-01", boxes: boxes) == "sky-01")
        #expect(Collection.effectiveSky(choice: "sky-04", boxes: boxes) == "sky-03")        // not owned → auto
        #expect(Collection.effectiveSky(choice: "sky-04", boxes: []) == nil)
        #expect(Collection.storedSky(nil) == "none" && Collection.storedSky("sky-02") == "sky-02")
    }
}
