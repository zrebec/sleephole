import Foundation
import Testing
@testable import SleepCore

@Suite struct BoxesTests {
    func key(_ s: String) -> NightKey { NightKey(s)! }

    func box(_ id: String, _ night: String, price: Int = 400, payout: Int = 0, prize: BoxPrize = .coins,
             seed: UInt64 = 1) -> BoxPurchase {
        BoxPurchase(id: id, at: Date(timeIntervalSince1970: 1_800_000_000), nightKey: key(night), price: price, seed: seed,
                    tableVersion: 1, prize: prize, payout: payout)
    }

    // MARK: prize encoding

    @Test func prizeRoundTrip() {
        let prizes: [BoxPrize] = [.coins, .luckyNight, .joker(.bronze), .joker(.silver),
                                  .collectible(.postcard, id: "tip-07"), .collectible(.sky, id: "aurora"),
                                  .collectible(.accessory, id: "a:b:c")]
        for p in prizes { #expect(BoxPrize(encoded: p.encoded) == p) }
        #expect(BoxPrize.collectible(.decoration, id: "x").encoded == "item:decoration:x")
    }

    @Test func garbledPrizeDecodesToNil() {
        for s in ["", "coin", "coins:1", "item", "item:postcard", "item:postcard:", "item:flag:x", "joker", "joker:gold",
                  "joker:platinum", "lucky:1", "::", "item::x", "ITEM:postcard:x"] {
            #expect(BoxPrize(encoded: s) == nil, "\(s)")
        }
    }

    @Test func storedPrizeNeverFailsAndKeepsUnreadableText() {
        #expect(BoxPrize(stored: "item:frame:x1") == .unknown("item:frame:x1"))
        #expect(BoxPrize(stored: "item:frame:x1").encoded == "item:frame:x1")
        #expect(BoxPrize(stored: "joker:gold").encoded == "joker:gold")
        #expect(BoxPrize(stored: "joker:silver") == .joker(.silver))
        #expect(BoxPrize(encoded: "item:frame:x1") == nil)                  // the strict reader stays strict
    }

    @Test func anUnknownPrizeCountsForCoinsAndBoxCountsOnly() {
        let u = box("u", "2026-10-31", price: 500, payout: 100, prize: .unknown("item:frame:x1"))
        let boxes = [u, box("v", "2026-10-30")]
        #expect(Boxes.coinDelta(boxes) == (100 - 500) + (0 - 400))
        #expect(Boxes.count(inMonthOf: key("2026-10-02"), boxes: boxes) == 2)
        #expect(Boxes.bought(on: key("2026-10-31"), boxes: boxes))
        #expect(CollectibleKind.allCases.allSatisfy { Boxes.owned($0, boxes: [u]).isEmpty })
        #expect(Boxes.heldJokers(boxes: [u], uses: [], at: key("2026-11-05"), calendar: bratislava).isEmpty)
        #expect(Jokers.block(.bronze, firstNight: key("2026-11-05"), uses: [], coins: 0, boxId: "u", boxes: [u],
                             calendar: bratislava) == .notHeldFromBox)
    }

    // MARK: derived numbers

    @Test func coinDeltaIsPayoutMinusPrice() {
        #expect(Boxes.coinDelta([]) == 0)
        let boxes = [box("a", "2026-10-30", price: 400, payout: 200), box("b", "2026-10-31", price: 500, payout: 0),
                     box("c", "2026-11-01", price: 600, payout: 1800)]
        #expect(Boxes.coinDelta(boxes) == (200 - 400) + (0 - 500) + (1800 - 600))
    }

    @Test func monthCountAcrossAMonthBoundary() {
        let boxes = [box("a", "2026-10-31"), box("b", "2026-11-01"), box("c", "2026-11-30"), box("d", "2026-10-01")]
        #expect(Boxes.count(inMonthOf: key("2026-10-15"), boxes: boxes) == 2)
        #expect(Boxes.count(inMonthOf: key("2026-11-01"), boxes: boxes) == 2)
        #expect(Boxes.count(inMonthOf: key("2026-12-01"), boxes: boxes) == 0)
        #expect(Boxes.count(inMonthOf: key("2026-10-31"), boxes: boxes) == 2)
    }

    @Test func monthCountAcrossAYearBoundary() {
        let boxes = [box("a", "2026-12-31"), box("b", "2027-01-01"), box("c", "2025-12-31")]
        #expect(Boxes.count(inMonthOf: key("2026-12-05"), boxes: boxes) == 1)      // the same month of another year is not it
        #expect(Boxes.count(inMonthOf: key("2027-01-20"), boxes: boxes) == 1)
    }

    @Test func boughtOnANight() {
        let boxes = [box("a", "2026-10-31")]
        #expect(Boxes.bought(on: key("2026-10-31"), boxes: boxes))
        #expect(!Boxes.bought(on: key("2026-11-01"), boxes: boxes) && !Boxes.bought(on: key("2026-10-30"), boxes: boxes))
    }

    @Test func ownedCollectibles() {
        let boxes = [box("a", "2026-10-01", prize: .collectible(.postcard, id: "p1")),
                     box("b", "2026-10-02", prize: .collectible(.postcard, id: "p1")),     // a duplicate
                     box("c", "2026-10-03", prize: .collectible(.postcard, id: "p2")),
                     box("d", "2026-10-04", prize: .collectible(.sky, id: "aurora")),
                     box("e", "2026-10-05", prize: .joker(.bronze)), box("f", "2026-10-06")]
        #expect(Boxes.owned(.postcard, boxes: boxes) == ["p1", "p2"])
        #expect(Boxes.owned(.sky, boxes: boxes) == ["aurora"])
        #expect(Boxes.owned(.accessory, boxes: boxes).isEmpty)
    }

    // MARK: box jokers

    @Test func expiryIsTheEndOfTheNextMonth() {
        let cal = bratislava
        func exp(_ s: String) -> NightKey { Boxes.expiry(of: box("x", s), calendar: cal) }
        #expect(exp("2026-10-31") == key("2026-11-30"))
        #expect(exp("2026-10-01") == key("2026-11-30"))
        #expect(exp("2026-12-15") == key("2027-01-31"))
        #expect(exp("2026-12-31") == key("2027-01-31"))
        #expect(exp("2027-01-20") == key("2027-02-28"))
        #expect(exp("2028-01-05") == key("2028-02-29"))          // a leap February
        #expect(exp("2026-11-30") == key("2026-12-31"))
        #expect(exp("2026-01-31") == key("2026-02-28"))
    }

    @Test func heldJokersValidityWindow() {
        let cal = bratislava
        let b = box("b1", "2026-10-31", prize: .joker(.bronze))
        func held(_ at: String, uses: [JokerUse] = []) -> [JokerTier: BoxPurchase] {
            Boxes.heldJokers(boxes: [b], uses: uses, at: key(at), calendar: cal)
        }
        #expect(held("2026-10-31").isEmpty)                      // not on the purchase night itself
        #expect(held("2026-11-01")[.bronze]?.id == "b1")
        #expect(held("2026-11-30")[.bronze]?.id == "b1")         // the last valid day
        #expect(held("2026-12-01").isEmpty)                      // gone after the expiry
        let used = JokerUse(tier: .bronze, firstNight: key("2026-11-05"), automatic: true, boxId: "b1")
        #expect(held("2026-11-10", uses: [used]).isEmpty)        // gone once used
        let other = JokerUse(tier: .bronze, firstNight: key("2026-11-05"), automatic: true)
        #expect(held("2026-11-10", uses: [other])[.bronze] != nil)   // a use without a box id spends none
    }

    @Test func heldJokersPicksTheEarlierExpiringAndSkipsOthers() {
        let cal = bratislava
        let late = box("late", "2026-11-10", prize: .joker(.silver))
        let early = box("early", "2026-10-20", prize: .joker(.silver))
        let coins = box("coins", "2026-10-21")
        let gold = box("second", "2026-10-22", prize: .joker(.silver))
        let held = Boxes.heldJokers(boxes: [late, early, coins, gold], uses: [], at: key("2026-11-12"), calendar: cal)
        #expect(held.count == 1)
        #expect(held[.silver]?.id != "late")
        // "early" (Oct 20) and "second" (Oct 22) expire both on 30 Nov; the earlier purchase wins the tie
        #expect(held[.silver]?.id == "early")
        #expect(held[.bronze] == nil)
    }
}

/// The joker rules with jokers won from boxes.
@Suite struct BoxJokerTests {
    let first = NightKey("2026-11-01")!
    func key(_ day: Int) -> NightKey { first.adding(days: day - 1, calendar: bratislava) }      // November days

    func results(_ days: [(Int, Outcome)]) -> [NightResult] {
        days.map { NightResult(key: key($0.0), outcome: $0.1, buildingId: "l1-house-a-0") }
    }

    func bronzeBox(_ id: String = "bb", night: String = "2026-10-31", prize: BoxPrize = .joker(.bronze)) -> BoxPurchase {
        BoxPurchase(id: id, at: Date(timeIntervalSince1970: 1_800_000_000), nightKey: NightKey(night)!, price: 400, seed: 1,
                    tableVersion: 1, prize: prize, payout: 0)
    }

    func apply(_ r: [NightResult], manual: [JokerUse] = [], last: Int, boxes: [BoxPurchase]) -> (results: [NightResult], uses: [JokerUse]) {
        Jokers.apply(results: r, manual: manual, lastNight: key(last), calendar: bratislava, boxes: boxes)
    }

    @Test func boxBronzeIsUsedOnlyAfterTheMonthsOwnBronze() {
        // 1–2 complete, 3 missed (the month's own bronze), 4 complete, 5 missed (the box bronze), 6 complete, 7 missed
        let r = results([(1, .complete), (2, .complete), (4, .complete), (6, .complete)])
        let (out, uses) = apply(r, last: 7, boxes: [bronzeBox()])
        #expect(uses == [JokerUse(tier: .bronze, firstNight: key(3), automatic: true),
                         JokerUse(tier: .bronze, firstNight: key(5), automatic: true, boxId: "bb")])
        #expect(out.first { $0.key == key(5) }?.outcome == .excused)
        #expect(out.first { $0.key == key(7) } == nil)               // the third miss is not saved: both are used
        #expect(Progression.currentStreak(out, lastNight: key(6), calendar: bratislava) == 4)       // 1, 2, 4, 6 – excused nights neither grow nor break
    }

    @Test func withoutBoxesNothingChanges() {
        let r = results([(1, .complete), (2, .complete), (4, .complete), (6, .complete)])
        let a = apply(r, last: 7, boxes: [])
        let b = Jokers.apply(results: r, manual: [], lastNight: key(7), calendar: bratislava)
        #expect(a.results == b.results && a.uses == b.uses)
        #expect(a.uses.count == 1)
    }

    @Test func boxBronzeNotUsedWhenExpired() {
        // the box of 31 Oct is valid through 30 Nov; the second miss is on 1 Dec
        let dec1 = NightKey("2026-12-01")!
        let r = [NightResult(key: NightKey("2026-11-28")!, outcome: .complete, buildingId: "x"),
                 NightResult(key: NightKey("2026-11-29")!, outcome: .complete, buildingId: "x")]
        // 11-30 missed → the month's own bronze; 12-01 missed → a new month: its own bronze, so use a miss pair in December
        let r2 = r + [NightResult(key: NightKey("2026-12-02")!, outcome: .complete, buildingId: "x")]
        let (_, uses) = Jokers.apply(results: r2, manual: [], lastNight: NightKey("2026-12-04")!, calendar: bratislava,
                                     breaks: [], boxes: [bronzeBox()])
        // 11-30 → own November bronze; 12-01 → December's own bronze; 12-03 and 12-04 would need a box bronze: expired
        #expect(uses.map(\.firstNight) == [NightKey("2026-11-30")!, dec1])
        #expect(uses.allSatisfy { $0.boxId == nil })
    }

    @Test func boxBronzeNotUsedBeforeItsPurchaseNightOrTwice() {
        let r = results([(1, .complete), (2, .complete), (4, .complete), (6, .complete), (8, .complete)])
        // the box is bought after night 4 → it cannot save night 3 or earlier, but may save night 5
        let late = bronzeBox(night: "2026-11-04")
        let (_, uses) = apply(r, last: 9, boxes: [late])
        #expect(uses.map(\.boxId) == [nil, "bb"] && uses.map(\.firstNight) == [key(3), key(5)])
        // one box = one use: nights 7 and 9 stay missed
        #expect(uses.count == 2)
    }

    @Test func aBoxBronzeAlreadyUsedByHandIsNotUsedAgain() {
        let r = results([(1, .complete), (2, .complete), (4, .complete), (6, .complete)])
        let manual = [JokerUse(tier: .bronze, firstNight: key(5), boxId: "bb")]
        let (_, uses) = apply(r, manual: manual, last: 7, boxes: [bronzeBox()])
        // 3 → the month's own bronze (the hand-used box bronze did not take it); 5 → the manual box bronze; 7 → nothing left
        #expect(uses.map(\.firstNight) == [key(3), key(5)])
        #expect(uses.filter { $0.boxId == "bb" }.count == 1)
    }

    @Test func noTwoJokersForOneNight() {
        // a manual silver covers 3–5; night 4 would be missed too, still only the silver is used
        let r = results([(1, .complete), (2, .complete), (6, .complete)])
        let manual = [JokerUse(tier: .silver, firstNight: key(3))]
        let (out, uses) = apply(r, manual: manual, last: 6, boxes: [bronzeBox()])
        #expect(uses == manual)
        #expect(out.filter { $0.outcome == .excused }.count == 3)
    }

    @Test func aBoxSilverIsManualAndLeavesTheMonthsSilverFree() {
        let silverBox = bronzeBox("sb", prize: .joker(.silver))
        let r = results([(1, .complete), (2, .complete), (6, .complete), (7, .complete)])
        let boxUse = JokerUse(tier: .silver, firstNight: key(3), boxId: "sb")
        let (out, uses) = apply(r, manual: [boxUse], last: 7, boxes: [silverBox])
        #expect(uses == [boxUse])                                    // never used by itself
        #expect(out.filter { $0.outcome == .excused }.map(\.key) == [key(3), key(4), key(5)])
        #expect(Progression.currentStreak(out, lastNight: key(7), calendar: bratislava) == 4)
        // the month's own silver is still free for the same month
        #expect(Jokers.block(.silver, firstNight: key(8), uses: uses, coins: 1000) == nil)
        // and a bought silver does not free a box silver's slot
        #expect(Jokers.block(.silver, firstNight: key(8), uses: [JokerUse(tier: .silver, firstNight: key(8))], coins: 1000)
                == .alreadyUsedThisMonth)
    }

    @Test func aBoxBronzeUsedByHandKeepsTheMonthsOwnBronze() {
        let r = results([(1, .complete), (2, .complete), (4, .complete)])
        let manual = [JokerUse(tier: .bronze, firstNight: key(3), boxId: "bb")]
        let (_, uses) = apply(r, manual: manual, last: 4, boxes: [bronzeBox()])
        #expect(uses == manual)                                      // night 3 is covered; no automatic bronze needed
        #expect(Jokers.block(.bronze, firstNight: key(10), uses: uses, coins: 0) == nil)    // the month's own slot is free
    }

    @Test func blockWithABox() {
        let cal = bratislava
        let b = bronzeBox()
        let silver = bronzeBox("sb", prize: .joker(.silver))
        func block(_ tier: JokerTier, _ night: Int, id: String?, uses: [JokerUse] = [], coins: Int = 0) -> Jokers.Block? {
            Jokers.block(tier, firstNight: key(night), uses: uses, coins: coins, boxId: id, boxes: [b, silver], calendar: cal)
        }
        #expect(block(.bronze, 3, id: "bb") == nil)                  // held, no coins needed
        #expect(block(.silver, 3, id: "sb", coins: 0) == nil)        // a box silver costs nothing
        #expect(block(.silver, 3, id: "bb") == .notHeldFromBox)      // that box holds a bronze
        #expect(block(.bronze, 3, id: "nope") == .notHeldFromBox)
        #expect(block(.bronze, 3, id: "bb", uses: [JokerUse(tier: .bronze, firstNight: key(1), automatic: true, boxId: "bb")])
                == .notHeldFromBox)                                  // used up
        #expect(block(.bronze, 3, id: "bb", uses: [JokerUse(tier: .bronze, firstNight: key(2))]) == nil)   // the month's own is taken: irrelevant
        // expired: 31 Oct box, valid through 30 Nov
        let dec = Jokers.block(.bronze, firstNight: NightKey("2026-12-01")!, uses: [], coins: 0, boxId: "bb", boxes: [b], calendar: cal)
        #expect(dec == .notHeldFromBox)
        // without a box id the old rule stands, price included
        #expect(block(.silver, 3, id: nil, coins: 10) == .notEnoughCoins(missing: 990))
    }
}
