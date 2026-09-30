import Foundation
import Testing
@testable import SleepCore

@Suite struct WeeklyJournalTests {
    /// Monday 5 Oct 2026 (an evening); the night Mon → Tue has the key 2026-10-06.
    let monday = NightKey("2026-10-05")!

    func night(_ eveningOffset: Int, _ o: Outcome, id: String = "l1-house-a-0", start: (Int, Int)? = (22, 25),
               wake: (Int, Int)? = (6, 31)) -> NightResult {
        let eve = monday.adding(days: eveningOffset, calendar: bratislava)
        let key = eve.adding(days: 1, calendar: bratislava)
        return NightResult(key: key, outcome: o, buildingId: id,
                           startedAt: start.map { at(eve.year, eve.month, eve.day, $0.0, $0.1) },
                           confirmedAt: wake.map { at(key.year, key.month, key.day, $0.0, $0.1) })
    }

    @Test func mondayOfAnyDay() {
        for d in 0..<7 {
            #expect(WeeklyJournal.monday(of: monday.adding(days: d, calendar: bratislava), calendar: bratislava) == monday)
        }
        #expect(WeeklyJournal.monday(of: monday.adding(days: 7, calendar: bratislava), calendar: bratislava)
                == monday.adding(days: 7, calendar: bratislava))
    }

    @Test func aWeekByTheEveningOfEachNight() {
        let results = [night(-1, .complete),                              // Sunday before → previous week
                       night(0, .complete, id: "a"), night(1, .complete, id: "b"), night(2, .unfinished, id: "c"),
                       night(3, .complete, id: "d"), night(4, .ruins, id: "e"),
                       night(6, .complete, id: "f", start: (23, 50), wake: (6, 10))]   // Sunday → Monday
        let naps = [NightResult(key: monday.adding(days: 2, calendar: bratislava), outcome: .complete, buildingId: nil),
                    NightResult(key: monday.adding(days: 7, calendar: bratislava), outcome: .complete, buildingId: nil)]
        let weeks = WeeklyJournal.weeks(results: results, naps: naps, calendar: bratislava)
        #expect(weeks.map(\.monday) == [monday.adding(days: 7, calendar: bratislava), monday,
                                        monday.adding(days: -7, calendar: bratislava)])      // newest first
        let w = weeks[1]
        #expect(w.complete == 4 && w.unfinished == 1 && w.ruins == 1 && w.nights == 6 && w.built == 5)
        #expect(w.buildingIds == ["a", "b", "c", "d", "f"])
        #expect(w.bestStreak == 3)                                          // Mon, Tue, (Wed unfinished), Thu
        #expect(w.completeNaps == 1)
        #expect(w.averageWake == TimeOfDay(6, 28))                          // 5× 6:31 + 6:10
        #expect(w.averageStart != nil && w.sunday == monday.adding(days: 6, calendar: bratislava))
        // coins: nights of the week incl. the streak bonus of the ledger + the nap
        let ledger = Economy.ledger(results, calendar: bratislava)
        let nightCoins = ledger.filter { e in results.dropFirst().contains { $0.key == e.key } }.reduce(0) { $0 + $1.coins }
        #expect(w.coins == nightCoins + 50)
        #expect(weeks[0].nights == 0 && weeks[0].completeNaps == 1)
        let empty = WeeklyJournal.week(monday: monday.adding(days: 21, calendar: bratislava), results: results,
                                       calendar: bratislava)
        #expect(empty.nights == 0 && empty.averageStart == nil && empty.coins == 0)
    }

    @Test func theFinishedWeekIsShownOnceAfterItsSunday() {
        func key(_ eveningOffset: Int) -> NightKey { monday.adding(days: eveningOffset + 1, calendar: bratislava) }
        let f = { (k: NightKey, p: NightKey?) in WeeklyJournal.finishedWeek(after: k, previous: p, calendar: bratislava) }
        #expect(f(key(6), key(5)) == monday)                                // Sunday night → its own week
        #expect(f(key(7), key(6)) == nil)                                   // Monday night: already shown
        #expect(f(key(7), key(5)) == monday)                                // Sunday skipped → the next night shows it
        #expect(f(key(3), key(2)) == nil)                                   // mid-week
        #expect(f(key(6), nil) == monday && f(key(3), nil) == nil)          // the very first night
        #expect(f(key(9), key(1)) == monday)                                // a longer gap
    }
}
