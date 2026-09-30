import AVFoundation
import SleepCore
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
        case storyForest = "story-forest"      // sound stories (owner 2026-09-30): a bed + random scenes
        case storyCave = "story-cave"
        case storyWorkshop = "story-workshop"     // since 2026-09-30 a carpenter's workshop (id kept)
        case storyJourney = "story-journey"       // the whole night: cabin → workshop → wind → storm → cave lake
        case silence = "silence"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .brownNoise: L("Brown noise")
            case .pinkNoise: L("Pink noise")
            case .whiteNoise: L("White noise")
            case .rainTent: L("Rain on a tent")
            case .rainWindow: L("Rain on a window")
            case .storyForest: L("Story: cabin in the woods")
            case .storyCave: L("Story: a cave")
            case .storyWorkshop: L("Story: carpenter's workshop")
            case .storyJourney: L("Story: the journey")
            case .silence: L("Silence")
            }
        }

        /// Recorded / pre-synthesised loops (assets/audio); nil = generated live.
        var loopFile: String? {
            switch self {
            case .rainTent: "rain_tent.caf"
            case .rainWindow: "rain_window.caf"
            case .storyForest, .storyCave, .storyWorkshop, .storyJourney: storyWorld?.chapters.first?.bed
            default: nil
            }
        }

        /// Sound stories: the world whose random scenes play over the bed loop.
        var storyWorld: StoryWorld? {
            switch self {
            case .storyForest: .forest
            case .storyCave: .cave
            case .storyWorkshop: .workshop
            case .storyJourney: .journey
            default: nil
            }
        }

        var detail: String {
            switch self {
            case .brownNoise: L("Deep and soft – like a distant waterfall.")
            case .pinkNoise: L("Balanced and gentle – like wind in a forest.")
            case .whiteNoise: L("Bright and even – like a fan.")
            case .rainTent: L("Drops tapping on the tent, now and then a big drip from a tree.")
            case .rainWindow: L("Soft rain outside the window (recording by InspectorJ, CC BY 4.0).")
            case .storyForest: L("A crackling camp fire, crickets and a brook; someone chops wood, the dog potters about, the chickens settle down, an owl calls. A different story every night.")
            case .storyCave: L("Deep silence and drips; someone explores a cave and digs with a pickaxe, pebbles fall. A different story every night.")
            case .storyWorkshop: L("A stove crackles, crickets outside; sawing, planing, sanding, nails, a broom, a purring cat. A different story every night.")
            case .storyJourney: L("A whole night's journey: an evening at the cabin, the workshop, the wind rises, a storm and a cave for shelter, an underground lake, and quiet after the rain.")
            case .silence: L("Nothing plays (the app still stays awake at night).")
            }
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            case "Hnedý šum": self = .brownNoise   // i18n-ignore (legacy persisted value)
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
    /// Two players for the bed loops, so a journey can crossfade from one chapter's bed to the next.
    private let bedPlayers = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private var currentBed = 0
    private var loopPlayer: AVAudioPlayerNode { bedPlayers[currentBed] }
    private var loopFile: String?
    /// Crossfade between chapter beds: the new bed at `bedFade`, the old one (`fadingBed`) at 1 − `bedFade`.
    private var bedFade: Float = 1
    private var fadingBed: AVAudioPlayerNode?
    private var bedFadeTask: Task<Void, Never>?
    private static var loopBuffers: [String: AVAudioPCMBuffer] = [:]
    /// Current sleep-sound level (applies to the generator OR the loop player).
    private var level: Float = 0
    // sound stories: random one-shots → mixer → reverb → main mixer, over the bed loop
    private let storyMixer = AVAudioMixerNode()
    private let storyReverb = AVAudioUnitReverb()
    private let storyPlayers = (0..<4).map { _ in AVAudioPlayerNode() }
    private var nextStoryPlayer = 0
    private var storyTask: Task<Void, Never>?
    private(set) var storyWorld: StoryWorld?
    /// Every story sound played (tests / diagnostics).
    private(set) var storySoundsPlayed = 0
    /// Unit tests: route everything through a silent mixer (nothing audible on the Mac).
    static var muted = false
    /// How many keepers are running (the night + the Settings preview). The shared audio session may only be
    /// deactivated when the last one stops – the preview used to deactivate it under a running night, which
    /// silenced the night for good (owner bug 2026-09-30: no sleep sound could be started any more).
    private(set) static var runningKeepers = 0

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
        bedPlayers.filter { $0.engine == nil }.forEach(engine.attach)
        if storyMixer.engine == nil {
            [storyMixer, storyReverb].forEach(engine.attach)
            engine.connect(storyMixer, to: storyReverb, format: nil)
            engine.connect(storyReverb, to: engine.mainMixerNode, format: nil)
            if let sample = Self.sample("st_grass_0.caf") {
                for p in storyPlayers {
                    engine.attach(p)
                    engine.connect(p, to: storyMixer, format: sample.format)
                }
            }
        }
        try engine.start()
        source = node
        isRunning = true
        Self.runningKeepers += 1
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
        // headphones / Bluetooth / a speaker change stop AVAudioEngine – start it again
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                        queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onInterruption?("audio configuration change")
                self?.ensureRunning()
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

    /// Starts the engine again when iOS (or anything else) stopped it while we are supposed to run.
    /// Called before every change of the sleep sound, so starting / switching a sound always works.
    @discardableResult
    func ensureRunning() -> Bool {
        guard isRunning else { return false }
        if engine.isRunning { return true }
        let session = AVAudioSession.sharedInstance()
        if !isAlarmRinging { try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers]) }
        try? session.setActive(true)
        guard (try? engine.start()) != nil else { return false }
        // the players stopped with the engine → schedule the current bed again
        finishBedFade()
        if let file = loopFile, let buffer = Self.loopBuffer(file) {
            loopPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            loopPlayer.play()
        }
        setLevel(level)
        return true
    }

    var isEngineRunning: Bool { engine.isRunning }

    /// Tests: what iOS does on a route change / a deactivated session.
    func stopEngineForTesting() { engine.stop() }

    func setVolume(_ volume: Float, ambience: Ambience) {
        ensureRunning()
        noise.mode = ambience
        applyMode(ambience)
        setLevel(ambience == .silence ? 0 : volume)
    }

    /// Generator modes play through the source node, loop modes through `loopPlayer` (seamless .loops),
    /// stories additionally run their scene scheduler.
    private func applyMode(_ ambience: Ambience) {
        guard isRunning else { return }
        if ambience.storyWorld != storyWorld {
            startStory(ambience.storyWorld)
        } else if ambience.storyWorld != nil, loopFile != nil {
            return                          // same story (e.g. a volume change): keep the current chapter's bed
        }
        guard let file = ambience.loopFile else {
            if loopFile != nil { finishBedFade(); loopPlayer.stop(); loopFile = nil }
            return
        }
        guard file != loopFile, let buffer = Self.loopBuffer(file) else { return }
        finishBedFade()
        loopPlayer.stop()
        engine.disconnectNodeOutput(loopPlayer)
        engine.connect(loopPlayer, to: engine.mainMixerNode, format: buffer.format)
        loopPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        loopPlayer.play()
        loopFile = file
    }

    /// Journey: the next chapter's bed fades in while the old one fades out (`seconds`).
    func crossfadeBed(to file: String, seconds: TimeInterval = 8) {
        guard isRunning, file != loopFile, let buffer = Self.loopBuffer(file) else { return }
        finishBedFade()
        let old = loopPlayer
        currentBed = 1 - currentBed
        loopPlayer.stop()
        engine.disconnectNodeOutput(loopPlayer)
        engine.connect(loopPlayer, to: engine.mainMixerNode, format: buffer.format)
        loopPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        loopFile = file
        fadingBed = old
        bedFade = 0
        setLevel(level)
        loopPlayer.play()
        bedFadeTask = Task { [weak self] in
            let steps = 40
            for k in 1...steps {
                try? await Task.sleep(for: .seconds(seconds / Double(steps)))
                guard let self, !Task.isCancelled else { return }
                self.bedFade = Float(k) / Float(steps)
                self.setLevel(self.level)
            }
            self?.finishBedFade()
        }
    }

    private func finishBedFade() {
        bedFadeTask?.cancel()
        bedFadeTask = nil
        fadingBed?.stop()
        fadingBed = nil
        bedFade = 1
        setLevel(level)
    }

    // MARK: sound stories

    /// The chapter the story is in now (a journey moves on every 10–20 min).
    private(set) var storyChapter: StoryChapter?

    private func enter(_ chapter: StoryChapter) {
        guard chapter != storyChapter else { return }
        storyReverb.loadFactoryPreset(chapter.reverb.preset)
        storyReverb.wetDryMix = chapter.reverb.wet
        if storyChapter != nil { crossfadeBed(to: chapter.bed) }            // the first bed comes from applyMode
        storyChapter = chapter
    }

    private func startStory(_ world: StoryWorld?) {
        storyTask?.cancel()
        storyTask = nil
        storyPlayers.forEach { $0.stop() }
        storyWorld = world
        storyChapter = nil
        guard let world else { return }
        enter(world.chapters[0])
        storyTask = Task { [weak self] in
            var teller = StoryTeller(world: world)
            var rng = SeededGenerator(seed: UInt64.random(in: 0...UInt64.max))
            try? await Task.sleep(for: .seconds(Double.random(in: 2...5)))
            while !Task.isCancelled {
                let scene = teller.next(using: &rng)
                self?.enter(scene.chapter)
                let start = Date()
                for e in scene.events.sorted(by: { $0.at < $1.at }) {
                    let wait = start.addingTimeInterval(e.at).timeIntervalSinceNow
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                    guard !Task.isCancelled, let self else { return }
                    self.playStory(e)
                }
                try? await Task.sleep(for: .seconds(scene.pause))
            }
        }
    }

    private func playStory(_ e: StoryEvent) {
        guard level > 0, let buffer = Self.sample(e.sample), engine.isRunning || ensureRunning() else { return }
        let p = storyPlayers[nextStoryPlayer]
        nextStoryPlayer = (nextStoryPlayer + 1) % storyPlayers.count
        p.volume = e.volume
        p.pan = e.pan
        p.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !p.isPlaying { p.play() }
        storySoundsPlayed += 1
    }

    /// A story sample from the bundle (cached like the loops).
    static func sample(_ file: String) -> AVAudioPCMBuffer? { loopBuffer(file) }

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
        loopPlayer.volume = isLoop ? g * bedFade : 0
        fadingBed?.volume = isLoop ? g * (1 - bedFade) : 0
        storyMixer.outputVolume = noise.mode.storyWorld != nil ? g : 0
    }

    private var fadeTask: Task<Void, Never>?
    /// When the current sleep sound goes silent (nil = plays until stopped).
    private(set) var sleepSoundEndsAt: Date?
    static let fadeSeconds: TimeInterval = 5

    /// Plays the current ambience at `volume` for EXACTLY `seconds` (nil = until stopped): the last 5 s fade out
    /// and the sound is silent precisely at the end. The engine keeps running in silence afterwards – it keeps
    /// the app alive (night detection, alarm, background playback with the screen off).
    func sleepTimer(seconds: TimeInterval?, volume: Float) {
        ensureRunning()
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
    var currentBedFile: String? { loopFile }
    var currentMode: Ambience { noise.mode }

    func stop() {
        stopAlarm()
        fadeTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        finishBedFade()
        bedPlayers.forEach { $0.stop() }
        loopFile = nil
        startStory(nil)
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        if isRunning { Self.runningKeepers -= 1 }
        isRunning = false
        // only the last running keeper releases the shared session (never under a running night)
        if Self.runningKeepers == 0 {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
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
                default:                                         // loops play through the player node
                    s = 0
                }
                data[i] = s * g
            }
        }
    }
}
