import Foundation
import Testing
@testable import SleepCore

@Suite struct ProgressionTests {
    /// Results for consecutive nights starting 2026-09-01.
    func results(_ outcomes: [Outcome]) -> [NightResult] {
        let first = NightKey("2026-09-01")!
        return outcomes.enumerated().map { i, o in
            NightResult(key: first.adding(days: i, calendar: bratislava), outcome: o, buildingId: "x")
        }
    }

    @Test(arguments: [(0, 1), (4, 1), (5, 2), (14, 2), (15, 3), (29, 3), (30, 4), (49, 4), (500, 4)])
    func ownerLevelRule(builtBefore: Int, maxLevel: Int) {
        // nights 1–5 → L1 · 6–15 → L1–2 · 16–30 → L1–3 · 31+ → L1–4
        #expect(Progression.unlockedMaxLevel(builtBefore: builtBefore) == maxLevel)
    }

    @Test func levelUpMoments() {
        #expect(Progression.levelUp(builtBefore: 4, builtAfter: 5) == 2)
        #expect(Progression.levelUp(builtBefore: 14, builtAfter: 15) == 3)
        #expect(Progression.levelUp(builtBefore: 29, builtAfter: 30) == 4)
        #expect(Progression.levelUp(builtBefore: 5, builtAfter: 6) == nil)
    }

    @Test func nightsToNextLevel() {
        #expect(Progression.nightsToNextLevel(built: 2)! == (2, 3))
        #expect(Progression.nightsToNextLevel(built: 20)! == (4, 10))
        #expect(Progression.nightsToNextLevel(built: 30) == nil)
    }

    @Test func buildNightsCountCompleteAndUnfinishedOnly() {
        #expect(Progression.builtNights(results([.complete, .unfinished, .ruins, .missed, .complete])) == 3)
    }

    @Test func streakIsGentleWithUnfinished() {
        let r = results([.complete, .complete, .unfinished, .complete])
        #expect(Progression.currentStreak(r, lastNight: r.last!.key, calendar: bratislava) == 3)
    }

    @Test func streakBreaksOnRuinsMissedAndGaps() {
        let r = results([.complete, .ruins, .complete, .complete])
        #expect(Progression.currentStreak(r, lastNight: r.last!.key, calendar: bratislava) == 2)
        let gap = [r[0], r[3]]                                  // nights 2 and 3 have no record
        #expect(Progression.currentStreak(gap, lastNight: r[3].key, calendar: bratislava) == 1)
        let lastMissing = r.last!.key.adding(days: 1, calendar: bratislava)
        #expect(Progression.currentStreak(r, lastNight: lastMissing, calendar: bratislava) == 0)
    }

    @Test func bestStreak() {
        let r = results([.complete, .complete, .complete, .missed, .complete, .unfinished, .complete])
        #expect(Progression.bestStreak(r, calendar: bratislava) == 3)
        #expect(Progression.bestStreak([], calendar: bratislava) == 0)
    }
}
