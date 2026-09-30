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
        #expect(h.model.graceEnds == date(5, 22, 35))                        // bedtime 22:30 + 5 min (early start)
        #expect(!h.model.confirm(code: "1234"))                               // too early
        h.clock.now = date(6, 6, 30); h.model.refresh()
        #expect(h.model.phase == .alarm)
        #expect(h.model.active?.log.has(.alarmFired) == true)
        #expect(!h.model.confirm(code: "0000"))                               // wrong code
        #expect(h.model.confirm(code: "1234"))
        #expect(h.model.shownResult?.log.has(.confirmedByCode) == true)
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
        #expect(h.model.shownResult?.log.has(.confirmedByShake) == true)
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

    @Test func vibrationsAtTheKeyMomentsOfANight() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        #expect(h.model.haptics == [.start])
        h.clock.now = date(5, 22, 30); h.model.refresh()                 // setup until 22:35, still in the app
        h.clock.now = date(5, 22, 34) + 50; h.model.refresh()
        #expect(h.model.haptics == [.start])                              // in the app → no "15 s left" buzz
        h.model.append(.leftApp)                                          // podcast app
        h.clock.now += 1; h.model.refresh()
        h.clock.now += 1; h.model.refresh()                               // only once per night
        #expect(h.model.haptics == [.start, .warning])
        h.clock.now = date(5, 22, 35) + 5; h.model.append(.returned)       // back in time, no warning was sent
        h.clock.now = date(5, 22, 36); h.model.append(.locked)
        #expect(h.model.haptics == [.start, .warning, .locked])
        h.clock.now = date(5, 23); h.model.append(.returned)
        h.model.append(.leftApp)                                          // after the setup → "Come back!"
        #expect(h.model.haptics.last == .warning && h.model.nudgesSent == 1)
        h.clock.now += 5; h.model.append(.returned)                       // in time → relief
        #expect(h.model.haptics.last == .relief)
        h.clock.now = date(5, 23, 30); h.model.append(.leftApp)
        h.clock.now += 60; h.model.append(.returned)                      // too late: collapsed, no relief
        #expect(h.model.collapsedAt != nil && h.model.haptics.last == .warning)
        h.clock.now = date(5, 23, 40); h.model.append(.locked)            // a collapsed building: no lock buzz
        #expect(h.model.haptics.last == .warning)
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

    @Test func coinsForRealNightsOnly() {
        let h = harness(at: date(1, 12))
        playNight(h, day: 1)                                              // complete +100
        #expect(h.model.coins == 100 && h.model.lastReward == 100)
        playNight(h, day: 2, confirmAfterWake: 30 * 60)                   // unfinished +50
        #expect(h.model.coins == 150)
        h.clock.now = date(3, 15)
        h.model.startTestNight(); h.model.startNight()                    // debug: nothing
        h.clock.now += 240; h.model.refresh(); h.model.confirm()
        #expect(h.model.coins == 150 && h.model.lastReward == 0)
        h.model.acknowledgeResult()
        h.model.nextTestNightCounts = true                                // the counted test night pays
        h.model.startTestNight(); h.model.startNight()
        h.clock.now += 240; h.model.refresh(); h.model.confirm()
        #expect(h.model.coins == 250)
    }

    @Test func seventhNightPaysTheStreakBonus() {
        let h = harness(at: date(1, 12))
        for d in 1...6 { playNight(h, day: d) }
        h.clock.now = date(7, 22, 25); h.model.refresh(); h.model.startNight()
        h.clock.now = date(8, 6, 31); h.model.refresh(); h.model.confirm(code: "1234")
        #expect(h.model.lastReward == 300 && h.model.lastStreakBonus == 200)
        #expect(h.model.coins == 900)
    }

    @Test func sleepSoundDuringTheNight() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh()
        h.model.playSleepSound(.rainTent, minutes: 15)                         // no night yet → ignored
        #expect(h.model.sleepSound == nil)
        h.model.startNight()
        h.clock.now = date(5, 22, 50)
        h.model.playSleepSound(.rainTent, minutes: 15)
        #expect(h.model.sleepSound?.ambience == .rainTent && h.model.sleepSound?.endsAt == date(5, 23, 5))
        #expect(h.model.settings.ambience == .rainTent && h.model.settings.ambienceMinutes == 15)
        h.model.playSleepSound(.pinkNoise, minutes: nil)                   // all night
        #expect(h.model.sleepSound?.endsAt == nil)
        h.model.stopSleepSound()
        #expect(h.model.sleepSound == nil)
        h.model.playSleepSound(.silence, minutes: 5)
        #expect(h.model.sleepSound == nil)
        #expect(h.model.collapsedAt == nil)                                // staying in the app is fine
    }

    @Test func napWindowOnePerDayAndMessages() {
        let h = harness(at: date(5, 12, 59))
        let was12h = Fmt.systemUses12h
        defer { Fmt.systemUses12h = was12h }
        Fmt.systemUses12h = false
        #expect(h.model.napBlockReason()?.contains("13:00–15:00") == true)
        Fmt.systemUses12h = true
        #expect(h.model.napBlockReason()?.replacingOccurrences(of: "\u{202F}", with: " ").contains("1:00 PM–3:00 PM") == true)
        h.model.language = .sk
        #expect(h.model.napBlockReason() == "Teraz nemôžeš odpočívať (13:00–15:00).")   // SK is always 24 h
        h.model.language = .en
        h.clock.now = date(5, 15, 0)                                        // edge: exactly the window end
        #expect(h.model.napBlockReason() == nil)
        h.model.startNap()
        #expect(h.model.active?.isNap == true && h.model.phase == .building)
        #expect(h.model.active?.wake == date(5, 15, 30))                    // 30 min default
        #expect(h.model.graceEnds == date(5, 15, 2))                         // 2 min setup
        #expect(h.model.napBlockReason() == "A night is in progress.")
        #expect(!h.model.confirm(code: "1234"))                             // only at the end
        h.clock.now = date(5, 15, 30); h.model.refresh()
        #expect(h.model.phase == .alarm)
        #expect(h.model.confirm(code: "1234"))
        #expect(h.model.shownResult?.isNap == true && h.model.shownResult?.outcome == .complete)
        #expect(h.model.coins == 50 && h.model.lastReward == 50 && h.model.levelUp == nil)
        #expect(h.model.napSummary.count == 1 && h.model.napSummary.coins == 50)
        #expect(h.model.builtNights == 0 && h.model.townSnapshot?.buildings.isEmpty == true && h.model.streak == 0)
        h.model.acknowledgeResult()
        #expect(h.model.napBlockReason() == "You've already had today's nap 😴")
        h.clock.now = date(5, 18, 0)
        #expect(h.model.napBlockReason() != nil)
    }

    @Test func sixtyMinuteNapFromTheEdgeAndAnInterruptedNap() {
        let h = harness(at: date(5, 15, 0))
        h.model.settings.nap.minutes = 60
        h.model.startNap()
        #expect(h.model.active?.wake == date(5, 16, 0))                     // 15:00 → 16:00
        h.clock.now = date(5, 15, 10); h.model.append(.leftApp)
        h.clock.now = date(5, 15, 12); h.model.append(.returned)
        #expect(h.model.collapsedAt != nil)
        h.clock.now = date(5, 16, 1); h.model.refresh(); h.model.confirm()
        #expect(h.model.shownResult?.outcome == .ruins && h.model.coins == 0)
        // a nap never blocks the night
        h.model.acknowledgeResult()
        h.clock.now = date(5, 22, 25); h.model.refresh()
        #expect(h.model.phase == .canStart)
    }

    @Test func settingsChangesArePersisted() {
        let h = harness(at: date(5, 12))
        h.model.settings.alarmSound = .alert
        #expect(AppSettings.load().alarmSound == .alert)
    }
}
