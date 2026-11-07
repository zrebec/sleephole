import AVFoundation
import SleepCore

/// Short one-shot sounds (result, UI). Plays through the current session.
@MainActor
enum SoundFX {
    private static var players: [AVAudioPlayer] = []

    private static var preview: AVAudioPlayer?
    private static var previewStop: Task<Void, Never>?

    /// Alarm preview in Settings: audible even with the silent switch on, stops after `seconds`.
    /// 13v: it plays at `level` (the "Rise to" share of the media volume, 1 = full).
    static func previewAlarm(_ name: String, seconds: Double = 8, level: Float = 1) {
        stopPreview()
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback { try? session.setCategory(.playback) }
        try? session.setActive(true)
        p.volume = AudioKeeper.muted ? 0 : level
        p.play()
        preview = p
        previewStop = Task { try? await Task.sleep(for: .seconds(seconds)); stopPreview() }
    }

    /// 13v "Try the rise": the melody (looped) from `start` to `end` over `rise` seconds (0 = `end` at once), then
    /// 3 s at `end` (8 s when there is no rise), then it stops. Levels are 0…1 shares of the media volume.
    static func previewAlarmRise(_ name: String, start: Double, end: Double, rise: Double) {
        stopPreview()
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback { try? session.setCategory(.playback) }
        try? session.setActive(true)
        p.numberOfLoops = -1
        let gain: (Double) -> Float = { AudioKeeper.muted ? 0 : Float(AlarmVolume.level(elapsed: $0, start: start, end: end, rise: rise)) }
        p.volume = gain(0)
        p.play()
        preview = p
        let total = rise > 0 ? rise + 3 : 8
        previewStop = Task {
            let began = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(began)
                if elapsed >= total { break }
                p.volume = gain(elapsed)
                try? await Task.sleep(for: .milliseconds(250))
            }
            if !Task.isCancelled { stopPreview() }
        }
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
