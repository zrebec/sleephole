import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// Drives the real AppModel with a FakeClock and an in-memory store (no audio / notifications).
@MainActor
struct AppModelTests {
    let catalog = SpriteLibrary.loadFromBundle().catalog!
    let cal = Calendar.current

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    final class Harness {
        let container: ModelContainer
        let clock: FakeClock
        let model: AppModel
        init(container: ModelContainer, clock: FakeClock, model: AppModel) {
            self.container = container; self.clock = clock; self.model = model
        }
    }

    func harness(at now: Date, container: ModelContainer? = nil) -> Harness {
        let c = container ?? (try! ModelContainer(for: NightRecord.self, UserProgress.self,
                                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let clock = FakeClock(now)
        var s = AppSettings()
        s.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        s.wakeCode = "1234"
        let m = AppModel(context: c.mainContext, catalog: catalog, clock: clock, settings: s, servicesEnabled: false)
        return Harness(container: c, clock: clock, model: m)
    }

    /// Plays one whole night starting on `day` (bedtime 22:30, wake 6:30 next day).
    @discardableResult
    func playNight(_ h: Harness, day: Int, leaveFor: TimeInterval = 0, confirmAfterWake: TimeInterval = 60) -> Outcome? {
        h.clock.now = date(day, 22, 25); h.model.refresh()
        #expect(h.model.phase == .canStart)
        h.model.startNight()
        if leaveFor > 0 {
            h.clock.now = date(day, 23, 30); h.model.append(.leftApp)
            h.clock.now += leaveFor; h.model.append(.returned)
        }
        h.clock.now = date(day + 1, 6, 30) + confirmAfterWake; h.model.refresh()
        if confirmAfterWake <= 3600 { #expect(h.model.confirm(code: "1234")) } else { h.model.refresh() }
        let outcome = h.model.shownResult?.outcome
        h.model.acknowledgeResult()
        return outcome
    }

    @Test func startWindowIsBedtimeMinus10ToPlus5() {
        let h = harness(at: date(5, 22, 19))
        #expect(h.model.phase == .idle)
        h.clock.now = date(5, 22, 20); h.model.refresh()
        #expect(h.model.phase == .canStart)
        h.clock.now = date(5, 22, 35); h.model.refresh()
        #expect(h.model.phase == .canStart)
        h.clock.now = date(5, 22, 36); h.model.refresh()
        #expect(h.model.phase == .idle)
    }

    @Test func aPerfectNightBuildsTheFirstHouse() {
        let h = harness(at: date(5, 12))
        h.clock.now = date(5, 22, 25); h.model.refresh()
        h.model.startNight()
        #expect(h.model.phase == .building)
        #expect(h.model.active?.buildingId.hasPrefix("l1-") == true)          // first nights: level 1 only
        #expect(h.model.graceEnds == date(5, 22, 30))
        #expect(!h.model.confirm(code: "1234"))                               // too early
        h.clock.now = date(6, 6, 30); h.model.refresh()
        #expect(h.model.phase == .alarm)
        #expect(h.model.active?.log.has(.alarmFired) == true)
        #expect(!h.model.confirm(code: "0000"))                               // wrong code
        #expect(h.model.confirm(code: "1234"))
        #expect(h.model.phase == .result)
        #expect(h.model.shownResult?.outcome == .complete)
        #expect(h.model.builtNights == 1)
        #expect(h.model.townSnapshot?.buildings.count == 1)
        #expect(h.model.townRender != nil && h.model.townVersion >= 2)
        h.model.acknowledgeResult()
        h.clock.now = date(6, 22, 20); h.model.refresh()
        #expect(h.model.phase == .canStart)                                  // next night
    }

    @Test func shakeConfirmsWithoutCode() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        h.clock.now = date(6, 6, 0); h.model.refresh()                        // wake − 30 min
        #expect(h.model.phase == .building)
        #expect(h.model.confirm())
        #expect(h.model.shownResult?.outcome == .complete)
    }

    @Test func leavingTheAppCollapsesTheBuilding() {
        let h = harness(at: date(5, 12))
        #expect(playNight(h, day: 5, leaveFor: 30) == .ruins)
        #expect(h.model.townSnapshot?.buildings.first?.state == .ruins)
    }

    @Test func shortTripIsTolerated() {
        let h = harness(at: date(5, 12))
        #expect(playNight(h, day: 5, leaveFor: 5) == .complete)
    }

    /// Regression (owner 2026-09-29): the "Vráť sa" warning was never sent.
    @Test func leavingAfterTheGraceSendsExactlyOneWarning() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        h.clock.now = date(5, 22, 27); h.model.append(.leftApp)          // inside the 5-min setup: no warning
        h.clock.now += 60; h.model.append(.returned)
        #expect(h.model.nudgesSent == 0)
        h.clock.now = date(5, 23, 30); h.model.append(.leftApp)          // after the setup → warning
        #expect(h.model.nudgesSent == 1)
        h.clock.now += 5; h.model.append(.returned)
        #expect(h.model.collapsedAt == nil)                               // back within 10 s after the warning
        h.clock.now = date(5, 23, 40); h.model.append(.leftApp)
        h.clock.now += 60; h.model.append(.returned)                      // too long → collapsed
        #expect(h.model.nudgesSent == 2 && h.model.collapsedAt != nil)
        h.clock.now = date(5, 23, 50); h.model.append(.leftApp)          // already collapsed: no more warnings
        #expect(h.model.nudgesSent == 2)
    }

    @Test func collapseIsVisibleLive() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        h.clock.now = date(5, 23); h.model.append(.leftApp)
        #expect(h.model.collapsedAt == date(5, 23) + 13)       // ~3 s to notice + 10 s to return
    }

    @Test func lateConfirmIsUnfinishedAndMissingConfirmIsRuins() {
        let h = harness(at: date(5, 12))
        #expect(playNight(h, day: 5, confirmAfterWake: 30 * 60) == .unfinished)
        #expect(playNight(h, day: 6, confirmAfterWake: 2 * 3600) == .ruins)
    }

    @Test func abandonMakesRuins() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        h.model.abandonNight()
        #expect(h.model.shownResult?.outcome == .ruins)
        #expect(h.model.active == nil)
    }

    @Test func levelTwoUnlocksAfterFiveNights() {
        let h = harness(at: date(1, 12))
        for d in 1...4 { playNight(h, day: d) }
        #expect(h.model.levelUp == nil)
        h.clock.now = date(5, 22, 25); h.model.refresh(); h.model.startNight()
        h.clock.now = date(6, 6, 31); h.model.refresh()
        #expect(h.model.confirm(code: "1234"))
        #expect(h.model.levelUp == 2)
        #expect(h.model.builtNights == 5)
    }

    @Test func testNightsDoNotCountButTheBonusOneDoes() {
        let h = harness(at: date(5, 15))
        h.model.startTestNight(minutes: 4, grace: 20)
        #expect(h.model.phase == .canStart && h.model.debugWindow != nil)
        h.model.startNight()
        #expect(h.model.active?.isDebug == true)
        h.clock.now += 4 * 60; h.model.refresh()
        #expect(h.model.confirm())
        #expect(h.model.builtNights == 0)
        h.model.acknowledgeResult()

        h.model.nextTestNightCounts = true
        h.model.startTestNight(minutes: 15, grace: 300)
        h.model.startNight()
        #expect(h.model.nextTestNightCounts == false)                         // one-shot
        #expect(h.model.active?.isDebug == false && h.model.active?.id.hasPrefix("bonus-") == true)
        h.clock.now += 15 * 60; h.model.refresh()
        #expect(h.model.confirm())
        #expect(h.model.builtNights == 1)
        #expect(h.model.townSnapshot?.buildings.count == 1)
    }

    @Test func cancelFastNightReturnsToIdle() {
        let h = harness(at: date(5, 15))
        h.model.startTestNight()
        h.model.cancelFastNight()
        #expect(h.model.phase == .idle && h.model.debugWindow == nil)
    }

    @Test func clearNightsWipesEverything() {
        let h = harness(at: date(5, 12))
        playNight(h, day: 5)
        h.model.clearNights()
        #expect(h.model.records().isEmpty && h.model.builtNights == 0)
        #expect(h.model.townSnapshot?.buildings.isEmpty == true)
    }

    @Test func aKilledAppResumesTheNight() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        let again = harness(at: date(6, 2), container: h.container)
        #expect(again.model.active != nil)
        #expect(again.model.phase == .building)
        #expect(again.model.active?.log.has(.appLaunched) == true)
    }

    @Test func streakFlameCountsCompleteNightsInARow() {
        let h = harness(at: date(1, 12))
        #expect(h.model.streak == 0)
        playNight(h, day: 1)
        playNight(h, day: 2)
        h.clock.now = date(3, 12); h.model.refresh()
        #expect(h.model.streak == 2)
        playNight(h, day: 3, confirmAfterWake: 30 * 60)                  // unfinished: neither +1 nor break
        h.clock.now = date(4, 12); h.model.refresh()
        #expect(h.model.streak == 2)
        h.clock.now = date(6, 12); h.model.refresh()                       // a missed night breaks it
        #expect(h.model.streak == 0)
    }

    @Test func confirmingAfterTheAlarmStoppedIsUnfinished() {
        let h = harness(at: date(5, 12))
        #expect(playNight(h, day: 5, confirmAfterWake: 2 * 60 + 16) == .unfinished)   // owner test 29.09 19:06
    }

    @Test func settingsChangesArePersisted() {
        let h = harness(at: date(5, 12))
        h.model.settings.alarmSound = .alert
        #expect(AppSettings.load().alarmSound == .alert)
    }
}
