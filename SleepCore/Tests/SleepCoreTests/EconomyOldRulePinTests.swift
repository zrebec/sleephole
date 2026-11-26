import Foundation
import Testing
@testable import SleepCore

/// Build 14, step 14a1: the pre-build-14 coin rule (a night with `coinRule == nil`) is pinned number by number. These
/// numbers were produced by the code BEFORE the new rule existed and must never change – every user's past balance
/// depends on them.
@Suite struct EconomyOldRulePinTests {
    static let first = NightKey("2026-10-01")!

    /// 40 nights with a gap, an unfinished night, ruins, an excused night, pauses, calm hours, mixed building levels,
    /// complete runs long enough for a +200 on the 7th night (twice), a schedule break and two lucky-night boxes.
    static func history() -> (results: [NightResult], breaks: [NightKey], boxes: [BoxPurchase]) {
        let ids = ["l1-house-a-0", "l2-park-small", "l3-police", "l4-sky-a-0"]
        let outcomes: [Outcome] = [
            .complete, .complete, .complete, .unfinished, .complete, .complete, .complete, .complete, .complete, .complete,   // 0-9: the 7th complete is night 7
            .ruins, .complete, .complete, .complete, .complete, .complete, .complete, .complete, .complete, .complete,         // 10-19
            .excused, .complete, .complete, .complete, .unfinished, .complete, .complete, .complete, .complete, .complete,     // 20-29
            .complete, .complete, .complete, .complete, .complete, .complete, .complete, .complete, .complete, .complete]      // 30-39
        var rs: [NightResult] = []
        var day = 0
        for (i, o) in outcomes.enumerated() {
            if i == 14 { day += 1 }                                    // a gap: one calendar day without any result
            let key = first.adding(days: day, calendar: bratislava)
            rs.append(NightResult(key: key, outcome: o, buildingId: ids[(i * 7 + i / 3) % 4],
                                  pauses: i % 5 == 2 ? 1 : (i % 11 == 0 ? nil : 0),
                                  calmHours: o.isBuildNight ? (i * 3) % 8 : nil, calmHoursTotal: o.isBuildNight ? 7 : nil))
            day += 1
        }
        let breakKey = first.adding(days: 27, calendar: bratislava)
        func box(_ id: String, after night: Int) -> BoxPurchase {
            BoxPurchase(id: id, at: Date(timeIntervalSince1970: 1_800_000_000 + Double(night)),
                        nightKey: rs[night].key, price: 400, seed: 1, tableVersion: 1, prize: .luckyNight, payout: 0)
        }
        return (rs, [breakKey], [box("b1", after: 8), box("b2", after: 22)])
    }

    @Test func theOldRuleLedgerIsPinned() throws {
        let catalog = try loadRealCatalog()
        let h = Self.history()
        let ledger = Economy.ledger(h.results, calendar: bratislava, breaks: h.breaks, catalog: catalog, boxes: h.boxes)
        #expect(ledger.map(\.coins) == Self.pinnedCoins)
        #expect(ledger.map(\.streakBonus).enumerated().filter { $0.element > 0 }.map(\.offset) == Self.pinnedStreakNights)
        #expect(ledger.map(\.luckyBonus).enumerated().filter { $0.element > 0 }.map(\.offset) == Self.pinnedLuckyNights)
        #expect(ledger.map(\.run) == Self.pinnedRuns)
        #expect(Economy.earned(h.results, calendar: bratislava, breaks: h.breaks, catalog: catalog, boxes: h.boxes) == Self.pinnedTotal)
    }

    static let pinnedCoins: [Int] = [100, 245, 180, 80, 170, 165, 140, 425, 180, 390, 0, 105, 120, 265, 190, 205, 150, 115, 160, 235,
                                     0, 415, 130, 310, 50, 245, 210, 155, 170, 165, 140, 255, 350, 165, 180, 135, 150, 235, 190, 405]
    static let pinnedStreakNights: [Int] = [7, 21, 32, 39]
    static let pinnedLuckyNights: [Int] = [9, 23]
    static let pinnedRuns: [Int] = [1, 2, 3, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 1, 2, 3, 4, 5, 6, 6, 7, 8, 9, 9, 10, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
    static let pinnedTotal = 7675
}
