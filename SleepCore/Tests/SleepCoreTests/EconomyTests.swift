import Foundation
import Testing
@testable import SleepCore

@Suite struct EconomyTests {
    let first = NightKey("2026-10-01")!

    func results(_ outcomes: [Outcome], skip: Set<Int> = []) -> [NightResult] {
        var out: [NightResult] = []
        var day = 0
        for o in outcomes {
            while skip.contains(day) { day += 1 }
            out.append(NightResult(key: first.adding(days: day, calendar: bratislava), outcome: o, buildingId: "x"))
            day += 1
        }
        return out
    }

    @Test func rewardsByOutcome() {
        #expect(Economy.reward(.complete) == 100 && Economy.reward(.unfinished) == 50)
        #expect(Economy.reward(.ruins) == 0 && Economy.reward(.missed) == 0 && Economy.reward(.excused) == 0)
    }

    @Test func higherLevelsPayMore() {                         // owner 2026-10-02
        #expect((1...4).map { Economy.reward(.complete, level: $0) } == [100, 120, 150, 200])
        #expect((1...4).map { Economy.reward(.unfinished, level: $0) } == [50, 60, 75, 100])
        let catalog = try! loadRealCatalog()
        let k = NightKey("2026-10-01")!
        let r = [NightResult(key: k, outcome: .complete, buildingId: "l1-house-a-0"),
                 NightResult(key: k.adding(days: 1, calendar: bratislava), outcome: .complete, buildingId: "l3-police"),
                 NightResult(key: k.adding(days: 2, calendar: bratislava), outcome: .unfinished, buildingId: "l2-park-small")]
        #expect(Economy.earned(r, calendar: bratislava, catalog: catalog) == 100 + 150 + 60)
        #expect(Economy.earned(r, calendar: bratislava) == 100 + 100 + 50)          // no catalog → level 1
        #expect(Economy.earned(results([.complete, .unfinished, .ruins]), calendar: bratislava) == 150)
    }

    @Test func ownerPrices() {
        #expect(Economy.price(level: 1) == 100 && Economy.price(level: 2) == 200)
        #expect(Economy.price(level: 3) == 400 && Economy.price(level: 4) == 1000)
    }

    @Test func seventhCompleteNightInARowPaysABonus() {
        let l = Economy.ledger(results(Array(repeating: .complete, count: 14)), calendar: bratislava)
        #expect(l[6].streakBonus == 200 && l[13].streakBonus == 200)
        #expect(l.filter { $0.streakBonus > 0 }.count == 2)
        #expect(Economy.earned(results(Array(repeating: .complete, count: 7)), calendar: bratislava) == 900)
    }

    @Test func unfinishedIsNeutralRuinsAndGapsBreak() {
        // 3 complete, unfinished, 4 complete → still the 7th complete in the run
        let neutral = Economy.ledger(results([.complete, .complete, .complete, .unfinished,
                                              .complete, .complete, .complete, .complete]), calendar: bratislava)
        #expect(neutral.last?.streakBonus == 200)
        let broken = Economy.ledger(results([.complete, .complete, .complete, .ruins,
                                             .complete, .complete, .complete, .complete]), calendar: bratislava)
        #expect(broken.allSatisfy { $0.streakBonus == 0 })
        let gap = Economy.ledger(results(Array(repeating: .complete, count: 7), skip: [3]), calendar: bratislava)
        #expect(gap.allSatisfy { $0.streakBonus == 0 })
    }

    @Test func sameDayBonusNightsDoNotBreakTheRun() {
        var r = results(Array(repeating: .complete, count: 6))
        r.append(NightResult(key: r.last!.key, outcome: .complete, buildingId: "x"))   // 2 nights with one key
        #expect(Economy.ledger(r, calendar: bratislava).last?.streakBonus == 200)
    }

    // MARK: - coin receipt (11a)

    func receipt(_ r: NightResult, run: [NightResult] = [], catalog: Catalog? = nil) -> Economy.Receipt? {
        let all = run + [r]
        let e = Economy.ledger(all, calendar: bratislava, catalog: catalog).last!
        return Economy.Receipt(e, calmTotal: r.calmHoursTotal)
    }

    @Test func receiptOfTheOwnersNight() {            // 100 + 30 + 8 calm hours (40) + the 21st night in a row (200) = 370
        let prior = results(Array(repeating: .complete, count: 20))
        let k = first.adding(days: 20, calendar: bratislava)
        let night = NightResult(key: k, outcome: .complete, buildingId: "x", pauses: 0, calmHours: 8, calmHoursTotal: 8)
        let r = receipt(night, run: prior)!
        #expect(r.lines.map(\.amount) == [100, 30, 40, 200])
        #expect(r.lines.map(\.kind) == [.building(level: 1), .withoutPause, .calmHours(calm: 8, total: 8), .streak(run: 21)])
        #expect(r.total == 370)
    }

    @Test func receiptOfAnUnfinishedLevelTwoNight() {
        let catalog = try! loadRealCatalog()
        let night = NightResult(key: first, outcome: .unfinished, buildingId: "l2-park-small")
        let r = receipt(night, catalog: catalog)!
        #expect(r.lines == [.init(kind: .unfinishedBuilding(level: 2), amount: 60)] && r.total == 60)
    }

    @Test func receiptHasNoPauseLineAfterAPauseAndNoCalmLineForZero() {
        let paused = NightResult(key: first, outcome: .complete, buildingId: "x", pauses: 1, calmHours: 3, calmHoursTotal: 7)
        let r = receipt(paused)!
        #expect(r.lines.map(\.kind) == [.building(level: 1), .calmHours(calm: 3, total: 7)] && r.total == 115)
        let zero = NightResult(key: first, outcome: .complete, buildingId: "x", pauses: 1, calmHours: 0, calmHoursTotal: 7)
        #expect(receipt(zero)!.lines.map(\.kind) == [.building(level: 1)])
    }

    @Test func receiptStreakLineOnlyOnEverySeventhNight() {
        let l = Economy.ledger(results(Array(repeating: .complete, count: 22)), calendar: bratislava)
        let runs = l.enumerated().compactMap { (i, e) -> Int? in
            Economy.Receipt(e, calmTotal: nil)!.lines.contains { if case .streak = $0.kind { true } else { false } } ? i + 1 : nil
        }
        #expect(runs == [7, 14, 21])
    }

    @Test func nothingPaidNoReceipt() {
        let l = Economy.ledger(results([.ruins, .missed, .excused]), calendar: bratislava)
        #expect(l.allSatisfy { Economy.Receipt($0, calmTotal: nil) == nil })
    }

    @Test func receiptTotalAlwaysEqualsTheLedgerCoins() {
        var outcomes: [Outcome] = []
        for i in 0..<60 { outcomes.append([.complete, .complete, .unfinished, .complete, .ruins, .complete, .excused][i % 7]) }
        var rs = results(outcomes)
        for i in rs.indices {
            let n = rs[i]
            rs[i] = NightResult(key: n.key, outcome: n.outcome, buildingId: "x", pauses: i % 3 == 0 ? 0 : 1,
                                calmHours: i % 4, calmHoursTotal: 8)
        }
        for e in Economy.ledger(rs, calendar: bratislava) {
            if let r = Economy.Receipt(e, calmTotal: 8) { #expect(r.total == e.coins) } else { #expect(e.coins == 0) }
        }
    }
}
