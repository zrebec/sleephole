import Foundation
import Observation

/// Settings "▶": plays the chosen night sound for exactly the chosen time ("Hrať"), in a seamless loop,
/// also with the screen off (background audio). nil minutes = until ■. Switches live, stops reliably.
@MainActor
@Observable
final class SoundPreview {
    private(set) var playing: AudioKeeper.Ambience?
    private(set) var endsAt: Date?
    @ObservationIgnored private let keeper = AudioKeeper()
    @ObservationIgnored private var endTask: Task<Void, Never>?

    var isRunning: Bool { keeper.isRunning }
    var gain: Float { keeper.currentGain }
    var mode: AudioKeeper.Ambience { keeper.currentMode }

    /// - Parameter seconds: exact playing time; nil = until stopped.
    func play(_ ambience: AudioKeeper.Ambience, volume: Float, seconds: TimeInterval?) {
        stop()
        guard ambience != .silence, (try? keeper.start(ambience: ambience, volume: volume)) != nil else { return }
        keeper.sleepTimer(seconds: seconds, volume: volume)
        playing = ambience
        endsAt = keeper.sleepSoundEndsAt
        if let seconds {
            endTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds + 0.2))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        }
    }

    /// Picker changed: switch the running sound immediately (the timer keeps running).
    func switchTo(_ ambience: AudioKeeper.Ambience, volume: Float) {
        guard playing != nil else { return }
        if ambience == .silence { stop(); return }
        keeper.setVolume(volume, ambience: ambience)
        playing = ambience
    }

    func setVolume(_ volume: Float) {
        guard let playing else { return }
        keeper.setVolume(volume, ambience: playing)
    }

    func stop() {
        endTask?.cancel()
        endTask = nil
        keeper.stop()
        playing = nil
        endsAt = nil
    }
}
