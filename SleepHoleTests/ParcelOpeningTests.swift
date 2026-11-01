import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// Step 11b4b: the opening's timeline and when the app asks the shop to play it.
@MainActor @Suite(.serialized) struct ParcelOpeningTests {
    init() { AudioKeeper.muted = true; Lang.current = .en }

    @Test func phasesFollowTheBoundariesScaledByThePace() {
        for pace in [1.0, Motion.pace, 2.5] {
            func p(_ u: Double) -> ParcelOpening.Phase { ParcelOpening.phase(at: u * pace, reduceMotion: false, pace: pace) }
            #expect(p(0) == .wobble && p(0.69) == .wobble)
            #expect(p(0.71) == .pop && p(0.99) == .pop)
            #expect(p(1.01) == .reveal && p(1.39) == .reveal)
            #expect(p(1.41) == .done && p(60) == .done)
        }
        #expect(abs(ParcelOpening.doneAt * Motion.pace - 2.24) < 0.001)
    }

    @Test func reduceMotionAndASkipGoStraightToTheEnd() {
        #expect(ParcelOpening.phase(at: 0, reduceMotion: true) == .done)
        #expect(ParcelOpening.phase(at: 0, reduceMotion: false, skipped: true) == .done)
        #expect(ParcelOpening.phase(at: 0, reduceMotion: false) == .wobble)
    }

    @Test func buyingSetsTheOpeningAndARefusedPurchaseDoesNot() {
        let cal = Calendar.current
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, BoxRecord.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        func date(_ d: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))! }
        let clock = FakeClock(date(19, 12, 0))
        var s = AppSettings(); s.wakeCode = "1234"
        let model = AppModel(context: c.mainContext, catalog: SpriteLibrary.loadFromBundle().catalog, clock: clock, settings: s,
                             servicesEnabled: false, defaults: UserDefaults(suiteName: "sleephole-opening-\(UUID().uuidString)")!)
        model.sync.firstReadDone = true
        for m in 20...24 {
            clock.now = date(m - 1, 22, 25); model.refresh(); model.startNight()
            clock.now = date(m, 6, 31); model.refresh(); model.confirm(code: "1234"); model.acknowledgeResult()
        }
        clock.now = date(24, 12, 0); model.refresh()
        #expect(model.openingParcel == nil)
        let bought = model.buyBox(seed: 5)
        #expect(bought != nil && model.openingParcel?.id == bought?.id)
        model.openingParcel = nil
        #expect(model.buyBox(seed: 6) == nil && model.openingParcel == nil)       // one a day
    }
}
