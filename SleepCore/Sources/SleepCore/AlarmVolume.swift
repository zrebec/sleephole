import Foundation

/// 13v: the in-app alarm's volume curve. All levels are shares (0…1) of the phone's media volume – an app may
/// never set the system volume, so this is only the player's own gain.
public enum AlarmVolume {
    /// The levels the user can pick, in percent (10…100, steps of 10).
    public static let percentOptions = Array(stride(from: 10, through: 100, by: 10))
    /// The explicit rise times the user can pick, in seconds (0 = at once). "By the melody" is nil.
    public static let riseOptions = [0, 15, 30, 45, 60, 90]
    public static let defaultStartPercent = 30
    public static let defaultEndPercent = 100

    /// Nearest allowed percent (ties go up), clamped to 10…100.
    public static func snapPercent(_ p: Int) -> Int {
        let clamped = min(100, max(10, p))
        return ((clamped + 5) / 10) * 10
    }

    /// The volume `elapsed` seconds after the alarm started: linear from `start` to `end` over `rise` seconds, then
    /// `end`. `rise <= 0` = `end` at once. Inputs are clamped to 0…1; a start above the end is lowered to the end.
    public static func level(elapsed: TimeInterval, start: Double, end: Double, rise: TimeInterval) -> Double {
        let hi = min(1, max(0, end))
        let lo = min(hi, min(1, max(0, start)))
        guard rise > 0 else { return hi }
        let t = min(1, max(0, elapsed / rise))
        return lo + (hi - lo) * t
    }

    /// The start level to give the player at once: the end level for an instant alarm, else the start level.
    public static func initialLevel(start: Double, end: Double, rise: TimeInterval) -> Double {
        level(elapsed: 0, start: start, end: end, rise: rise)
    }
}
