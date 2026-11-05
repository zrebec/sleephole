import Foundation
import SleepCore
import Testing
@testable import SleepHole

/// Step 13o: small state bugs found by the audit of 13j (L3, L9; M2 / M3 / M9 are tested next to their subjects).
@MainActor
struct StateFixes13oTests {
    @Test func theTownSelectionFollowsTheNightNotTheIndex() {
        let sprites = SpriteLibrary.loadFromBundle()
        func town(_ days: [Int]) -> TownSnapshot {
            TownBuilder.build(results: days.map {
                NightResult(key: NightKey(year: 2026, month: 10, day: $0), outcome: .complete, buildingId: "l1-house-a-0")
            }, catalog: sprites.catalog!)
        }
        let chosen = NightKey(year: 2026, month: 10, day: 7)
        let before = town([5, 7])
        let index = before.buildings.firstIndex { $0.nightKey == chosen }!
        #expect(before.building(forNight: chosen)?.nightKey == chosen)
        let after = town([2, 5, 7])                                     // a rebuild inserts an older night
        #expect(after.building(forNight: chosen)?.nightKey == chosen)
        #expect(after.buildings[index].nightKey != chosen)              // the old index would now show another building
        #expect(after.building(forNight: NightKey(year: 2026, month: 10, day: 30)) == nil)
    }

    @Test func theFormattersFollowAChangedTimeZone() {
        let was = NSTimeZone.default
        let lang = Lang.current
        let was12h = Fmt.systemUses12h
        defer { NSTimeZone.default = was; Lang.current = lang; Fmt.systemUses12h = was12h }
        Lang.current = .en
        Fmt.systemUses12h = false
        let noonUTC = Date(timeIntervalSince1970: 1_799_971_200 + 12 * 3600)       // 2027-01-15 12:00 UTC (a multiple of 86 400)
        NSTimeZone.default = TimeZone(identifier: "UTC")!
        #expect(Fmt.time(noonUTC) == "12:00", "\(Fmt.time(noonUTC))")                           // fills the cache
        NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!
        #expect(Fmt.time(noonUTC) == "21:00")
        #expect(Fmt.timeSec(noonUTC) == "21:00:00")
    }
}
