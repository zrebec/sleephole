import Foundation
import Testing
@testable import SleepCore

@Suite struct BuddyTalkTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func date(_ d: Int, _ h: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))!
    }
    private func town(_ ids: [(String, BuildingState)]) -> TownSnapshot {
        var t = TownSnapshot()
        for (n, e) in ids.enumerated() {
            t.buildings.append(TownBuilding(placement: Placement(catalogId: e.0, origin: Cell(n, 0), size: 1),
                                            nightKey: NightKey(year: 2026, month: 9, day: n % 28 + 1),
                                            buildingId: e.0, state: e.1))
        }
        return t
    }
    private func input(day: Int = 14, hour: Int = 10, town t: TownSnapshot = TownSnapshot(), last: BuddyTalkInput.LastNight? = nil,
                       streak: Int = 1, best: Int = 1, built: Int = 20, level: Int = 1,
                       bed: Date? = nil) -> BuddyTalkInput {
        BuddyTalkInput(now: date(day, hour), calendar: cal, town: t, lastNight: last, streak: streak, bestStreak: best,
                       builtNights: built, unlockedMaxLevel: level, nextBedtime: bed)
    }
    private func last(_ o: Outcome, id: String? = "l1-house-a", res: Int = 4, day: Int = 14) -> BuddyTalkInput.LastNight {
        .init(key: NightKey(year: 2026, month: 10, day: day), outcome: o, buildingId: id, residents: res)
    }
    private func lines(_ i: BuddyTalkInput) -> [BuddyLine] { BuddyTalk.lines(i) }

    @Test func lastNightLines() {
        #expect(lines(input(last: last(.complete))).contains(.movedIn(buildingId: "l1-house-a", people: 4)))
        #expect(lines(input(last: last(.complete, id: "l2-park-small", res: 0))).contains(.newSight(buildingId: "l2-park-small")))
        #expect(lines(input(last: last(.unfinished))).contains(.waiting(buildingId: "l1-house-a")))
        #expect(lines(input(last: last(.ruins))).contains(.dayOff))
        #expect(lines(input(last: last(.excused, id: nil))).contains(.streakSafe))
        #expect(!lines(input(last: last(.missed, id: nil))).contains(.dayOff))
    }

    @Test func lastNightOnlyOnItsMorning() {
        let l = lines(input(day: 15, last: last(.complete, day: 14)))
        #expect(!l.contains { $0.tier == 1 })
        #expect(lines(input(day: 14, last: last(.complete, day: 14))).contains { $0.tier == 1 })
        #expect(!lines(input()).contains { $0.tier == 1 })
    }

    @Test func bedtimeOnlyWithinTwoHours() {
        let soon = lines(input(hour: 21, bed: date(14, 22)))
        #expect(soon.contains(.bedtimeSoon(date(14, 22))))
        #expect(!soon.contains(.tonight))
        let far = lines(input(hour: 10, bed: date(14, 22)))
        #expect(!far.contains { $0.tier == 2 })
        #expect(far.contains(.tonight))
        #expect(!lines(input(hour: 23, bed: date(14, 22))).contains { $0.tier == 2 })   // already past
    }

    @Test func streakLines() {
        #expect(lines(input(streak: 7)).contains(.week))
        #expect(lines(input(streak: 7)).contains(.streak(7)))
        #expect(!lines(input(streak: 8)).contains(.week))
        #expect(lines(input(streak: 14)).contains(.week))
        #expect(!lines(input(streak: 1)).contains { if case .streak = $0 { true } else { false } })
        #expect(lines(input(streak: 0, best: 3)).contains(.newStreak))
        #expect(!lines(input(streak: 0, best: 0)).contains(.newStreak))
        #expect(!lines(input(streak: 2, best: 3)).contains(.newStreak))
    }

    @Test func sizeLinesNeedResidents() {
        #expect(!lines(input()).contains { if case .size = $0 { true } else { false } })
        let t = town([("l1-house-a", .complete), ("l1-house-b", .complete)])
        let p = Population.total(t)
        #expect(p > 0)
        let l = lines(input(town: t))
        #expect(l.contains(.size(.hamlet, people: p)))
        #expect(l.contains(.nextSize(missing: 100 - p, .village)))
        // ruins hold nobody
        #expect(!lines(input(town: town([("l1-house-a", .ruins)]))).contains { if case .size = $0 { true } else { false } })
    }

    @Test func biggestSizeHasNoNextSize() {
        #expect(TownSize.metropolis.next == nil)
        #expect(TownSize.hamlet.next == .village)
        for s in TownSize.allCases { #expect(TownSize.of(residents: s.minResidents) == s) }
    }

    @Test func firstNeighboursOnlyEarly() {
        #expect(lines(input(built: 5)).contains(.firstNeighbours))
        #expect(!lines(input(built: 6)).contains(.firstNeighbours))
    }

    @Test func placesInTheTown() {
        let t = town([("l2-park-small", .complete), ("l2-park-pond", .unfinished), ("l2-park-garden", .ruins),
                      ("l2-library-a", .complete), ("l2-museum-b", .complete), ("l4-tower-m", .complete)])
        let l = lines(input(town: t))
        #expect(l.contains(.parks(2)))
        #expect(l.contains(.library)); #expect(l.contains(.museum)); #expect(l.contains(.tallest))
        let none = lines(input(town: town([("l2-library-a", .ruins)])))
        #expect(!none.contains(.library)); #expect(!none.contains(.tallest))
        #expect(!none.contains { if case .parks = $0 { true } else { false } })
    }

    @Test func servicesOnlyFromLevelThree() {
        let low = lines(input(level: 2))
        #expect(!low.contains(.noFireStation)); #expect(!low.contains(.noTownHall))
        let high = lines(input(level: 3))
        for x in [BuddyLine.noFireStation, .noHospital, .noPolice, .noSchool, .noTownHall] { #expect(high.contains(x)) }
        let t = town([("l3-firestation", .complete), ("l3-hospital", .complete), ("l3-school", .ruins)])
        let l = lines(input(town: t, level: 3))
        #expect(l.contains(.fireStation)); #expect(l.contains(.hospital))
        #expect(!l.contains(.noFireStation)); #expect(!l.contains(.noHospital))
        #expect(l.contains(.noSchool))      // a ruin is not a school
        #expect(l.contains(.noPolice))
    }

    @Test func chatterAlwaysThere() {
        let l = lines(input())
        for k in 0..<BuddyLine.chatterCount { #expect(l.contains(.chatter(k))) }
    }

    @Test func tiersAreInOrder() {
        let t = town([("l1-house-a", .complete), ("l2-park-small", .complete), ("l2-library-a", .complete)])
        let l = lines(input(town: t, last: last(.complete), streak: 7, level: 3, bed: date(14, 11)))
        let tiers = l.map(\.tier)
        #expect(tiers == tiers.sorted())
        #expect(Set(tiers) == [1, 2, 3, 4, 5])
    }

    @Test func sameDaySameOrderOtherDayMayDiffer() {
        let t = town([("l1-house-a", .complete), ("l2-park-small", .complete), ("l2-library-a", .complete)])
        let a = lines(input(day: 14, town: t, level: 3)), b = lines(input(day: 14, hour: 20, town: t, level: 3))
        #expect(a == b)
        let others = (15...25).map { lines(input(day: $0, town: t, level: 3)) }
        #expect(others.contains { $0 != a })
        #expect(Set(others.map { $0.map(\.tier) }).count == 1)    // tiers stay the same
    }

    @Test func wrapAround() {
        #expect(BuddyTalk.next(after: 0, count: 3) == 1)
        #expect(BuddyTalk.next(after: 2, count: 3) == 0)
        #expect(BuddyTalk.next(after: 0, count: 0) == 0)
    }
}
