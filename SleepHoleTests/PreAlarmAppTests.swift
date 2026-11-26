import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// W7 (build 14b1): the silent pre-alarm in Developer test nights and the Developer lab – never in real nights or naps.
/// Driven by the real AppModel with a FakeClock, a fake alarm and a counting keep-alive (see `SystemAlarmTests`).
@MainActor
struct PreAlarmAppTests {
    let base = SystemAlarmTests()
    var alarmFile: String { base.alarmFile }
    var t0: Date { base.date(5, 12) }
    /// A quick test night of 4 minutes started at `t0` wakes at t0 + 4 min.
    var wake: Date { t0 + 240 }

    func harness(consent: SystemAlarmConsent = .allowed, keepAlive: any KeepAlive = NoKeepAlive(),
                 testNights: Bool? = true, keepAliveOn: Bool? = true) async -> SystemAlarmTests.Harness {
        let h = await base.harness(consent: consent, at: t0, keepAlive: keepAlive)
        h.model.preAlarmTestNightsOverride = testNights
        h.model.preAlarmKeepAliveOverride = keepAliveOn
        return h
    }

    func startDebugNight(_ h: SystemAlarmTests.Harness, minutes: Double = 4) async {
        h.model.startTestNight(minutes: minutes, grace: 20)
        h.model.startNight()
        await h.model.systemAlarmIdle()
    }

    /// The track of the running night, or of the one just settled.
    func diagLines(_ h: SystemAlarmTests.Harness) -> [String] {
        let rec = h.model.active ?? h.model.shownResult
        let stored = rec?.diagLog.entries ?? []
        return (stored + h.model.diag.buffer).map { "\($0.k) \($0.v ?? "")" }
    }

    // MARK: scheduling

    @Test func aDebugNightSchedulesThePreAlarmOnceAtWakeMinus30s() async {
        let h = await harness()
        await startDebugNight(h)
        #expect(h.alarm.preSchedules == [wake - 30])
        #expect(h.alarm.events == [.schedulePre(wake - 30), .schedule(wake + 30, alarmFile)])   // the backup is unchanged
        #expect(h.model.preAlarmAt == wake - 30)
        #expect(diagLines(h).contains("prealarm schedule at=wake-30s ok=1"))
        h.clock.now = t0 + 100; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.preSchedules.count == 1)                                  // never scheduled twice
    }

    @Test func anEightMinuteQuickNightAlsoFiresAtWakeMinus30s() async {
        let h = await harness()
        await startDebugNight(h, minutes: 8)
        #expect(h.alarm.preSchedules == [t0 + 8 * 60 - 30])
    }

    @Test func aRealNightNeverGetsOne() async {
        let h = await harness()
        await base.startTonight(h)
        #expect(h.alarm.preSchedules.isEmpty && h.model.preAlarmAt == nil)
        #expect(h.alarm.events == [.schedule(base.wake + 30, alarmFile)])
        #expect(!diagLines(h).contains { $0.hasPrefix("prealarm") })
    }

    @Test func aCountedTestNightNeverGetsOne() async {
        let h = await harness()
        h.model.nextTestNightCounts = true
        await startDebugNight(h)
        #expect(h.model.active?.isDebug == false)
        #expect(h.alarm.preSchedules.isEmpty && h.model.preAlarmAt == nil)
    }

    @Test func aNapNeverGetsOne() async {
        let h = await base.harness(consent: .allowed, at: base.date(8, 13, 30))
        h.model.preAlarmTestNightsOverride = true
        h.model.refresh()
        h.model.startNap()
        await h.model.systemAlarmIdle()
        #expect(h.model.active?.isNap == true)
        #expect(h.alarm.preSchedules.isEmpty && h.model.preAlarmAt == nil)
    }

    @Test func theToggleOffMeansNone() async {
        let h = await harness(testNights: false)
        await startDebugNight(h)
        #expect(h.alarm.preSchedules.isEmpty && h.model.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm skip why=off"))
    }

    @Test func underTestTheTogglesDefaultToOff() async {
        let h = await harness(testNights: nil, keepAliveOn: nil)               // no override: the UserDefaults read is skipped under test
        #expect(!h.model.preAlarmTestNightsOn && !h.model.preAlarmKeepAliveOn)
        await startDebugNight(h)
        #expect(h.alarm.preSchedules.isEmpty)
    }

    @Test(arguments: [SystemAlarmConsent.denied, .notAsked, .unavailable])
    func withoutConsentThereIsNoPreAlarmAndATestNightDoesNotAsk(consent: SystemAlarmConsent) async {
        let h = await harness(consent: consent)
        h.model.settings.usesSystemAlarm = false                                // so that nothing else asks
        await startDebugNight(h)
        #expect(h.alarm.preSchedules.isEmpty && h.alarm.requests == 0 && h.model.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm skip why=consent"))
    }

    @Test func aNightTooShortForTheLeadSkipsWithWhyLate() async {
        let h = await harness()
        h.model.startTestNight(minutes: 0.5, grace: 5)                          // wake in 30 s: wake − 30 s is not ahead
        h.model.startNight()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.preSchedules.isEmpty && h.model.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm skip why=late"))
    }

    @Test func itDoesNotDependOnTheBackupSwitch() async {
        let h = await harness()
        h.model.settings.usesSystemAlarm = false
        await startDebugNight(h)
        #expect(h.alarm.events == [.schedulePre(wake - 30)])
    }

    @Test func theBackupSwitchOffMidNightLeavesAWaitingPreAlarmAlone() async {
        let h = await harness()
        await startDebugNight(h)
        h.alarm.forgetEvents()
        h.model.setSystemAlarm(on: false)
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.cancelBackup])                              // never `.cancel`: that ends every alarm of the app
        #expect(h.model.preAlarmAt == wake - 30)
    }

    @Test func aRefusedPreAlarmLeavesNoIntentBehind() async {
        let h = await harness()
        h.alarm.accepts = false
        await startDebugNight(h)
        #expect(h.model.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm schedule at=wake-30s ok=0"))
    }

    // MARK: ending

    @Test func ourAlarmEndsItWhenAudible() async {
        let h = await harness()
        await startDebugNight(h)
        h.alarm.forgetEvents()
        h.clock.now = wake; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre])
        #expect(h.model.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm end why=ours"))
        h.clock.now = wake + 1; h.model.refresh()                               // idempotent
        await h.model.systemAlarmIdle()
        #expect(h.alarm.preEnds == 1)
    }

    @Test func ourInaudibleAlarmEndsItBeforeTheAtOnceMove() async {
        let h = await harness()
        await startDebugNight(h)
        h.model.setMediaVolume(0)
        h.alarm.forgetEvents()
        h.clock.now = wake; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre, .schedule(wake + SystemAlarmPlan.atOnce, alarmFile)])   // 13ah: after the end
    }

    @Test func movingTheBackupBehindOursNeverEndsItBeforeTheWake() async {
        let h = await harness()
        await startDebugNight(h)
        h.alarm.forgetEvents()
        h.clock.now = wake - 10; h.model.refresh()
        h.model.alarmSoundStarted()                                             // the hand-over, as if our sound had started
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(wake + 120, alarmFile)])           // moved to wake + 2 min, no .endPre, no .cancel
        #expect(h.model.preAlarmAt == wake - 30)
    }

    @Test func aTickAtOrAfterTheWakeEndsAnOrphanedPreAlarm() async {
        // a relaunched app: the alarm has fired already (the journal says so) but the memory still holds a pre-alarm
        let h = await harness()
        await startDebugNight(h)
        h.clock.now = wake; h.model.refresh()
        await h.model.systemAlarmIdle()
        SystemAlarmMemory(defaults: h.defaults).preAt = wake - 30
        h.alarm.forgetEvents()
        h.clock.now = wake + 5
        let again = base.model(h, alarm: h.alarm)                                // same store, same defaults
        await again.systemAlarmIdle()
        #expect(again.active != nil && again.active?.log.has(.alarmFired) == true)
        #expect(again.preAlarmAt == nil)
        #expect(h.alarm.events == [.endPre])
        #expect(SystemAlarmMemory(defaults: h.defaults).preAt == nil)
    }

    @Test func aRelaunchBeforeTheWakeKeepsItAndSchedulesNothingTwice() async {
        let h = await harness()
        await startDebugNight(h)
        h.alarm.forgetEvents()
        h.clock.now = t0 + 60
        let again = base.model(h, alarm: h.alarm)
        again.preAlarmTestNightsOverride = true
        await again.systemAlarmIdle()
        #expect(again.preAlarmAt == wake - 30)
        #expect(h.alarm.events.isEmpty)
    }

    @Test func confirmingEarlyEndsItAndKeepsTheSafetyAlarm() async {
        let h = await harness()
        await startDebugNight(h)
        h.alarm.forgetEvents()
        h.clock.now = wake - 20; h.model.refresh()                              // test nights open confirming at wake − 30 s
        #expect(h.model.confirm(code: "1234"))
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre, .schedule(wake, alarmFile)])        // the safety alarm at the wake time stays
        #expect(h.model.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm end why=confirmed"))
    }

    @Test func abandoningEndsIt() async {
        let h = await harness()
        await startDebugNight(h)
        h.alarm.forgetEvents()
        h.clock.now = t0 + 60
        h.model.abandonNight()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre, .cancel])
        #expect(h.model.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm end why=abandoned"))
    }

    @Test func aNightThatExpiresEndsItToo() async {
        let h = await harness()
        await startDebugNight(h)
        h.clock.now = wake + 61 * 60; h.model.refresh()                         // past confirmLateUntil: finalized as it is
        await h.model.systemAlarmIdle()
        #expect(h.model.active == nil && h.model.preAlarmAt == nil)
        #expect(h.alarm.preEnds >= 1)
    }

    @Test func launchWithNoNightClearsTheMemoryAndEndsEverything() async {
        let h = await harness()
        SystemAlarmMemory(defaults: h.defaults).preAt = t0 + 100                // left behind by a killed run
        h.alarm.forgetEvents()
        let again = base.model(h, alarm: h.alarm)
        await again.systemAlarmIdle()
        #expect(again.preAlarmAt == nil && SystemAlarmMemory(defaults: h.defaults).preAt == nil)
        #expect(h.alarm.cancels == 1)                                           // `cancel()` ends every alarm, the pre-alarm included
    }

    // MARK: the keep-alive

    @Test func theKeepAliveBeginsThreeSecondsBeforeTheFireAndEndsWhenOurSoundStarts() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka)
        await startDebugNight(h)
        h.clock.now = wake - 34; h.model.refresh()
        #expect(ka.began == 0)
        h.clock.now = wake - 33; h.model.refresh()
        #expect(ka.began == 1 && ka.open == 1 && ka.names == ["pre-alarm"])
        h.clock.now = wake - 20; h.model.refresh()
        #expect(ka.began == 1)                                                  // once
        h.clock.now = wake; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(ka.open == 1)                                                   // our sound has not started yet: still alive
        h.model.alarmSoundStarted()
        #expect(ka.open == 0 && ka.began == 1)
        #expect(diagLines(h).contains("prealarm keepalive begin"))
        #expect(diagLines(h).contains("prealarm keepalive end why=sound"))
    }

    @Test func theKeepAliveEndsAtFifteenSecondsAfterTheWakeAtTheLatest() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka)
        await startDebugNight(h)
        h.clock.now = wake - 33; h.model.refresh()
        h.clock.now = wake + 14; h.model.refresh()
        #expect(ka.open == 1)
        h.clock.now = wake + 15; h.model.refresh()
        #expect(ka.open == 0 && ka.began == 1)
    }

    @Test func anExpiredKeepAliveIsClosedAndNotBegunAgain() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka)
        await startDebugNight(h)
        h.clock.now = wake - 33; h.model.refresh()
        ka.expireLast()
        #expect(ka.open == 0)
        h.clock.now = wake - 20; h.model.refresh()
        #expect(ka.began == 1 && ka.open == 0)
        #expect(diagLines(h).contains("prealarm keepalive expired"))
    }

    @Test func theKeepAliveEndsWhenTheNightEnds() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka)
        await startDebugNight(h)
        h.clock.now = wake - 31; h.model.refresh()
        #expect(ka.open == 1)
        h.model.abandonNight()
        await h.model.systemAlarmIdle()
        #expect(ka.began == 1 && ka.open == 0)
    }

    @Test func theKeepAliveToggleOffBeginsNone() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka, keepAliveOn: false)
        await startDebugNight(h)
        h.clock.now = wake - 31; h.model.refresh()
        #expect(ka.began == 0)
        #expect(h.model.preAlarmAt == wake - 30)                                // the pre-alarm itself is still armed
    }

    @Test func aRealNightBeginsNoKeepAlive() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka)
        await base.startTonight(h)
        h.clock.now = base.wake - 31; h.model.refresh()
        #expect(ka.began == 0)
    }

    // MARK: the lab

    @Test func theLabSchedulesAndStopsOnlyThePreAlarm() async {
        let h = await base.harness(consent: .allowed, at: t0)
        #expect(h.model.labPreAlarm(after: 20))
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedulePre(t0 + 20)])
        h.model.labStopPreAlarm()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedulePre(t0 + 20), .endPre])
        #expect(h.model.preAlarmAt == nil)                                      // the lab never touches a night's intent
    }

    @Test func theLabRefusesWhileANightRunsOrWithoutConsent() async {
        let denied = await base.harness(consent: .denied, at: t0)
        #expect(!denied.model.labPreAlarm(after: 20))
        let h = await harness()
        await startDebugNight(h)
        h.alarm.forgetEvents()
        #expect(!h.model.labPreAlarm(after: 20))
        #expect(!h.model.labRealAndPreAlarm())
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.isEmpty)
    }

    @Test func realPlusPreAlarmStopSeparately() async {
        let h = await base.harness(consent: .allowed, at: t0)
        #expect(h.model.labRealAndPreAlarm())
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(t0 + 45, alarmFile), .schedulePre(t0 + 20)])
        h.model.labStopPreAlarm()                                               // only the pre-alarm: the real one stays
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.last == .endPre && h.alarm.cancels == 0)
        #expect(h.model.testAlarmAt == t0 + 45)
        h.model.labStopTestAlarmOnly()                                          // only the real one: `cancelBackup`, never `cancel`
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.last == .cancelBackup && h.alarm.cancels == 0)
        #expect(h.model.testAlarmAt == nil)
    }
}
