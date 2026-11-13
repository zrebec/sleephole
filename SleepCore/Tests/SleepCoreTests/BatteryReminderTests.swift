import Testing
@testable import SleepCore

@Suite("Battery reminder (13l)")
struct BatteryReminderTests {
    @Test func atThirtyUnpluggedReminds() {
        #expect(BatteryReminder.shouldRemind(level: 0.30, plug: .unplugged, isNap: false))
        #expect(BatteryReminder.shouldRemind(level: 0.24, plug: .unplugged, isNap: false))
        #expect(BatteryReminder.shouldRemind(level: 0, plug: .unplugged, isNap: false))
    }
    @Test func aboveThirtyDoesNot() {
        #expect(!BatteryReminder.shouldRemind(level: 0.31, plug: .unplugged, isNap: false))
        #expect(!BatteryReminder.shouldRemind(level: 1, plug: .unplugged, isNap: false))
    }
    @Test func pluggedOrUnknownStateDoesNot() {
        for plug in [BatteryPlug.charging, .full, .unknown] {
            #expect(!BatteryReminder.shouldRemind(level: 0.10, plug: plug, isNap: false))
        }
    }
    @Test func unknownLevelDoesNot() {
        #expect(!BatteryReminder.shouldRemind(level: -1, plug: .unplugged, isNap: false))
    }
    @Test func aNapNeverReminds() {
        #expect(!BatteryReminder.shouldRemind(level: 0.10, plug: .unplugged, isNap: true))
    }
    @Test func percentIsRounded() {
        #expect(BatteryReminder.percent(0.236) == 24)
        #expect(BatteryReminder.percent(0.30) == 30)
    }
}
