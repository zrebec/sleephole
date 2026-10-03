import AVFoundation

/// A friendly synthesised voice (owner 2026-10-02): "Good night" when the night starts, "Good morning" when a
/// building is finished. Uses the app's audio session (the night's `.playback` keeps it audible with the screen off).
@MainActor
enum Voice {
    private static let synth = AVSpeechSynthesizer()

    static func say(_ text: String) {
        guard !AudioKeeper.muted else { return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = bestVoice(Lang.current == .sk ? "sk-SK" : "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        u.pitchMultiplier = 1.1
        u.volume = 0.9
        synth.speak(u)
    }

    /// The best installed voice for the language (premium/enhanced if the owner downloaded one in iOS Settings).
    static func bestVoice(_ language: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    /// The sentences, in one place (the sound test in Settings plays them too).
    enum Line: CaseIterable {
        case goodNight, napStart, buildingDone, napDone

        var text: String {
            switch self {
            case .goodNight: L("Good night! Your building starts now. Sweet dreams.")
            case .napStart: L("Time for a little rest. I'll wake you up.")
            case .buildingDone: L("Good morning! Your building is finished. Well done!")
            case .napDone: L("Welcome back! Nicely rested.")
            }
        }
    }
}
