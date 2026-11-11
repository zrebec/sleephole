import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// 13ae (B55, B56, X1): the warnings around a phone call and at the end of the setup. The model is driven by a FakeClock;
/// the monitor by its seams. What a notification promises (the seconds, the collapse moment) must equal what
/// `NightEvaluator` decides.
@MainActor
struct CallSetupWarningTests {
    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }
    static var kept: [ModelContainer] = []

    /// Bedtime 22:30, wake 6:30; a night started at 22:25 has its setup until 22:35 (`graceEnds`).
    func model(strict: Bool = true, alarm: any SystemAlarm = NoSystemAlarm()) -> (AppModel, FakeClock, Date) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self, BoxRecord.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(date(5, 22, 25))
        var s = AppSettings()
        s.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        s.wakeCode = "1234"
        s.strictMode = strict
        let m = AppModel(context: c.mainContext, catalog: SpriteLibrary.loadFromBundle().catalog!, clock: clock,
                         settings: s, servicesEnabled: false, systemAlarm: alarm)
        Self.kept.append(c)
        m.refresh(); m.startNight()
        return (m, clock, m.graceEnds!)
    }

    func notes(_ m: AppModel) -> [String] {
        m.diag.flush()
        return (m.active?.diagLog.entries ?? []).map { "\($0.k) \($0.v ?? "")" }
    }

    // MARK: - B55: a trip that begins during a call

    @Test func aLeaveDuringACallSendsNothingUntilTheCallEnds() {
        let (m, _, g) = model()
        m.append(.callStarted, at: g + 60)
        m.append(.leftApp, at: g + 65)
        #expect(m.nudgesSent == 0 && m.collapseNoticeAt == nil && m.lockWarningDeadline == nil && m.lastWarning == nil)
        #expect(notes(m).contains("warn held why=call kind=leftApp"))
        #expect(m.collapsedAt == nil)                                      // the evaluator excuses the call
        m.append(.callEnded, at: g + 200)
        #expect(m.nudgesSent == 1 && m.lastNudgeSeconds == 15 && m.lastWarning == .comeBack)
        // the notice and the promise are what the evaluator will decide
        #expect(m.collapseNoticeAt == g + 200 + 18)
        #expect(m.collapseNoticeAt == m.collapsedAt)
        let promised: TimeInterval = m.collapseNoticeAt!.timeIntervalSince(g + 200) - m.active!.rules.noticeDelay
        #expect(promised == TimeInterval(m.lastNudgeSeconds))
        m.append(.returned, at: g + 205)
        #expect(m.collapseNoticeAt == nil && m.collapsedAt == nil)
    }

    @Test func lockScreenUseDuringACallSendsNothingUntilTheCallEndsThenWarnsInFull() async {
        let alarm = FakeSystemAlarm(consent: .allowed)
        let (m, _, g) = model(alarm: alarm)
        m.append(.callStarted, at: g + 60)
        m.append(.usedLockScreen, at: g + 70)
        await m.systemAlarmIdle()
        #expect(m.nudgesSent == 0 && m.collapseNoticeAt == nil && m.lockWarningDeadline == nil && alarm.warningRings == 0)
        m.append(.callEnded, at: g + 200)
        await m.systemAlarmIdle()
        #expect(m.nudgesSent == 1 && m.lastWarning == .lockScreen && m.lastNudgeSeconds == 15)
        #expect(alarm.events.last == .ringWarning("alarm_alert.caf", 15))
        #expect(m.collapseNoticeAt == g + 200 + 18 && m.collapseNoticeAt == m.collapsedAt)
        #expect(m.lockWarningDeadline == g + 200 + 18)
        m.append(.locked, at: g + 205)
        #expect(m.lockWarningDeadline == nil && m.collapseNoticeAt == nil)
    }

    @Test func theOwnerBackBeforeTheCallEndsGetsNoWarning() {
        let (m, _, g) = model()
        m.append(.callStarted, at: g + 60)
        m.append(.leftApp, at: g + 65)
        m.append(.returned, at: g + 100)
        m.append(.callEnded, at: g + 200)
        #expect(m.nudgesSent == 0 && m.collapseNoticeAt == nil && m.collapsedAt == nil)
    }

    @Test func aCallStartingWithAPendingNudgeAndALockWarningWithdrawsThem() async {
        let alarm = FakeSystemAlarm(consent: .allowed)
        let (m, _, g) = model(alarm: alarm)
        m.append(.usedLockScreen, at: g + 60)                              // the loud lock warning is on
        await m.systemAlarmIdle()
        #expect(m.lockWarningDeadline == g + 78 && alarm.warningRings == 1 && m.collapseNoticeAt == g + 78)
        m.append(.callStarted, at: g + 62)
        await m.systemAlarmIdle()
        #expect(m.lockWarningDeadline == nil && alarm.warningStops == 1 && m.collapseNoticeAt == nil)
        let log = notes(m)
        #expect(log.contains("warn nudge cancelled why=call") && log.contains("warn lock end why=call"))
        #expect(log.contains("notice collapse cancelled why=call"))
        // a leave before the call: the nudge is withdrawn as well
        let (n, _, h) = model()
        n.append(.leftApp, at: h + 60)
        #expect(n.nudgesSent == 1 && n.collapseNoticeAt == h + 78)
        n.append(.callStarted, at: h + 62)
        #expect(n.collapseNoticeAt == nil)
        #expect(notes(n).contains("warn nudge cancelled why=call"))
        n.append(.callEnded, at: h + 100)                                  // still out: the normal warning, in full
        #expect(n.nudgesSent == 2 && n.lastNudgeSeconds == 15 && n.collapseNoticeAt == h + 118 && n.collapseNoticeAt == n.collapsedAt)
    }

    @Test func aGentleLockScreenUseDuringACallGetsItsCalmReminderAfterTheCall() {
        let (m, _, g) = model(strict: false)
        m.append(.callStarted, at: g + 60)
        m.append(.usedLockScreen, at: g + 70)
        #expect(m.lockRemindersSent == 0)
        m.append(.callEnded, at: g + 200)
        #expect(m.lockRemindersSent == 1 && m.nudgesSent == 0 && m.lockWarningDeadline == nil && m.collapseNoticeAt == nil)
    }

    @Test func aRelaunchEndsACallInTheRuleSideState() {
        let (m, _, g) = model()
        m.append(.callStarted, at: g + 60)
        m.append(.appLaunched, at: g + 70)
        m.append(.leftApp, at: g + 80)                                     // the call is no longer open: a normal warning
        #expect(m.nudgesSent == 1)
    }

    // MARK: - B56: a trip still open when the setup ends

    @Test func aLeaveInsideTheSetupWarnsThreeSecondsAfterItsEnd() {
        let (m, clock, g) = model()
        m.append(.leftApp, at: g - 10)
        #expect(m.pendingNudgeAt == g + 3 && m.collapseNoticeAt == g + 18 && m.nudgesSent == 0)
        #expect(m.collapseNoticeAt!.timeIntervalSince(g + 3) == 15)        // "within 15s" after the warning
        m.append(.returned, at: g + 5)                                     // back (nothing fired yet)
        #expect(m.pendingNudgeAt == nil && m.collapseNoticeAt == nil)
        let log = notes(m)
        #expect(log.contains { $0.hasPrefix("warn setupEnd scheduled") && $0.contains("kind=leftApp") })
        #expect(log.contains { $0.hasPrefix("warn nudge scheduled") && $0.contains("secs=15") })
        #expect(log.contains { $0.hasPrefix("notice collapse scheduled") })
        #expect(log.contains("warn nudge cancelled why=returned") && log.contains("notice collapse cancelled why=returned"))
        _ = clock
    }

    @Test func noReturnTheWarningFiresAndTheBuildingFallsWhereTheNoticeSaid() {
        let (m, clock, g) = model()
        m.append(.leftApp, at: g - 10)
        clock.now = g + 2; m.refresh()
        #expect(m.nudgesSent == 0 && m.pendingNudgeAt == g + 3)
        clock.now = g + 4; m.refresh()
        #expect(m.nudgesSent == 1 && m.lastNudgeSeconds == 15 && m.lastWarning == .comeBack && m.pendingNudgeAt == nil)
        #expect(m.collapsedAt == g + 18 && m.collapsedAt == m.collapseNoticeAt)
        m.append(.returned, at: g + 10)                                    // back in time: the notice is withdrawn
        #expect(m.collapseNoticeAt == nil)
    }

    @Test func theSetupEndWarningUsesTheNightsStoredTolerance() {
        let (m, _, g) = model()
        m.active!.accidentalTolerance = 10                                 // a night from before build 9j
        m.append(.leftApp, at: g - 10)
        #expect(m.pendingNudgeAt == g + 3 && m.collapseNoticeAt == g + 13)
        #expect(m.setupEndWarning?.seconds == 10 && m.collapsedAt == g + 13)
    }

    @Test func lockScreenUseInsideTheSetupRingsTheStrictWarningAtTheSetupsEnd() async {
        let alarm = FakeSystemAlarm(consent: .allowed)
        let (m, clock, g) = model(alarm: alarm)
        m.append(.usedLockScreen, at: g - 10)
        await m.systemAlarmIdle()
        #expect(m.pendingNudgeAt == g + 3 && m.collapseNoticeAt == g + 18 && alarm.warningRings == 0)
        clock.now = g + 4; m.refresh()
        await m.systemAlarmIdle()
        #expect(m.lastWarning == .lockScreen && m.nudgesSent == 1)
        #expect(alarm.events.last == .ringWarning("alarm_alert.caf", 15) && m.lockWarningDeadline == g + 18)
        #expect(m.collapsedAt == g + 18)
        m.append(.locked, at: g + 8)
        await m.systemAlarmIdle()
        #expect(m.lockWarningDeadline == nil && alarm.warningStops == 1 && m.collapseNoticeAt == nil)
    }

    @Test func aGentleNightGetsTheCalmReminderInsteadOfTheStrictWarning() async {
        let alarm = FakeSystemAlarm(consent: .allowed)
        let (m, clock, g) = model(strict: false, alarm: alarm)
        m.append(.usedLockScreen, at: g - 10)
        #expect(m.pendingNudgeAt == g + 3 && m.collapseNoticeAt == nil)    // the building stays: no collapse notice
        clock.now = g + 4; m.refresh()
        await m.systemAlarmIdle()
        #expect(m.lockRemindersSent == 1 && m.nudgesSent == 0 && m.lockWarningDeadline == nil && alarm.warningRings == 0)
    }

    @Test func aClosureInsideTheSetupSchedulesTheClosedNoticeForItsEnd() {
        let (m, _, g) = model()
        m.append(.closedByOwner, at: g - 10)
        #expect(m.pendingNudgeAt == g + 3 && m.collapseNoticeAt == g + 18 && m.nudgesSent == 0)
        #expect(notes(m).contains { $0.hasPrefix("notice closed scheduled") && $0.contains("secs=15") })
    }

    @Test func aCallInsideTheSetupMovesTheWarningToTheCallsEnd() {
        let (m, _, g) = model()
        m.append(.leftApp, at: g - 30)
        #expect(m.pendingNudgeAt == g + 3)
        m.append(.callStarted, at: g - 20)                                 // the call excuses the trip
        #expect(m.pendingNudgeAt == nil && m.collapseNoticeAt == nil)
        m.append(.callEnded, at: g + 100)                                  // still out after the setup: counted from here
        #expect(m.nudgesSent == 1 && m.collapseNoticeAt == g + 118 && m.collapseNoticeAt == m.collapsedAt)
        let (n, _, h) = model()
        n.append(.leftApp, at: h - 30)
        n.append(.callStarted, at: h - 20)
        n.append(.callEnded, at: h - 5)                                    // the call ended inside the setup
        #expect(n.pendingNudgeAt == h + 3 && n.collapseNoticeAt == h + 18 && n.collapsedAt == h + 18)
    }

    @Test func theSetupReminderComesFirstAndANormalTripAfterTheSetupIsUnchanged() {
        let (m, _, g) = model()
        m.append(.leftApp, at: g - 100)
        #expect(m.setupReminderAt != nil && m.pendingNudgeAt == g + 3)     // "15s of setup left" first, the warning after
        m.append(.returned, at: g - 50)
        #expect(m.setupReminderAt == nil && m.pendingNudgeAt == nil)
        m.append(.leftApp, at: g + 60)                                     // a normal trip is unchanged
        #expect(m.nudgesSent == 1 && m.collapseNoticeAt == g + 78 && m.pendingNudgeAt == nil)
    }

    @Test func finalisingClearsWhatWasSetForTheSetupsEnd() {
        let (m, _, g) = model()
        m.append(.leftApp, at: g - 10)
        m.abandonNight()
        #expect(m.pendingNudgeAt == nil && m.collapseNoticeAt == nil)
    }


    // MARK: - the review's findings

    @Test func aSecondEventOfTheSameTripInTheSetupReplacesTheFirstWarning() {
        let (m, _, g) = model()
        m.append(.leftApp, at: g - 120)
        #expect(m.setupEndWarning?.kind == .leftApp && m.pendingNudgeAt == g + 3)
        m.append(.closedByOwner, at: g - 100)                              // swiped away while in the other app
        #expect(m.setupEndWarning?.kind == .closedByOwner && m.pendingNudgeAt == g + 3)
        #expect(notes(m).contains("warn setupEnd replaced kind=leftApp"))
        #expect(m.collapseNoticeAt == g + 18)
        // gentle: the calm reminder of a lock-screen use gives way to the nudge of the leave that follows it
        let (n, _, h) = model(strict: false)
        n.append(.usedLockScreen, at: h - 120)
        #expect(n.setupEndWarning?.gentle == true)
        n.append(.leftApp, at: h - 100)
        #expect(n.setupEndWarning?.kind == .leftApp && n.setupEndWarning?.gentle == false)
        #expect(notes(n).contains("warn setupEnd replaced kind=usedLockScreen"))
    }

    @Test func aClosureAfterALeaveHeldDuringACallPromisesWhatTheEvaluatorWillDecide() {
        // the relaunch drops the open call and counts the trip from the held leave: collapse at leave + 18 s
        let (m, _, g) = model()
        m.append(.callStarted, at: g + 60)
        m.append(.leftApp, at: g + 65)
        m.append(.closedByOwner, at: g + 120)
        var reopened = m.active!.log
        reopened.append(.appLaunched, at: g + 125)
        let decided = NightEvaluator.collapsedAt(reopened, rules: m.active!.rules)
        #expect(decided == g + 65 + 18)
        #expect(m.nudgesSent == 0)                                         // no "open it within 15 seconds": it is too late
        #expect(m.collapseNoticeAt == g + 120 && m.collapseNoticeAt! >= decided!)    // the collapse notice, at once
        // an early closure still gets a true number of seconds
        let (n, _, h) = model()
        n.append(.callStarted, at: h + 60)
        n.append(.leftApp, at: h + 65)
        n.append(.closedByOwner, at: h + 70)
        #expect(n.nudgesSent == 1 && n.lastNudgeSeconds == 10)             // 13 s to the collapse minus the 3 s notice delay
        #expect(n.collapseNoticeAt == h + 83)
        var back = n.active!.log
        back.append(.appLaunched, at: h + 75)
        #expect(NightEvaluator.collapsedAt(back, rules: n.active!.rules) == nil)    // back at 75: in time
        var late = n.active!.log
        late.append(.appLaunched, at: h + 100)
        #expect(NightEvaluator.collapsedAt(late, rules: n.active!.rules) == n.collapseNoticeAt)
    }

    @Test func aLeaveStampedInsideACallThatEndedBeforeItWasReportedCountsFromTheCallsEnd() {
        let (m, _, g) = model()
        m.append(.callStarted, at: g + 60)
        m.append(.callEnded, at: g + 100)
        m.append(.leftApp, at: g + 99)                                     // didEnterBackground one second before the hang-up
        #expect(m.nudgesSent == 1 && m.collapseNoticeAt == g + 118)
        #expect(m.collapseNoticeAt == m.collapsedAt)                       // never earlier than the evaluator
    }

    @Test func aLongCallStillHoldsTheWarningAsTheEvaluatorExcusesIt() {
        // the evaluator subtracts a call that never ended up to the wake time, so no warning and no collapse notice
        let (m, _, g) = model()
        m.append(.callStarted, at: g + 60)
        m.append(.leftApp, at: g + 60 + 5 * 3600)
        #expect(m.nudgesSent == 0)
        #expect(m.collapseNoticeAt == nil)
        #expect(m.collapsedAt == nil)
    }

    // MARK: - X1: the 8 s window of recognised use and a call

    @MainActor final class Rig {
        let monitor = LifecycleMonitor()
        var events: [NightEventKind] = []
        var active = false
        var protectedData = true
        init() {
            monitor.screenWindow = .milliseconds(150)
            monitor.backgroundDelay = .milliseconds(100)
            monitor.isAppActive = { [unowned self] in active }
            monitor.isProtectedDataAvailable = { [unowned self] in protectedData }
            monitor.canTellLockFromLeaving = { true }
            monitor.onEvent = { [unowned self] k, _ in events.append(k) }
        }
        func call(_ id: UUID, ended: Bool) {
            monitor.callChanged(CallInfo(uuid: id, isOutgoing: false, hasConnected: true, hasEnded: ended))
        }
    }
    func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
    func waitUntil(_ timeout: Double = 5, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { await wait(0.02) }
    }

    @Test func noRecognisedUseWindowRunsDuringACall() async {
        let r = Rig()
        r.monitor.start()
        r.monitor.dataProtectionChanged(locked: true)
        let id = UUID()
        r.call(id, ended: false)
        r.monitor.dataProtectionChanged(locked: false)                      // Face ID recognises him during the call
        await wait(0.5)
        #expect(!r.events.contains(.usedLockScreen))
        r.monitor.stop()
    }

    @Test func theWindowStartsAtTheCallsEndAndRunsTheSameEightSeconds() async {
        let r = Rig()
        r.monitor.start()
        r.monitor.dataProtectionChanged(locked: true)
        let id = UUID()
        r.call(id, ended: false)
        r.monitor.dataProtectionChanged(locked: false)
        await wait(0.3)                                                     // longer than the window: nothing yet
        #expect(!r.events.contains(.usedLockScreen))
        let ended = Date()
        r.call(id, ended: true)
        await waitUntil { r.events.contains(.usedLockScreen) }
        let waited = Date().timeIntervalSince(ended)
        #expect(r.events.filter { $0 == .usedLockScreen }.count == 1)
        #expect(waited >= 0.14 && waited < 0.6)                             // the same window (150 ms here), anchored at the end
        r.monitor.stop()
    }

    @Test func noWindowAfterTheCallIfThePhoneLocksWithinIt() async {
        let r = Rig()
        r.monitor.start()
        r.monitor.dataProtectionChanged(locked: true)
        let id = UUID()
        r.call(id, ended: false)
        r.monitor.dataProtectionChanged(locked: false)
        r.call(id, ended: true)
        r.monitor.dataProtectionChanged(locked: true)                       // locked again before the window ends
        await wait(0.5)
        #expect(!r.events.contains(.usedLockScreen))
        r.monitor.stop()
    }

    @Test func aWindowThatWasRunningWhenACallBeganIsVoid() async {
        let r = Rig()
        r.monitor.start()
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.dataProtectionChanged(locked: false)                      // the window starts
        let id = UUID()
        r.call(id, ended: false)                                            // a call comes in at once
        await wait(0.5)
        #expect(!r.events.contains(.usedLockScreen))
        r.monitor.stop()
    }

    @Test func aCallEndingWithTheAppInFrontStartsNoWindow() async {
        let r = Rig()
        r.active = true
        r.monitor.start()
        let id = UUID()
        r.call(id, ended: false)
        r.call(id, ended: true)
        await wait(0.4)
        #expect(!r.events.contains(.usedLockScreen))
        r.monitor.stop()
    }
}
