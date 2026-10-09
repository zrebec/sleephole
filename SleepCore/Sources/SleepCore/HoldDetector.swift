import Foundation

/// Tells whether the phone is HELD IN THE HAND, from device-motion samples (owner 2026-10-09: a lit lock screen used
/// without Face ID – filming with the lock-screen camera – counts as leaving the app, but only in a hand; a phone that
/// lies or stands still never does, whatever lights its screen).
///
/// Measured on a real phone (lock-screen lab), per-second peak of `userAcceleration` and the `gravity` vector:
///  * resting on a table, also while its screen lights up: 0–1 of 12 seconds above 0.02 g (median 0.003 g, one tap on
///    the screen = a single second of ~0.05 g); the gravity direction drifts 0.0°;
///  * held in the hand (filming, or holding still to tap a share sheet): 11–12 of 12 seconds above 0.02 g; the gravity
///    direction drifts ≥ 6.4° within 12 s (usually 15–85°).
/// Held = at least `minActiveSeconds` of the window's seconds have a peak above `accelerationThreshold` AND the gravity
/// direction moved by at least `minTiltDegrees` within the window. Both conditions: a phone that only vibrates in place
/// (acceleration, no change of direction) is not held, and neither is one that drifts slowly without any acceleration.
public struct HoldDetector: Sendable {
    public static let window: TimeInterval = 12
    public static let accelerationThreshold = 0.02      // g, per-second peak
    public static let minActiveSeconds = 4
    public static let minTiltDegrees = 3.0

    public struct Sample: Sendable, Equatable {
        public let time: TimeInterval                   // any monotonic clock, seconds
        public let acceleration: Double                 // |userAcceleration| in g
        public let gx: Double, gy: Double, gz: Double   // gravity vector
        public init(time: TimeInterval, acceleration: Double, gx: Double, gy: Double, gz: Double) {
            self.time = time; self.acceleration = acceleration; self.gx = gx; self.gy = gy; self.gz = gz
        }
    }

    private var samples: [Sample] = []

    public init() {}

    public mutating func add(_ s: Sample) {
        samples.append(s)
        let cutoff = s.time - Self.window
        if let first = samples.firstIndex(where: { $0.time >= cutoff }), first > 0 { samples.removeFirst(first) }
    }

    public mutating func reset() { samples.removeAll() }

    /// What the window looks like – the numbers `isHeld` is derived from (shown in the lock-screen lab's log).
    public struct Summary: Sendable, Equatable {
        public let activeSeconds: Int       // one-second buckets whose peak acceleration is above the threshold
        public let tiltDegrees: Double      // the largest angle between two gravity vectors of the window
        public let sampleCount: Int
        public var isHeld: Bool {
            activeSeconds >= HoldDetector.minActiveSeconds && tiltDegrees >= HoldDetector.minTiltDegrees
        }
        public var text: String {
            "active=\(activeSeconds)/\(Int(HoldDetector.window)) tilt=\(String(format: "%.1f", tiltDegrees))° samples=\(sampleCount)"
        }
    }

    /// The time of the newest sample (nil when there is none): lets a caller ask without comparing clocks.
    public var latestTime: TimeInterval? { samples.last?.time }

    /// The last `window` seconds up to `now`. Samples older than the window are ignored.
    public func summary(at now: TimeInterval) -> Summary {
        let w = samples.filter { $0.time > now - Self.window && $0.time <= now }
        var peaks: [Int: Double] = [:]          // per-second peaks, buckets counted from the start of the window
        for s in w { let k = Int(s.time - (now - Self.window)); peaks[k] = max(peaks[k] ?? 0, s.acceleration) }
        var maxAngle = 0.0
        for i in 0..<w.count { for j in (i + 1)..<w.count { maxAngle = max(maxAngle, Self.angle(w[i], w[j])) } }
        return Summary(activeSeconds: peaks.values.filter { $0 > Self.accelerationThreshold }.count,
                       tiltDegrees: maxAngle, sampleCount: w.count)
    }

    /// The window that ends at the newest sample (clock-free).
    public func summaryNow() -> Summary {
        guard let t = latestTime else { return Summary(activeSeconds: 0, tiltDegrees: 0, sampleCount: 0) }
        return summary(at: t)
    }

    /// Held during the last `window` seconds up to `now`.
    public func isHeld(at now: TimeInterval) -> Bool { summary(at: now).isHeld }

    /// Held during the last `window` seconds up to the newest sample.
    public func isHeldNow() -> Bool { summaryNow().isHeld }

    static func angle(_ a: Sample, _ b: Sample) -> Double {
        let na = (a.gx * a.gx + a.gy * a.gy + a.gz * a.gz).squareRoot()
        let nb = (b.gx * b.gx + b.gy * b.gy + b.gz * b.gz).squareRoot()
        guard na > 0, nb > 0 else { return 0 }
        let c = max(-1, min(1, (a.gx * b.gx + a.gy * b.gy + a.gz * b.gz) / (na * nb)))
        return acos(c) * 180 / .pi
    }
}
