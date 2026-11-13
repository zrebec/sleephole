import Foundation

/// The volume reminder (13r, owner 2026-11-06): the app's own alarm plays through the media volume, which the user may
/// have turned down together with the night sound. An app can read that volume but never set it, so the night screen
/// shows a calm line while it is low. It never blocks, delays or changes a start.
public enum VolumeReminder {
    public enum Level: Sendable, Equatable { case low, off }

    /// At or below this volume (inclusive, whole percent after rounding) the reminder shows. The iPhone moves in steps
    /// of 1/16, so 0.25 is the 4th step.
    public static let threshold = 0.25

    /// `volume` is 0…1; a negative or non-finite value (unknown) gives nothing.
    public static func level(volume: Double) -> Level? {
        guard volume.isFinite, volume >= 0 else { return nil }
        let percent = (min(volume, 1) * 100).rounded()
        if percent == 0 { return .off }
        return percent <= threshold * 100 ? .low : nil
    }

    /// Below this volume (whole percent) our alarm cannot be heard: the first iPhone step (6 %) is quieter than the
    /// alarm's own start gain allows (13ag, owner 2026-11-12).
    public static let alarmInaudibleBelow = 0.10

    /// Whether our own alarm, played through the media volume, can be heard (13ag, owner 2026-11-12). Unknown (negative
    /// or non-finite) counts as audible; otherwise the whole percent (rounded like `level(volume:)`) must reach 10.
    public static func alarmAudible(volume: Double) -> Bool {
        guard volume.isFinite, volume >= 0 else { return true }
        let percent = (min(volume, 1) * 100).rounded()
        return percent >= alarmInaudibleBelow * 100
    }
}
