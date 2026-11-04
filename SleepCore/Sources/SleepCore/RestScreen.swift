import Foundation

/// The rest screen (build 13k, owner 2026-11-04): after the setup, with the app in front and nobody touching it, the
/// night screen turns black (a dim clock and one line) so a phone whose Auto-Lock is "Never" does not burn its display
/// all night. It is only a look – it never changes what a night counts. The app feeds the facts in; this decides.
public enum RestScreen {
    /// Seconds without a touch before the screen rests.
    public static let defaultDelay: TimeInterval = 30

    /// What the app knows about the moment.
    public struct Facts: Equatable, Sendable {
        /// The night phase is on (not idle, the alarm or the result).
        public var isBuilding: Bool
        /// The active record is a nap.
        public var isNap: Bool
        /// The end of the setup of the active night; nil = unknown (no night).
        public var setupEnds: Date?
        public var pauseRunning: Bool
        public var sceneActive: Bool
        public var voiceOverRunning: Bool
        /// A sheet, dialog or alert is open, or the wake-code field has the keyboard.
        public var presentationOpen: Bool

        public init(isBuilding: Bool, isNap: Bool, setupEnds: Date?, pauseRunning: Bool, sceneActive: Bool,
                    voiceOverRunning: Bool, presentationOpen: Bool) {
            self.isBuilding = isBuilding; self.isNap = isNap; self.setupEnds = setupEnds
            self.pauseRunning = pauseRunning; self.sceneActive = sceneActive
            self.voiceOverRunning = voiceOverRunning; self.presentationOpen = presentationOpen
        }
    }

    /// Everything but the waiting: the screen may rest (or keep resting) at `now`.
    public static func mayRest(_ f: Facts, now: Date) -> Bool {
        guard f.isBuilding, !f.isNap, f.sceneActive, !f.pauseRunning, !f.voiceOverRunning, !f.presentationOpen,
              let setupEnds = f.setupEnds, now >= setupEnds else { return false }
        return true
    }

    /// The screen starts to rest: `mayRest` and `delay` seconds have passed since the latest of the last touch, the scene
    /// becoming active, the night screen appearing and (here) the end of the setup.
    public static func shouldRest(_ f: Facts, now: Date, lastActivity: Date, delay: TimeInterval = defaultDelay) -> Bool {
        guard mayRest(f, now: now), let setupEnds = f.setupEnds else { return false }
        return now.timeIntervalSince(max(lastActivity, setupEnds)) >= delay
    }

    /// OLED burn-in guard: where the clock sits, a deterministic jump within ±`range` points of the centre, picked
    /// from the minute of the epoch (a different place every minute, the same one for the same minute).
    public static func offset(minute: Int, range: Double = 16) -> (x: Double, y: Double) {
        func unit(_ seed: UInt64) -> Double {                       // splitmix64 → 0…1
            var z = seed &+ 0x9E37_79B9_7F4A_7C15
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z % 10_001) / 10_000
        }
        let m = UInt64(bitPattern: Int64(minute))
        return ((unit(m) * 2 - 1) * range, (unit(m &+ 7_919) * 2 - 1) * range)
    }
}
