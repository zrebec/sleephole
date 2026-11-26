import Foundation
import Testing
@testable import SleepCore

/// Build 14, step 14a1: coin rule 1 (`CoinRule.playerLevel`) – the pay follows the player's level, a consistency
/// multiplier of the last 10 nights replaces the +200 streak bonus. Nights without a marker keep the old rule
/// (pinned in `EconomyOldRulePinTests`, `EconomyTests`).
@Suite struct EconomyCoinRuleTests {
    /// The night the example plays on.
    let k = NightKey("2026-11-27")!
    func day(_ offset: Int) -> NightKey { k.adding(days: offset, calendar: bratislava) }

    func night(_ key: NightKey, _ o: Outcome = .complete, pauses: Int? = 0, calm: Int = 0, rule: Int? = 1,
               building: String? = "l1-house-a-0", test: Bool? = nil) -> NightResult {
        NightResult(key: key, outcome: o, buildingId: building, pauses: pauses,
                    calmHours: o.isBuildNight ? calm : nil, calmHoursTotal: o.isBuildNight ? 7 : nil,
                    isTestNight: test, coinRule: rule)
    }

    /// A history that ends with `tonight` on key `k`: `playerBuilt` build nights before it in total, `others` of them
    /// (complete, directly before `k`) inside its window, the rest long before it.
    func history(playerBuilt: Int, others: Int, tonight: NightResult) -> [NightResult] {
        precondition(others <= 9 && playerBuilt >= others)
        var rs: [NightResult] = []
        for i in 0..<(playerBuilt - others) { rs.append(night(day(-200 + i))) }
        for i in stride(from: others, through: 1, by: -1) { rs.append(night(day(-i))) }
        rs.append(tonight)
        return rs
    }

    func last(_ rs: [NightResult], boxes: [BoxPurchase] = []) -> Economy.Entry {
        Economy.ledger(rs, calendar: bratislava, boxes: boxes).last!
    }

    func luckyBox(after key: NightKey, id: String = "lucky") -> BoxPurchase {
        BoxPurchase(id: id, at: Date(timeIntervalSince1970: 1_800_000_000), nightKey: key, price: 400, seed: 1,
                    tableVersion: 1, prize: .luckyNight, payout: 0)
    }

    // MARK: - the owner's six examples

    @Test func goldenExampleOne_theOwnersRealNight() {      // L4, complete, 1 pause, 7 calm, n = 7 → 235 → 268
        let e = last(history(playerBuilt: 30, others: 6, tonight: night(k, pauses: 1, calm: 7)))
        #expect(e.playerLevel == 4 && e.levelBonus == 100 && e.windowNights == 7)
        #expect(e.base == 100 && e.undisturbedBonus == 0 && e.calmBonus == 35)
        #expect(e.coins == 268 && e.multiplierBonus == 33 && e.luckyBonus == 0 && e.streakBonus == 0)
        let r = Economy.Receipt(e, calmTotal: 7)!
        #expect(r.lines.map(\.amount) == [100, 100, 35, 33] && r.total == 268)
    }

    @Test func goldenExampleTwo_firstNightNoPause() {       // L1 first night, complete, no pause, 7 calm, n = 1 → 185 → 189
        let e = last([night(k, pauses: 0, calm: 7)])
        #expect(e.playerLevel == 1 && e.windowNights == 1)
        #expect(e.coins == 189 && e.multiplierBonus == 4)
        #expect(Economy.Receipt(e, calmTotal: 7)!.lines.map(\.amount) == [100, 20, 30, 35, 4])
    }

    @Test func goldenExampleThree_unfinishedL4() {          // L4 unfinished, 3 calm, n = 10 → 115 → 138
        let e = last(history(playerBuilt: 30, others: 9, tonight: night(k, .unfinished, pauses: nil, calm: 3)))
        #expect(e.playerLevel == 4 && e.windowNights == 10)
        #expect(e.base == 50 && e.levelBonus == 50 && e.calmBonus == 15 && e.undisturbedBonus == 0)
        #expect(e.coins == 138 && e.multiplierBonus == 23)
        let r = Economy.Receipt(e, calmTotal: 7)!
        #expect(r.lines.map(\.amount) == [50, 50, 15, 23] && r.total == 138)
        #expect(r.lines.map(\.kind) == [.unfinishedNight, .playerLevelHalf(level: 4), .calmHours(calm: 3, total: 7),
                                        .multiplier(nights: 10, percent: 120)])
    }

    @Test func goldenExampleFour_anExactHalfGoesUp() {      // L1 complete, 1 pause, 1 calm, n = 1 → 125 → 128 (127.5)
        let e = last([night(k, pauses: 1, calm: 1)])
        #expect(e.coins == 128 && e.multiplierBonus == 3)
    }

    @Test func goldenExampleFive_luckyNight() {             // L4 complete, no pause, 8 calm, n = 10, lucky → 270 → 324 + 324
        let rs = history(playerBuilt: 30, others: 9, tonight: night(k, pauses: 0, calm: 8))
        let e = last(rs, boxes: [luckyBox(after: day(-1))])
        #expect(e.coins == 648 && e.luckyBonus == 324 && e.multiplierBonus == 54)
        let r = Economy.Receipt(e, calmTotal: 8)!
        #expect(r.lines.map(\.amount) == [100, 100, 30, 40, 54, 324] && r.total == 648)
        #expect(r.lines.last?.kind == .luckyNight)
    }

    @Test func goldenExampleSix_unfinishedL1() {            // L1 unfinished, 0 calm, n = 1 → 60 → 61
        let e = last([night(k, .unfinished, pauses: nil, calm: 0)])
        #expect(e.coins == 61 && e.base == 50 && e.levelBonus == 10 && e.multiplierBonus == 1)
        #expect(Economy.Receipt(e, calmTotal: nil)!.lines.map(\.amount) == [50, 10, 1])
    }

    // MARK: - the level

    @Test func theLevelFollowsTheBuiltNightsBeforeTonight() {
        // 40 nights in a row, an unfinished one among them counts as built
        let rs = (0..<40).map { night(day(-40 + $0), $0 == 3 ? .unfinished : .complete, pauses: 1) }
        let l = Economy.ledger(rs, calendar: bratislava)
        let bonus = l.map { $0.outcome == .unfinished ? $0.levelBonus * 2 : $0.levelBonus }
        #expect(bonus == (0..<40).map { $0 < 5 ? 20 : $0 < 15 ? 40 : $0 < 30 ? 60 : 100 })
        #expect(l.map(\.playerLevel) == (0..<40).map { $0 < 5 ? 1 : $0 < 15 ? 2 : $0 < 30 ? 3 : 4 })
        #expect(l[3].outcome == .unfinished && l[3].levelBonus == 10 && l[3].base == 50)
        #expect(l[3].windowNights == 4 && l[3].coins == 65)                  // 60 × 1.08 = 64.8
    }

    @Test func theSixthBuiltNightIsTheFirstOnLevelTwoAndShowsTheLevelAtItsStart() throws {
        let catalog = try loadRealCatalog()
        // the buildings drawn are level 1 houses and a level 3 police station: the pay ignores them
        let ids = ["l1-house-a-0", "l1-house-a-0", "l1-house-a-0", "l1-house-a-0", "l1-house-a-0", "l3-police", "l3-police"]
        let rs = ids.enumerated().map { night(day(-7 + $0.offset), pauses: 1, building: $0.element) }
        let l = Economy.ledger(rs, calendar: bratislava, catalog: catalog)
        #expect(l[4].playerLevel == 1 && l[4].levelBonus == 20)
        #expect(l[5].playerLevel == 2 && l[5].levelBonus == 40 && l[5].level == 3)       // the building's level stays
        #expect(l[0].level == 1 && l[0].playerLevel == 1)
        let r = Economy.Receipt(l[5], calmTotal: nil)!
        #expect(r.lines.map(\.kind).prefix(2) == [.night, .playerLevel(level: 2)])
    }

    // MARK: - the window

    @Test func theWindowCountsKeysOnceAndOnlyBuiltAndExcusedNights() {
        var rs: [NightResult] = []
        rs.append(night(day(-9), .complete))                       // K-9: the oldest night inside the window → counts
        rs.append(night(day(-10), .complete))                      // K-10: outside
        rs.append(night(day(-8), .excused, pauses: nil))           // a joker night counts
        rs.append(night(day(-7), .ruins, pauses: nil))             // a ruin does not
        // K-6 has no result at all; K-5 has two results (a counted test night): one key
        rs.append(night(day(-5), .complete))
        rs.append(night(day(-5), .unfinished, test: true))
        rs.append(night(day(-4), .missed, pauses: nil))            // missed does not
        rs.append(night(day(-3), .complete, rule: nil))            // a night of the old rule counts like any other
        rs.append(night(k, .complete))
        let e = Economy.ledger(rs, calendar: bratislava).last!
        #expect(e.windowNights == 5)                               // K-9, K-8, K-5, K-3, K
        #expect(e.coins == Economy.multiplied(e.base + e.levelBonus + e.undisturbedBonus + e.calmBonus, nights: 5))
    }

    @Test func theWindowNeverLooksAtLaterNightsAndKeysBeforeTheFirstResultDoNotCount() {
        let rs = (0..<12).map { night(day(-11 + $0), .complete) }
        let n = Economy.ledger(rs, calendar: bratislava).map(\.windowNights)
        #expect(n == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 10])
    }

    @Test func unpaidNightsOfTheNewRuleCarryNoReceiptAndNoCoins() {
        let rs = [night(day(-3), .ruins, pauses: nil), night(day(-2), .missed, pauses: nil), night(day(-1), .excused, pauses: nil)]
        let l = Economy.ledger(rs, calendar: bratislava)
        #expect(l.allSatisfy { $0.coins == 0 && $0.multiplierBonus == 0 && Economy.Receipt($0, calmTotal: nil) == nil })
    }

    // MARK: - rounding

    @Test func theMultiplierRoundsInIntegersAndHalvesGoUp() {
        for n in 1...10 {
            #expect(Economy.multiplierPercent(nights: n) == 100 + 2 * n)
            for sum in 50...400 {
                let exact = Double(sum) * Double(100 + 2 * n) / 100
                let total = Economy.multiplied(sum, nights: n)
                #expect(total == Int((exact + 0.5).rounded(.down)), "sum \(sum) n \(n)")
                #expect(total > sum)
            }
        }
        #expect(Economy.multiplied(125, nights: 1) == 128 && Economy.multiplied(235, nights: 7) == 268)
    }

    // MARK: - no streak bonus, mixed histories

    @Test func aNewRuleSeventhNightGetsNoPlusTwoHundredButTheRunKeepsCounting() {
        let rs = (0..<14).map { night(day(-14 + $0), pauses: 1) }
        let l = Economy.ledger(rs, calendar: bratislava)
        #expect(l.allSatisfy { $0.streakBonus == 0 })
        #expect(l[6].run == 7 && l[13].run == 14)
        #expect(l.allSatisfy { Economy.Receipt($0, calmTotal: nil)!.lines.allSatisfy { if case .streak = $0.kind { false } else { true } } })
    }

    @Test func aMixedHistoryKeepsThePlusTwoHundredOnOldNightsOnly() {
        // nights 1-5 of the old rule, nights 6-14 of the new one: the run goes on through both
        let rs = (0..<14).map { night(day(-14 + $0), pauses: 1, rule: $0 < 5 ? nil : 1) }
        let l = Economy.ledger(rs, calendar: bratislava)
        #expect(l.map(\.run) == Array(1...14))
        #expect(l[6].streakBonus == 0 && l[13].streakBonus == 0)       // new-rule 7th and 14th: nothing
        let old = Economy.ledger((0..<7).map { night(day(-7 + $0), pauses: 1, rule: nil) }, calendar: bratislava)
        #expect(old[6].streakBonus == 200 && old[6].rule == nil && old[6].playerLevel == 0)
        // the old 7th night is not touched by new-rule nights after it
        let both = old.map(\.coins) == Economy.ledger((0..<7).map { night(day(-7 + $0), pauses: 1, rule: nil) } +
                                                     [night(day(0), pauses: 1)], calendar: bratislava).dropLast().map(\.coins)
        #expect(both)
    }

    @Test func aMarkerFromALaterBuildIsPricedByTheNewestKnownRule() {
        let a = Economy.ledger([night(k, rule: 1)], calendar: bratislava).last!
        let b = Economy.ledger([night(k, rule: 7)], calendar: bratislava).last!
        #expect(a.coins == b.coins && b.rule == CoinRule.current)
        #expect(Economy.ledger([night(k, rule: 0)], calendar: bratislava).last!.rule == nil)       // 0 is no marker
    }

    // MARK: - the lucky night

    @Test func theLuckyNightDoublesTheMultipliedTotalOfTheFirstCompleteNightAfterTheBox() {
        // night -3 complete, the box comes after it; -2 unfinished (not doubled), -1 complete (doubled), tonight untouched
        let rs = [night(day(-3), pauses: 0), night(day(-2), .unfinished, pauses: nil),
                  night(day(-1), pauses: 0, calm: 2), night(k, pauses: 0)]
        let l = Economy.ledger(rs, calendar: bratislava, boxes: [luckyBox(after: day(-3))])
        #expect(l.map(\.luckyBonus) == [0, 0, l[2].coins / 2, 0])
        #expect(l[2].luckyBonus > 0 && l[2].coins == 2 * l[2].luckyBonus)
        #expect(Economy.Receipt(l[2], calmTotal: 7)!.total == l[2].coins)
        // a box bought the same morning as the night does not double that night (the key must be later)
        let same = Economy.ledger([night(k)], calendar: bratislava, boxes: [luckyBox(after: k)])
        #expect(same[0].luckyBonus == 0)
    }

    @Test func twoBoxesDoubleTwoNightsInOrder() {
        let rs = (0..<4).map { night(day(-4 + $0), pauses: 0) }
        let l = Economy.ledger(rs, calendar: bratislava, boxes: [luckyBox(after: day(-4), id: "a"), luckyBox(after: day(-4), id: "b")])
        #expect(l.map { $0.luckyBonus > 0 } == [false, true, true, false])
    }

    // MARK: - receipts

    @Test func receiptsAddUpToTheLedgerOnAMixedHistory() {
        var rs: [NightResult] = []
        for i in 0..<70 {
            let o: Outcome = [.complete, .complete, .unfinished, .complete, .ruins, .complete, .excused][i % 7]
            rs.append(night(day(-70 + i), o, pauses: i % 3 == 0 ? 0 : i % 3 == 1 ? 1 : nil, calm: i % 8, rule: i < 20 ? nil : 1))
        }
        let boxes = [luckyBox(after: day(-60), id: "a"), luckyBox(after: day(-30), id: "b")]
        for e in Economy.ledger(rs, calendar: bratislava, boxes: boxes) {
            if let r = Economy.Receipt(e, calmTotal: 8) { #expect(r.total == e.coins) } else { #expect(e.coins == 0) }
        }
    }

    @Test func receiptKindsAndOrderOfANewRuleNight() {
        let e = last(history(playerBuilt: 5, others: 3, tonight: night(k, pauses: 0, calm: 2)), boxes: [luckyBox(after: day(-1))])
        let r = Economy.Receipt(e, calmTotal: 8)!
        #expect(r.lines.map(\.kind) == [.night, .playerLevel(level: 2), .withoutPause, .calmHours(calm: 2, total: 8),
                                        .multiplier(nights: 4, percent: 108), .luckyNight])
        // an unfinished night still gets a receipt
        let u = last([night(k, .unfinished, pauses: nil)])
        #expect(Economy.Receipt(u, calmTotal: nil) != nil)
    }

    // MARK: - the model

    @Test func withoutClockTimesKeepsTheMarker() {
        #expect(night(k, rule: 1).withoutClockTimes.coinRule == 1)
        #expect(night(k, rule: nil).withoutClockTimes.coinRule == nil)
    }

    @Test func aStoredNightWithoutTheMarkerStillDecodes() throws {
        let old = NightResult(key: k, outcome: .complete, buildingId: "x")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "coinRule")
        let back = try JSONDecoder().decode(NightResult.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(back.coinRule == nil && back == old)
        let new = night(k, rule: 1)
        #expect(try JSONDecoder().decode(NightResult.self, from: JSONEncoder().encode(new)).coinRule == 1)
    }

    // MARK: - the order, and the statistics

    /// A counted test night shares its key with a real night at the 5 → 6 built-nights threshold, a lucky parcel is
    /// waiting: the statistics (which price `withoutClockTimes` copies) and the balance must agree, whichever order the
    /// two nights come in.
    @Test func statisticsAndBalanceAgreeWithACountedTestNightOnTheSameKey() {
        for testFirst in [false, true] {
            var rs = (0..<4).map { night(day(-6 + $0), pauses: 1, calm: 3) }                        // 4 built nights
            let real = NightResult(key: day(-2), outcome: .complete, buildingId: "x", startedAt: at(2026, 11, 25, 22),
                                   confirmedAt: at(2026, 11, 26, 6), pauses: 0, calmHours: 7, calmHoursTotal: 7, coinRule: 1)
            let test = NightResult(key: day(-2), outcome: .complete, buildingId: "x", startedAt: at(2026, 11, 26, 14),
                                   confirmedAt: at(2026, 11, 26, 15), pauses: 1, calmHours: 2, calmHoursTotal: 2,
                                   isTestNight: true, coinRule: 1)
            rs += testFirst ? [test, real] : [real, test]
            rs.append(night(day(-1), pauses: 0, calm: 5))
            rs.append(night(k, pauses: 0, calm: 5))
            let boxes = [luckyBox(after: day(-4))]
            let input = rs.map { $0.isTestNight == true ? $0.withoutClockTimes : $0 }
            let stats = Stats.summary(input, today: day(1), calendar: bratislava, boxes: boxes)
            #expect(stats.coins == Economy.earned(rs, calendar: bratislava, boxes: boxes))
            #expect(stats.coins == Economy.earned(input, calendar: bratislava, boxes: boxes))
            #expect(Economy.ledger(rs, calendar: bratislava, boxes: boxes).filter { $0.luckyBonus > 0 }.count == 1)
            // the 6th built night is the one that earns the level 2 bonus (whichever of the two it is)
            let l = Economy.ledger(input, calendar: bratislava, boxes: boxes)
            #expect(l.map(\.playerLevel).prefix(7) == [1, 1, 1, 1, 1, 2, 2])
        }
    }

    @Test func sameKeyNightsKeepTheCallersOrder() {
        let a = night(k, pauses: 1, calm: 0)
        let b = night(k, pauses: 0, calm: 7)
        let both = Economy.ledger([a, b], calendar: bratislava)
        let swapped = Economy.ledger([b, a], calendar: bratislava)
        #expect(both.map(\.coins) == [swapped[1].coins, swapped[0].coins])
        #expect(both[0].coins == last([a]).coins)
    }
}
