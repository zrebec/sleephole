import CoreHaptics
import UIKit

/// Vibrations of a night (owner 2026-09-30, idea XS). Only while SleepHole is on screen: iOS does not let apps
/// vibrate in the background (owner test 2026-09-30). In the background the notifications ("⏳ 15 s of setup
/// left", "⚠️ Come back!") vibrate the phone through their sound.
enum Haptic: Equatable, CaseIterable {
    case start      // "Go to sleep" / "Nap" tapped
    case relief     // came back in time after a "Come back!" warning – "phew"
    case purr       // petting the cat on Today (plan P2b): a soft rumble with gentle pulses, ~1.2 s
    case pet        // petting the cat: one light tap (arched back, wink)
}

/// Core Haptics with strong, long patterns (the first version – an unprepared UIKit impact – was barely noticeable).
@MainActor
enum Haptics {
    private static var engine: CHHapticEngine?
    /// What happened with the last vibration (Settings → Developer → Vibration test).
    private(set) static var lastResult = "–"

    static var supportsHaptics: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    static func play(_ h: Haptic) {
        do {
            let engine = try runningEngine()
            try engine.makePlayer(with: pattern(h)).start(atTime: CHHapticTimeImmediate)
            lastResult = "Core Haptics ✓ \(h)"
        } catch {
            lastResult = "Core Haptics ✗ \(error.localizedDescription) → UIKit"
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(h == .start ? .warning : .success)       // .pet / .purr too: a soft "success"
        }
    }

    private static func runningEngine() throws -> CHHapticEngine {
        guard supportsHaptics else { throw HapticsError.unsupported }
        let e = try engine ?? CHHapticEngine()
        if engine == nil {
            e.playsHapticsOnly = true          // never touch the audio session the night's sound lives in
            e.isAutoShutdownEnabled = true
            engine = e
        }
        try e.start()          // cheap when already running; restarts after a reset or a stop
        return e
    }

    enum HapticsError: LocalizedError {
        case unsupported
        var errorDescription: String? { "no Taptic Engine" }
    }

    static func pattern(_ h: Haptic) throws -> CHHapticPattern {
        func tap(_ t: TimeInterval, sharp: Float = 0.6) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp)], relativeTime: t)
        }
        func buzz(_ t: TimeInterval, _ d: TimeInterval, _ i: Float, sharp: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp)], relativeTime: t, duration: d)
        }
        /// A light, round transient (petting).
        func soft(_ t: TimeInterval, _ i: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)], relativeTime: t)
        }
        let events: [CHHapticEvent] = switch h {
        case .start: [tap(0), tap(0.15), buzz(0.3, 0.45, 0.9, sharp: 0.5)]
        case .relief: [tap(0, sharp: 0.4), tap(0.2, sharp: 0.4), buzz(0.4, 0.3, 0.6, sharp: 0.2)]
        case .purr:
            // a continuous low rumble, with a few gentle pulses on top so it feels like purring
            [buzz(0, 1.2, 0.45, sharp: 0.1)]
                + [0.1, 0.35, 0.6, 0.85, 1.1].map { soft($0, 0.3) }
        case .pet: [soft(0, 0.6)]
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}
