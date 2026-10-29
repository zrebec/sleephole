import Foundation
import Testing
@testable import SleepCore

/// Step 11b3: the mystery box rules – catalog, price, offer, odds D, the draw, the joker rule and the lucky night.
@Suite struct BoxRulesTests {
    func key(_ s: String) -> NightKey { NightKey(s)! }

    func box(_ id: String, _ night: String = "2026-10-20", price: Int = 400, prize: BoxPrize = .coins, payout: Int = 0,
             seed: UInt64 = 1, at secs: TimeInterval = 0) -> BoxPurchase {
        BoxPurchase(id: id, at: Date(timeIntervalSince1970: 1_800_000_000 + secs), nightKey: key(night), price: price,
                    seed: seed, tableVersion: 1, prize: prize, payout: payout)
    }

    // MARK: catalog

    @Test func catalogSizesAndUniqueIds() {
        #expect(CollectibleKind.allCases.map { BoxCatalog.size($0) } == [30, 12, 6, 4])
        for k in CollectibleKind.allCases { #expect(Set(BoxCatalog.ids(k)).count == BoxCatalog.size(k)) }
        let all = CollectibleKind.allCases.flatMap { BoxCatalog.ids($0) }
        #expect(Set(all).count == 52)
        #expect(BoxCatalog.ids(.postcard).first == "postcard-01" && BoxCatalog.ids(.postcard).last == "postcard-30")
        #expect(BoxCatalog.ids(.decoration).last == "decoration-12" && BoxCatalog.ids(.sky) == ["sky-01", "sky-02", "sky-03", "sky-04"])
        #expect(BoxCatalog.ids(.accessory) == ["nightcap", "top-hat", "builder-helmet", "sunglasses", "fish-bowl", "rug"])
    }

    // MARK: price

    @Test func priceExamples() {
        let expect: [(Int, Int, Int?)] = [
            (0, 1, 400), (1999, 1, 400), (2000, 1, 400), (2050, 1, 410), (5555, 1, 1110),
            (0, 4, 400), (1999, 4, 790), (2000, 4, 800), (2050, 4, 820), (5555, 4, 2220),
            (0, 7, 400), (1999, 7, 1190), (2000, 7, 1200), (2050, 7, 1230), (5555, 7, 3330),
            (5555, 10, nil), (0, 0, nil)]
        for (bal, n, want) in expect { #expect(BoxRules.price(balance: bal, boxNumber: n) == want, "\(bal) #\(n)") }
        #expect(BoxRules.price(balance: -50, boxNumber: 1) == 400)
    }

    @Test func productionMatchesTheSimulationTheOwnerChose() {
        for n in 1...9 {
            for bal in stride(from: 0, through: 12_000, by: 7) {
                if let sim = SimBoxRules.price(balance: bal, boxNumber: n) {
                    #expect(BoxRules.price(balance: bal, boxNumber: n) == sim)
                }
            }
            #expect(BoxRules.percent(boxNumber: n) == SimBoxRules.percent(boxNumber: n))
        }
        #expect(BoxRules.percent(boxNumber: 10) == nil && SimBoxRules.percent(boxNumber: 10) == nil)
        #expect(BoxRules.floorPrice == SimBoxRules.floor && BoxRules.maxPerMonth == SimBoxRules.maxPerMonth)
        let sim = SimOddsVariant.D.table
        #expect(sim.count == BoxRules.odds.count)
        for (s, o) in zip(sim, BoxRules.odds) {
            #expect(s.1 == o.permille)
            switch (s.0, o.roll) {
            case (.coins(let a), .coins(let b)): #expect(a == b)
            case (.luckyNight, .luckyNight): break
            case (.collectible(let c), .collectible(let k)):
                #expect(c.size == BoxCatalog.size(k) && c.rawValue == [CollectibleKind.postcard, .decoration, .accessory, .sky].firstIndex(of: k)!)
            case (.bronze, .joker(.bronze)), (.silver, .joker(.silver)): break
            default: Issue.record("odds row differs: \(s.0) vs \(o.roll)")
            }
        }
        #expect(BoxRules.odds.reduce(0) { $0 + $1.permille } == 1000)
        #expect(BoxRules.reserve == 1000 && BoxRules.tableVersion == 1)
    }

    @Test func theReserve() {
        #expect(BoxRules.canAfford(balance: 400, price: 400, firstEver: true))
        #expect(!BoxRules.canAfford(balance: 399, price: 400, firstEver: true))
        #expect(!BoxRules.canAfford(balance: 1399, price: 400, firstEver: false))
        #expect(BoxRules.canAfford(balance: 1400, price: 400, firstEver: false))
    }

    @Test func coinsMissing() {
        #expect(BoxRules.coinsMissing(balance: 1400, boxNumber: 1, firstEver: false) == 0)
        #expect(BoxRules.coinsMissing(balance: 1000, boxNumber: 1, firstEver: false) == 400)
        #expect(BoxRules.coinsMissing(balance: 0, boxNumber: 1, firstEver: true) == 400)
        #expect(BoxRules.coinsMissing(balance: -20, boxNumber: 1, firstEver: true) == 400)
        #expect(BoxRules.coinsMissing(balance: 100, boxNumber: 10, firstEver: false) == nil)
        // not monotone (box 7, 60 %): 2480 ok, 2489 not, 2490 ok
        func ok(_ b: Int) -> Bool { BoxRules.canAfford(balance: b, price: BoxRules.price(balance: b, boxNumber: 7)!, firstEver: false) }
        #expect(ok(2480) && !ok(2489) && ok(2490))
        #expect(BoxRules.coinsMissing(balance: 2489, boxNumber: 7, firstEver: false) == 1)
        #expect(BoxRules.coinsMissing(balance: 2480, boxNumber: 7, firstEver: false) == 0)
        // whatever it returns is the smallest d
        for bal in stride(from: 0, to: 4000, by: 13) {
            let d = BoxRules.coinsMissing(balance: bal, boxNumber: 4, firstEver: false)!
            let b = bal + d
            #expect(BoxRules.canAfford(balance: b, price: BoxRules.price(balance: b, boxNumber: 4)!, firstEver: false))
            for x in 0..<d {
                #expect(!BoxRules.canAfford(balance: bal + x, price: BoxRules.price(balance: bal + x, boxNumber: 4)!, firstEver: false))
            }
        }
    }

    // MARK: offer

    @Test func offerStatesAndOrder() {
        let today = key("2026-10-21")
        func offer(_ night: Outcome?, _ boxes: [BoxPurchase] = [], _ bal: Int = 3000) -> BoxOffer {
            BoxRules.offer(today: today, todaysNight: night, boxes: boxes, balance: bal)
        }
        #expect(offer(.complete) == .available(price: 600, boxNumber: 1))
        #expect(offer(.complete, [], 399) == .notEnoughCoins(price: 400, missing: 1, boxNumber: 1))     // first ever: no reserve
        #expect(offer(.complete, [box("a", "2026-10-20")], 1000) == .notEnoughCoins(price: 400, missing: 400, boxNumber: 2))
        for o in [Outcome.unfinished, .ruins, .missed, .excused] { #expect(offer(o) == .needsCompleteNight) }
        #expect(offer(nil) == .needsCompleteNight)
        #expect(offer(.complete, [box("a", "2026-10-21")]) == .alreadyBoughtToday)
        #expect(offer(.unfinished, [box("a", "2026-10-21")]) == .alreadyBoughtToday)                   // checked first
        let nine = (1...9).map { box("b\($0)", "2026-10-\(String(format: "%02d", $0))") }
        #expect(offer(.complete, nine) == .monthFull)
        #expect(offer(.unfinished, nine) == .monthFull)
        #expect(offer(.complete, [box("u", "2026-10-21", prize: .unknown("future"))]) == .alreadyBoughtToday)
        let one = offer(.complete, [box("u", "2026-10-20", prize: .unknown("future"))], 1500)
        #expect(one == .available(price: 400, boxNumber: 2))                                           // counts in the month and is not firstEver
    }

    @Test func monthBoundaries() {
        let oct = (1...9).map { box("b\($0)", "2026-10-\(String(format: "%02d", $0 + 20 > 31 ? $0 : $0 + 20))") }
        #expect(Set(oct.map(\.nightKey)).count == 9)
        #expect(BoxRules.offer(today: key("2026-10-30"), todaysNight: .complete, boxes: oct, balance: 9000) == .monthFull)
        #expect(BoxRules.offer(today: key("2026-11-01"), todaysNight: .complete, boxes: oct, balance: 9000)
                == .available(price: 1800, boxNumber: 1))
        let b31 = [box("x", "2026-10-31")]
        #expect(Boxes.count(inMonthOf: key("2026-10-01"), boxes: b31) == 1)
        #expect(BoxRules.offer(today: key("2026-11-01"), todaysNight: .complete, boxes: b31, balance: 3000)
                == .available(price: 600, boxNumber: 1))
        let dec = (1...9).map { box("d\($0)", "2026-12-\(String(format: "%02d", $0))") }
        #expect(BoxRules.offer(today: key("2026-12-31"), todaysNight: .complete, boxes: dec, balance: 9000) == .monthFull)
        #expect(BoxRules.offer(today: key("2027-01-01"), todaysNight: .complete, boxes: dec, balance: 9000)
                == .available(price: 1800, boxNumber: 1))
    }

    // MARK: the draw

    func draw(_ seed: UInt64, price: Int = 400, boxes: [BoxPurchase] = [], uses: [JokerUse] = [],
              night: String = "2026-10-21") -> BoxDraw {
        BoxRules.draw(seed: seed, price: price, nightKey: key(night), boxes: boxes, uses: uses, calendar: bratislava)
    }

    /// A seed whose first roll lands on the given table row.
    func seed(for wanted: (BoxRoll) -> Bool) -> UInt64 {
        (0..<100_000).map(UInt64.init).first { wanted(draw($0).roll) }!
    }

    @Test func theDrawIsDeterministicAndMatchesTheTable() {
        #expect(draw(42) == draw(42))
        var counts: [Int: Int] = [:]
        let n = 100_000
        for s in 0..<UInt64(n) {
            let r = draw(s * 7919 + 13).roll
            counts[BoxRules.odds.firstIndex { $0.roll == r }!, default: 0] += 1
        }
        for (i, o) in BoxRules.odds.enumerated() {
            let expected = Double(n) * Double(o.permille) / 1000
            let sigma = (expected * (1 - Double(o.permille) / 1000)).squareRoot()
            #expect(abs(Double(counts[i, default: 0]) - expected) <= 5 * sigma + 1, "row \(i)")
        }
        let p = BoxRules.purchase(id: "z", at: Date(timeIntervalSince1970: 5), nightKey: key("2026-10-21"), price: 400, seed: 42,
                                  boxes: [], uses: [], calendar: bratislava)
        #expect(p.tableVersion == 1 && p.prize == draw(42).prize && p.payout == draw(42).payout && p.seed == 42)
    }

    @Test func coinPrizesPayAMultipleOfThePrice() {
        let s = seed { $0 == .coins(tenths: 5) }
        let d = draw(s, price: 410)
        #expect(d.prize == .coins && d.payout == 205)
        let s3 = seed { $0 == .coins(tenths: 30) }
        #expect(draw(s3, price: 410).payout == 1230)
        let l = draw(seed { $0 == .luckyNight })
        #expect(l.prize == .luckyNight && l.payout == 0)
    }

    @Test func aMissingItemComesFirst() {
        let s = seed { $0 == .collectible(.postcard) }
        let ids = BoxCatalog.ids(.postcard)
        let owned = ids.dropLast(0).enumerated().filter { $0.offset != 17 }.map {
            box("p\($0.offset)", "2026-09-\(String(format: "%02d", ($0.offset % 28) + 1))", prize: .collectible(.postcard, id: $0.element))
        }
        let d = draw(s, boxes: owned)
        #expect(d.prize == .collectible(.postcard, id: "postcard-18") && d.payout == 0)
        let all = ids.enumerated().map { box("p\($0.offset)", "2026-09-10", prize: .collectible(.postcard, id: $0.element)) }
        let dup = draw(s, price: 410, boxes: all)
        guard case .collectible(.postcard, let id) = dup.prize else { Issue.record("not a postcard"); return }
        #expect(ids.contains(id) && dup.payout == 102)
        // ids foreign to the catalog never count as owned
        let foreign = [box("f", "2026-09-10", prize: .collectible(.postcard, id: "tip-03"))]
        #expect(draw(s, boxes: foreign).payout == 0)
    }

    @Test func oneBoxJokerOfEachKindIsHeld() {
        let sb = seed { $0 == .joker(.bronze) }
        let first = BoxRules.purchase(id: "j1", at: Date(timeIntervalSince1970: 1), nightKey: key("2026-10-10"), price: 400, seed: sb,
                                      boxes: [], uses: [], calendar: bratislava)
        #expect(first.prize == .joker(.bronze) && first.payout == 0)
        let second = BoxRules.purchase(id: "j2", at: Date(timeIntervalSince1970: 2), nightKey: key("2026-10-20"), price: 410, seed: sb,
                                       boxes: [first], uses: [], calendar: bratislava)
        #expect(second.prize == .joker(.bronze) && second.payout == 102)
        let boxes = [first, second]
        let held = Boxes.heldJokers(boxes: boxes, uses: [], at: key("2026-10-25"), calendar: bratislava)
        #expect(held[.bronze]?.id == "j1" && held.count == 1)
        #expect(Boxes.wonJoker(first) == .bronze && Boxes.wonJoker(second) == nil)
        // a missed night after a complete one: the held bronze saves it, the converted one never
        let r = [NightResult(key: key("2026-10-21"), outcome: .complete, buildingId: "x"),
                 NightResult(key: key("2026-10-22"), outcome: .missed, buildingId: nil),
                 NightResult(key: key("2026-10-23"), outcome: .complete, buildingId: "x"),
                 NightResult(key: key("2026-10-24"), outcome: .missed, buildingId: nil)]
        let used = Jokers.apply(results: r, manual: [], lastNight: key("2026-10-24"), calendar: bratislava, boxes: boxes).uses
        #expect(used.compactMap(\.boxId) == ["j1"])
        #expect(!used.contains { $0.boxId == "j2" })
        #expect(Jokers.block(.bronze, firstNight: key("2026-10-25"), uses: [], coins: 0, boxId: "j2", boxes: boxes,
                             calendar: bratislava) == .notHeldFromBox)
        #expect(Jokers.block(.bronze, firstNight: key("2026-10-25"), uses: [], coins: 0, boxId: "j1", boxes: boxes,
                             calendar: bratislava) == nil)
        // used → the next one is held again
        let usedJ = [JokerUse(tier: .bronze, firstNight: key("2026-10-22"), automatic: true, boxId: "j1")]
        let third = BoxRules.purchase(id: "j3", at: Date(timeIntervalSince1970: 3), nightKey: key("2026-10-23"), price: 400, seed: sb,
                                      boxes: [first], uses: usedJ, calendar: bratislava)
        #expect(third.payout == 0)
        // expired → the next one is held again (j1 from 10 Oct lasts through 30 Nov)
        let later = BoxRules.purchase(id: "j4", at: Date(timeIntervalSince1970: 4), nightKey: key("2026-12-01"), price: 400, seed: sb,
                                      boxes: [first], uses: [], calendar: bratislava)
        #expect(later.payout == 0)
        // a silver does not interfere with the bronze
        let ss = seed { $0 == .joker(.silver) }
        #expect(draw(ss, boxes: [first]).payout == 0)
    }

    // MARK: lucky night

    func nights(_ start: String, _ outcomes: [Outcome]) -> [NightResult] {
        outcomes.enumerated().map {
            NightResult(key: key(start).adding(days: $0.offset, calendar: bratislava), outcome: $0.element, buildingId: "x", pauses: 0,
                        calmHours: 2, calmHoursTotal: 2)
        }
    }

    @Test func luckyNightDoublesTheNextCompleteNight() {
        let n = nights("2026-10-01", [.complete, .complete, .unfinished, .complete])
        let plain = Economy.ledger(n, calendar: bratislava)
        #expect(plain.allSatisfy { $0.luckyBonus == 0 })
        #expect(plain == Economy.ledger(n, calendar: bratislava, boxes: []))
        let lucky = box("L", "2026-10-02", prize: .luckyNight)
        let l = Economy.ledger(n, calendar: bratislava, boxes: [lucky])
        #expect(l[1].luckyBonus == 0)                                         // the box's own night is never doubled
        #expect(l[2].luckyBonus == 0 && l[2].coins == plain[2].coins)         // unfinished: it waits
        #expect(l[3].luckyBonus == plain[3].coins && l[3].coins == plain[3].coins * 2)
        #expect(Economy.earned(n, calendar: bratislava, boxes: [lucky]) == plain.reduce(0) { $0 + $1.coins } + plain[3].coins)
    }

    @Test func luckyNightDoublesTheStreakBonusAndTwoBoxesTwoNights() {
        let n = nights("2026-10-01", Array(repeating: .complete, count: 9))
        let plain = Economy.ledger(n, calendar: bratislava)
        #expect(plain[6].streakBonus == 200)
        let one = Economy.ledger(n, calendar: bratislava, boxes: [box("L", "2026-10-06", prize: .luckyNight)])
        #expect(one[6].luckyBonus == plain[6].coins && one[6].luckyBonus > 300)                // the 7th night: streak bonus doubled too
        #expect(one.filter { $0.luckyBonus > 0 }.count == 1)
        let two = Economy.ledger(n, calendar: bratislava, boxes: [box("L2", "2026-10-06", prize: .luckyNight, at: 5),
                                                                   box("L1", "2026-10-06", prize: .luckyNight, at: 1)])
        #expect(two.filter { $0.luckyBonus > 0 }.map(\.key) == [key("2026-10-07"), key("2026-10-08")])
        // ruins / missed / excused wait as well
        let m = nights("2026-10-01", [.complete, .ruins, .missed, .excused, .complete])
        let lm = Economy.ledger(m, calendar: bratislava, boxes: [box("L", "2026-10-01", prize: .luckyNight)])
        #expect(lm.filter { $0.luckyBonus > 0 }.map(\.key) == [key("2026-10-05")])
    }

    @Test func theReceiptWithTheLuckyLineAddsUp() throws {
        let n = nights("2026-10-01", [.complete, .complete])
        let e = Economy.ledger(n, calendar: bratislava, boxes: [box("L", "2026-10-01", prize: .luckyNight)])[1]
        let r = try #require(Economy.Receipt(e, calmTotal: 2))
        #expect(r.lines.last?.kind == .luckyNight && r.lines.last?.amount == e.luckyBonus)
        #expect(r.total == e.coins)
        let withAch = r.addingAchievements(50)
        #expect(withAch.lines.last?.kind == .achievements && withAch.lines[withAch.lines.count - 2].kind == .luckyNight)
    }
}

/// The weekly journal and the statistics must show the same coins as the balance (a lucky night ×2 included).
@Suite struct BoxCoinsEverywhereTests {
    @Test func journalWeekAndStatsFollowTheLuckyNight() {
        let first = NightKey("2026-10-06")!                       // a Tuesday morning: the week of Monday 5 Oct
        let results = (0..<4).map {
            NightResult(key: first.adding(days: $0, calendar: bratislava), outcome: .complete, buildingId: "x")
        }
        let lucky = BoxPurchase(id: "L", at: Date(timeIntervalSince1970: 1_800_000_000), nightKey: first, price: 400, seed: 1,
                                tableVersion: 1, prize: .luckyNight, payout: 0)
        let monday = NightKey("2026-10-05")!
        let plain = WeeklyJournal.week(monday: monday, results: results, calendar: bratislava)
        let doubled = WeeklyJournal.week(monday: monday, results: results, calendar: bratislava, boxes: [lucky])
        let night = Economy.ledger(results, calendar: bratislava)[1].coins
        #expect(doubled.coins == plain.coins + night && plain.coins == Economy.earned(results, calendar: bratislava))
        #expect(WeeklyJournal.weeks(results: results, calendar: bratislava, boxes: [lucky]).first { $0.monday == monday }?.coins
                == doubled.coins)
        #expect(WeeklyJournal.week(monday: monday, results: results, calendar: bratislava, boxes: []).coins == plain.coins)
        let today = first.adding(days: 5, calendar: bratislava)
        let s = Stats.summary(results, today: today, calendar: bratislava, boxes: [lucky])
        #expect(s.coins == Economy.earned(results, calendar: bratislava, boxes: [lucky]) && s.coins == plain.coins + night)
        #expect(Stats.summary(results, today: today, calendar: bratislava).coins == plain.coins)
    }
}
