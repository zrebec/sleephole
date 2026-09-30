import AVFoundation
import Foundation

/// Keeps the app alive overnight with background audio (UIBackgroundModes = audio) and, later, rings the
/// alarm. Category `.playback` ignores the silent switch. Plan §6.3.
@MainActor
final class AudioKeeper {
    /// Night sound. Raw values are stable ids (not UI text – ready for an EN version); old saved Slovak
    /// values ("Hnedý šum", "Ticho") are still understood.
    enum Ambience: String, Codable, CaseIterable, Identifiable {
        case brownNoise = "brown"
        case pinkNoise = "pink"
        case whiteNoise = "white"
        case rainTent = "rain"            // id kept from the first (synthesised) rain → old settings still load
        case rainWindow = "rain-window"
        case silence = "silence"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .brownNoise: "Hnedý šum"
            case .pinkNoise: "Ružový šum"
            case .whiteNoise: "Biely šum"
            case .rainTent: "Dážď na stan"
            case .rainWindow: "Dážď na okno"
            case .silence: "Ticho"
            }
        }

        /// Recorded / pre-synthesised loops (assets/audio); nil = generated live.
        var loopFile: String? {
            switch self {
            case .rainTent: "rain_tent.caf"
            case .rainWindow: "rain_window.caf"
            default: nil
            }
        }

        var detail: String {
            switch self {
            case .brownNoise: "Hlboký, tlmený – ako vzdialený vodopád."
            case .pinkNoise: "Vyvážený, mäkký – ako vietor v lese."
            case .whiteNoise: "Jasný, rovnomerný – ako ventilátor."
            case .rainTent: "Ťukanie kvapiek na plachtu stanu, občas väčšia kvapka zo stromu."
            case .rainWindow: "Tlmený dážď za oknom (nahrávka InspectorJ, CC BY 4.0)."
            case .silence: "Nič nehrá (appka aj tak zostane v noci bdieť)."
            }
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            case "Hnedý šum": self = .brownNoise
            case "Ticho": self = .silence
            default: self = Ambience(rawValue: raw) ?? .brownNoise
            }
        }
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
    private let loopPlayer = AVAudioPlayerNode()
    private var loopFile: String?
    private static var loopBuffers: [String: AVAudioPCMBuffer] = [:]
    /// Current sleep-sound level (applies to the generator OR the loop player).
    private var level: Float = 0
    /// Unit tests: route everything through a silent mixer (nothing audible on the Mac).
    static var muted = false

    func start(ambience: Ambience, volume: Float) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        // .mixWithOthers: a podcast / bedtime story started in another app must NOT interrupt us –
        // otherwise our audio stops and iOS suspends the app after the lock (no detection, no alarm).
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        noise.mode = ambience
        let format = engine.outputNode.inputFormat(forBus: 0)
        let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        let node = Self.makeNoiseNode(format: mono, state: noise)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = Self.muted ? 0 : 1
        engine.attach(loopPlayer)
        try engine.start()
        source = node
        isRunning = true
        applyMode(ambience)
        setLevel(ambience == .silence ? 0 : volume)

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
        setLevel(0)
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
        noise.mode = ambience
        applyMode(ambience)
        setLevel(ambience == .silence ? 0 : volume)
    }

    /// Generator modes play through the source node, loop modes through `loopPlayer` (seamless .loops).
    private func applyMode(_ ambience: Ambience) {
        guard isRunning else { return }
        guard let file = ambience.loopFile else {
            if loopFile != nil { loopPlayer.stop(); loopFile = nil }
            return
        }
        guard file != loopFile, let buffer = Self.loopBuffer(file) else { return }
        loopPlayer.stop()
        engine.disconnectNodeOutput(loopPlayer)
        engine.connect(loopPlayer, to: engine.mainMixerNode, format: buffer.format)
        loopPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        loopPlayer.play()
        loopFile = file
    }

    private static func loopBuffer(_ file: String) -> AVAudioPCMBuffer? {
        if let b = loopBuffers[file] { return b }
        guard let url = Bundle.main.url(forResource: file, withExtension: nil),
              let f = try? AVAudioFile(forReading: url),
              let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: b)) != nil else { return nil }
        loopBuffers[file] = b
        return b
    }

    private func setLevel(_ g: Float) {
        level = g
        let isLoop = noise.mode.loopFile != nil
        noise.gain = isLoop ? 0 : g
        loopPlayer.volume = isLoop ? g : 0
    }

    private var fadeTask: Task<Void, Never>?
    /// When the current sleep sound goes silent (nil = plays until stopped).
    private(set) var sleepSoundEndsAt: Date?
    static let fadeSeconds: TimeInterval = 5

    /// Plays the current ambience at `volume` for EXACTLY `seconds` (nil = until stopped): the last 5 s fade out
    /// and the sound is silent precisely at the end. The engine keeps running in silence afterwards – it keeps
    /// the app alive (night detection, alarm, background playback with the screen off).
    func sleepTimer(seconds: TimeInterval?, volume: Float) {
        fadeTask?.cancel()
        setLevel(noise.mode == .silence ? 0 : volume)
        guard let seconds else { sleepSoundEndsAt = nil; return }
        let end = Date() + max(0, seconds)
        sleepSoundEndsAt = end
        fadeTask = Task { [weak self] in
            let fadeStart = end - Self.fadeSeconds
            if fadeStart > Date() { try? await Task.sleep(for: .seconds(fadeStart.timeIntervalSinceNow)) }
            while let self, !Task.isCancelled {
                let left = end.timeIntervalSinceNow
                if left <= 0 { self.setLevel(0); return }
                self.setLevel(volume * Float(min(1, left / Self.fadeSeconds)))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Stops the sleep sound immediately (engine keeps running in silence).
    func silenceNow() {
        fadeTask?.cancel()
        setLevel(0)
        sleepSoundEndsAt = Date()
    }

    var currentGain: Float { level }
    var isLoopPlaying: Bool { loopFile != nil && loopPlayer.isPlaying }
    var currentMode: Ambience { noise.mode }

    func stop() {
        stopAlarm()
        fadeTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        loopPlayer.stop()
        loopFile = nil
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Noise generators shared with the real-time audio thread (brown / pink / white / rain).
private final class NoiseState: @unchecked Sendable {
    var gain: Float = 0.1
    var mode: AudioKeeper.Ambience = .brownNoise
    private var last: Float = 0
    private var seed: UInt32 = 22222
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0

    private func white() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed >> 9) / Float(1 << 23) * 2 - 1
    }

    /// Paul Kellet's pink-noise filter.
    private func pink(_ w: Float) -> Float {
        b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520; b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.0168980
        let p = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return p * 0.11
    }

    func render(frameCount: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let g = gain, m = mode
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for i in 0..<frameCount {
                let w = white()
                var s: Float
                switch m {
                case .brownNoise:
                    last = (last + 0.02 * w) / 1.02                 // integrate → brown noise
                    s = last * 3.5
                case .pinkNoise:
                    s = pink(w)
                case .whiteNoise:
                    s = w * 0.25
                case .rainTent, .rainWindow, .silence:           // loops play through the player node
                    s = 0
                }
                data[i] = s * g
            }
        }
    }
}
