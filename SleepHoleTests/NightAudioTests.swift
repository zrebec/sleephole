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
}
