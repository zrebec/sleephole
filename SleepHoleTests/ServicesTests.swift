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

    @Test func notificationsScheduleAndCancel() {
        Notifications.scheduleReminders(Schedule(reminderOffsets: [30, 0]))
        Notifications.scheduleNight(start: Date(), setupGrace: 300, wake: Date() + 3600, alarmFile: "alarm_gentle.caf")
        Notifications.nudge(tolerance: 10)
        Notifications.cancelNudge()
        Notifications.cancelBackupAlarm()
        Notifications.cancelNight()
        // (requestAuthorization is not called: the permission alert would block the test run forever)
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
