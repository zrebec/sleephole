import AVFoundation
import Foundation

/// Keeps the app alive overnight with background audio (UIBackgroundModes = audio) and, later, rings the
/// alarm. Category `.playback` ignores the silent switch. Plan §6.3.
@MainActor
final class AudioKeeper {
    enum Ambience: String, Codable, CaseIterable, Identifiable {
        case brownNoise = "Hnedý šum"
        case silence = "Ticho"
        var id: String { rawValue }
    }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let noise = NoiseState()
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning = false
    var onInterruption: ((String) -> Void)?
    private let alarmPlayer = AVAudioPlayerNode()
    private var alarmTask: Task<Void, Never>?
    private(set) var isAlarmRinging = false
    /// Unit tests: route everything through a silent mixer (nothing audible on the Mac).
    static var muted = false

    func start(ambience: Ambience, volume: Float) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        // .mixWithOthers: a podcast / bedtime story started in another app must NOT interrupt us –
        // otherwise our audio stops and iOS suspends the app after the lock (no detection, no alarm).
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        noise.gain = ambience == .silence ? 0 : volume
        let format = engine.outputNode.inputFormat(forBus: 0)
        let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        let node = Self.makeNoiseNode(format: mono, state: noise)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = Self.muted ? 0 : 1
        try engine.start()
        source = node
        isRunning = true

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                        queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated {
                self?.onInterruption?(began ? "audio interruption began" : "audio interruption ended")
                if !began { try? self?.engine.start() }          // resume after a call
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil,
                                        queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onInterruption?("media services reset")
                if let self, self.isRunning { try? self.start(ambience: ambience, volume: volume) }
            }
        })
    }

    /// Must be `nonisolated`: a closure created inside this @MainActor class would inherit MainActor
    /// isolation and Swift 6 inserts a runtime check → crash on the real-time audio thread
    /// (`_dispatch_assert_queue_fail` on AURemoteIO::IOThread, seen on the device 2026-09-29).
    nonisolated private static func makeNoiseNode(format: AVAudioFormat, state: NoiseState) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, bufferList -> OSStatus in
            state.render(frameCount: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
    }

    /// Rings `file` in a loop, volume ramping 0.3 → 1.0 over `ramp` s (0 = full volume at once), for at
    /// most `maxDuration` (D15: 2 min). The ambience is muted meanwhile. `onStop` fires when it stops on its own.
    func ringAlarm(file: String, ramp: TimeInterval, maxDuration: TimeInterval,
                   onStop: @escaping @MainActor () -> Void) {
        guard !isAlarmRinging, let url = Bundle.main.url(forResource: file, withExtension: nil),
              let audioFile = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat,
                                            frameCapacity: AVAudioFrameCount(audioFile.length)) else { return }
        try? audioFile.read(into: buffer)
        if !isRunning { try? start(ambience: .silence, volume: 0) }
        // the alarm must win: switch to a non-mixable session (interrupts a podcast still playing)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        noise.gain = 0
        if alarmPlayer.engine == nil {
            engine.attach(alarmPlayer)
        }
        engine.connect(alarmPlayer, to: engine.mainMixerNode, format: buffer.format)
        if !engine.isRunning { try? engine.start() }
        alarmPlayer.volume = ramp > 0 ? 0.3 : 1
        alarmPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        alarmPlayer.play()
        isAlarmRinging = true
        alarmTask = Task { [weak self] in
            let started = Date()
            while let self, !Task.isCancelled, Date().timeIntervalSince(started) < maxDuration {
                if ramp > 0 {
                    self.alarmPlayer.volume = min(1, 0.3 + Float(Date().timeIntervalSince(started) / ramp) * 0.7)
                }
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled else { return }
            self.stopAlarm()
            onStop()
        }
    }

    func stopAlarm() {
        alarmTask?.cancel()
        alarmTask = nil
        if isAlarmRinging { alarmPlayer.stop() }
        isAlarmRinging = false
    }

    func setVolume(_ volume: Float, ambience: Ambience) {
        noise.gain = ambience == .silence ? 0 : volume
    }

    func stop() {
        stopAlarm()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Brown-noise generator shared with the real-time audio thread.
private final class NoiseState: @unchecked Sendable {
    var gain: Float = 0.1
    private var last: Float = 0
    private var seed: UInt32 = 22222

    func render(frameCount: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let g = gain
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for i in 0..<frameCount {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let white = Float(seed >> 9) / Float(1 << 23) * 2 - 1
                last = (last + 0.02 * white) / 1.02                 // integrate → brown noise
                data[i] = last * 3.5 * g
            }
        }
    }
}
