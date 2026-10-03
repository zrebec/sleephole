import Foundation
import Testing
@testable import SleepCore

@Suite struct SkyTests {
    func sky(_ h: Int, _ m: Int = 0, schedule: Schedule = defaultSchedule, day: Int = 15) -> SkyState {
        Sky.state(at: at(2026, 10, day, h, m), schedule: schedule, calendar: bratislava)
    }

    @Test func phasesFollowTheDefaultSchedule() {          // 22:30 → 06:30
        #expect(sky(3).phase == .night)
        #expect(sky(5, 59).phase == .night)
        #expect(sky(6, 0).phase == .dawn)                  // wake − 30 min
        #expect(sky(7, 29).phase == .dawn)
        #expect(sky(7, 30).phase == .day)                  // wake + 60 min
        #expect(sky(14).phase == .day)
        #expect(sky(21, 0).phase == .dusk)                 // bedtime − 90 min
        #expect(sky(22, 29).phase == .dusk)
        #expect(sky(22, 30).phase == .night)
        #expect(sky(23, 59).phase == .night)
    }

    @Test func daylightAndGlowAreContinuous() {
        #expect(sky(3).daylight == 0)
        #expect(sky(12).daylight == 1 && sky(12).glow == 0)
        let midDawn = sky(6, 45)
        #expect(abs(midDawn.daylight - 0.5) < 0.01 && midDawn.glow > 0.99)
        let midDusk = sky(21, 45)
        #expect(abs(midDusk.daylight - 0.5) < 0.01 && midDusk.glow > 0.99)
        #expect(sky(22, 29).daylight < 0.01)
    }

    @Test func arcRunsLeftToRight() {
        #expect(sky(22, 30).arc == 0)                       // moon rises at bedtime
        #expect(abs(sky(2, 15).arc - 0.5) < 0.01)           // 22:30 … 06:00 → middle at 02:15
        #expect(sky(6, 0).arc == 0)                         // sun rises at dawn
        #expect(sky(14).arc > 0.4 && sky(14).arc < 0.6)
    }

    @Test func bedtimeAfterMidnightWorks() {
        let late = Schedule(bedtime: TimeOfDay(0, 30), wake: TimeOfDay(8, 0))
        #expect(sky(23, 30, schedule: late).phase == .dusk)
        #expect(sky(1, schedule: late).phase == .night)
        #expect(sky(7, 45, schedule: late).phase == .dawn)
        #expect(sky(12, schedule: late).phase == .day)
    }

    @Test func shortDayDawnAndDuskMeetInTheMiddle() {
        // awake only 06:00 … 08:00: dawn 05:30 … 06:45, dusk 06:45 … 08:00
        let short = Schedule(bedtime: TimeOfDay(8, 0), wake: TimeOfDay(6, 0))
        #expect(sky(6, 30, schedule: short).phase == .dawn)
        #expect(sky(7, 0, schedule: short).phase == .dusk)
        #expect(sky(12, schedule: short).phase == .night)
    }

    @Test func dstNightsStillHaveOneWake() {                 // 25 Oct 2026: clocks go back at 03:00
        #expect(sky(2, 30, day: 25).phase == .night)
        #expect(sky(6, 15, day: 25).phase == .dawn)
        #expect(sky(12, day: 25).phase == .day)
    }
}
