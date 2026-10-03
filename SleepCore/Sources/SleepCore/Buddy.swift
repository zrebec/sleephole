import Foundation

/// What the sleep buddy (the cat on the bed) is doing: it looks at the owner, or it sleeps.
public enum BuddyState: Equatable, Sendable {
    case awake
    case asleep
}

/// The rule behind the sleep buddy (owner 2026-10-03, plan P2: "it reacts to me"). Pure – the UI only draws it.
///
/// * Nothing is running (Today): always awake.
/// * During a night or a nap it is awake only while the owner is likely to be looking at the phone: during the
///   setup, during a pause and from the wake time on (the alarm screen included).
/// * Otherwise it sleeps – also in the early-confirm window before the wake time, and after a collapse
///   (the cat never judges, so a collapsed night still shows it asleep).
public enum Buddy {
    /// - Parameters:
    ///   - now: the moment to decide for.
    ///   - running: a night or a nap has been started and is not finished yet.
    ///   - setupEnds: the end of the setup time (nil = unknown / none).
    ///   - pauseEnds: the end of the pause that is on at `now` (nil = no pause is on).
    ///   - wake: the night's wake time (nil = unknown).
    public static func state(at now: Date, running: Bool, setupEnds: Date? = nil, pauseEnds: Date? = nil,
                             wake: Date? = nil) -> BuddyState {
        guard running else { return .awake }
        if let setupEnds, now < setupEnds { return .awake }
        if let pauseEnds, now < pauseEnds { return .awake }
        if let wake, now >= wake { return .awake }
        return .asleep
    }
}
