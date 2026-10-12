import Foundation
import notify
import SleepCore
import Testing
import UIKit
@testable import SleepHole

/// System glue: lifecycle monitor, audio keeper, notifications, shake, sounds.
@MainActor
struct ServicesTests {
    init() { AudioKeeper.muted = true }

    func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    @Test func audioReportsMapToTheirOwnJournalKinds() {
        #expect(AudioKeeper.Report.allCases.map(\.journalKind) ==
                [.audioInterrupted, .audioResumed, .audioRouteChanged, .audioServicesReset])
        #expect(Set(AudioKeeper.Report.allCases.map(\.journalKind)).count == 4)
        #expect(AudioKeeper.Report.configurationChange.rawValue == "audio configuration change")
    }

    @Test func lifecycleMonitorMapsSignalsToEvents() async {
        let monitor = LifecycleMonitor()
        var events: [NightEventKind] = []
        var raw: [String] = []
        monitor.onEvent = { kind, _ in events.append(kind) }
        monitor.onRaw = { raw.append($0) }
        monitor.start()
        monitor.start()                                            // idempotent
        let nc = NotificationCenter.default
        nc.post(name: UIApplication.willResignActiveNotification, object: nil)
        nc.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.post(name: UIApplication.didBecomeActiveNotification, object: nil)      // back before decision
        nc.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        nc.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        nc.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        nc.post(name: UIApplication.willTerminateNotification, object: nil)
        notify_post("com.apple.springboard.lockcomplete")
        notify_post("com.apple.springboard.hasBlankedScreen")
        await wait(0.3)
        // background → lock signal within the decision window → "locked"
        nc.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        notify_post("com.apple.springboard.lockcomplete")
        await wait(3.4)
        nc.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        monitor.stop()
        #expect(raw.contains { $0.hasPrefix("didEnterBackground") })
        #expect(raw.contains { $0.contains("short background ignored") })
        #expect(raw.contains { $0.contains("lockcomplete") })
        #expect(events.contains(.returned))
        #expect(raw.last == "monitor stopped")
    }

    @Test func darwinNotificationsDeliverState() async {
        var got: [String] = []
        DarwinNotifications.shared.observe(["sk.zrebec.sleephole.test"]) { name, _ in got.append(name) }
        notify_post("sk.zrebec.sleephole.test")
        await wait(0.2)
        DarwinNotifications.shared.removeAll()
        #expect(got == ["sk.zrebec.sleephole.test"])
    }

    @Test func audioKeeperRunsAndRingsSilently() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .brownNoise, volume: 0.1)
        #expect(audio.isRunning)
        audio.setVolume(0.2, ambience: .silence)
        var stopped = false
        audio.ringAlarm(file: "alarm_digital.caf", ramp: 1, maxDuration: 1.2) { stopped = true }
        #expect(audio.isAlarmRinging)
        await wait(2.5)
        #expect(stopped && !audio.isAlarmRinging)
        audio.ringAlarm(file: "missing.caf", ramp: 0, maxDuration: 1) {}
        #expect(!audio.isAlarmRinging)
        audio.stop()
        #expect(!audio.isRunning)
        NotificationCenter.default.post(name: AVAudioSessionInterruptionNotificationName, object: nil)
    }

    @Test func everyNoiseRendersAndTheSleepTimerFadesToSilence() async throws {
        let audio = AudioKeeper()
        for a in AudioKeeper.Ambience.allCases {
            try audio.start(ambience: a, volume: 0.2)
            try? await Task.sleep(for: .milliseconds(150))                 // let the render block run
            #expect(audio.isRunning)
        }
        try audio.start(ambience: .rainTent, volume: 0.2)
        audio.sleepTimer(seconds: 6, volume: 0.2)                         // exact end: 6 s (last 5 s fade)
        let end = try #require(audio.sleepSoundEndsAt)
        #expect(abs(end.timeIntervalSinceNow - 6) < 0.2)
        try? await Task.sleep(for: .seconds(0.5))
        #expect(audio.currentGain > 0.1)                                  // still full before the fade
        let deadline = Date() + 25                                        // tests share the main actor → poll
        while audio.currentGain > 0.001, Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        #expect(audio.currentGain < 0.001 && audio.isRunning)            // silent but still alive
        #expect(Date() >= end - 0.15)                                     // not (noticeably) earlier than the end
        audio.sleepTimer(seconds: nil, volume: 0.2)                       // all night: no end
        #expect(audio.sleepSoundEndsAt == nil && audio.currentGain > 0.1)
        audio.silenceNow()
        #expect(audio.currentGain == 0)
        audio.stop()
    }

    @Test func rainLoopsPlayThroughThePlayerAndObeyTheTimer() async throws {
        let audio = AudioKeeper()
        try audio.start(ambience: .rainWindow, volume: 0.3)
        #expect(audio.isLoopPlaying && audio.currentGain == 0.3)
        audio.setVolume(0.3, ambience: .rainTent)                         // switch loop → other loop
        #expect(audio.isLoopPlaying && audio.currentMode == .rainTent)
        audio.setVolume(0.3, ambience: .brownNoise)                       // loop → generator
        #expect(!audio.isLoopPlaying && audio.currentGain == 0.3)
        audio.setVolume(0.3, ambience: .rainTent)
        audio.silenceNow()
        #expect(audio.currentGain == 0 && audio.isRunning)
        audio.stop()
        #expect(!audio.isLoopPlaying)
        for a in AudioKeeper.Ambience.allCases where a.loopFile != nil {
            #expect(Bundle.main.url(forResource: a.loopFile, withExtension: nil) != nil)
        }
    }

    /// Owner bug 2026-09-30: after starting a nap no sleep sound could be played – the Settings preview
    /// deactivated the shared audio session under the running night, and a stopped engine never restarted.
    @Test func aStoppedEngineStartsAgainAndThePreviewNeverSilencesTheNight() throws {
        let night = AudioKeeper()
        try night.start(ambience: .silence, volume: 0.2)
        let running = AudioKeeper.runningKeepers
        let preview = SoundPreview()
        preview.play(.brownNoise, volume: 0.2, seconds: nil)
        #expect(AudioKeeper.runningKeepers == running + 1)
        preview.stop()
        #expect(AudioKeeper.runningKeepers == running && night.isEngineRunning)
        night.stopEngineForTesting()                                      // what iOS does on a route change
        #expect(!night.isEngineRunning)
        night.setVolume(0.2, ambience: .rainWindow)                       // choosing a sound starts it again
        #expect(night.isEngineRunning && night.isLoopPlaying && night.currentGain == 0.2)
        night.stopEngineForTesting()
        night.sleepTimer(seconds: 60, volume: 0.2)
        #expect(night.isEngineRunning && night.isLoopPlaying)
        night.stop()
        #expect(!night.ensureRunning())                                   // a stopped keeper stays stopped
    }

    /// Owner bug 2026-09-30: white → pink did not switch and Stop did not stop.
    @Test func soundPreviewSwitchesLiveAndStops() async {
        let p = SoundPreview()
        p.switchTo(.pinkNoise, volume: 0.2)                      // nothing playing → nothing starts
        #expect(p.playing == nil && !p.isRunning)
        p.play(.whiteNoise, volume: 0.2, seconds: 15 * 60)
        #expect(p.playing == .whiteNoise && p.mode == .whiteNoise && p.isRunning)
        #expect(abs((p.endsAt ?? .distantPast).timeIntervalSinceNow - 900) < 1)       // plays 15 min, not 10 s
        p.switchTo(.pinkNoise, volume: 0.2)
        #expect(p.playing == .pinkNoise && p.mode == .pinkNoise && p.isRunning)
        p.setVolume(0.3)
        #expect(abs(p.gain - 0.3) < 0.001)
        p.stop()
        #expect(p.playing == nil && !p.isRunning)
        p.play(.rainTent, volume: 0.2, seconds: nil)                  // "Celú noc": until ■
        #expect(p.endsAt == nil && p.playing == .rainTent)
        p.switchTo(.silence, volume: 0.2)                         // silence = stop
        #expect(p.playing == nil && !p.isRunning)
        p.play(.silence, volume: 0.2, seconds: 60)                // nothing to play
        #expect(p.playing == nil)
        p.play(.brownNoise, volume: 0.2, seconds: 0.3)            // stops by itself
        let deadline = Date() + 10
        while p.playing != nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        #expect(p.playing == nil && !p.isRunning)
    }

    @Test func notificationsScheduleAndCancel() {
        Notifications.scheduleReminders(Schedule(reminderOffsets: [30, 0]))
        Notifications.scheduleNight(setupEnds: Date() + 300, wake: Date() + 3600, alarmFile: "alarm_gentle.caf")
        Notifications.nudge(tolerance: 10)
        Notifications.cancelNudge()
        Notifications.cancelBackupAlarm()
        Notifications.cancelNight()
        // (requestAuthorization is not called: the permission alert would block the test run forever)
    }

    @Test func reminderTriggersAreDailyWithoutQuietAndWeeklyWithoutTonightWithIt() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Bratislava")!
        func at(_ d: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))! }
        let sched = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30), reminderOffsets: [30])
        let daily = Notifications.reminderTriggers(schedule: sched, offset: 30, quietUntil: nil, calendar: cal)
        #expect(daily.count == 1 && daily[0].suffix == "")
        #expect(daily[0].components.hour == 22 && daily[0].components.minute == 0 && daily[0].components.weekday == nil)
        // Monday 2026-10-05 is tonight: six weekly triggers, none on Monday (weekday 2)
        let weekly = Notifications.reminderTriggers(schedule: sched, offset: 30, quietUntil: at(5, 22, 30), calendar: cal)
        #expect(weekly.map(\.suffix) == ["-w1", "-w3", "-w4", "-w5", "-w6", "-w7"])
        #expect(weekly.allSatisfy { $0.components.hour == 22 && $0.components.minute == 0 && $0.components.weekday != 2 })
        #expect(weekly.map { $0.components.weekday } == [1, 3, 4, 5, 6, 7])
        // a bedtime shortly after midnight: the reminder moment is Monday 23:45 → Monday is skipped
        let late = Schedule(bedtime: TimeOfDay(0, 15), wake: TimeOfDay(7, 0), reminderOffsets: [30])
        let l = Notifications.reminderTriggers(schedule: late, offset: 30, quietUntil: at(6, 0, 15), calendar: cal)
        #expect(l.count == 6 && l.allSatisfy { $0.components.weekday != 2 && $0.components.hour == 23 && $0.components.minute == 45 })
    }

    @Test func schedulingRemindersWithQuietDoesNotCrash() {
        Notifications.scheduleReminders(Schedule(reminderOffsets: [30]), quietUntil: Date() + 3600)
        Notifications.scheduleReminders(Schedule(reminderOffsets: [30]))
    }

    @Test func shakeAndSounds() {
        var shaken = false
        let token = NotificationCenter.default.addObserver(forName: .deviceDidShake, object: nil, queue: nil) { _ in
            shaken = true
        }
        UIWindow().motionEnded(.motionShake, with: nil)
        NotificationCenter.default.removeObserver(token)
        #expect(shaken)
        SoundFX.play("ui_confirm")
        SoundFX.play("missing")
        SoundFX.previewAlarm("alarm_gentle", seconds: 0.1)
        SoundFX.previewAlarm("missing")
        SoundFX.stopPreview()
    }
}

import AVFoundation
private let AVAudioSessionInterruptionNotificationName = AVAudioSession.interruptionNotification
