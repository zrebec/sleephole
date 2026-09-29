import Foundation
import Testing
@testable import SleepCore

@Suite struct ScheduleTests {
    @Test(arguments: [
        (at(2026, 9, 28, 12), "2026-09-29"),          // noon: heading into tonight
        (at(2026, 9, 28, 21), "2026-09-29"),
        (at(2026, 9, 29, 2), "2026-09-29"),           // middle of the night
        (at(2026, 9, 29, 6, 50), "2026-09-29"),       // after wake, confirm window
        (at(2026, 9, 29, 7, 29), "2026-09-29"),       // still in the late window
        (at(2026, 9, 29, 7, 31), "2026-09-30"),       // after the late window → next night
    ])
    func windowContaining(t: Date, key: String) {
        let w = defaultSchedule.window(containing: t, calendar: bratislava)
        #expect(w.key.description == key)
        #expect(bratislava.component(.hour, from: w.bedtime) == 22)
        #expect(bratislava.component(.hour, from: w.wake) == 6)
        #expect(w.wake > w.bedtime)
    }

    @Test func derivedWindows() {
        #expect(night.bedtime == at(2026, 9, 28, 22, 30))
        #expect(night.wake == at(2026, 9, 29, 6, 30))
        #expect(night.startOpens == at(2026, 9, 28, 22, 20))      // bedtime − 10 min (owner rule)
        #expect(night.confirmOpens == at(2026, 9, 29, 6, 0))
        #expect(night.confirmOnTimeUntil == at(2026, 9, 29, 6, 32))       // only while the alarm rings
        #expect(night.confirmLateUntil == at(2026, 9, 29, 7, 30))
        #expect(night.duration == 8 * 3600)
    }

    @Test func bedtimeAfterMidnight() {
        let s = Schedule(bedtime: TimeOfDay(0, 30), wake: TimeOfDay(8, 0))
        let w = s.window(containing: at(2026, 9, 28, 23), calendar: bratislava)
        #expect(w.bedtime == at(2026, 9, 29, 0, 30))
        #expect(w.wake == at(2026, 9, 29, 8, 0))
        #expect(w.key.description == "2026-09-29")
    }

    @Test func springForwardNightIsOneHourShorter() {       // 29 Mar 2026: 02:00 → 03:00
        let w = defaultSchedule.window(containing: at(2026, 3, 28, 20), calendar: bratislava)
        #expect(w.key.description == "2026-03-29")
        #expect(w.duration == 7 * 3600)
    }

    @Test func fallBackNightIsOneHourLonger() {             // 25 Oct 2026: 03:00 → 02:00
        let w = defaultSchedule.window(containing: at(2026, 10, 24, 20), calendar: bratislava)
        #expect(w.key.description == "2026-10-25")
        #expect(w.duration == 9 * 3600)
    }

    @Test func windowForKeyMatchesWindowContaining() {
        let key = NightKey("2026-09-29")!
        #expect(defaultSchedule.window(for: key, calendar: bratislava) == night)
    }

    @Test func nightKeyArithmeticAndParsing() {
        let k = NightKey("2026-10-31")!
        #expect(k.adding(days: 1, calendar: bratislava).description == "2026-11-01")
        #expect(k.adding(days: -31, calendar: bratislava).description == "2026-09-30")
        #expect(NightKey("nonsense") == nil)
        #expect(NightKey("2026-09-29")! < NightKey("2026-10-01")!)
    }
}
