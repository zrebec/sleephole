import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// A quick test night behaves like a real night: confirming opens shortly before its wake, also after a relaunch.
@MainActor
struct TestNightConfirmTests {
    let sprites = SpriteLibrary.loadFromBundle()

    init() { AudioKeeper.muted = true }

    func makeModel(at now: Date) -> (AppModel, FakeClock, ModelContainer) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, BoxRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(now)
        var s = AppSettings()
        s.wakeCode = "1234"
        let m = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s, servicesEnabled: false)
        return (m, clock, c)
    }

    @Test func testNightCannotBeConfirmedRightAfterItsStart() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let (m, clock, c) = makeModel(at: start)
        withExtendedLifetime(c) {
            m.startTestNight()
            m.startNight()
            #expect(m.active?.isDebug == true)
            clock.now = start + 12
            #expect(m.confirm() == false)
            #expect(m.confirm(code: "1234") == false)
            m.shakeBeforeConfirm()                                   // the too-early note, no event
            #expect(m.earlyShakeAt == clock.now)
            #expect(m.active?.log.events.contains { $0.kind == .confirmed } == false)
            clock.now = start + 240 - 20                             // the last ~30 s
            m.shakeBeforeConfirm()
            #expect(m.earlyShakeAt == start + 12)                    // no new note once confirming is open
            #expect(m.confirm() == true)
        }
    }

    @Test func recordRoundTripKeepsTheOpening() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let live = NightWindow(key: NightKey(date: now, calendar: .current), bedtime: now, wake: now + 240,
                               earlyConfirmOverride: NightWindow.testNightConfirmLead)
        let debug = NightRecord(window: live, buildingId: "x", isDebug: true, setupGrace: 15)
        #expect(debug.window.confirmOpens == live.confirmOpens)
        let real = NightRecord(window: live, buildingId: "x", isDebug: false, setupGrace: 300)
        #expect(real.window.confirmOpens == live.wake - NightWindow.earlyConfirm)
        let nap = NightRecord(window: live, buildingId: "", isDebug: false, setupGrace: 120, isNap: true)
        #expect(nap.window.confirmOpens == live.wake - NapPlan.confirmLead(forLength: 240))   // a nap opens in its last 20 %
    }
}
