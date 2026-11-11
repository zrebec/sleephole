import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// 13ac-2 (B53): with the media volume at 0 our alarm "rings" but nobody hears it, so the backup notifications and the
/// system alarm must stay as they were armed. The tests drive the real AppModel (no audio) through `setMediaVolume`.
extension SystemAlarmTests {
    /// Every diagnostic line of the running night as "k v" (stored + waiting).
    @MainActor
    func diagLines(_ h: Harness) -> [String] {
        let stored = h.model.active?.diagLog.entries ?? []
        return (stored + h.model.diag.buffer).map { "\($0.k) \($0.v ?? "")" }
    }

    @Test func atMediaVolumeZeroOurAlarmLeavesTheBackupsAndTheSystemAlarmWhereTheyWere() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.model.setMediaVolume(0)
        h.clock.now = wake; h.model.refresh()
        h.model.alarmSoundStarted()
        h.clock.now = wake + 20
        h.model.alarmSoundStarted()                                         // the per-second retry
        await h.model.systemAlarmIdle()
        #expect(h.model.backupNotificationsOn)
        #expect(h.model.systemAlarmAt == wake + 30)
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile)])
        let lines = diagLines(h)
        #expect(lines.filter { $0 == "notif backup kept why=inaudible" }.count == 1)
        #expect(lines.filter { $0 == "sysalarm keep why=inaudible" }.count == 1)
    }

    @Test func aDueSystemAlarmIsNeitherCancelledNorMovedWhileOursCannotBeHeard() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.model.setMediaVolume(0)
        h.clock.now = wake; h.model.refresh()
        h.model.alarmSoundStarted()
        h.clock.now = wake + 31                                             // the system alarm rings and stopped our engine
        h.model.alarmSoundStarted()
        await h.model.systemAlarmIdle()
        #expect(h.model.yieldsToDueSystemAlarm)                             // the retry does not start ours on top of it
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile)])
        #expect(h.model.systemAlarmAt == wake + 30 && h.model.backupNotificationsOn)
    }

    @Test func theRetryYieldsOnlyWhileTheSystemAlarmIsDueAndOursIsInaudible() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.model.setMediaVolume(0)
        h.clock.now = wake + 10
        #expect(!h.model.yieldsToDueSystemAlarm)                            // not due yet: ours may ring (silently)
        h.clock.now = wake + 30
        #expect(h.model.yieldsToDueSystemAlarm)
        h.model.setMediaVolume(0.5)
        #expect(!h.model.yieldsToDueSystemAlarm)                            // audible: today's rules
        h.model.setMediaVolume(-1)
        #expect(!h.model.yieldsToDueSystemAlarm)                            // unknown: audible
        h.model.setMediaVolume(0.004)                                       // rounds to 0 %
        #expect(h.model.yieldsToDueSystemAlarm)
    }

    @Test func theVolumeRisingStandsTheAlarmDownExactlyOnce() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.model.setMediaVolume(0)
        h.clock.now = wake; h.model.refresh()
        h.model.alarmSoundStarted()
        await h.model.systemAlarmIdle()
        #expect(h.model.backupNotificationsOn && h.model.systemAlarmAt == wake + 30)
        h.clock.now = wake + 10
        h.model.setMediaVolume(0.5)                                         // now it can be heard
        await h.model.systemAlarmIdle()
        #expect(!h.model.backupNotificationsOn)
        #expect(h.model.systemAlarmAt == wake + 120)
        h.model.setMediaVolume(0.6)                                         // a further change does nothing more
        h.model.setMediaVolume(0.7)
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile), .schedule(wake + 120, alarmFile)])
        let lines = diagLines(h)
        #expect(lines.filter { $0 == "notif backup cancelled why=soundStarted" }.count == 1)
        #expect(lines.contains("sysalarm move at=wake+120s"))
    }

    @Test func theVolumeRisingWhileTheSystemAlarmIsDueStopsItAndSetsItBehindOurs() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.model.setMediaVolume(0)
        h.clock.now = wake; h.model.refresh()
        h.model.alarmSoundStarted()
        h.clock.now = wake + 45
        h.model.setMediaVolume(0.3)
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile), .cancel, .schedule(wake + 120, alarmFile)])
        #expect(!h.model.backupNotificationsOn && h.model.systemAlarmAt == wake + 120)
    }

    @Test func aVolumeThatWasAlwaysAudibleKeepsTodaysBehaviour() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.model.setMediaVolume(0.5)
        h.clock.now = wake; h.model.refresh()
        h.model.alarmSoundStarted()
        await h.model.systemAlarmIdle()
        #expect(!h.model.backupNotificationsOn && h.model.systemAlarmAt == wake + 120)
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile), .schedule(wake + 120, alarmFile)])
        #expect(!h.model.yieldsToDueSystemAlarm)
    }

    @Test func anUnknownReadingKeepsTodaysBehaviour() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        #expect(h.model.mediaVolume == -1)
        h.clock.now = wake; h.model.refresh()
        h.model.alarmSoundStarted()
        await h.model.systemAlarmIdle()
        #expect(!h.model.backupNotificationsOn && h.model.systemAlarmAt == wake + 120)
    }

    @Test func aLowButNotZeroVolumeStillHandsOver() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.model.setMediaVolume(0.0625)                                      // the first step: 6 %, quiet but heard
        h.clock.now = wake; h.model.refresh()
        h.model.alarmSoundStarted()
        await h.model.systemAlarmIdle()
        #expect(!h.model.backupNotificationsOn && h.model.systemAlarmAt == wake + 120)
    }

    @Test func aNapAtVolumeZeroKeepsItsBackupsToo() async {
        let h = await harness(consent: .allowed, at: date(5, 13, 30))
        h.model.refresh()
        h.model.startNap()
        await h.model.systemAlarmIdle()
        let napWake = h.model.active!.wake
        #expect(h.model.systemAlarmAt == napWake + 30)
        h.model.setMediaVolume(0)
        h.clock.now = napWake; h.model.refresh()
        h.model.alarmSoundStarted()
        await h.model.systemAlarmIdle()
        #expect(h.model.backupNotificationsOn && h.model.systemAlarmAt == napWake + 30)
    }

    @Test func theVolumeBurstBecomesOneLineWithWasAndTheEndIsWritten() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.model.setMediaVolume(0.5)
        h.model.setMediaVolume(0.4)
        h.model.setMediaVolume(0.3)
        h.model.setMediaVolume(0.25)
        #expect(!diagLines(h).contains { $0.hasPrefix("vol media=") && $0.contains("was=") })   // still inside the quiet time
        h.clock.now = wake; h.model.refresh()
        h.model.alarmSoundStarted()
        #expect(diagLines(h).contains("vol media=25 at=alarm"))
        #expect(h.model.confirm(code: "1234"))
        // the night is over: the track kept the burst as ONE line (was = the value before the burst) and the end volume
        let rec = h.model.shownResult!
        let lines = rec.diagLog.entries.map { "\($0.k) \($0.v ?? "")" }
        #expect(lines.filter { $0.hasPrefix("vol media=25 was=") }.count == 1)
        #expect(lines.contains("vol media=25 at=end"))
    }

    // MARK: a rising volume stands down only while OUR alarm really rings (review of 13ac)

    @Test func aVolumeRiseAfterOurAlarmIsOverNeverTouchesTheRingingSystemAlarm() async {
        for late in [119.0, 180.0] {
            let h = await harness(consent: .allowed, at: date(5, 12))
            await startTonight(h)
            h.model.setMediaVolume(0)
            h.clock.now = wake; h.model.refresh()
            h.model.alarmSoundStarted()                                     // ours rings, unheard: the system alarm stays
            h.clock.now = wake + late
            if late > 120 { h.model.append(.alarmStopped) }                 // ours ran out its two minutes
            h.model.setMediaVolume(0.5)                                     // a Bluetooth route, a sleepy volume press
            await h.model.systemAlarmIdle()
            #expect(h.alarm.events == [.schedule(wake + 30, alarmFile)], "late \(late)")   // no cancel: it is the only audible channel
            #expect(h.model.systemAlarmAt == wake + 30 && h.model.backupNotificationsOn)
        }
    }

    // MARK: through startAlarmSound, with the real (muted) audio

    /// A model WITH services (the real keeper, muted) and a fake system alarm; the media volume comes from `reading`.
    func servicesHarness(at now: Date) async -> Harness {
        let suite = "sleephole-handover-\(UUID().uuidString)"
        let h = Harness(container: try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self,
                                                       ScheduleChange.self, JokerRecord.self, BoxRecord.self,
                                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)),
                        clock: FakeClock(now), alarm: FakeSystemAlarm(consent: .allowed),
                        defaults: UserDefaults(suiteName: suite)!, suite: suite)
        h.model = AppModel(context: h.container.mainContext, catalog: sprites.catalog, clock: h.clock, settings: settings(),
                           servicesEnabled: true, systemAlarm: h.alarm, defaults: h.defaults)
        await h.model.systemAlarmIdle()
        h.alarm.forgetEvents()
        return h
    }

    @Test func theRetryNeverStartsOursOnTopOfADueSystemAlarmWhileOursWouldBeInaudible() async {
        let h = await servicesHarness(at: date(5, 12))
        h.model.mediaVolumeReader = { 0 }
        await startTonight(h)
        h.model.setMediaVolume(0)
        h.clock.now = wake; h.model.refresh()                               // the alarm rings (muted), unheard
        #expect(h.model.audio.isAlarmRinging && h.model.audio.isEngineRunning)
        #expect(h.model.backupNotificationsOn && h.model.systemAlarmAt == wake + 30)
        h.model.audio.stopEngineForTesting()                                // the system alarm rings and took our engine
        h.clock.now = wake + 31
        h.model.refresh()                                                   // the per-second retry
        await h.model.systemAlarmIdle()
        #expect(!h.model.audio.isEngineRunning)                             // ours did not start on top of it
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile)])        // not cancelled, not moved
        #expect(h.model.backupNotificationsOn && h.model.systemAlarmAt == wake + 30)
        // the volume comes up: the next tick rings ours and only THEN stands the system alarm down, once
        h.model.mediaVolumeReader = { 0.5 }
        h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.model.audio.isEngineRunning && h.model.audio.isAlarmRinging && h.model.audio.isAlarmPlayerPlaying)
        #expect(!h.model.backupNotificationsOn && h.model.systemAlarmAt == wake + 120)
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile), .cancel, .schedule(wake + 120, alarmFile)])
        h.model.abandonNight()
    }

    @Test func theVolumeIsReadAgainAtTheAlarmWhateverTheObserverLastSaid() async {
        let h = await servicesHarness(at: date(5, 12))
        h.model.mediaVolumeReader = { 0.4 }
        await startTonight(h)
        h.model.setMediaVolume(0.4)                                         // the last thing the observer reported …
        h.model.mediaVolumeReader = { 0 }                                   // … then the volume went to 0 with no callback
        h.clock.now = wake; h.model.refresh()
        #expect(h.model.mediaVolume == 0)
        #expect(h.model.backupNotificationsOn && h.model.systemAlarmAt == wake + 30)   // so nothing was handed over
        h.model.abandonNight()
    }

    // MARK: a call that was live at the start / a second call (review of 13ac)

    @Test func aSeededCallHoldSurvivesAnotherCallEndingAndIsReleasedWhenNoCallIsLeft() async {
        let h = await servicesHarness(at: date(5, 12))
        var live = true
        h.model.liveCallProbe = { live }
        h.model.callPollInterval = .milliseconds(50)
        await startTonight(h)                                               // started during call A
        #expect(h.model.audio.isCallHeld)
        let lines = diagLines(h)                                            // the track was open while the services started
        #expect(lines.contains("sound hold on"), "\(lines)")
        #expect(lines.contains { $0.hasPrefix("sound start amb=") }, "\(lines)")
        h.model.monitorEvent(.callStarted, at: h.clock.now)                 // call B rings …
        h.model.monitorEvent(.callEnded, at: h.clock.now)                   // … and is declined: A is still live
        #expect(h.model.audio.isCallHeld)
        live = false
        for _ in 0..<40 where h.model.audio.isCallHeld { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(!h.model.audio.isCallHeld)
        h.model.abandonNight()
    }
}
