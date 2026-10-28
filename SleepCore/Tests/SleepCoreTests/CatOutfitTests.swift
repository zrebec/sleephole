import Foundation
import Testing
@testable import SleepCore

@Suite struct CatOutfitTests {
    @Test func slotTableCoversExactlyTheCatalog() {
        let ids = BoxCatalog.ids(.accessory)
        for id in ids { #expect(AccessorySlot.of(id) != nil) }
        #expect(ids.count == 6)
        #expect(AccessorySlot.of("nightcap") == .head && AccessorySlot.of("top-hat") == .head
            && AccessorySlot.of("builder-helmet") == .head)
        #expect(AccessorySlot.of("sunglasses") == .face)
        #expect(AccessorySlot.of("fish-bowl") == .bed && AccessorySlot.of("rug") == .bed)
        #expect(AccessorySlot.of("postcard-01") == nil && AccessorySlot.of("") == nil)
    }

    @Test func idsKeepFirstValidPerSlot() {
        let o = CatOutfit(ids: ["bogus", "top-hat", "nightcap", "sunglasses", "rug", "fish-bowl"])
        #expect(o == CatOutfit(head: "top-hat", face: "sunglasses", bed: "rug"))
        #expect(CatOutfit(ids: []) == .none)
        #expect(CatOutfit(ids: ["x", "decoration-01"]).isEmpty)
    }

    @Test func wrongSlotIsIgnored() {
        let o = CatOutfit(head: "rug", face: "nightcap", bed: "sunglasses")
        #expect(o == .none)
    }

    @Test func layerOrderIsBedFaceHead() {
        #expect(CatOutfit(ids: ["nightcap", "sunglasses", "fish-bowl"]).layers == ["fish-bowl", "sunglasses", "nightcap"])
        #expect(CatOutfit(ids: ["builder-helmet"]).layers == ["builder-helmet"])
        #expect(CatOutfit.none.layers.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        let o = CatOutfit(ids: ["top-hat", "rug"])
        let back = try JSONDecoder().decode(CatOutfit.self, from: JSONEncoder().encode(o))
        #expect(back == o)
    }
}
