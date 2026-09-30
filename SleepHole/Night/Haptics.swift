import AudioToolbox
import UIKit

/// Short vibrations at the key moments of a night (owner 2026-09-30, idea XS).
enum Haptic: Equatable {
    case start      // "Go to sleep" / "Nap" tapped – gentle
    case locked     // phone locked while building – "the building goes on"
    case warning    // setup ends in 15 s while away, or "Come back!" – strong, twice
    case relief     // came back in time after a "Come back!" warning – gentle "phew"
}

@MainActor
enum Haptics {
    static func play(_ h: Haptic) {
        switch h {
        case .start: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .relief: UINotificationFeedbackGenerator().notificationOccurred(.success)
        // lock / leaving happen while the app goes to the background, where UIKit feedback generators
        // are silent – the system vibration works thanks to the background audio session
        case .locked: AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        case .warning: vibrateTwice()
        }
    }

    /// nonisolated: the completion runs on an audio thread – a main-actor closure would trap there (Swift 6).
    nonisolated private static func vibrateTwice() {
        AudioServicesPlaySystemSoundWithCompletion(kSystemSoundID_Vibrate) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}
