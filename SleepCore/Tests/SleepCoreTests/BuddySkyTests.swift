import Foundation
import Testing
@testable import SleepCore

/// The buddy's sentences about the sky (phase 8f). Dates were checked against the code's own `Astro`: the October 2026
/// full moon peaks on the evening of 25 Oct (23:00 UTC), the new moon on 10 Oct.
@Suite struct BuddySkyTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func sky(_ y: Int, _ m: Int, _ d: Int, south: Bool = false) -> [BuddyLine] {
        BuddySky.lines(day: NightKey(year: y, month: m, day: d), calendar: cal, southernHemisphere: south)
    }
    private func phase(_ l: [BuddyLine]) -> [MoonQuarter] {
        l.compactMap { if case let .moonPhase(q) = $0 { q } else { nil } }
    }

    @Test func fullMoonTonightTomorrowAndSoon() {
        #expect(sky(2026, 10, 25) == [.fullMoonTonight])
        #expect(sky(2026, 10, 24).contains(.fullMoonTomorrow))
        #expect(sky(2026, 10, 23).contains(.fullMoonSoon(days: 2)))
        #expect(sky(2026, 10, 22).contains(.fullMoonSoon(days: 3)))
        #expect(!sky(2026, 10, 21).contains { if case .fullMoonSoon = $0 { true } else { false } })
        // only one evening of the several above 0.97 is "the full moon"
        #expect(!sky(2026, 10, 26).contains(.fullMoonTonight))
        #expect(!sky(2026, 10, 24).contains(.fullMoonTonight))
    }

    @Test func newMoonTonight() {
        #expect(sky(2026, 10, 10) == [.newMoonTonight])
        #expect(!sky(2026, 10, 9).contains(.newMoonTonight) && !sky(2026, 10, 11).contains(.newMoonTonight))
    }

    @Test func oneEverydayPhaseLineUnlessFullOrNew() {
        for d in 1...31 {
            let l = sky(2026, 10, d)
            let full = l.contains(.fullMoonTonight) || l.contains(.newMoonTonight)
            #expect(phase(l).count == (full ? 0 : 1), "day \(d)")
        }
        #expect(phase(sky(2026, 10, 15)) == [.waxingCrescent])
        #expect(phase(sky(2026, 10, 18)) == [.firstQuarter])
        #expect(phase(sky(2026, 10, 21)) == [.waxingGibbous])
        #expect(phase(sky(2026, 10, 28)) == [.waningGibbous])
        #expect(phase(sky(2027, 9, 22)) == [.lastQuarter])
        #expect(phase(sky(2026, 10, 8)) == [.waningCrescent])
        #expect(phase(sky(2027, 9, 24)) == [.waningCrescent])
    }

    @Test func solsticesFollowTheHemisphere() {
        #expect(sky(2026, 12, 21).contains(.longestNight) && !sky(2026, 12, 21).contains(.shortestNight))
        #expect(sky(2026, 12, 21, south: true).contains(.shortestNight))
        #expect(sky(2027, 6, 21).contains(.shortestNight))
        #expect(sky(2027, 6, 21, south: true).contains(.longestNight))
        #expect(!sky(2026, 12, 20).contains(.longestNight) && !sky(2026, 12, 22).contains(.longestNight))
    }

    @Test func equinoxes() {
        #expect(sky(2027, 3, 20).contains(.equinox))
        #expect(sky(2027, 9, 23).contains(.equinox))
        #expect(!sky(2027, 3, 19).contains(.equinox) && !sky(2027, 3, 21).contains(.equinox))
        #expect(!sky(2026, 10, 15).contains(.equinox))
    }

    @Test func tiersAndDeterminism() {
        #expect(BuddyLine.fullMoonTonight.tier == 2 && BuddyLine.equinox.tier == 2)
        #expect(BuddyLine.fullMoonTomorrow.tier == 4 && BuddyLine.fullMoonSoon(days: 2).tier == 4)
        #expect(BuddyLine.moonPhase(.firstQuarter).tier == 5)
        #expect(sky(2026, 10, 24) == sky(2026, 10, 24))
        let input = BuddyTalkInput(now: cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 10))!, calendar: cal,
                                   town: TownSnapshot(), lastNight: nil, streak: 0, bestStreak: 0, builtNights: 20,
                                   unlockedMaxLevel: 1, nextBedtime: nil)
        #expect(BuddyTalk.lines(input) == BuddyTalk.lines(input))
        #expect(BuddyTalk.lines(input).first == .fullMoonTonight)
    }
}
