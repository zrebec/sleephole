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
        #expect(lines(input(last: last(.excused, id: nil))).contains(.streakSafe))
        #expect(!lines(input(last: last(.missed, id: nil))).contains { $0.tier == 1 })
    }

    private func ruinTown(older: [(String, BuildingState)] = [], lastId: String = "l1-house-a",
                          catalogId: String? = nil, lastDay: Int = 14) -> TownSnapshot {
        var t = TownSnapshot()
        for (n, e) in older.enumerated() {
            t.buildings.append(TownBuilding(placement: Placement(catalogId: e.0, origin: Cell(n, 0), size: 1),
                                            nightKey: NightKey(year: 2026, month: 9, day: n + 1),
                                            buildingId: e.0, state: e.1))
        }
        t.buildings.append(TownBuilding(placement: Placement(catalogId: catalogId ?? lastId, origin: Cell(9, 9), size: 1),
                                        nightKey: NightKey(year: 2026, month: 10, day: lastDay),
                                        buildingId: lastId, state: .ruins))
        return t
    }
    private func ruinedLine(_ t: TownSnapshot, last l: BuddyTalkInput.LastNight? = nil) -> [BuddyLine] {
        lines(input(town: t, last: l ?? last(.ruins))).filter { $0.tier == 1 }
    }

    @Test func ruinsNameTheBuildingAndTellTheTruthAboutRepair() {
        // nothing older to help → tonight repairs it
        #expect(ruinedLine(ruinTown()) == [.ruined(buildingId: "l1-house-a", repairsTonight: true)])
        // an older unfinished building goes first
        #expect(ruinedLine(ruinTown(older: [("l1-house-b", .unfinished)]))
                == [.ruined(buildingId: "l1-house-a", repairsTonight: false)])
        // an older repairable ruin goes first
        #expect(ruinedLine(ruinTown(older: [("l1-house-b", .ruins)]))
                == [.ruined(buildingId: "l1-house-a", repairsTonight: false)])
        // an older lit-street ruin is never repaired → does not count
        var lit = ruinTown(older: [("l2-road-lit-we", .ruins)])
        lit.buildings[0] = TownBuilding(placement: Placement(catalogId: "o-ruin-1", origin: Cell(0, 0), size: 1),
                                        nightKey: lit.buildings[0].nightKey, buildingId: "l2-road-lit-we", state: .ruins)
        #expect(ruinedLine(lit) == [.ruined(buildingId: "l1-house-a", repairsTonight: true)])
    }

    @Test func ruinsWithoutRepairableBuildingSayNothingInTierOne() {
        var litTown = ruinTown(older: [("l1-house-b", .complete)], lastId: "l2-road-lit-we", catalogId: "o-ruin-1")
        #expect(ruinedLine(litTown).isEmpty)
        litTown.buildings.removeLast()
        #expect(ruinedLine(litTown).isEmpty)                       // building missing
        // not last night's morning → no line
        #expect(ruinedLine(ruinTown(), last: last(.ruins, day: 13)).isEmpty)
        // a missed night → no ruined line
        #expect(ruinedLine(ruinTown(), last: last(.missed, id: nil)).isEmpty)
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

    @Test func availableLinesAreInTierOrder() {
        let t = town([("l1-house-a", .complete), ("l2-park-small", .complete), ("l2-library-a", .complete)])
        let a = lines(input(day: 14, town: t, level: 3))
        #expect(a == lines(input(day: 14, hour: 20, town: t, level: 3)))
        #expect(a.map(\.tier) == a.map(\.tier).sorted())
    }

    // MARK: the bag (owner 2026-10-15)

    private let l1 = BuddyLine.chatter(0), l2 = BuddyLine.chatter(1), l3 = BuddyLine.chatter(2), l4 = BuddyLine.chatter(3)
    private let news1 = BuddyLine.ruined(buildingId: "l1-house-a", repairsTonight: true), news2 = BuddyLine.equinox

    @Test func newsLeadsTierOneBeforeTwo() {
        for seed in 0..<20 {
            var g = SeededGenerator(seed: UInt64(seed)); var bag = BuddyBag()
            #expect(bag.open(available: [l1, news2, l2, news1], ledToday: [], using: &g) == news1)
            var g2 = SeededGenerator(seed: UInt64(seed)); var bag2 = BuddyBag()
            #expect(bag2.open(available: [l1, news2, l2], ledToday: [], using: &g2) == news2)
        }
    }

    @Test func newsThatLedTodayDoesNotLeadAgain() {
        var openers = Set<BuddyLine>()
        for seed in 0..<40 {
            var g = SeededGenerator(seed: UInt64(seed)); var bag = BuddyBag()
            openers.insert(bag.open(available: [l1, l2, news1], ledToday: [news1.newsKey], using: &g)!)
        }
        #expect(openers == [l1, l2, news1])     // no longer forced: a plain random opener
        for seed in 0..<20 {
            var g = SeededGenerator(seed: UInt64(seed))
            var bag2 = BuddyBag()
            // tier 1 already led, tier 2 still may
            #expect(bag2.open(available: [l1, news1, news2], ledToday: [news1.newsKey], using: &g) == news2)
        }
    }

    @Test func withoutNewsTheOpenerIsFromTheAvailableSet() {
        var seen = Set<BuddyLine>()
        for seed in 0..<60 {
            var g = SeededGenerator(seed: UInt64(seed)); var bag = BuddyBag()
            if let o = bag.open(available: [l1, l2, l3], ledToday: [], using: &g) { seen.insert(o) }
        }
        #expect(seen == [l1, l2, l3])
        var g = SeededGenerator(seed: 1); var empty = BuddyBag()
        #expect(empty.open(available: [], ledToday: [], using: &g) == nil)
    }

    @Test func noRepeatWithinARoundAndEveryLineOnce() {
        for seed in 0..<30 {
            var g = SeededGenerator(seed: UInt64(seed)); var bag = BuddyBag()
            let all = [l1, l2, l3, l4]
            var round = [bag.open(available: all, ledToday: [], using: &g)!]
            for _ in 0..<3 { round.append(bag.next(available: all, using: &g)!) }
            #expect(Set(round) == Set(all))
        }
    }

    @Test func aNewRoundNeverStartsWithTheLineOnScreen() {
        for seed in 0..<50 {
            var g = SeededGenerator(seed: UInt64(seed)); var bag = BuddyBag()
            let all = [l1, l2, l3]
            var prev = bag.open(available: all, ledToday: [], using: &g)!
            for _ in 0..<30 {
                let n = bag.next(available: all, using: &g)!
                #expect(n != prev)
                prev = n
            }
        }
    }

    @Test func aSingleLineStays() {
        var g = SeededGenerator(seed: 3); var bag = BuddyBag()
        #expect(bag.open(available: [l1], ledToday: [], using: &g) == l1)
        #expect(bag.next(available: [l1], using: &g) == l1)
    }

    @Test func vanishedLinesAreNotShownAndNewOnesJoin() {
        for seed in 0..<30 {
            var g = SeededGenerator(seed: UInt64(seed)); var bag = BuddyBag()
            _ = bag.open(available: [l1, l2, l3], ledToday: [], using: &g)
            let shown = bag.current!
            // l3 disappears, l4 appears – the line on screen is untouched until a tap
            let now = [l1, l2, l4]
            #expect(bag.current == shown)
            let n = bag.next(available: now, using: &g)!
            #expect(now.contains(n) && n != shown)
            // the second tap still has an unheard line (l4 joined) before any line repeats
            let m = bag.next(available: now, using: &g)!
            #expect(now.contains(m) && m != n)
        }
    }

    @Test func aTickDoesNotResetWhatWasHeard() {
        var g = SeededGenerator(seed: 5); var bag = BuddyBag()
        let all = [l1, l2, l3]
        var round = [bag.open(available: all, ledToday: [], using: &g)!]
        round.append(bag.next(available: all, using: &g)!)
        round.append(bag.next(available: all, using: &g)!)
        #expect(Set(round).count == 3)
    }

    @Test func forceShowsTheGivenLine() {
        var bag = BuddyBag()
        #expect(bag.force(l2) == l2 && bag.current == l2)
    }
}
