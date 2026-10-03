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
        let gold = JokerUse(tier: .gold, firstNight: key(3))
        let out = apply(results([(1, .complete)]), manual: [gold], last: 4).results
        #expect(out.map(\.key) == [key(1), key(3), key(4)])
    }

    @Test func blockingRules() {
        let used = [JokerUse(tier: .bronze, firstNight: key(4), automatic: true)]
        #expect(Jokers.block(.silver, firstNight: key(20), uses: used, coins: 9999) == .alreadyUsedThisMonth)
        #expect(Jokers.block(.silver, firstNight: NightKey("2026-11-02")!, uses: used, coins: 400) == .notEnoughCoins(missing: 600))
        #expect(Jokers.block(.bronze, firstNight: NightKey("2026-11-02")!, uses: used, coins: 0) == nil)
    }

    /// Owner bug 2026-10-03: the first missed night of a holiday used the automatic bronze, so the morning after
    /// silver / gold were refused. A bigger joker that starts on that very night replaces the bronze.
    @Test func aHolidayJokerReplacesTheAutomaticBronze() {
        // complete 1–3, the night of the 4th missed → automatic bronze; on the 5th the owner switches gold on
        let r = results([(1, .complete), (2, .complete), (3, .complete)])
        let auto = apply(r, last: 4).uses
        #expect(auto == [JokerUse(tier: .bronze, firstNight: key(4), automatic: true)])
        #expect(Jokers.block(.gold, firstNight: key(4), uses: auto, coins: 5000) == nil)
        #expect(Jokers.block(.silver, firstNight: key(4), uses: auto, coins: 0) == .notEnoughCoins(missing: 1000))
        #expect(Jokers.block(.bronze, firstNight: key(4), uses: auto, coins: 0) == .alreadyUsedThisMonth)
        #expect(Jokers.block(.gold, firstNight: key(6), uses: auto, coins: 5000) == .alreadyUsedThisMonth)   // not that night
        // with the gold one switched on, the bronze is gone and the whole week is protected
        let gold = JokerUse(tier: .gold, firstNight: key(4))
        let (out, uses) = apply(r + results([(11, .complete)]), manual: [gold], last: 11)
        #expect(uses == [gold])
        #expect(Progression.currentStreak(out, lastNight: key(11), calendar: bratislava) == 4)
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
