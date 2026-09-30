import Foundation
import Testing
@testable import SleepCore

@Suite struct AchievementsTests {
    let first = NightKey("2026-10-01")!

    func key(_ day: Int) -> NightKey { first.adding(days: day, calendar: bratislava) }

    func results(_ outcomes: [Outcome], building: (Int) -> String = { _ in "l1-house-a-0" },
                 skip: Set<Int> = []) -> [NightResult] {
        var out: [NightResult] = []
        var day = 0
        for (i, o) in outcomes.enumerated() {
            while skip.contains(day) { day += 1 }
            out.append(NightResult(key: key(day), outcome: o, buildingId: building(i)))
            day += 1
        }
        return out
    }

    func unlocked(_ r: [NightResult], naps: [NightResult] = [], repairs: [NightKey] = [],
                  catalog: Catalog? = nil) -> [Achievement: NightKey] {
        Dictionary(uniqueKeysWithValues: Achievements.unlocked(results: r, naps: naps, repairs: repairs,
                                                               catalog: catalog, calendar: bratislava)
            .map { ($0.achievement, $0.key) })
    }

    @Test func nothingWithoutNights() {
        #expect(Achievements.unlocked(results: [], catalog: nil, calendar: bratislava).isEmpty)
    }

    @Test func firstBuildingAndStreaksAsInTheCoinLedger() {
        // ruins first, then 3 complete, an unfinished (neutral), then 4 more complete = 7 in a row
        let r = results([.ruins, .complete, .complete, .complete, .unfinished, .complete, .complete, .complete, .complete])
        let u = unlocked(r)
        #expect(u[.firstBuilding] == key(1))
        #expect(u[.streak3] == key(3) && u[.streak7] == key(8) && u[.streak30] == nil)
    }

    @Test func aGapOrARuinBreaksTheStreak() {
        #expect(unlocked(results([.complete, .complete, .complete], skip: [2]))[.streak3] == nil)
        #expect(unlocked(results([.complete, .complete, .ruins, .complete]))[.streak3] == nil)
    }

    @Test func builtNightsCountCompleteAndUnfinished() {
        let r = results(Array(repeating: .unfinished, count: 100))
        let u = unlocked(r)
        #expect(u[.built10] == key(9) && u[.built50] == key(49) && u[.built100] == key(99))
        #expect(u[.streak3] == nil)                                   // unfinished never makes a streak
    }

    @Test func firstBuildingOfEachLevel() throws {
        let catalog = try loadRealCatalog()
        let ids = ["l1-house-a-0", "l2-road-lit-ns", "l2-library-a", "l3-police", "l4-sky-a-0"]
        let r = results([.complete, .complete, .ruins, .complete, .unfinished], building: { ids[$0] })
        let u = unlocked(r, catalog: catalog)
        #expect(u[.firstLevel2] == nil)                               // lit streets don't count, the library became ruins
        #expect(u[.firstLevel3] == key(3) && u[.firstSkyscraper] == key(4))
    }

    @Test func napAndRepair() {
        let naps = [NightResult(key: key(4), outcome: .unfinished, buildingId: nil),
                    NightResult(key: key(6), outcome: .complete, buildingId: nil)]
        let u = unlocked([], naps: naps, repairs: [key(9), key(7)])
        #expect(u[.firstNap] == key(6) && u[.firstRepair] == key(7))
    }

    @Test func rewardsAndOrder() {
        #expect(Achievement.streak30.reward == 200 && Achievement.built100.reward == 200
                && Achievement.firstSkyscraper.reward == 200 && Achievement.firstBuilding.reward == 50)
        let list = Achievements.unlocked(results: results([.complete, .complete, .complete]), catalog: nil,
                                         calendar: bratislava)
        #expect(list.map(\.achievement) == [.firstBuilding, .streak3])
        #expect(Achievements.coins(list) == 100)
        #expect(Achievement.firstNap.id == "firstNap")
    }

    @Test func townRecordsTheNightsThatRepairedARuin() throws {
        let catalog = try loadRealCatalog()
        let r = results([.ruins, .complete, .complete])
        let town = TownBuilder.build(results: r, catalog: catalog)
        #expect(town.repairs == [key(1)])
    }
}
