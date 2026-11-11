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

    /// A `var`: after a media-services reset an engine that cannot start again is replaced by a fresh one (with fresh nodes).
    private var engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let noise = NoiseState()
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning = false
    /// What the audio session reported. The texts feed the developer "Detection test" screen; `journalKind` is what the
    /// night journal records (diagnostics only).
    enum Report: String, CaseIterable {
        case interruptionBegan = "audio interruption began"
        case interruptionEnded = "audio interruption ended"
        case configurationChange = "audio configuration change"
        case servicesReset = "media services reset"

        var journalKind: NightEventKind {
            switch self {
            case .interruptionBegan: .audioInterrupted
            case .interruptionEnded: .audioResumed
            case .configurationChange: .audioRouteChanged
            case .servicesReset: .audioServicesReset
            }
        }
    }
    var onInterruption: ((Report) -> Void)?
    private var alarmPlayer = AVAudioPlayerNode()
    private var alarmTask: Task<Void, Never>?
    private(set) var isAlarmRinging = false
    /// Two players for the bed loops, so a journey can crossfade from one chapter's bed to the next.
    private var bedPlayers = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private var currentBed = 0
    private var loopPlayer: AVAudioPlayerNode { bedPlayers[currentBed] }
    private var loopFile: String?
    /// Crossfade between chapter beds: the new bed at `bedFade`, the old one (`fadingBed`) at 1 − `bedFade`.
    private var bedFade: Float = 1
    private var fadingBed: AVAudioPlayerNode?
    private var bedFadeTask: Task<Void, Never>?
    private static var loopBuffers: [String: AVAudioPCMBuffer] = [:]
    /// File of the bed that is fading out (kept in the cache until the crossfade is over).
    private var fadingFile: String?
    /// True while the sound is stopped (timer over, ■, silence): only the silent source node renders, the loop and
    /// story players are paused and the reverb is bypassed. The engine always keeps one running source – without
    /// it iOS may shut the hardware down and suspend the app (13m, audit M5).
    private var isIdle = false
    /// What the sleep sound should be right now (mode, level, stopped, timer end) – what a reset restarts.
    private(set) var desired = SleepSoundState(ambience: .silence, volume: 0, stopped: true, endsAt: nil)
    private var resumeRetry: Task<Void, Never>?
    /// The retry of a restart after a media-services reset that failed (not cancelled by the restart's own teardown).
    private var resetRetry: Task<Void, Never>?
    /// Current sleep-sound level (applies to the generator OR the loop player).
    private var level: Float = 0
    // sound stories: random one-shots → mixer → reverb → main mixer, over the bed loop
    private var storyMixer = AVAudioMixerNode()
    private var storyReverb = AVAudioUnitReverb()
    private var storyPlayers = (0..<4).map { _ in AVAudioPlayerNode() }
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
        resetRetry?.cancel()
        resetRetry = nil
        try begin(ambience: ambience, volume: volume)
        if wantedHold { setCallHold(true) }                 // a call that began while the keeper was down is still on
    }

    /// The real start (also the restart after a media-services reset – which must not cancel its own retry).
    private func begin(ambience: Ambience, volume: Float) throws {
        teardown()
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
        do { try engine.start() } catch { engine.detach(node); throw error }
        source = node
        isRunning = true
        Self.runningKeepers += 1
        isIdle = false
        desired = SleepSoundState(ambience: ambience, volume: volume, stopped: ambience == .silence || volume <= 0,
                                  endsAt: nil)
        applyMode(ambience)
        setLevel(ambience == .silence ? 0 : volume)
        if ambience == .silence { enterIdle(why: "silence") }
        diag("sound", "start amb=\(ambience.rawValue) level=\(Int((volume * 100).rounded()))")

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                        queue: .main) { [weak self] note in
            let info = Self.interruption(from: note.userInfo)
            MainActor.assumeIsolated { self?.receive(info) }
        })
        // headphones / Bluetooth / a speaker change stop AVAudioEngine – start it again
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                        queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onInterruption?(.configurationChange)
                self?.restartEngine(by: "config")
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                        queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                self?.diag("audio.route", "out=\(DeviceReading.routeTypes()) reason=\(Self.routeReasonName(raw))")
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil,
                                        queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onInterruption?(.servicesReset)
                if let self, self.isRunning { self.restartAfterReset() }
            }
        })
    }

    /// The story graph (4 players → mixer → reverb) exists only while a story ambience is chosen.
    private func attachStoryGraph() {
        guard storyMixer.engine == nil, let sample = Self.sample("st_grass_0.caf") else { return }
        [storyMixer, storyReverb].forEach(engine.attach)
        engine.connect(storyMixer, to: storyReverb, format: nil)
        engine.connect(storyReverb, to: engine.mainMixerNode, format: nil)
        for p in storyPlayers {
            engine.attach(p)
            engine.connect(p, to: storyMixer, format: sample.format)
        }
        storyReverb.bypass = isIdle
    }

    private func detachStoryGraph() {
        guard storyMixer.engine != nil else { return }
        storyPlayers.forEach { $0.stop(); engine.detach($0) }
        [storyReverb, storyMixer].forEach(engine.detach)
    }

    /// A media-services reset: restart with what the sound is NOW (mode, level, stopped, the timer's end) – never
    /// with what the night started with (audit M6: a stopped rain came back at 3 a.m. at full volume). An alarm that
    /// was ringing rings on (13ac); a call hold stays. An engine that cannot start again is replaced by a fresh one
    /// (Apple's guidance after a reset); when even that fails the restart is tried again every 3 s.
    func restartAfterReset() {
        let now = Date()
        let plan = desired.restartPlan(now: now)
        performReset(plan: plan, ends: desired.endsAt, alarm: isAlarmRinging ? alarmRun : nil)
    }

    private func performReset(plan: (ambience: Ambience, volume: Float, timerSeconds: TimeInterval?), ends: Date?,
                              alarm: AlarmRun?) {
        resetRetry?.cancel()
        resetRetry = nil
        do {
            do { try begin(ambience: plan.ambience, volume: plan.volume) } catch {
                teardown()
                rebuildEngine()
                try begin(ambience: plan.ambience, volume: plan.volume)
            }
        } catch {
            teardown()
            diag("audio.engine", "restart by=reset ok=0 err=\((error as NSError).code)")
            resetRetry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled, !self.isRunning else { return }
                self.performReset(plan: plan, ends: ends, alarm: alarm)
            }
            return
        }
        diag("audio.engine", "restart by=reset ok=1")
        if wantedHold { setCallHold(true) }                 // the hold as it is NOW (a call may have begun or ended meanwhile)
        if let seconds = plan.timerSeconds { sleepTimer(seconds: seconds, volume: plan.volume) }
        else { sleepSoundEndsAt = ends }
        if let alarm { resumeAlarm(alarm) }
        onRestored?()
    }

    /// A fresh engine with fresh nodes (the old ones are dropped). Only while the keeper is not running.
    private func rebuildEngine() {
        guard !isRunning else { return }
        engine = AVAudioEngine()
        alarmPlayer = AVAudioPlayerNode()
        bedPlayers = [AVAudioPlayerNode(), AVAudioPlayerNode()]
        currentBed = 0
        storyMixer = AVAudioMixerNode()
        storyReverb = AVAudioUnitReverb()
        storyPlayers = (0..<4).map { _ in AVAudioPlayerNode() }
    }

    /// An interruption (a call) ended: the engine starts again and the players the engine took down are scheduled
    /// again (audit M7). iOS may end an interruption without the "should resume" option – the keep-alive must
    /// restart anyway, so the option is not looked at; when the session is still held a second try follows.
    func resumeAfterInterruption(by: String = "intEnded") {
        guard isRunning else { return }
        resumeRetry?.cancel()
        if !engine.isRunning {
            restartEngine(by: by)
        } else {
            restorePlayers(force: true)
            if isAlarmRinging, !alarmPlayer.isPlaying { restoreAlarm() }
        }
        onRestored?()
    }

    /// Starts the engine again; a failure is tried again every 3 s while the keeper runs.
    private func restartEngine(by: String) {
        if !ensureRunning(by: by) { retryResume() }
    }

    private func retryResume() {
        resumeRetry?.cancel()
        resumeRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, self.isRunning, !self.engine.isRunning else { return }
            self.restartEngine(by: "retry")
        }
    }

    /// Schedules again what the current state needs and iOS (or an idle phase) stopped: the loop and the story
    /// teller. Does nothing while the sound is stopped; `force` also reschedules a loop that still claims to play
    /// (a player keeps `isPlaying` when its engine was stopped under it).
    private func restorePlayers(force: Bool = false) {
        guard isRunning, !isIdle, engine.isRunning else { return }
        if let file = loopFile, force || !loopPlayer.isPlaying, let buffer = Self.loopBuffer(file) {
            finishBedFade()
            loopPlayer.stop()
            loopPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            loopPlayer.play()
        }
        if let world = storyWorld, storyTask == nil { launchTeller(world) }
        setLevel(level)
    }

    /// Stops all work except the silent source node (see `isIdle`).
    private func enterIdle(why: String) {
        if !isIdle { diag("sound", "idle why=\(why)") }
        fadeTask?.cancel()                                  // a running fade must not wake the stopped sound
        isIdle = true
        desired.stopped = true
        setLevel(0)
        finishBedFade()
        bedPlayers.forEach { $0.pause() }
        storyTask?.cancel()
        storyTask = nil
        storyPlayers.forEach { $0.stop() }
        if storyReverb.engine != nil { storyReverb.bypass = true }
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

    /// Everything the alarm needs to ring again after an engine restart (13ac, B57): the decoded melody, when it
    /// began and how its volume rises. The volume for a moment is computed from the elapsed time – a restart never
    /// restarts the rise.
    struct AlarmRun {
        let buffer: AVAudioPCMBuffer
        let started: Date
        let ramp: TimeInterval
        let startLevel: Double
        let endLevel: Double
        let maxDuration: TimeInterval
        let onStop: @MainActor () -> Void

        func volume(at now: Date) -> Float {
            Float(AlarmVolume.level(elapsed: now.timeIntervalSince(started), start: startLevel, end: endLevel, rise: ramp))
        }
        func isOver(at now: Date) -> Bool { now.timeIntervalSince(started) >= maxDuration }
    }
    private var alarmRun: AlarmRun?
    /// The alarm has started at least once since `start`: the sleep sound is over for this night (`setVolume` and
    /// `sleepTimer` do nothing any more). Cleared by `stop()` only – a reset restart keeps it.
    private var alarmHasStarted = false
    /// Why the last `ringAlarm` returned false: `file` (missing / unreadable), `engine` (would not run: a call, another
    /// app's alarm) or `ringing` (it already rings). For the diagnostic track (13ac).
    private(set) var lastRingFailure = "file"
    /// The alarm player's gain as a whole percent (the share of the media volume it plays at): now while it rings, else
    /// what it was when it last stopped.
    var alarmGainPercent: Int { isAlarmRinging ? Int((alarmPlayer.volume * 100).rounded()) : lastAlarmGainPercent }
    private var lastAlarmGainPercent = 0

    /// Rings `file` in a loop, volume rising `startLevel` → `endLevel` (shares of the media volume) over `ramp` s (0 = `endLevel` at once), for at
    /// most `maxDuration` (D15: 2 min). The ambience is muted meanwhile – for good: once the alarm starts, the sleep sound
    /// is over for this night (13ac). `onStop` fires when it stops on its own.
    /// Returns whether the alarm really rings: false when the sound can't start (the file is missing, a phone
    /// call or another app's alarm holds the audio) – the caller keeps the backup notifications then and tries
    /// again (audit 2026-10-03, B1: `play()` on an engine that is not running raises an exception).
    /// The alarm player is never gated by the call hold.
    @discardableResult
    func ringAlarm(file: String, ramp: TimeInterval, startLevel: Double = 0.3, endLevel: Double = 1, maxDuration: TimeInterval,
                   onStop: @escaping @MainActor () -> Void) -> Bool {
        guard !isAlarmRinging else { lastRingFailure = "ringing"; return false }
        guard let url = Bundle.main.url(forResource: file, withExtension: nil),
              let audioFile = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat,
                                            frameCapacity: AVAudioFrameCount(audioFile.length)) else {
            lastRingFailure = "file"
            return false
        }
        try? audioFile.read(into: buffer)
        if !isRunning { try? start(ambience: .silence, volume: 0) }
        // the alarm must win: switch to a non-mixable session (interrupts a podcast still playing)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        alarmHasStarted = true
        enterIdle(why: "alarm")                             // the sleep sound is over (the restart plan is silent too)
        if !engine.isRunning { _ = startEngine(by: "alarm") }
        guard engine.isRunning else { lastRingFailure = "engine"; return false }
        let run = AlarmRun(buffer: buffer, started: Date(), ramp: ramp, startLevel: startLevel, endLevel: endLevel,
                           maxDuration: maxDuration, onStop: onStop)
        alarmRun = run
        playAlarmPlayer(run)
        isAlarmRinging = true
        launchAlarmTask(run)
        return true
    }

    /// (Re)connects, schedules and plays the alarm player with the volume of the elapsed time.
    private func playAlarmPlayer(_ run: AlarmRun) {
        if alarmPlayer.engine == nil { engine.attach(alarmPlayer) }
        alarmPlayer.stop()
        engine.disconnectNodeOutput(alarmPlayer)
        engine.connect(alarmPlayer, to: engine.mainMixerNode, format: run.buffer.format)
        alarmPlayer.volume = run.volume(at: Date())
        alarmPlayer.scheduleBuffer(run.buffer, at: nil, options: .loops)
        alarmPlayer.play()
    }

    private func launchAlarmTask(_ run: AlarmRun) {
        alarmTask?.cancel()
        alarmTask = Task { [weak self] in
            while let self, !Task.isCancelled, !run.isOver(at: Date()) {
                if run.ramp > 0 { self.alarmPlayer.volume = run.volume(at: Date()) }
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled else { return }
            self.stopAlarm()
            run.onStop()
        }
    }

    /// The engine was restarted (or an interruption ended) while the alarm rings: ring again, no restart of the rise.
    private func restoreAlarm() {
        guard isAlarmRinging, let run = alarmRun, engine.isRunning else { return }
        playAlarmPlayer(run)
    }

    /// After a media-services reset: the alarm that was ringing rings on for what is left of its time.
    private func resumeAlarm(_ run: AlarmRun) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard !run.isOver(at: Date()) else { run.onStop(); return }
        guard engine.isRunning else { return }
        alarmRun = run
        playAlarmPlayer(run)
        isAlarmRinging = true
        launchAlarmTask(run)
    }

    func stopAlarm() {
        alarmTask?.cancel()
        alarmTask = nil
        if isAlarmRinging {
            lastAlarmGainPercent = Int((alarmPlayer.volume * 100).rounded())
            alarmPlayer.stop()
        }
        isAlarmRinging = false
        alarmRun = nil
    }

    /// Starts the engine, noting the attempt in the diagnostic track.
    private func startEngine(by: String) -> Bool {
        do {
            try engine.start()
            diag("audio.engine", "restart by=\(by) ok=1")
            return true
        } catch {
            diag("audio.engine", "restart by=\(by) ok=0 err=\((error as NSError).code)")
            return false
        }
    }

    /// Starts the engine again when iOS (or anything else) stopped it while we are supposed to run.
    /// Called before every change of the sleep sound, so starting / switching a sound always works. `by` names the
    /// caller in the diagnostic track (only an attempt that was really needed is noted).
    @discardableResult
    func ensureRunning(by: String = "ui") -> Bool {
        guard isRunning else { return false }
        if engine.isRunning { return true }
        let session = AVAudioSession.sharedInstance()
        if !isAlarmRinging { try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers]) }
        try? session.setActive(true)
        guard startEngine(by: by) else { return false }
        // the players stopped with the engine → schedule the current bed again (not while the sound is stopped)
        finishBedFade()
        restorePlayers(force: true)
        restoreAlarm()
        setLevel(level)
        return true
    }

    var isEngineRunning: Bool { engine.isRunning }

    /// Tests: what iOS does on a route change / a deactivated session.
    func stopEngineForTesting() { engine.stop() }

    func setVolume(_ volume: Float, ambience: Ambience) {
        guard !alarmHasStarted else { return }              // the alarm has rung: the sleep sound is over for this night
        ensureRunning()
        noise.mode = ambience
        let wantsSound = ambience != .silence && volume > 0
        let wasIdle = isIdle
        if wantsSound { isIdle = false; if storyReverb.engine != nil { storyReverb.bypass = false } }
        if ambience != desired.ambience { diag("sound", "mode amb=\(ambience.rawValue)") }
        desired.ambience = ambience
        desired.volume = volume
        desired.stopped = !wantsSound
        applyMode(ambience)
        if wantsSound && wasIdle { diag("sound", "wake"); restorePlayers() }        // ▶ after the timer / ■
        setLevel(wantsSound ? volume : 0)
        if !wantsSound { enterIdle(why: "silence") }
    }

    /// Generator modes play through the source node, loop modes through `loopPlayer` (seamless .loops),
    /// stories additionally run their scene scheduler.
    private func applyMode(_ ambience: Ambience) {
        guard isRunning else { return }
        if ambience.storyWorld != nil { attachStoryGraph() }
        if ambience.storyWorld != storyWorld {
            startStory(ambience.storyWorld)
            if ambience.storyWorld == nil { detachStoryGraph() }
        } else if ambience.storyWorld != nil, loopFile != nil {
            return                          // same story (e.g. a volume change): keep the current chapter's bed
        }
        guard let file = ambience.loopFile else {
            if loopFile != nil { finishBedFade(); loopPlayer.stop(); loopFile = nil }
            Self.trimBeds(keeping: [])
            return
        }
        guard file != loopFile, let buffer = Self.loopBuffer(file) else { return }
        finishBedFade()
        loopPlayer.stop()
        engine.disconnectNodeOutput(loopPlayer)
        engine.connect(loopPlayer, to: engine.mainMixerNode, format: buffer.format)
        // B58: `play()` on an engine that is not running raises an Obj-C exception – only the state is recorded then,
        // `restorePlayers(force:)` schedules the bed at the next successful `ensureRunning`
        if engine.isRunning {
            loopPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            loopPlayer.play()
        }
        loopFile = file
        trimBeds()
    }

    /// Journey: the next chapter's bed fades in while the old one fades out (`seconds`).
    func crossfadeBed(to file: String, seconds: TimeInterval = 8) {
        guard isRunning, file != loopFile, let buffer = Self.loopBuffer(file) else { return }
        finishBedFade()
        guard engine.isRunning else {                       // B58: only record the bed, `restorePlayers` plays it later
            loopPlayer.stop()
            engine.disconnectNodeOutput(loopPlayer)
            engine.connect(loopPlayer, to: engine.mainMixerNode, format: buffer.format)
            loopFile = file
            trimBeds()
            return
        }
        let old = loopPlayer
        let oldFile = loopFile
        currentBed = 1 - currentBed
        loopPlayer.stop()
        engine.disconnectNodeOutput(loopPlayer)
        engine.connect(loopPlayer, to: engine.mainMixerNode, format: buffer.format)
        loopPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        loopFile = file
        fadingBed = old
        fadingFile = oldFile
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
            self?.trimBeds()
        }
    }

    private func finishBedFade() {
        bedFadeTask?.cancel()
        bedFadeTask = nil
        fadingBed?.stop()
        fadingBed = nil
        fadingFile = nil
        bedFade = 1
        setLevel(level)
    }

    // MARK: sound stories

    /// The chapter the story is in now (a journey moves on every 10–20 min).
    private(set) var storyChapter: StoryChapter?

    private func enter(_ chapter: StoryChapter) {
        guard chapter != storyChapter else { return }
        if storyWorld == .journey { diag("sound", "chapter=\(chapter.rawValue)") }
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
        launchTeller(world)
    }

    /// The scene scheduler: random scenes over the bed, a journey moving on every 10–20 min.
    private func launchTeller(_ world: StoryWorld) {
        storyTask?.cancel()
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
        // during a call nothing is scheduled and the engine is not touched (13ac, B52)
        guard !isCallHeld, level > 0, let buffer = Self.sample(e.sample),
              engine.isRunning || ensureRunning(by: "story") else { return }
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

    /// Cache policy (audit M8): of the decoded beds / loops only the ones that play, the one fading out and the next
    /// chapter's bed stay in memory; story one-shots (`st_…`, small) stay while a keeper runs.
    nonisolated static func bedsToDrop(cached: [String], keeping: Set<String>) -> [String] {
        cached.filter { !$0.hasPrefix("st_") && !keeping.contains($0) }
    }

    /// The files in the cache (tests).
    static var cachedFiles: [String] { Array(loopBuffers.keys) }

    private static func trimBeds(keeping: Set<String>) {
        for file in bedsToDrop(cached: Array(loopBuffers.keys), keeping: keeping) { loopBuffers[file] = nil }
    }

    private func trimBeds() {
        var keep = Set([loopFile, fadingFile].compactMap { $0 })
        if let world = storyWorld, let chapter = storyChapter, let i = world.chapters.firstIndex(of: chapter),
           world.chapters.indices.contains(i + 1) {
            keep.insert(world.chapters[i + 1].bed)
        }
        Self.trimBeds(keeping: keep)
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
        if g > 0, isIdle {                                  // the sound is wanted again (a timer set after ■, …)
            isIdle = false
            diag("sound", "wake")
            if storyReverb.engine != nil { storyReverb.bypass = false }
            restorePlayers()
        }
        level = g                                           // what the sound should be – never changed by a call
        let applied = isCallHeld ? 0 : g                    // what is audible: silent during a call (13ac, B52)
        let isLoop = noise.mode.loopFile != nil
        noise.gain = isLoop ? 0 : applied
        loopPlayer.volume = isLoop ? applied * bedFade : 0
        fadingBed?.volume = isLoop ? applied * (1 - bedFade) : 0
        storyMixer.outputVolume = noise.mode.storyWorld != nil ? applied : 0
    }

    private var fadeTask: Task<Void, Never>?
    /// When the current sleep sound goes silent (nil = plays until stopped).
    private(set) var sleepSoundEndsAt: Date?
    static let fadeSeconds: TimeInterval = 5

    /// Plays the current ambience at `volume` for EXACTLY `seconds` (nil = until stopped): the last 5 s fade out
    /// and the sound is silent precisely at the end. The engine keeps running in silence afterwards – it keeps
    /// the app alive (night detection, alarm, background playback with the screen off).
    func sleepTimer(seconds: TimeInterval?, volume: Float) {
        guard !alarmHasStarted else { return }
        ensureRunning()
        diag("sound", "timer=\(seconds.map { "\(Int($0))s" } ?? "all")")
        fadeTask?.cancel()
        let wantsSound = noise.mode != .silence && volume > 0
        setLevel(wantsSound ? volume : 0)
        desired.volume = volume
        desired.stopped = !wantsSound
        guard let seconds else {
            sleepSoundEndsAt = nil
            desired.endsAt = nil
            if !wantsSound { enterIdle(why: "silence") }
            return
        }
        let end = Date() + max(0, seconds)
        sleepSoundEndsAt = end
        desired.endsAt = end
        fadeTask = Task { [weak self] in
            let fadeStart = end - Self.fadeSeconds
            if fadeStart > Date() { try? await Task.sleep(for: .seconds(fadeStart.timeIntervalSinceNow)) }
            while let self, !Task.isCancelled {
                let left = end.timeIntervalSinceNow
                if left <= 0 { self.enterIdle(why: "timer"); return }       // the lullaby really stops (audit M5)
                self.setLevel(volume * Float(min(1, left / Self.fadeSeconds)))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Stops the sleep sound immediately (engine keeps running in silence).
    func silenceNow() {
        fadeTask?.cancel()
        enterIdle(why: "stop")
        sleepSoundEndsAt = Date()
        desired.endsAt = sleepSoundEndsAt
    }

    var currentGain: Float { level }
    /// Tests: what is audible – `currentGain` is what the sound should be, this is what the players really apply.
    var appliedGain: Float {
        max(noise.gain, loopPlayer.volume, fadingBed?.volume ?? 0, storyMixer.engine == nil ? 0 : storyMixer.outputVolume)
    }
    var isLoopPlaying: Bool { loopFile != nil && loopPlayer.isPlaying }
    var currentBedFile: String? { loopFile }
    var currentMode: Ambience { noise.mode }
    /// Tests: what runs while the sound is stopped.
    var isTellerRunning: Bool { storyTask != nil }
    var isStoryGraphAttached: Bool { storyMixer.engine != nil }
    var isStoryReverbBypassed: Bool { storyReverb.bypass }
    /// Tests: the alarm player (ungated by the call hold) and what a story event does.
    var isAlarmPlayerPlaying: Bool { alarmPlayer.isPlaying }
    var alarmPlayerVolume: Float { alarmPlayer.volume }
    func playStoryForTesting(_ e: StoryEvent) { playStory(e) }
    /// Tests: what a reset that cannot restart the old engine does – a fresh engine with fresh nodes.
    func rebuildEngineForTesting() { rebuildEngine() }
    func postConfigurationChangeForTesting() {
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
    }

    // MARK: call hold (13ac, B52)

    /// True while a phone call is live: every audible gain is 0 (the stored level and `desired` stay), the story teller
    /// schedules nothing, the alarm player is not gated. The engine keeps running – the silent source is the keep-alive
    /// that stops iOS from suspending the app in the background, so a call never stops the engine or the session.
    private(set) var isCallHeld = false
    /// The hold as the last `setCallHold` wanted it – applied after a restart. Cleared by `stop()` only.
    private var wantedHold = false
    /// Called after an ended interruption and after a reset restart: `AppModel` reads the media volume again then (a
    /// change made while the session was down never reached its observer).
    var onRestored: (() -> Void)?

    /// Set by `AppModel` at the start / end of a call. Only while the keeper runs (`stop()` clears it); it comes back
    /// after a reset restart. Release: the engine is checked and the current level applied again.
    func setCallHold(_ on: Bool) {
        wantedHold = on                                     // recorded even while the keeper is down (a failed reset restart)
        guard isRunning, on != isCallHeld else { return }
        isCallHeld = on
        diag("sound", "hold \(on ? "on" : "off")")
        if !on { restartEngine(by: "hold") }
        setLevel(level)
        if !on { restorePlayers() }
    }

    // MARK: diagnostics (13ac)

    /// The diagnostic track's line writer (`AppModel` wires it to `model.diag.note`; nil for the Settings preview).
    var onDiag: ((String, String) -> Void)?
    private func diag(_ k: String, _ v: String) { onDiag?(k, v) }

    /// "sound state engine=1 bed=1 teller=1" – at each interruption and at the end.
    private func noteState() {
        diag("sound", "state engine=\(engine.isRunning ? 1 : 0) bed=\(isLoopPlaying ? 1 : 0) teller=\(storyTask != nil ? 1 : 0)")
    }

    /// An interruption notification: what it says is read and noted, a call's end brings the engine back. A notification
    /// without a readable type is ignored (it used to count as "ended"). Internal for tests.
    func receiveInterruption(userInfo: [AnyHashable: Any]?) { receive(Self.interruption(from: userInfo)) }

    private func receive(_ info: InterruptionInfo?) {
        guard let info else { return }
        diag("audio.int", "\(info.began ? "began" : "ended") reason=\(info.reason) resume=\(info.shouldResume ? 1 : 0) suspended=\(info.wasSuspended ? 1 : 0)")
        noteState()
        onInterruption?(info.began ? .interruptionBegan : .interruptionEnded)
        if !info.began { resumeAfterInterruption() }        // resume after a call
    }

    struct InterruptionInfo: Equatable, Sendable {
        var began: Bool
        var reason: String
        var shouldResume: Bool
        var wasSuspended: Bool
    }

    /// Reads an interruption notification: nil when it carries no readable type (it is then ignored).
    nonisolated static func interruption(from userInfo: [AnyHashable: Any]?) -> InterruptionInfo? {
        // only the two known values count (an imported C enum accepts any raw value)
        let began = AVAudioSession.InterruptionType.began.rawValue, ended = AVAudioSession.InterruptionType.ended.rawValue
        guard let raw = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, raw == began || raw == ended else { return nil }
        let reasonName: String
        if let r = userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt {
            switch r {
            case 0: reasonName = "default"
            case 1: reasonName = "appWasSuspended"
            case 2: reasonName = "builtInMicMuted"
            case 4: reasonName = "routeDisconnected"
            default: reasonName = "raw\(r)"
            }
        } else { reasonName = "none" }
        let options = (userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
            .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
        let suspended = (userInfo?["AVAudioSessionInterruptionWasSuspendedKey"] as? Bool) ?? false
        return InterruptionInfo(began: raw == began, reason: reasonName,
                                shouldResume: options.contains(.shouldResume), wasSuspended: suspended)
    }

    nonisolated static func routeReasonName(_ raw: UInt?) -> String {
        guard let raw, let r = AVAudioSession.RouteChangeReason(rawValue: raw) else { return "none" }
        switch r {
        case .newDeviceAvailable: return "newDevice"
        case .oldDeviceUnavailable: return "oldDeviceGone"
        case .categoryChange: return "category"
        case .override: return "override"
        case .wakeFromSleep: return "wake"
        case .noSuitableRouteForCategory: return "noRoute"
        case .routeConfigurationChange: return "config"
        default: return "unknown"
        }
    }

    /// Stops everything. The session is released – and its category put back to `.ambient` – when the last keeper
    /// stops (13ac, B59: the alarm made it non-mixable `.playback`, and every later effect ignored the silent switch).
    func stop() {
        resetRetry?.cancel()
        resetRetry = nil
        wantedHold = false
        alarmHasStarted = false
        if isRunning { noteState() }
        teardown()
    }

    private func teardown() {
        stopAlarm()
        fadeTask?.cancel()
        resumeRetry?.cancel()
        resumeRetry = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        finishBedFade()
        bedPlayers.forEach { $0.stop() }
        loopFile = nil
        startStory(nil)
        engine.stop()
        detachStoryGraph()                                  // the graph lives only with a story (not into the next night)
        if let source { engine.detach(source) }
        source = nil
        if isRunning { Self.runningKeepers -= 1 }
        isRunning = false
        isIdle = false
        isCallHeld = false
        if Self.runningKeepers == 0 { Self.loopBuffers.removeAll() }       // end of the night / nap: free the memory
        // only the last running keeper releases the shared session (never under a running night)
        if Self.runningKeepers == 0 {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(.ambient)
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
        let silent = g == 0 || m.loopFile != nil                // the cheapest keep-alive: zeros, no synthesis
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            if silent { data.update(repeating: 0, count: frameCount); continue }
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

/// What the sleep sound should be right now. Pure, so the decisions after an audio reset can be tested without an
/// engine (13m, audit M6).
struct SleepSoundState: Equatable {
    var ambience: AudioKeeper.Ambience
    var volume: Float
    /// Silenced by ■, by the end of the timer or by choosing silence.
    var stopped: Bool
    /// When the sleep timer ends (nil = plays until stopped).
    var endsAt: Date?

    /// What a restart of the audio (media-services reset) starts: the sound at its current level, with the timer's
    /// remaining time when its end is still ahead; a stopped sound restarts only the silent keep-alive.
    func restartPlan(now: Date) -> (ambience: AudioKeeper.Ambience, volume: Float, timerSeconds: TimeInterval?) {
        let ended = endsAt.map { $0 <= now } ?? false
        if stopped || ended || ambience == .silence || volume <= 0 { return (.silence, 0, nil) }
        return (ambience, volume, endsAt.map { $0.timeIntervalSince(now) })
    }
}
