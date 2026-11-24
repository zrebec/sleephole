import Foundation
import Testing
import SleepCore
import SwiftData
import UIKit
@testable import SleepHole

/// The rest screen's brightness (13k): dim → restore gives back exactly what was found; nothing else.
@MainActor
struct RestBrightnessTests {
    final class FakeScreen: ScreenBrightness {
        var brightness: CGFloat
        init(_ b: CGFloat) { brightness = b }
    }

    @Test func dimThenRestoreGivesBackTheSavedValue() {
        let screen = FakeScreen(0.8)
        let d = BrightnessDimmer(screen: screen)
        d.dim()
        #expect(screen.brightness == BrightnessDimmer.level)
        d.restore()
        #expect(screen.brightness == 0.8)
        #expect(!d.isDimmed)
    }

    @Test func aSecondDimWhileDimmedKeepsTheFirstValue() {
        let screen = FakeScreen(0.7)
        let d = BrightnessDimmer(screen: screen)
        d.dim(); d.dim()
        d.restore()
        #expect(screen.brightness == 0.7)
    }

    @Test func restoreWithoutADimDoesNothing() {
        let screen = FakeScreen(0.4)
        let d = BrightnessDimmer(screen: screen)
        d.restore()
        #expect(screen.brightness == 0.4)
    }

    @Test func aDimAfterARestoreSavesTheThenCurrentValue() {
        let screen = FakeScreen(0.8)
        let d = BrightnessDimmer(screen: screen)
        d.dim(); d.restore()
        screen.brightness = 0.5                       // the user changed it meanwhile
        d.dim()
        d.restore()
        #expect(screen.brightness == 0.5)
    }

    @Test func aScreenThatReadsZeroIsNeverDimmedNorRestored() {
        let screen = FakeScreen(0)
        let d = BrightnessDimmer(screen: screen)
        #expect(!d.dim())
        #expect(!d.isDimmed)
        screen.brightness = 0.6                                  // the display woke up meanwhile
        d.restore()
        #expect(screen.brightness == 0.6)                        // nothing was saved, so nothing is put back
    }

    @Test func dimAndRestoreAreWrittenToTheTrackInWholePercents() {
        let screen = FakeScreen(0.8)
        let d = BrightnessDimmer(screen: screen)
        var lines: [String] = []
        d.onDiag = { k, v in lines.append("\(k) \(v ?? "")") }
        d.dim(); d.restore()
        #expect(lines == ["bright dim from=80 to=10", "bright restore to=80"])
    }

    @Test func aScreenAlreadyAtOrBelowTheLevelIsLeftUntouched() {
        let screen = FakeScreen(0.05)
        let d = BrightnessDimmer(screen: screen)
        d.dim()
        #expect(screen.brightness == 0.05)
        d.restore()
        #expect(screen.brightness == 0.05)
    }
}

/// The controller around the rule, with a fake screen and a fake clock.
@MainActor
struct RestControllerTests {
    final class FakeScreen: ScreenBrightness {
        var brightness: CGFloat = 0.9
    }

    func make(_ screen: FakeScreen, at clock: Box<Date>) -> RestController {
        let c = RestController(screen: screen)
        c.now = { clock.value }
        c.delay = 30
        c.sceneActive = true
        c.appActive = { true }                                  // the test host is not the active application
        c.uikitPresentation = { false }
        let t0 = clock.value
        c.night = { .init(isBuilding: true, setupEnds: t0.addingTimeInterval(10), pauseRunning: false) }
        return c
    }
    final class Box<T> { var value: T; init(_ v: T) { value = v } }

    @Test func restsAfterTheDelayDimsAndWakesWithTheBrightnessBack() {
        let screen = FakeScreen()
        let clock = Box(Date(timeIntervalSinceReferenceDate: 10_000))
        let c = make(screen, at: clock)
        c.evaluate()
        clock.value += 39; c.evaluate()                        // 29 s after the setup
        #expect(!c.resting && screen.brightness == 0.9)
        clock.value += 1; c.evaluate()
        #expect(c.resting && screen.brightness == BrightnessDimmer.level)
        c.touched()                                            // a touch wakes and restores
        #expect(!c.resting && screen.brightness == 0.9)
        clock.value += 29; c.evaluate()
        #expect(!c.resting)                                    // the 30 s start again
        clock.value += 1; c.evaluate()
        #expect(c.resting)
    }

    @Test func aPhaseChangeEndsTheRestAtOnce() {
        let screen = FakeScreen()
        let clock = Box(Date(timeIntervalSinceReferenceDate: 10_000))
        let c = make(screen, at: clock)
        c.evaluate()
        clock.value += 60; c.evaluate()
        #expect(c.resting)
        c.night = { .init(isBuilding: false, setupEnds: nil, pauseRunning: false) }
        c.evaluate()
        #expect(!c.resting && screen.brightness == 0.9)
    }

    @Test func aDisabledControllerNeverRests() {
        let screen = FakeScreen()
        let clock = Box(Date(timeIntervalSinceReferenceDate: 10_000))
        let c = make(screen, at: clock)
        c.enabled = false
        c.evaluate()
        clock.value += 600; c.evaluate()
        #expect(!c.resting && screen.brightness == 0.9)
    }

    @Test func anOpenDialogOrFocusedFieldHoldsTheRestBack() {
        let screen = FakeScreen()
        let clock = Box(Date(timeIntervalSinceReferenceDate: 10_000))
        let c = make(screen, at: clock)
        c.evaluate()
        c.nightDialogOpen = true
        clock.value += 600; c.evaluate()
        #expect(!c.resting)
        c.nightDialogOpen = false
        c.evaluate()
        #expect(c.resting)
    }

    @Test func aNapRestsLikeANightAndTheBrightnessComesBack() {
        let screen = FakeScreen()
        let clock = Box(Date(timeIntervalSinceReferenceDate: 10_000))
        let c = make(screen, at: clock)                        // the controller no longer knows a nap from a night
        var lines: [String] = []
        c.onDiag = { k, v in lines.append("\(k) \(v ?? "")") }
        c.evaluate()
        clock.value += 39; c.evaluate()
        #expect(!c.resting)
        clock.value += 1; c.evaluate()
        #expect(c.resting && screen.brightness == BrightnessDimmer.level)
        let t0 = clock.value - 40
        c.night = { .init(isBuilding: false, setupEnds: t0.addingTimeInterval(10), pauseRunning: false) }   // the alarm: phase leaves .building
        c.evaluate()
        #expect(!c.resting && screen.brightness == 0.9)
        #expect(lines == ["bright dim from=90 to=10", "rest on", "bright restore to=90", "rest off why=phase"])
    }

    @Test func theApplicationNotReallyActiveDoesNotRest() {
        let screen = FakeScreen()
        let clock = Box(Date(timeIntervalSinceReferenceDate: 10_000))
        let c = make(screen, at: clock)
        c.appActive = { false }                                // a lock keeps the scene flag stale for a moment
        c.evaluate()
        clock.value += 600; c.evaluate()
        #expect(!c.resting && screen.brightness == 0.9)
        c.appActive = { true }
        c.evaluate()
        #expect(c.resting)
        c.appActive = { false }                                // and an active rest ends when the app is not in front
        c.evaluate()
        #expect(!c.resting && screen.brightness == 0.9)
    }

    /// A reading of 0 is never saved, dimmed or put back – yet the rest screen itself still shows (a phone with the slider
    /// at its minimum must not lose the black screen; a lock is kept away by `appActive`).
    @Test func aZeroBrightnessReadingRestsWithoutSavingOrDimmingIt() {
        let screen = FakeScreen()
        screen.brightness = 0
        let clock = Box(Date(timeIntervalSinceReferenceDate: 10_000))
        let c = make(screen, at: clock)
        var lines: [String] = []
        c.onDiag = { k, v in lines.append("\(k) \(v ?? "")") }
        c.evaluate()
        clock.value += 600; c.evaluate()
        #expect(c.resting && screen.brightness == 0)
        screen.brightness = 0.7                                // the user turned the slider up meanwhile
        c.touched()
        #expect(!c.resting && screen.brightness == 0.7)        // never a 0 put back
        #expect(lines == ["bright skip at=0", "rest on", "rest off why=touch"])
    }

    @Test func restAndBlockedLinesGoToTheTrack() {
        let screen = FakeScreen()
        let clock = Box(Date(timeIntervalSinceReferenceDate: 10_000))
        let c = make(screen, at: clock)
        var lines: [String] = []
        c.onDiag = { k, v in lines.append("\(k) \(v ?? "")") }
        c.nightDialogOpen = true
        c.evaluate()
        clock.value += 600; c.evaluate()
        clock.value += 10; c.evaluate()                        // once per reason
        #expect(lines == ["rest blocked why=sheet"])
        c.nightDialogOpen = false
        c.evaluate()
        c.touched()
        #expect(Array(lines.dropFirst()) == ["bright dim from=90 to=10", "rest on", "bright restore to=90", "rest off why=touch"])
        c.wake(why: "volume")                                  // not resting: no line
        #expect(lines.count == 5)
    }
}

/// B54b (13ad): the volume buttons make no touch, so a turn down into the 🔇 / 🔉 range wakes the black screen.
@MainActor
struct RestVolumeWakeTests {
    let cal = Calendar.current
    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }
    /// A real model with a nap running and the rest screen on (the nap window of the default settings: 13:00–15:00).
    func restingNap(volume: Double) -> (AppModel, FakeClock) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self, BoxRecord.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(date(5, 13, 10))
        var s = AppSettings()
        s.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        let m = AppModel(context: c.mainContext, catalog: SpriteLibrary.loadFromBundle().catalog!, clock: clock, settings: s,
                         servicesEnabled: false)
        // the model's own rest controller (wired to the night by `configureRestScreen`) with its test seams
        m.rest.enabled = true
        m.rest.appActive = { true }
        m.rest.sceneActive = true
        m.rest.uikitPresentation = { false }
        m.rest.delay = 30
        m.rest.now = { clock.now }
        m.startNap()
        m.setMediaVolume(volume)
        clock.now += 121; m.refresh()                           // past the nap's 2 min setup
        clock.now += 31; m.refresh()                            // and 30 s without a touch
        return (m, clock)
    }

    @Test func aNapRestsInTheRealModel() {
        let (m, _) = restingNap(volume: 0.6)
        #expect(m.active?.isNap == true)
        #expect(m.rest.resting)
    }

    /// The nap's alarm ends the black screen through the model's own phase change (not only the controller's facts).
    @Test func theNapAlarmEndsTheRestInTheRealModel() {
        let (m, clock) = restingNap(volume: 0.6)
        #expect(m.rest.resting)
        clock.now = m.active!.wake.addingTimeInterval(1); m.refresh()
        #expect(m.phase == .alarm)
        #expect(!m.rest.resting)
    }

    @Test func aTurnDownToZeroWakesTheRestingScreen() {
        let (m, clock) = restingNap(volume: 0.6)
        #expect(m.rest.resting)
        m.setMediaVolume(0)
        #expect(!m.rest.resting)
        clock.now += 29; m.refresh()
        #expect(!m.rest.resting)                                // the normal 30 s start again
        clock.now += 1; m.refresh()
        #expect(m.rest.resting)
    }

    @Test func aTurnDownIntoTheLowRangeWakesIt() {
        let (m, _) = restingNap(volume: 0.6)
        m.setMediaVolume(0.25)                                   // 25 %: the line's range is inclusive
        #expect(!m.rest.resting)
    }

    @Test func aDropThatStaysAboveTheRangeOrARiseDoesNotWake() {
        let (m, _) = restingNap(volume: 0.6)
        m.setMediaVolume(0.4)
        #expect(m.rest.resting)
        m.setMediaVolume(0.3)
        #expect(m.rest.resting)
        m.setMediaVolume(0.6)                                    // a rise
        #expect(m.rest.resting)
        let (low, _) = restingNap(volume: 0.1)
        low.setMediaVolume(0.2)                                  // a rise inside the range
        #expect(low.rest.resting)
        low.setMediaVolume(-1)                                   // unknown
        #expect(low.rest.resting)
    }

    @Test func aDropFromLowToOffWakesAndNothingHappensWhenNotResting() {
        let (m, _) = restingNap(volume: 0.2)
        m.setMediaVolume(0.05)
        #expect(!m.rest.resting)
        m.setMediaVolume(0.0)                                    // awake already: nothing to do, nothing breaks
        #expect(!m.rest.resting)
    }
}
