import Foundation
import Testing
@testable import SleepCore

@Suite struct JokersTests {
    let first = NightKey("2026-10-01")!

    func key(_ day: Int) -> NightKey { first.adding(days: day - 1, calendar: bratislava) }

    /// Results for October days; days not listed have no result (missed – the app did not run).
    func results(_ days: [(Int, Outcome)]) -> [NightResult] {
        days.map { NightResult(key: key($0.0), outcome: $0.1, buildingId: "l1-house-a-0") }
    }

    func apply(_ r: [NightResult], manual: [JokerUse] = [], last: Int) -> (results: [NightResult], uses: [JokerUse]) {
        Jokers.apply(results: r, manual: manual, lastNight: key(last), calendar: bratislava)
    }

    @Test func tiers() {
        #expect(JokerTier.allCases.map(\.nights) == [1, 3, 7])
        #expect(JokerTier.allCases.map(\.price) == [0, 1000, 5000])
        let gold = JokerUse(tier: .gold, firstNight: key(10))
        #expect(gold.lastNight(calendar: bratislava) == key(16))
        #expect(gold.covers(key(10), calendar: bratislava) && gold.covers(key(16), calendar: bratislava))
        #expect(!gold.covers(key(17), calendar: bratislava) && !gold.covers(key(9), calendar: bratislava))
    }

    @Test func automaticBronzeSavesTheFirstMissedNightOfAMonth() {
        // 1–3 complete, 4 missed (no result), 5–6 complete
        let r = results([(1, .complete), (2, .complete), (3, .complete), (5, .complete), (6, .complete)])
        let (out, uses) = apply(r, last: 6)
        #expect(uses == [JokerUse(tier: .bronze, firstNight: key(4), automatic: true)])
        #expect(out.first { $0.key == key(4) }?.outcome == .excused)
        #expect(Progression.currentStreak(out, lastNight: key(6), calendar: bratislava) == 5)      // not reset
    }

    @Test func onlyOneJokerPerMonth() {
        let r = results([(1, .complete), (2, .complete), (4, .complete), (5, .ruins), (6, .complete)])
        let (out, uses) = apply(r, last: 6)
        #expect(uses.count == 1 && uses[0].firstNight == key(3))
        #expect(out.first { $0.key == key(5) }?.outcome == .ruins)                                // second miss breaks
        #expect(Progression.currentStreak(out, lastNight: key(6), calendar: bratislava) == 1)
    }

    @Test func noAutomaticJokerWithoutAStreakToSave() {
        let r = results([(1, .ruins), (3, .complete)])
        #expect(apply(r, last: 3).uses.isEmpty)
    }

    @Test func aNewMonthHasANewJoker() {
        let start = NightKey("2026-09-28")!
        let k = { (d: Int) in start.adding(days: d, calendar: bratislava) }      // 0 = 28 Sep … 4 = 2 Oct
        let r = [(0, Outcome.complete), (2, .complete), (4, .complete)].map {
            NightResult(key: k($0.0), outcome: $0.1, buildingId: nil)
        }
        let uses = Jokers.apply(results: r, manual: [], lastNight: k(4), calendar: bratislava).uses
        #expect(uses.map(\.firstNight) == [k(1), k(3)])                                       // 29 Sep and 1 Oct
    }

    @Test func manualGoldProtectsAHoliday() {
        // complete 1–2, holiday 3–9 (gold from 3), back on 10
        let r = results([(1, .complete), (2, .complete), (5, .ruins), (10, .complete)])
        let gold = JokerUse(tier: .gold, firstNight: key(3))
        let (out, uses) = apply(r, manual: [gold], last: 10)
        #expect(uses == [gold])                                                                // no extra bronze
        #expect((3...9).allSatisfy { d in out.first { $0.key == key(d) }?.outcome == .excused })
        #expect(Progression.currentStreak(out, lastNight: key(10), calendar: bratislava) == 3)
        #expect(Economy.earned(out, calendar: bratislava) == 300)                              // holidays pay nothing
        #expect(TownBuilder.build(results: out, catalog: try! loadRealCatalog()).buildings.count == 3)
    }

    @Test func aGoodNightInsideAJokerStillCounts() {
        let r = results([(1, .complete), (2, .complete), (3, .unfinished)])
        let silver = JokerUse(tier: .silver, firstNight: key(2))
        let out = apply(r, manual: [silver], last: 4).results
        #expect(out.map(\.outcome) == [.complete, .complete, .unfinished, .excused])
    }

    @Test func resultsSharingAKeyAreAllKept() {
        let r = results([(1, .complete), (2, .complete), (2, .complete)])        // a counted test night
        #expect(apply(r, last: 2).results.count == 3)
    }

    @Test func futureNightsAreNeverTouched() {
        let gold = JokerUse(tier: .gold, firstNight: key(2))
        let out = apply(results([(1, .complete)]), manual: [gold], last: 4).results
        #expect(out.map(\.key) == [key(1), key(2), key(3), key(4)])
    }

    @Test func blockingRules() {
        let used = [JokerUse(tier: .bronze, firstNight: key(4), automatic: true)]
        #expect(Jokers.block(.bronze, firstNight: key(20), uses: used, coins: 0) == .alreadyUsedThisMonth)
        #expect(Jokers.block(.silver, firstNight: key(20), uses: used, coins: 9999) == nil)       // other kind is free
        #expect(Jokers.block(.silver, firstNight: key(20), uses: used, coins: 400) == .notEnoughCoins(missing: 600))
        #expect(Jokers.block(.gold, firstNight: key(20), uses: used, coins: 100) == .notEnoughCoins(missing: 4900))
        #expect(Jokers.block(.bronze, firstNight: NightKey("2026-11-02")!, uses: used, coins: 0) == nil)
        let silver = [JokerUse(tier: .silver, firstNight: key(4))]
        #expect(Jokers.block(.silver, firstNight: key(20), uses: silver, coins: 9999) == .alreadyUsedThisMonth)   // two silvers
        #expect(Jokers.block(.gold, firstNight: key(20), uses: silver, coins: 9999) == nil)
        #expect(Jokers.block(.bronze, firstNight: key(20), uses: silver, coins: 0) == nil)
    }

    @Test func eachKindOncePerMonthIndependently() {
        // 1–3 complete, 4 missed → automatic bronze; silver bought later for 10–12 → both in effect
        let r = results([(1, .complete), (2, .complete), (3, .complete), (5, .complete), (13, .complete)])
        let silver = JokerUse(tier: .silver, firstNight: key(10))
        let (out, uses) = apply(r, manual: [silver], last: 13)
        #expect(uses.map(\.tier) == [.bronze, .silver] && uses[0].automatic)
        #expect([4, 10, 11, 12].allSatisfy { d in out.first { $0.key == key(d) }?.outcome == .excused })
    }

    @Test func aSilverDoesNotUseUpTheAutomaticBronze() {
        // silver 3–5 first, then night 8 is missed (outside it) → the automatic bronze still comes
        let r = results([(1, .complete), (2, .complete), (6, .complete), (7, .complete), (9, .complete)])
        let silver = JokerUse(tier: .silver, firstNight: key(3))
        let (out, uses) = apply(r, manual: [silver], last: 9)
        #expect(uses == [silver, JokerUse(tier: .bronze, firstNight: key(8), automatic: true)].sorted { $0.firstNight < $1.firstNight })
        #expect(out.first { $0.key == key(8) }?.outcome == .excused)
        #expect(Progression.currentStreak(out, lastNight: key(9), calendar: bratislava) == 5)
    }

    @Test func aManualBronzeAndTheAutomaticOneExcludeEachOther() {
        // manual bronze on 4; the missed night 6 gets no second bronze → the streak breaks there
        let r = results([(1, .complete), (2, .complete), (3, .complete), (5, .complete), (7, .complete)])
        let bronze = JokerUse(tier: .bronze, firstNight: key(4))
        let (out, uses) = apply(r, manual: [bronze], last: 7)
        #expect(uses == [bronze])
        #expect(out.first { $0.key == key(6) } == nil)
        #expect(Jokers.block(.bronze, firstNight: key(6), uses: uses, coins: 0) == .alreadyUsedThisMonth)
        // the other way round: the automatic bronze blocks a manual one that month
        let auto = apply(results([(1, .complete), (2, .complete), (3, .complete)]), last: 4).uses
        #expect(Jokers.block(.bronze, firstNight: key(8), uses: auto, coins: 0) == .alreadyUsedThisMonth)
    }

    @Test func aManualJokerAlreadyCoveringANightSpendsNoBronze() {
        let r = results([(1, .complete), (2, .complete), (5, .complete)])
        let silver = JokerUse(tier: .silver, firstNight: key(3))
        #expect(apply(r, manual: [silver], last: 5).uses == [silver])
    }

    /// Owner bug 2026-10-03 (rule of 2026-10-09: each kind once a month): the holiday gold may start on the night
    /// the automatic bronze saved; that night is then covered by the gold and the bronze is free again.
    @Test func aHolidayJokerStartingOnTheBronzeNightFreesTheBronze() {
        let r = results([(1, .complete), (2, .complete), (3, .complete)])
        let auto = apply(r, last: 4).uses
        #expect(auto == [JokerUse(tier: .bronze, firstNight: key(4), automatic: true)])
        #expect(Jokers.block(.gold, firstNight: key(4), uses: auto, coins: 5000) == nil)
        #expect(Jokers.block(.gold, firstNight: key(6), uses: auto, coins: 5000) == nil)
        #expect(Jokers.block(.silver, firstNight: key(4), uses: auto, coins: 0) == .notEnoughCoins(missing: 1000))
        #expect(Jokers.block(.bronze, firstNight: key(4), uses: auto, coins: 0) == .alreadyUsedThisMonth)
        // gold from the 4th (7 nights → 10th), back on the 11th, a later night (13th) missed
        let gold = JokerUse(tier: .gold, firstNight: key(4))
        let r2 = r + results([(11, .complete), (12, .complete), (14, .complete)])
        let (out, uses) = apply(r2, manual: [gold], last: 14)
        #expect((4...10).allSatisfy { d in out.first { $0.key == key(d) }?.outcome == .excused })
        #expect(uses == [gold, JokerUse(tier: .bronze, firstNight: key(13), automatic: true)])
        #expect(Progression.currentStreak(out, lastNight: key(14), calendar: bratislava) == 6)
    }

    @Test func firstNightRepairsLastNightOrStartsTonight() {
        let tonight = key(5)
        #expect(Jokers.firstNight(tonight: tonight, lastNightResult: nil, calendar: bratislava) == key(4))
        let ruined = NightResult(key: key(4), outcome: .ruins, buildingId: nil)
        #expect(Jokers.firstNight(tonight: tonight, lastNightResult: ruined, calendar: bratislava) == key(4))
        let good = NightResult(key: key(4), outcome: .complete, buildingId: nil)
        #expect(Jokers.firstNight(tonight: tonight, lastNightResult: good, calendar: bratislava) == tonight)
    }
}
