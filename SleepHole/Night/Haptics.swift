import AudioToolbox
import AVFoundation
import CoreHaptics
import UIKit

/// Vibrations at the key moments of a night (owner 2026-09-30, idea XS).
enum Haptic: Equatable, CaseIterable {
    case start      // "Go to sleep" / "Nap" tapped
    case locked     // phone locked while building – "the building goes on"
    case warning    // setup ends in 15 s while away, or "Come back!" – strongest, three pulses
    case relief     // came back in time after a "Come back!" warning – "phew"
}

/// Core Haptics with strong, long patterns (owner 2026-09-30: the first version – a UIKit impact and the
/// system vibration – was barely noticeable). The engine shares the app's audio session, so with the
/// background audio of a night it can also play while the app is in the background; the system vibration
/// is played as well for `locked` / `warning`, which happen exactly when the app goes to the background.
@MainActor
enum Haptics {
    private static var engine: CHHapticEngine?
    /// What happened with the last vibration (Settings → Developer → Vibration test).
    private(set) static var lastResult = "–"

    static var supportsHaptics: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    static func play(_ h: Haptic) {
        if h == .locked || h == .warning { systemVibration(times: h == .warning ? 2 : 1) }
        do {
            let engine = try runningEngine()
            try engine.makePlayer(with: pattern(h)).start(atTime: CHHapticTimeImmediate)
            lastResult = "Core Haptics ✓ \(h)"
        } catch {
            lastResult = "Core Haptics ✗ \(error.localizedDescription) → fallback"
            fallback(h)
        }
    }

    private static func runningEngine() throws -> CHHapticEngine {
        guard supportsHaptics else { throw HapticsError.unsupported }
        let e = try engine ?? CHHapticEngine(audioSession: AVAudioSession.sharedInstance())
        if engine == nil {
            e.playsHapticsOnly = true
            e.isAutoShutdownEnabled = false
            engine = e
        }
        try e.start()          // cheap when already running; restarts after a reset / a stop in the background
        return e
    }

    enum HapticsError: LocalizedError {
        case unsupported
        var errorDescription: String? { "no Taptic Engine" }
    }

    // MARK: patterns

    static func pattern(_ h: Haptic) throws -> CHHapticPattern {
        func tap(_ t: TimeInterval, _ i: Float = 1, sharp: Float = 0.6) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp)], relativeTime: t)
        }
        func buzz(_ t: TimeInterval, _ d: TimeInterval, _ i: Float = 1, sharp: Float = 0.5) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp)], relativeTime: t, duration: d)
        }
        let events: [CHHapticEvent]
        switch h {
        case .start: events = [tap(0), tap(0.15), buzz(0.3, 0.45, 0.9)]
        case .locked: events = [buzz(0, 0.6, 1, sharp: 0.4)]
        case .warning: events = [buzz(0, 0.45, 1, sharp: 0.8), buzz(0.65, 0.45, 1, sharp: 0.8),
                                 buzz(1.3, 0.45, 1, sharp: 0.8)]
        case .relief: events = [tap(0, sharp: 0.4), tap(0.2, sharp: 0.4), buzz(0.4, 0.3, 0.6, sharp: 0.2)]
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    // MARK: fallbacks

    private static func fallback(_ h: Haptic) {
        switch h {
        case .start, .relief:
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(h == .start ? .warning : .success)
        case .locked, .warning: break                     // the system vibration already played
        }
    }

    /// Works in the background (with the night's audio session); obeys Settings → Sounds & Haptics.
    nonisolated private static func systemVibration(times: Int) {
        guard times > 0 else { return }
        // nonisolated: the completion runs on an audio thread – a main-actor closure would trap there (Swift 6)
        AudioServicesPlaySystemSoundWithCompletion(kSystemSoundID_Vibrate) { systemVibration(times: times - 1) }
    }
}
