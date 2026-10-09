import Foundation
import Testing
@testable import SleepCore

struct HoldDetectorTests {
    typealias S = HoldDetector.Sample

    /// 10 Hz samples from `from` to `to`; `acc(t)` the acceleration, `tilt(t)` the gravity tilt in degrees.
    func feed(_ d: inout HoldDetector, from: Double, to: Double,
              acc: (Double) -> Double, tilt: (Double) -> Double = { _ in 0 }) {
        var t = from
        while t <= to + 1e-9 {
            let a = tilt(t) * .pi / 180
            d.add(S(time: t, acceleration: acc(t), gx: sin(a), gy: 0, gz: -cos(a)))
            t += 0.1
        }
    }

    @Test func aPhoneLyingStillIsNotHeld() {
        var d = HoldDetector()
        feed(&d, from: 0, to: 12, acc: { _ in 0.003 })
        #expect(!d.isHeld(at: 12))
    }

    @Test func aSingleTapIsNotHeld() {
        var d = HoldDetector()
        feed(&d, from: 0, to: 12, acc: { abs($0 - 5.5) < 0.3 ? 0.05 : 0.003 })
        #expect(!d.isHeld(at: 12))
    }

    @Test func vibrationInPlaceIsNotHeld() {
        var d = HoldDetector()
        feed(&d, from: 0, to: 12, acc: { _ in 0.08 })
        #expect(!d.isHeld(at: 12))
    }

    @Test func aHandHoldingThePhoneIsHeld() {
        var d = HoldDetector()
        feed(&d, from: 0, to: 12, acc: { _ in 0.06 }, tilt: { $0 * 0.5 })     // 6° in 12 s
        #expect(d.isHeld(at: 12))
    }

    @Test func aSlowDriftWithoutAccelerationIsNotHeld() {
        var d = HoldDetector()
        feed(&d, from: 0, to: 12, acc: { _ in 0.005 }, tilt: { $0 * 2 })
        #expect(!d.isHeld(at: 12))
    }

    @Test func tooLittleTiltIsNotHeld() {
        var d = HoldDetector()
        feed(&d, from: 0, to: 12, acc: { _ in 0.06 }, tilt: { $0 * 0.1 })     // 1.2°
        #expect(!d.isHeld(at: 12))
    }

    @Test func fewerThanFourActiveSecondsIsNotHeld() {
        var d = HoldDetector()
        feed(&d, from: 0, to: 12, acc: { $0 < 3 ? 0.06 : 0.003 }, tilt: { $0 * 2 })   // 3 active seconds
        #expect(!d.isHeld(at: 12))
        var e = HoldDetector()
        feed(&e, from: 0, to: 12, acc: { $0 < 4.5 ? 0.06 : 0.003 }, tilt: { $0 * 2 })  // 5 active seconds
        #expect(e.isHeld(at: 12))
    }

    @Test func oldSamplesAreForgotten() {
        var d = HoldDetector()
        feed(&d, from: 0, to: 12, acc: { _ in 0.06 }, tilt: { $0 * 2 })
        #expect(d.isHeld(at: 12))
        feed(&d, from: 12.1, to: 30, acc: { _ in 0.003 }, tilt: { _ in 24 })
        #expect(!d.isHeld(at: 30))
    }

    @Test func noSamplesIsNotHeld() {
        #expect(!HoldDetector().isHeld(at: 12))
    }

    @Test func resetForgetsEverything() {
        var d = HoldDetector()
        feed(&d, from: 0, to: 12, acc: { _ in 0.06 }, tilt: { $0 * 2 })
        d.reset()
        #expect(!d.isHeld(at: 12))
    }

    @Test func theSummaryHoldsTheNumbersIsHeldIsDerivedFrom() {
        var d = HoldDetector()
        feed(&d, from: 0, to: 11.9, acc: { $0 < 4.5 ? 0.06 : 0.003 }, tilt: { $0 * 0.5 })
        let s = d.summary(at: 11.9)
        #expect(s.activeSeconds == 5)
        #expect(abs(s.tiltDegrees - 5.95) < 0.01)
        #expect(s.sampleCount == 120)
        #expect(s.isHeld == d.isHeld(at: 11.9))
        #expect(s.text.hasPrefix("active=5/12 tilt=") && s.text.hasSuffix("° samples=120"))
    }

    @Test func theNewestSampleDefinesTheWindowWithoutAnyClock() {
        var d = HoldDetector()
        #expect(d.latestTime == nil && !d.isHeldNow() && d.summaryNow().sampleCount == 0)
        // a time base far away from any "now": the clock-free answer does not care
        feed(&d, from: 90_000, to: 90_012, acc: { _ in 0.06 }, tilt: { ($0 - 90_000) * 0.5 })
        #expect(d.latestTime != nil && abs(d.latestTime! - 90_012) < 0.01)
        #expect(d.isHeldNow())
        #expect(!d.isHeld(at: 12))                      // a mismatching clock would have killed the rule
    }
}
