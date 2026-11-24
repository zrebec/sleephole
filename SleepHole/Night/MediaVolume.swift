import AVFoundation
import Foundation

/// The media volume for the whole night / nap (13ac, B53): ONE observer of `AVAudioSession.outputVolume`, alive from the
/// start of the night services until they stop. The model publishes what it reports (`AppModel.mediaVolume`), and the
/// alarm hand-over decides from it whether our own alarm can be heard at all. The watcher only reads – it never
/// activates or configures the audio session (`AudioKeeper` owns it).
///
/// In the simulator (DEBUG) `-fakeVolume V[,S,V2]` replaces the reading: V from the start, V2 after S seconds – and
/// every re-read (`reading()`) returns the fake's CURRENT value, so a flip is never undone by the next re-read.
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
        #if DEBUG && targetEnvironment(simulator)
        Self.fakeCurrent = Self.fake                     // every night starts at the fake's first value
        #endif
        onChange(Self.reading())
        #if DEBUG && targetEnvironment(simulator)
        if let flip = Self.fakeFlip {
            flipTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(flip.after))
                guard !Task.isCancelled else { return }
                Self.fakeCurrent = flip.volume
                self?.onChange?(flip.volume)
            }
            return
        }
        if Self.fake != nil { return }
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
        if let f = fakeCurrent ?? fake { return f }
        #endif
        return Double(AVAudioSession.sharedInstance().outputVolume)
    }

    #if DEBUG && targetEnvironment(simulator)
    /// `-fakeVolume 0.12[,S,0.6]` (simulator and DEBUG only). With S,V the volume becomes V after S seconds. Tests replace
    /// the parts to inject a fake.
    static var fakeParts: [String]? = DevArgs.value(after: "-fakeVolume").map { $0.split(separator: ",").map(String.init) }
    static var fake: Double? { fakeParts?.first.flatMap(Double.init) }
    static var fakeFlip: (after: Double, volume: Double)? {
        guard let p = fakeParts, p.count > 2, let after = Double(p[1]), let v = Double(p[2]) else { return nil }
        return (after, v)
    }
    /// The fake's value right now: the first one at the start, the flipped one after the flip.
    static var fakeCurrent: Double?
    #endif
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
