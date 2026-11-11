import AVFoundation
import Foundation
import Testing
@testable import SleepHole

/// 13m: the cheaper, sturdier night audio – a stopped sound renders almost nothing, a reset restarts the CURRENT
/// sound, an interruption brings the players back, the decoded beds are freed.
@MainActor
@Suite(.serialized)
struct NightAudioTests {
    init() { AudioKeeper.muted = true }

    func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    // MARK: the pure state (M6)

    @Test func aResetRestartsTheCurrentSoundNotTheOriginalOne() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var s = SleepSoundState(ambience: .rainWindow, volume: 0.3, stopped: false, endsAt: now + 600)
        var plan = s.restartPlan(now: now)
        #expect(plan.ambience == .rainWindow && plan.volume == 0.3 && plan.timerSeconds == 600)
        s.volume = 0.1                                                  // the level changed since the start
        #expect(s.restartPlan(now: now + 100).volume == 0.1 && s.restartPlan(now: now + 100).timerSeconds == 500)
        plan = s.restartPlan(now: now + 600)                            // the timer is over → only the keep-alive
        #expect(plan.ambience == .silence && plan.volume == 0 && plan.timerSeconds == nil)
        s.endsAt = nil                                                  // plays until stopped: no timer to re-arm
        #expect(s.restartPlan(now: now).timerSeconds == nil && s.restartPlan(now: now).ambience == .rainWindow)
        s.stopped = true                                                // ■ pressed
        #expect(s.restartPlan(now: now).ambience == .silence)
        #expect(SleepSoundState(ambience: .silence, volume: 0.3, stopped: false, endsAt: nil)
            .restartPlan(now: now).volume == 0)
    }

    // MARK: the cache policy (M8)

    @Test func onlyThePlayingFadingAndNextBedsStayCached() {
        let cached = ["bed_forest.caf", "bed_workshop.caf", "bed_wind.caf", "rain_tent.caf", "st_owl_0.caf"]
        let drop = AudioKeeper.bedsToDrop(cached: cached, keeping: ["bed_workshop.caf", "bed_wind.caf"])
        #expect(Set(drop) == ["bed_forest.caf", "rain_tent.caf"])       // the one-shots are not beds
        #expect(AudioKeeper.bedsToDrop(cached: cached, keeping: []).contains("st_owl_0.caf") == false)
    }

    @Test func chaptersChangingFreeTheOldBedsAndStopFreesEverything() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .storyJourney, volume: 0.3)
        func beds() -> [String] { AudioKeeper.cachedFiles.filter { !$0.hasPrefix("st_") } }
        func settle(_ done: () -> Bool) async {                         // the fade runs on timers → poll
            let deadline = Date() + 8
            while !done(), Date() < deadline { await wait(0.1) }
        }
        audio.crossfadeBed(to: StoryChapter.carpentry.bed, seconds: 0.2)
        await settle { !beds().contains("bed_forest.caf") }
        audio.crossfadeBed(to: StoryChapter.wind.bed, seconds: 0.2)
        await settle { !beds().contains("bed_workshop.caf") }
        #expect(!beds().contains("bed_forest.caf") && beds().contains("bed_wind.caf"), "\(beds())")
        #expect(beds().count <= 2, "\(beds())")
        audio.stop()
        // freed with the last running keeper (other suites may run a keeper at the same time)
        #expect(AudioKeeper.runningKeepers > 0 || AudioKeeper.cachedFiles.isEmpty)
    }

    // MARK: a stopped sound (M5)

    @Test func aStoppedSoundPausesEverythingButTheKeepAliveAndComesBackOnPlay() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .storyJourney, volume: 0.3)
        #expect(audio.isLoopPlaying && audio.isTellerRunning && audio.isStoryGraphAttached)
        audio.silenceNow()
        #expect(!audio.isLoopPlaying && !audio.isTellerRunning && audio.isEngineRunning && audio.isRunning)
        #expect(audio.isStoryReverbBypassed)
        #expect(audio.desired.stopped)
        audio.setVolume(0.3, ambience: .storyJourney)                   // ▶ from the sound sheet
        #expect(audio.isLoopPlaying && audio.isTellerRunning && !audio.isStoryReverbBypassed)
        #expect(!audio.desired.stopped && audio.currentGain == 0.3)
        audio.setVolume(0.3, ambience: .brownNoise)
        #expect(!audio.isStoryGraphAttached && !audio.isTellerRunning)  // the story graph only lives with a story
        audio.silenceNow()
        #expect(audio.currentGain == 0 && audio.isEngineRunning)
        audio.stop()
    }

    @Test func theTimerEndingStopsTheLullabyAndPlayAfterwardsStartsItAgain() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .rainTent, volume: 0.3)
        audio.sleepTimer(seconds: 0.2, volume: 0.3)
        let deadline = Date() + 5
        while audio.isLoopPlaying, Date() < deadline { await wait(0.1) }
        #expect(!audio.isLoopPlaying && audio.currentGain == 0 && audio.isEngineRunning && audio.desired.stopped)
        audio.setVolume(0.3, ambience: .rainTent)
        audio.sleepTimer(seconds: nil, volume: 0.3)
        #expect(audio.isLoopPlaying && audio.currentGain == 0.3 && !audio.desired.stopped)
        audio.stop()
    }

    // MARK: a reset (M6) and an interruption (M7)

    @Test func aMediaServicesResetKeepsTheTimerAndTheCurrentLevel() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .rainWindow, volume: 0.3)
        audio.setVolume(0.2, ambience: .rainWindow)
        audio.sleepTimer(seconds: 600, volume: 0.2)
        let end = try #require(audio.sleepSoundEndsAt)
        audio.restartAfterReset()
        #expect(audio.isLoopPlaying && audio.currentMode == .rainWindow && audio.currentGain == 0.2)
        #expect(abs(try #require(audio.sleepSoundEndsAt).timeIntervalSince(end)) < 1)
        audio.silenceNow()
        audio.restartAfterReset()                                       // a stopped sound stays stopped
        #expect(!audio.isLoopPlaying && audio.currentGain == 0 && audio.isEngineRunning && audio.isRunning)
        audio.stop()
    }

    @Test func theResetNotificationRestartsTheKeeper() async throws {
        let audio = AudioKeeper()
        var reports: [AudioKeeper.Report] = []
        try audio.start(ambience: .rainTent, volume: 0.25)
        audio.onInterruption = { reports.append($0) }
        audio.silenceNow()
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        await wait(0.5)
        #expect(reports.contains(.servicesReset))
        #expect(audio.isRunning && audio.isEngineRunning && !audio.isLoopPlaying && audio.currentGain == 0)
        audio.stop()
    }

    @Test func afterAnInterruptionTheLoopAndTheStoryComeBack() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .storyCave, volume: 0.3)
        audio.stopEngineForTesting()                                    // what a call does to the engine
        #expect(!audio.isEngineRunning)
        let note = Notification(name: AVAudioSession.interruptionNotification, object: nil,
                                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        NotificationCenter.default.post(note)                           // "ended" without the resume option
        await wait(0.5)
        #expect(audio.isEngineRunning && audio.isLoopPlaying && audio.currentBedFile == "bed_cave.caf")
        audio.stopEngineForTesting()
        audio.silenceNow()
        audio.resumeAfterInterruption()                                 // stopped sound: only the keep-alive restarts
        #expect(audio.isEngineRunning && !audio.isLoopPlaying)
        audio.stop()
    }

    @Test func chooseSilenceDuringAFadeKeepsTheSoundStopped() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .rainTent, volume: 0.3)
        audio.sleepTimer(seconds: 3, volume: 0.3)                       // the fade (last 5 s) is already running
        await wait(0.5)
        audio.setVolume(0.3, ambience: .silence)                        // Settings → Silence
        let end = try #require(audio.sleepSoundEndsAt)
        while Date() < end + 0.5 {
            #expect(audio.currentGain == 0 && !audio.isLoopPlaying)
            await wait(0.2)
        }
        #expect(audio.currentGain == 0 && audio.isEngineRunning)
        audio.stop()
    }

    @Test func theStoryGraphDoesNotOutliveTheStory() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .storyCave, volume: 0.3)
        #expect(audio.isStoryGraphAttached)
        audio.stop()
        try audio.start(ambience: .rainTent, volume: 0.3)
        #expect(!audio.isStoryGraphAttached)
        try audio.start(ambience: .storyForest, volume: 0.3)
        #expect(audio.isStoryGraphAttached && audio.isTellerRunning)
        audio.stop()
    }

    // MARK: a phone call (13ac, B52)

    private func ended(_ extra: [String: Any] = [:]) -> Notification {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue]
        extra.forEach { info[$0.key] = $0.value }
        return Notification(name: AVAudioSession.interruptionNotification, object: nil, userInfo: info)
    }

    private let sceneEvent = StoryEvent(at: 0, sample: "st_grass_0.caf", volume: 0.5, pan: 0)

    @Test func aCallHoldKeepsTheEngineRunningSilencesTheSoundAndTheStoryAndGivesItBack() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .storyCave, volume: 0.3)
        audio.setCallHold(true)
        #expect(audio.isCallHeld && audio.appliedGain == 0)
        #expect(audio.currentGain == 0.3 && audio.desired.volume == 0.3 && !audio.desired.stopped)   // the state stays
        audio.stopEngineForTesting()                                    // the call takes the engine down …
        NotificationCenter.default.post(ended())                        // … and the interruption ends
        await wait(0.5)
        #expect(audio.isEngineRunning && audio.appliedGain == 0 && audio.currentGain == 0.3)
        audio.stopEngineForTesting()
        audio.postConfigurationChangeForTesting()                       // a route change during the call
        await wait(0.5)
        #expect(audio.isEngineRunning && audio.appliedGain == 0)
        let before = audio.storySoundsPlayed
        audio.playStoryForTesting(sceneEvent)
        #expect(audio.storySoundsPlayed == before)                      // nothing is scheduled during the call
        audio.stopEngineForTesting()
        audio.playStoryForTesting(sceneEvent)
        #expect(!audio.isEngineRunning)                                 // … and the story never restarts the engine
        audio.setCallHold(false)                                        // the call is over
        #expect(audio.isEngineRunning && audio.isLoopPlaying && audio.currentBedFile == "bed_cave.caf")
        #expect(audio.appliedGain == 0.3 && audio.desired.volume == 0.3)
        audio.playStoryForTesting(sceneEvent)
        #expect(audio.storySoundsPlayed == before + 1)
        audio.stop()
        #expect(!audio.isCallHeld)
    }

    @Test func theHoldSilencesALoopAndAGeneratorToo() throws {
        let audio = AudioKeeper()
        for mode in [AudioKeeper.Ambience.rainTent, .brownNoise] {
            try audio.start(ambience: mode, volume: 0.25)
            #expect(audio.appliedGain == 0.25)
            audio.setCallHold(true)
            #expect(audio.appliedGain == 0 && audio.currentGain == 0.25)
            audio.setVolume(0.2, ambience: mode)                        // a volume change in the call stays silent
            #expect(audio.appliedGain == 0 && audio.currentGain == 0.2)
            audio.setCallHold(false)
            #expect(audio.appliedGain == 0.2)
            if mode == .rainTent { #expect(audio.isLoopPlaying) }
        }
        audio.stop()
    }

    @Test func theAlarmRingsDuringACallAndTheSleepSoundStaysSilentAfterwards() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .rainTent, volume: 0.3)
        audio.setCallHold(true)
        #expect(audio.ringAlarm(file: "alarm_digital.caf", ramp: 0, maxDuration: 30) {})
        #expect(audio.isAlarmRinging && audio.isAlarmPlayerPlaying && audio.alarmPlayerVolume > 0)   // not gated
        #expect(audio.currentGain == 0 && audio.appliedGain == 0 && audio.desired.stopped)
        audio.setCallHold(false)
        #expect(audio.currentGain == 0 && audio.appliedGain == 0)       // the sleep sound is over for this night
        #expect(audio.isAlarmRinging && audio.isAlarmPlayerPlaying)
        audio.stop()
    }

    @Test func aResetKeepsACallHold() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .brownNoise, volume: 0.3)
        audio.setCallHold(true)
        audio.restartAfterReset()
        #expect(audio.isCallHeld && audio.appliedGain == 0 && audio.currentGain == 0.3)
        audio.setCallHold(false)
        #expect(audio.appliedGain == 0.3)
        audio.stop()
    }

    @Test func aHoldWantedWhileTheKeeperIsDownIsAppliedWhenItRunsAgainAndStopClearsIt() async throws {
        let audio = AudioKeeper()
        audio.setCallHold(true)                                         // a call began while the keeper was down
        #expect(!audio.isCallHeld)                                      // nothing to silence yet …
        try audio.start(ambience: .brownNoise, volume: 0.3)
        #expect(audio.isCallHeld && audio.appliedGain == 0 && audio.currentGain == 0.3)   // … but the hold comes with the start
        audio.setCallHold(false)
        #expect(!audio.isCallHeld && audio.appliedGain == 0.3)
        audio.setCallHold(true)
        audio.stop()                                                    // the end of the night forgets the wish
        try audio.start(ambience: .brownNoise, volume: 0.3)
        #expect(!audio.isCallHeld && audio.appliedGain == 0.3)
        audio.stop()
    }

    @Test func afterTheAlarmStartedNeitherAVolumeChangeNorATimerWakesTheSleepSound() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .rainTent, volume: 0.3)
        #expect(audio.ringAlarm(file: "alarm_digital.caf", ramp: 0, maxDuration: 30) {})
        audio.setVolume(0.4, ambience: .rainTent)
        audio.sleepTimer(seconds: 60, volume: 0.4)
        #expect(audio.currentGain == 0 && audio.appliedGain == 0 && audio.desired.stopped && audio.isAlarmPlayerPlaying)
        audio.stop()
        try audio.start(ambience: .rainTent, volume: 0.3)               // the next night plays again
        #expect(audio.appliedGain == 0.3)
        audio.stop()
    }

    @Test func theKeeperTellsWhenTheAudioCameBack() async throws {
        let audio = AudioKeeper()
        var restored = 0
        audio.onRestored = { restored += 1 }
        try audio.start(ambience: .brownNoise, volume: 0.3)
        audio.stopEngineForTesting()
        audio.receiveInterruption(userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        #expect(restored == 1)
        audio.restartAfterReset()
        #expect(restored == 2)
        audio.stop()
    }

    // MARK: an engine that is not running (B58) and an alarm that must survive a restart (B57)

    @Test func aBedChangeOnAStoppedEngineOnlyRecordsTheStateAndTheBedPlaysAfterTheRestart() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .storyJourney, volume: 0.3)
        audio.stopEngineForTesting()
        audio.crossfadeBed(to: StoryChapter.carpentry.bed, seconds: 0.2)   // used to raise an Obj-C exception
        #expect(audio.currentBedFile == "bed_workshop.caf" && !audio.isLoopPlaying)
        #expect(AudioKeeper.cachedFiles.contains("bed_workshop.caf"))
        #expect(audio.ensureRunning())
        #expect(audio.isLoopPlaying && audio.currentBedFile == "bed_workshop.caf")
        audio.stop()
    }

    @Test func theAlarmRingsAgainAfterAnEngineRestartWithoutRestartingTheRise() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .silence, volume: 0)
        #expect(audio.ringAlarm(file: "alarm_digital.caf", ramp: 2, startLevel: 0.3, endLevel: 1, maxDuration: 30) {})
        await wait(1.2)
        audio.stopEngineForTesting()                                    // a configuration change
        audio.postConfigurationChangeForTesting()
        await wait(0.3)
        #expect(audio.isEngineRunning && audio.isAlarmRinging && audio.isAlarmPlayerPlaying)
        #expect(audio.alarmPlayerVolume > 0.5)                          // the volume of the elapsed time, not 0.3 again
        audio.stopEngineForTesting()                                    // an interruption that ended
        NotificationCenter.default.post(ended())
        await wait(0.3)
        #expect(audio.isAlarmPlayerPlaying && audio.alarmPlayerVolume > 0.5)
        audio.stop()
    }

    @Test func aResetAfterTheAlarmStartedKeepsTheSleepSoundOffAndTheAlarmRinging() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .brownNoise, volume: 0.3)
        var stopped = false
        #expect(audio.ringAlarm(file: "alarm_digital.caf", ramp: 0, maxDuration: 30) { stopped = true })
        #expect(audio.desired.stopped && audio.currentGain == 0)
        audio.restartAfterReset()
        #expect(audio.isAlarmRinging && audio.isAlarmPlayerPlaying && !stopped)
        #expect(audio.currentGain == 0 && audio.appliedGain == 0)       // not the night level in the morning
        audio.stop()
        #expect(!audio.isAlarmRinging)
    }

    @Test func aFreshEngineWithFreshNodesPlaysAStoryAndTheAlarm() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .storyJourney, volume: 0.3)
        audio.stop()
        audio.rebuildEngineForTesting()                                 // after a reset the old engine is dropped
        try audio.start(ambience: .storyCave, volume: 0.3)
        #expect(audio.isEngineRunning && audio.isLoopPlaying && audio.isTellerRunning && audio.appliedGain == 0.3)
        #expect(audio.ringAlarm(file: "alarm_digital.caf", ramp: 0, maxDuration: 30) {} && audio.isAlarmPlayerPlaying)
        audio.stop()
    }

    // MARK: the interruption notification (13ac)

    @Test func anInterruptionWithoutAReadableTypeIsIgnored() async throws {
        let audio = AudioKeeper()
        var reports: [AudioKeeper.Report] = []
        var lines: [String] = []
        try audio.start(ambience: .storyCave, volume: 0.3)
        await wait(0.6)                                                 // the simulator posts its own "ended" after a start
        audio.onInterruption = { reports.append($0) }
        audio.onDiag = { lines.append("\($0) \($1)") }
        audio.stopEngineForTesting()
        audio.receiveInterruption(userInfo: nil)                        // called directly: the simulator posts real ones
        audio.receiveInterruption(userInfo: [AVAudioSessionInterruptionTypeKey: UInt(99)])
        audio.receiveInterruption(userInfo: [AVAudioSessionInterruptionOptionKey: UInt(1)])
        #expect(reports.isEmpty && lines.isEmpty, "\(reports) \(lines)")
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil)   // through the observer
        await wait(0.3)
        #expect(reports.isEmpty && lines.isEmpty && !audio.isEngineRunning, "\(reports) \(lines)")   // no "ended", no resume
        audio.receiveInterruption(userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        #expect(reports == [.interruptionEnded] && audio.isEngineRunning)
        audio.stop()
    }

    @Test func anInterruptionIsReadFullyAndWrittenToTheDiagnosticTrack() async throws {
        let info = AudioKeeper.interruption(from: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
            AVAudioSessionInterruptionReasonKey: UInt(1),
            "AVAudioSessionInterruptionWasSuspendedKey": true])
        #expect(info == .init(began: false, reason: "appWasSuspended", shouldResume: true, wasSuspended: true))
        #expect(AudioKeeper.interruption(from: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            == .init(began: true, reason: "none", shouldResume: false, wasSuspended: false))
        #expect(AudioKeeper.interruption(from: nil) == nil && AudioKeeper.interruption(from: [:]) == nil)

        let audio = AudioKeeper()
        var lines: [String] = []
        audio.onDiag = { lines.append("\($0) \($1)") }
        try audio.start(ambience: .storyJourney, volume: 0.3)
        audio.setCallHold(true)
        audio.stopEngineForTesting()
        audio.receiveInterruption(userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                             AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        audio.setCallHold(false)
        audio.setVolume(0.3, ambience: .brownNoise)
        audio.silenceNow()
        audio.setVolume(0.3, ambience: .brownNoise)
        audio.stop()
        func has(_ prefix: String) -> Bool { lines.contains { $0.hasPrefix(prefix) } }
        #expect(has("sound start amb=story-journey level=30"), "\(lines)")
        #expect(has("sound hold on") && has("sound hold off"))
        #expect(has("audio.int ended reason=none resume=1 suspended=0"))
        #expect(has("audio.engine restart by=intEnded ok=1"))
        #expect(has("sound state engine=0 bed=") && has("sound state engine=1 bed=0 teller=0"), "\(lines)")
        #expect(has("sound mode amb=brown") && has("sound idle why=stop") && has("sound wake"))
        #expect(lines.last?.hasPrefix("sound state engine=") == true)
    }

    // MARK: the session category (B59)

    @Test func afterTheLastKeeperStopsTheCategoryIsAmbientAgainAndEffectsKeepIt() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .silence, volume: 0)
        #expect(audio.ringAlarm(file: "alarm_digital.caf", ramp: 0, maxDuration: 30) {})
        #expect(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers) == false)
        audio.stop()
        guard AudioKeeper.runningKeepers == 0 else { return }           // another suite's keeper runs: nothing to say
        #expect(AVAudioSession.sharedInstance().category == .ambient)
        SoundFX.play("fx_sleep")
        #expect(AVAudioSession.sharedInstance().category == .ambient)
        SoundFX.previewAlarm("alarm_digital", seconds: 30)
        SoundFX.stopPreview()
        #expect(AVAudioSession.sharedInstance().category == .ambient)
    }
}
