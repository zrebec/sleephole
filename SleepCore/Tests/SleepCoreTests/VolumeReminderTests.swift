import Testing
@testable import SleepCore

@Suite("Volume reminder (13r)")
struct VolumeReminderTests {
    @Test func zeroIsOff() { #expect(VolumeReminder.level(volume: 0) == .off) }
    @Test func lowSteps() {
        #expect(VolumeReminder.level(volume: 0.0625) == .low)
        #expect(VolumeReminder.level(volume: 0.25) == .low)
    }
    @Test func aboveThresholdIsNothing() {
        #expect(VolumeReminder.level(volume: 0.3125) == nil)
        #expect(VolumeReminder.level(volume: 1) == nil)
        #expect(VolumeReminder.level(volume: 1.5) == nil)
    }
    @Test func roundsToWholePercent() {
        #expect(VolumeReminder.level(volume: 0.2500001) == .low)
        #expect(VolumeReminder.level(volume: 0.2499) == .low)
        #expect(VolumeReminder.level(volume: 0.2551) == nil)
        #expect(VolumeReminder.level(volume: 0.004) == .off)
    }
    @Test func unknownIsNothing() {
        #expect(VolumeReminder.level(volume: -1) == nil)
        #expect(VolumeReminder.level(volume: .nan) == nil)
        #expect(VolumeReminder.level(volume: .infinity) == nil)
    }
}
