import AVFoundation
import Foundation

/// The media volume for the whole night / nap (13ac, B53): ONE observer of `AVAudioSession.outputVolume`, alive from the
/// start of the night services until they stop. The model publishes what it reports (`AppModel.mediaVolume`), and the
/// alarm hand-over decides from it whether our own alarm can be heard at all. The watcher only reads – it never
/// activates or configures the audio session (`AudioKeeper` owns it).
///
/// In the simulator (DEBUG) `-fakeVolume V[,S,V2]` replaces the reading: V from the start, V2 after S seconds.
@MainActor
final class MediaVolumeWatcher {
    private var observation: NSKeyValueObservation?
    private var flipTask: Task<Void, Never>?
    private var onChange: ((Double) -> Void)?

    var isRunning: Bool { onChange != nil }

    /// Reads the volume now (reported at once) and then on every change until `stop()`.
    func start(onChange: @escaping (Double) -> Void) {
        stop()
        self.onChange = onChange
        onChange(Self.reading())
        #if DEBUG && targetEnvironment(simulator)
        if let flip = VolumeNote.fakeFlip {
            flipTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(flip.after))
                guard !Task.isCancelled else { return }
                self?.onChange?(flip.volume)
            }
            return
        }
        if VolumeNote.fake != nil { return }
        #endif
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            Task { @MainActor in self?.onChange?(Double(v)) }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        flipTask?.cancel()
        flipTask = nil
        onChange = nil
    }

    static func reading() -> Double {
        #if DEBUG && targetEnvironment(simulator)
        if let f = VolumeNote.fake { return f }
        #endif
        return Double(AVAudioSession.sharedInstance().outputVolume)
    }
}

/// A burst of changes of one value becomes ONE diagnostic line after `quiet` seconds without a change, carrying the
/// value before the burst (`was`) and the last one. `flush()` writes a waiting line at once (the end of the night).
@MainActor
final class QuietNote {
    var quiet: TimeInterval
    private var was: Int?
    private var last = 0
    private var task: Task<Void, Never>?
    private let emit: @MainActor (_ now: Int, _ was: Int) -> Void

    init(quiet: TimeInterval = 2, emit: @escaping @MainActor (_ now: Int, _ was: Int) -> Void) {
        self.quiet = quiet
        self.emit = emit
    }

    func change(from old: Int, to new: Int) {
        if was == nil { was = old }
        last = new
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.quiet ?? 2))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        task?.cancel()
        task = nil
        guard let w = was else { return }
        was = nil
        if w != last { emit(last, w) }
    }
}
