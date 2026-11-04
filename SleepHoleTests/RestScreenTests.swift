import Foundation
import Testing
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
        c.uikitPresentation = { false }
        let t0 = clock.value
        c.night = { .init(isBuilding: true, isNap: false, setupEnds: t0.addingTimeInterval(10), pauseRunning: false) }
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
        c.night = { .init(isBuilding: false, isNap: false, setupEnds: nil, pauseRunning: false) }
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
}
