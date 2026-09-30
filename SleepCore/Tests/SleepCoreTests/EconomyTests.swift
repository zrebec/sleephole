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
        #expect(Economy.reward(.ruins) == 0 && Economy.reward(.missed) == 0)
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
}
