import CoreMotion
import Foundation
import SleepCore

/// "Is the phone held in a hand?" – the seam `LifecycleMonitor` asks while a lit lock screen may be in use without
/// Face ID having recognised anyone (owner 2026-10-09). Replaceable in tests. Started only while it is needed.
@MainActor
protocol HandMotion: AnyObject {
    func start()
    func stop()
    func isHeld() -> Bool
    /// The numbers behind `isHeld()` for the log ("" when there is nothing to say).
    func describe() -> String
}

extension HandMotion {
    func describe() -> String { "" }
}

/// CoreMotion device motion at 10 Hz feeding `HoldDetector` (the rule and its measured numbers live there).
/// Raw device motion needs no permission and no Info.plist key. Without the sensor the phone is never held.
@MainActor
final class CoreMotionHold: HandMotion {
    private var manager: CMMotionManager?
    private var detector = HoldDetector()
    /// When the last sample ARRIVED – no clock of the sensor is compared with ours.
    private var lastArrival: Date?
    private static let staleAfter: TimeInterval = 1.5

    func start() {
        guard manager == nil else { return }
        let m = CMMotionManager()
        guard m.isDeviceMotionAvailable else { return }
        manager = m
        detector.reset()
        lastArrival = nil
        m.deviceMotionUpdateInterval = 0.1
        m.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let u = motion.userAcceleration, g = motion.gravity
            let sample = HoldDetector.Sample(time: motion.timestamp,
                                             acceleration: (u.x * u.x + u.y * u.y + u.z * u.z).squareRoot(),
                                             gx: g.x, gy: g.y, gz: g.z)
            MainActor.assumeIsolated { self?.detector.add(sample); self?.lastArrival = Date() }
        }
    }

    func stop() {
        manager?.stopDeviceMotionUpdates()
        manager = nil
        detector.reset()
        lastArrival = nil
    }

    /// The window ends at the newest sample; data that stopped arriving more than 1.5 s ago answers false.
    private var isFresh: Bool {
        manager != nil && lastArrival.map { Date().timeIntervalSince($0) <= Self.staleAfter } == true
    }

    func isHeld() -> Bool { isFresh && detector.isHeldNow() }

    func describe() -> String {
        manager == nil ? "no sensor" : (isFresh ? "" : "stale ") + detector.summaryNow().text
    }
}
