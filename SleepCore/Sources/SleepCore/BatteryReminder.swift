import Foundation

/// The phone's charging state, mapped from UIKit's `UIDevice.BatteryState` so the rule stays UIKit-free.
public enum BatteryPlug: String, Sendable, Equatable {
    case unplugged, charging, full, unknown
}

/// The battery reminder at a night's start (13l, owner 2026-11-04): a phone that is not on the charger and has 30 % or
/// less will probably not last until the morning. It is a calm reminder on the night screen during the setup – it never
/// stops, delays or changes the start.
public enum BatteryReminder {
    /// At or below this level (inclusive) the reminder shows.
    public static let threshold = 0.30

    /// `level` is 0…1, or a negative number when iOS does not know it (the simulator gives −1).
    /// Nights only – a nap never reminds.
    public static func shouldRemind(level: Double, plug: BatteryPlug, isNap: Bool) -> Bool {
        guard !isNap, level >= 0, plug == .unplugged else { return false }
        return (level * 100).rounded() <= threshold * 100
    }

    /// The whole percent shown in the text (0.236 → 24).
    public static func percent(_ level: Double) -> Int { Int((max(0, level) * 100).rounded()) }
}
