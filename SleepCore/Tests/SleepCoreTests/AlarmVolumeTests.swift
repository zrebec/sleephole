import Foundation
import Testing
@testable import SleepCore

@Suite("Alarm volume (13v)")
struct AlarmVolumeTests {
    @Test func defaultsReproduceTheOldRampOfSixtySeconds() {
        // today: 0.3 → 1.0 linearly over 60 s
        #expect(AlarmVolume.level(elapsed: 0, start: 0.3, end: 1, rise: 60) == 0.3)
        #expect(abs(AlarmVolume.level(elapsed: 30, start: 0.3, end: 1, rise: 60) - 0.65) < 1e-9)
        #expect(AlarmVolume.level(elapsed: 60, start: 0.3, end: 1, rise: 60) == 1)
        #expect(AlarmVolume.level(elapsed: 500, start: 0.3, end: 1, rise: 60) == 1)
    }
    @Test func aMelodyWithoutARampPlaysAtFullAtOnce() {
        #expect(AlarmVolume.level(elapsed: 0, start: 0.3, end: 1, rise: 0) == 1)
        #expect(AlarmVolume.initialLevel(start: 0.3, end: 1, rise: 0) == 1)
        #expect(AlarmVolume.initialLevel(start: 0.3, end: 1, rise: 10) == 0.3)
    }
    @Test func theEndLevelCapsAnInstantAlarmToo() {
        #expect(AlarmVolume.level(elapsed: 0, start: 0.1, end: 0.5, rise: 0) == 0.5)
        #expect(AlarmVolume.level(elapsed: 100, start: 0.1, end: 0.5, rise: 30) == 0.5)
    }
    @Test func inputsAreClamped() {
        #expect(AlarmVolume.level(elapsed: -5, start: 0.3, end: 1, rise: 60) == 0.3)
        #expect(AlarmVolume.level(elapsed: 10, start: -1, end: 2, rise: 10) == 1)
        #expect(AlarmVolume.level(elapsed: 0, start: 0.9, end: 0.4, rise: 30) == 0.4)     // start above end → end
    }
    @Test func percentsSnapToTens() {
        #expect(AlarmVolume.snapPercent(35) == 40)
        #expect(AlarmVolume.snapPercent(34) == 30)
        #expect(AlarmVolume.snapPercent(0) == 10)
        #expect(AlarmVolume.snapPercent(250) == 100)
        #expect(AlarmVolume.percentOptions.first == 10 && AlarmVolume.percentOptions.last == 100
                && AlarmVolume.percentOptions.count == 10)
    }
    @Test func riseOptionsFitTheAppsRing() {
        let ring = SleepRules.forNewNights.alarmDuration
        #expect(AlarmVolume.riseOptions.allSatisfy { $0 >= 0 && TimeInterval($0) <= ring })
        #expect(AlarmVolume.riseOptions.contains(120))
        #expect(AlarmVolume.riseOptions.max() == Int(ring))
    }
}
