import AVFoundation
import Observation
import UIKit
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

    /// 13z: what the progress line under "Try the rise" shows. Nil = no rise preview is running.
    @MainActor @Observable
    final class RiseState {
        let began: Date
        let rise: Double
        let start: Double
        let end: Double
        let total: Double
        init(began: Date, rise: Double, start: Double, end: Double, total: Double) {
            (self.began, self.rise, self.start, self.end, self.total) = (began, rise, start, end, total)
        }
        func elapsed(at now: Date = Date()) -> Double { max(0, now.timeIntervalSince(began)) }
        func percent(at now: Date = Date()) -> Int {
            AlarmVolume.percent(elapsed: elapsed(at: now), start: start, end: end, rise: rise)
        }
        /// 0…1 of the rise (1 for an instant alarm).
        func fraction(at now: Date = Date()) -> Double { rise > 0 ? min(1, elapsed(at: now) / rise) : 1 }
    }

    /// The running rise preview (observed by Settings); nil when none.
    static var riseState: RiseState? { riseHolder.state }
    @MainActor @Observable final class RiseHolder { var state: RiseState? }
    static let riseHolder = RiseHolder()
    private static var savedIdleTimer: Bool?

    /// 13v "Try the rise": the melody (looped) from `start` to `end` over `rise` seconds (0 = `end` at once), then
    /// 3 s at `end` (8 s when there is no rise), then it stops. Levels are 0...1 shares of the media volume.
    /// 13z: the screen stays awake meanwhile, and a player that stopped by itself (B47) is started again.
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
        let began = Date()
        let state = RiseState(began: began, rise: rise, start: start, end: end, total: total)
        riseHolder.state = state
        if savedIdleTimer == nil { savedIdleTimer = UIApplication.shared.isIdleTimerDisabled }
        UIApplication.shared.isIdleTimerDisabled = true
        previewStop = Task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(began)
                if elapsed >= total { break }
                if !p.isPlaying {                       // B47: it stopped by itself – start the melody again
                    let s = AVAudioSession.sharedInstance()
                    if s.category != .playback { try? s.setCategory(.playback) }
                    try? s.setActive(true)
                    p.currentTime = 0
                    p.play()
                }
                p.volume = gain(elapsed)
                try? await Task.sleep(for: .milliseconds(250))
            }
            if !Task.isCancelled { stopPreview() }
        }
    }

    /// Test hook: whether the preview's player is playing right now.
    static var isPreviewPlaying: Bool { preview?.isPlaying ?? false }

    static func stopPreview() {
        previewStop?.cancel()
        let wasPlaying = preview != nil
        preview?.stop()
        preview = nil
        if wasPlaying { restoreAmbientSession() }
        riseHolder.state = nil
        if let saved = savedIdleTimer {
            UIApplication.shared.isIdleTimerDisabled = saved
            savedIdleTimer = nil
        }
    }

    /// A Settings preview made the session `.playback`; when it ends and no keeper runs it goes back to `.ambient`
    /// (13ac, B59), so that effects follow the silent switch again and other apps' music may resume.
    private static func restoreAmbientSession() {
        guard AudioKeeper.runningKeepers == 0 else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.ambient)
    }

    /// Test hook: the idle timer is restored after the preview.
    static var idleTimerSaved: Bool { savedIdleTimer != nil }

    static func play(_ name: String, volume: Float = 0.8) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        let session = AVAudioSession.sharedInstance()
        // never downgrade the night's .playback session (it keeps the app alive in the background) – but with no
        // keeper running an effect follows the silent switch and mixes with other apps' music (13ac, B59). It is the
        // keepers, not the current category, that decide: an alarm used to leave the category at .playback for good.
        if AudioKeeper.runningKeepers == 0, preview == nil {
            try? session.setCategory(.ambient)
            try? session.setActive(true)
        }
        p.volume = AudioKeeper.muted ? 0 : volume
        p.play()
        players.removeAll { !$0.isPlaying }
        players.append(p)
    }
}
