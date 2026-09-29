import AVFoundation

/// Short one-shot sounds (result, UI). Plays through the current session.
@MainActor
enum SoundFX {
    private static var players: [AVAudioPlayer] = []

    private static var preview: AVAudioPlayer?
    private static var previewStop: Task<Void, Never>?

    /// Alarm preview in Settings: audible even with the silent switch on, stops after `seconds`.
    static func previewAlarm(_ name: String, seconds: Double = 8) {
        stopPreview()
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback { try? session.setCategory(.playback) }
        try? session.setActive(true)
        if AudioKeeper.muted { p.volume = 0 }
        p.play()
        preview = p
        previewStop = Task { try? await Task.sleep(for: .seconds(seconds)); stopPreview() }
    }

    static func stopPreview() {
        previewStop?.cancel()
        preview?.stop()
        preview = nil
    }

    static func play(_ name: String, volume: Float = 0.8) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        let session = AVAudioSession.sharedInstance()
        // never downgrade the night's .playback session (it keeps the app alive in the background)
        if session.category != .playback {
            try? session.setCategory(.ambient)
            try? session.setActive(true)
        }
        p.volume = AudioKeeper.muted ? 0 : volume
        p.play()
        players.removeAll { !$0.isPlaying }
        players.append(p)
    }
}
