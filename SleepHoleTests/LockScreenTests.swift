import Foundation
import SleepCore
import SwiftData
import Testing
import notify
import UIKit
@testable import SleepHole

/// The documented-signals-only lock detection (owner 2026-10-14, after ITMS-90699) and the "no warning after the wake
/// time" rule.
@MainActor
struct LockScreenTests {
    @MainActor final class Rig {
        let monitor = LifecycleMonitor()
        var events: [NightEventKind] = []
        var stamps: [(NightEventKind, Date)] = []
        var raw: [String] = []
        var active = false
        var protectedData = true
        var capable = true
        init() {
            monitor.screenWindow = .milliseconds(150)
            monitor.backgroundDelay = .milliseconds(100)
            monitor.isAppActive = { [unowned self] in active }
            monitor.isProtectedDataAvailable = { [unowned self] in protectedData }
            monitor.canTellLockFromLeaving = { [unowned self] in capable }
            monitor.onEvent = { [unowned self] k, d in events.append(k); stamps.append((k, d)) }
            monitor.onRaw = { [unowned self] t in raw.append(t) }
        }
    }

    func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    /// Polls until `condition` holds (at most `timeout` s) – a loaded machine only makes the tests slower, never wrong.
    func waitUntil(_ timeout: Double = 5, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { await wait(0.02) }
    }

    func leftApps(_ r: Rig) -> [Date] { r.stamps.filter { $0.0 == .leftApp }.map(\.1) }

    // MARK: - the monitor: documented signals only

    @Test func protectedDataEventsOnlyOnAChange() {
        let r = Rig()
        r.active = true
        r.monitor.dataProtectionChanged(locked: false)            // already unlocked: nothing
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.dataProtectionChanged(locked: false)
        r.monitor.dataProtectionChanged(locked: false)            // twice in a row, as measured
        #expect(r.events == [.dataLocked, .ownerRecognised])
        #expect(r.raw.filter { $0 == "protectedDataDidBecomeAvailable" }.count == 3)
    }

    @Test func backgroundWithADataLockWithinTwoAndAHalfSecondsIsLocked() async {
        let r = Rig()
        r.monitor.didEnterBackground()
        r.monitor.dataProtectionChanged(locked: true)
        await waitUntil { r.events.contains(.locked) }
        await wait(0.2)
        #expect(r.events == [.dataLocked, .locked])
        #expect(leftApps(r).isEmpty)
    }

    @Test func aPlainBackgroundIsOneLeftAppStampedAtTheBackgroundMoment() async {
        let r = Rig()
        r.monitor.backgroundDelay = .milliseconds(800)
        let t0 = Date()
        r.monitor.didEnterBackground()
        await waitUntil { !leftApps(r).isEmpty }
        await wait(0.3)
        let l = leftApps(r)
        #expect(l.count == 1 && abs((l.first ?? .distantPast).timeIntervalSince(t0)) < 0.4)   // not the 0.8 s later
    }

    @Test func aBackgroundThatIsActiveAgainAtTheDecisionIsNothing() async {
        let r = Rig()
        r.monitor.didEnterBackground()
        r.active = true
        await wait(0.4)
        #expect(leftApps(r).isEmpty && r.events.isEmpty)
    }

    @Test func aPhoneWithoutPasscodeOrFaceIdNeverCountsABackgroundAsLeaving() async {
        let r = Rig()
        r.capable = false
        r.monitor.didEnterBackground()
        await wait(0.5)
        #expect(leftApps(r).isEmpty && r.events.isEmpty)
        #expect(r.raw.contains { $0.contains("cannot tell a lock from leaving") })
    }

    @Test func dataAvailableWhileInactiveFor8SecondsIsUsingTheLockScreenOnce() async {
        let r = Rig()
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.dataProtectionChanged(locked: false)            // recognised
        r.monitor.dataProtectionChanged(locked: false)            // sometimes twice
        await waitUntil { r.events.contains(.usedLockScreen) }
        await wait(0.4)
        #expect(r.events == [.dataLocked, .ownerRecognised, .usedLockScreen])
        #expect(leftApps(r).isEmpty)
    }

    @Test func lockedAgainBeforeTheWindowEndsIsNothing() async {
        let r = Rig()
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.dataProtectionChanged(locked: false)
        await wait(0.05)
        r.monitor.dataProtectionChanged(locked: true)             // a glance, then the screen went off
        await wait(0.5)
        #expect(r.events == [.dataLocked, .ownerRecognised, .dataLocked])
    }

    @Test func theAppBecomingActiveInTheWindowCancelsIt() async {
        let r = Rig()
        r.monitor.start()
        defer { r.monitor.stop() }
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.dataProtectionChanged(locked: false)
        r.active = true
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await wait(0.5)
        #expect(!r.events.contains(.usedLockScreen))
    }

    @Test func recognisedWhileTheAppIsActiveStartsNoWindow() async {
        let r = Rig()
        r.active = true
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.dataProtectionChanged(locked: false)
        await wait(0.5)
        #expect(!r.events.contains(.usedLockScreen))
    }

    @Test func noSecondTripWhileOneIsOpen() async {
        let r = Rig()
        r.monitor.didEnterBackground()
        await waitUntil { !leftApps(r).isEmpty }                  // a real leave is open
        r.monitor.dataProtectionChanged(locked: false)            // (data was available already: no change)
        r.monitor.dataProtectionChanged(locked: true)             // lock ends the trip
        r.monitor.dataProtectionChanged(locked: false)            // recognised: a window, a new trip
        await waitUntil { r.events.contains(.usedLockScreen) }
        #expect(leftApps(r).count == 1)
        #expect(r.events.filter { $0 == .usedLockScreen }.count == 1)
        #expect(r.events.contains(.locked))
    }

    @Test func aLockScreenTripFollowedByARealBackgroundStillReportsTheLeave() async {
        let r = Rig()
        r.protectedData = false                                   // the phone starts locked: no lock signal is recorded
        r.monitor.start()
        defer { r.monitor.stop() }
        r.monitor.dataProtectionChanged(locked: false)
        await waitUntil { r.events.contains(.usedLockScreen) }
        r.monitor.didEnterBackground()
        await waitUntil { r.events.contains(.leftApp) }
        await wait(0.3)
        #expect(r.events.filter { $0 == .usedLockScreen }.count == 1 && r.events.filter { $0 == .leftApp }.count == 1)
    }

    @Test func theUndocumentedLockNotificationsAreNotObserved() async {
        // the old Darwin names must not drive the monitor any more (ITMS-90699)
        let r = Rig()
        r.monitor.start()
        defer { r.monitor.stop() }
        notify_post("com.apple.springboard.lockcomplete")
        notify_post("com.apple.springboard.hasBlankedScreen")
        await wait(0.3)
        #expect(!r.raw.contains { $0.contains("darwin") })
    }

    // MARK: - the return is counted at willEnterForeground (build 9a)

    @Test func returnIsCountedAtWillEnterForegroundAndNotTwice() async {
        let r = Rig()
        r.monitor.didEnterBackground()
        await waitUntil { r.events.contains(.leftApp) }
        let before = Date()
        r.active = true
        r.monitor.willEnterForeground()
        #expect(r.events.filter { $0 == .returned }.count == 1)
        #expect(r.stamps.last(where: { $0.0 == .returned })!.1 >= before)
        r.monitor.didBecomeActive()                                  // ~0.8 s later: nothing more
        #expect(r.events.filter { $0 == .returned }.count == 1)
    }

    @Test func willEnterForegroundBeforeTheDecisionEmitsNothing() async {
        let r = Rig()
        r.monitor.backgroundDelay = .seconds(5)
        r.monitor.didEnterBackground()
        r.active = true
        r.monitor.willEnterForeground()
        r.monitor.didBecomeActive()
        #expect(r.events.isEmpty)
        #expect(r.raw.contains("(short background ignored)"))
    }

    @Test func didBecomeActiveAloneStillReturns() {
        let r = Rig()
        r.monitor.didBecomeActive()
        #expect(r.events == [.returned])
    }

    @Test func aLockScreenTripEndsAtWillEnterForeground() async {
        let r = Rig()
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.dataProtectionChanged(locked: false)
        await waitUntil { r.events.contains(.usedLockScreen) }
        r.active = true
        r.monitor.willEnterForeground()
        #expect(r.events.last == .returned)
        r.monitor.didBecomeActive()
        #expect(r.events.filter { $0 == .returned }.count == 1)
    }

    // MARK: - B26: nothing from the lock screen counts at or after the alarm

    @Test func lockScreenUseAtOrAfterTheWakeTimeIsNotStored() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let wake = date(6, 6, 30)
        m.append(.usedLockScreen, at: wake + 5)
        #expect(m.active?.log.events.contains { $0.kind == .usedLockScreen } == false)
        #expect(m.nudgesSent == 0 && m.lastWarning == nil)
        m.append(.usedLockScreen, at: wake - 120)                    // shortly before: still a trip
        #expect(m.active?.log.events.contains { $0.kind == .usedLockScreen } == true)
        #expect(m.nudgesSent == 1 && m.lastWarning == .lockScreen)
    }

    // MARK: - AppModel: no warning after the wake time

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    /// `strict`: Strict mode (owner 2026-10-09). The tests written before it describe the strict behaviour, so the
    /// helper starts strict by default; the gentle tests pass `strict: false` (the app's own default).
    func model(at now: Date, alarm: any SystemAlarm = NoSystemAlarm(),
               keepAlive: any KeepAlive = NoKeepAlive(), strict: Bool = true) -> (AppModel, FakeClock) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(now)
        var s = AppSettings()
        s.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        s.wakeCode = "1234"
        s.strictMode = strict
        let m = AppModel(context: c.mainContext, catalog: SpriteLibrary.loadFromBundle().catalog!, clock: clock,
                         settings: s, servicesEnabled: false, systemAlarm: alarm, keepAlive: keepAlive)
        Self.kept.append(c)
        return (m, clock)
    }
    static var kept: [ModelContainer] = []

    @Test func noComeBackWarningAtOrAfterTheWakeTime() {
        let (m, clock) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let wake = date(6, 6, 30)
        m.append(.leftApp, at: wake - 20 * 60)
        #expect(m.nudgesSent == 1)
        m.append(.returned, at: wake - 19 * 60)
        m.append(.leftApp, at: wake)
        #expect(m.nudgesSent == 1)
        m.append(.leftApp, at: wake + 60)
        #expect(m.nudgesSent == 1)
        _ = clock
    }

    // MARK: - AppModel: the lock-screen warning

    @Test func usedLockScreenSendsTheLockScreenWarningAndCounts() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let wake = date(6, 6, 30)
        m.append(.usedLockScreen, at: wake - 120 * 60)
        #expect(m.nudgesSent == 1 && m.lastWarning == .lockScreen)
        m.append(.screenOff, at: wake - 120 * 60 + 5)
        m.append(.locked, at: wake - 120 * 60 + 6)
        m.append(.leftApp, at: wake - 60 * 60)
        #expect(m.nudgesSent == 2 && m.lastWarning == .comeBack)
        m.append(.returned, at: wake - 60 * 60 + 5)
    }

    @Test func noLockScreenWarningInAPauseOrAtTheWakeTime() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let wake = date(6, 6, 30)
        m.append(.pauseStarted, at: wake - 180 * 60)
        m.append(.usedLockScreen, at: wake - 180 * 60 + 60)
        #expect(m.nudgesSent == 0 && m.lastWarning == nil)
        m.append(.locked, at: wake - 180 * 60 + 90)
        m.append(.usedLockScreen, at: wake)
        m.append(.usedLockScreen, at: wake + 60)
        #expect(m.nudgesSent == 0 && m.lastWarning == nil)
    }

    @Test func diagnosticKindsAreStoredAndSendNothing() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let t = date(6, 1)
        for k in [NightEventKind.screenOn, .screenOff, .ownerRecognised, .dataLocked] { m.append(k, at: t) }
        #expect(m.nudgesSent == 0 && m.lastWarning == nil)
        #expect(m.active?.log.events.map(\.kind).suffix(4) == [.screenOn, .screenOff, .ownerRecognised, .dataLocked])
    }

    // MARK: - The owner's quick-night scenario (2026-10-08): a video from the lock screen

    /// The real monitor wired to the real model; events are stamped with the model's fake clock.
    @MainActor final class Scene {
        let rig = Rig()
        let model: AppModel
        let clock: FakeClock
        let t0: Date
        var kinds: [NightEventKind] = []
        var window: TimeInterval { Double(LifecycleMonitor.lockScreenWindow.components.seconds) }   // 8
        init(_ t: LockScreenTests, alarm: any SystemAlarm = NoSystemAlarm(), keepAlive: any KeepAlive = NoKeepAlive(),
             strict: Bool = true) {
            t0 = t.date(5, 15)
            (model, clock) = t.model(at: t0, alarm: alarm, keepAlive: keepAlive, strict: strict)
            let (m, c) = (model, clock)
            rig.monitor.onEvent = { [weak self] kind, _ in self?.kinds.append(kind); m.append(kind, at: c.now) }
        }
        /// Steps 1–3: quick night, started, display switched off after the setup. Returns the end of the setup.
        func startAndLock() -> Date {
            model.refresh()
            model.startTestNight(minutes: 4, grace: 20)
            model.startNight()
            let graceEnds = model.graceEnds!
            clock.now = graceEnds + 5
            model.append(.locked, at: clock.now)
            rig.active = false
            rig.monitor.dataProtectionChanged(locked: true)
            return graceEnds
        }
        /// Step 4: the owner wakes the lock screen at `clock.now + 10` and Face ID recognises him (or not).
        func wakeLockScreen() -> Date {
            clock.now += 10
            let t = clock.now
            rig.monitor.dataProtectionChanged(locked: false)
            return t
        }
        /// Step 7: back in the app at `at`.
        func comeBack(at: Date) {
            clock.now = at
            rig.active = true
            model.append(.returned, at: clock.now)
            rig.monitor.stop()
        }
    }

    @Test func aVideoFromTheLockScreenFor25SecondsWarnsInTimeAndCollapses() async {
        let s = Scene(self)
        s.model.refresh()
        s.model.startTestNight(minutes: 4, grace: 20)                       // 1
        s.model.startNight()                                                // 2
        #expect(s.model.active != nil)
        #expect(s.model.graceEnds == s.t0 + 20)
        s.clock.now = s.model.graceEnds! + 5                                // 3
        s.model.append(.locked, at: s.clock.now)
        s.rig.active = false
        s.rig.monitor.dataProtectionChanged(locked: true)
        #expect(s.model.nudgesSent == 0)
        #expect(s.model.collapsedAt == nil)
        let t = s.wakeLockScreen()                          // 4
        s.clock.now = t + s.window                                          // 5
        await wait(0.4)
        #expect(s.kinds.contains(.usedLockScreen))
        let secondsToWarning = 8.0, promised = 15, warningToCollapse = 18.0  // 6
        #expect(s.window == secondsToWarning)
        #expect(s.model.nudgesSent == 1)
        #expect(s.model.lastWarning == .lockScreen)
        #expect(s.model.lastNudgeSeconds == promised)
        #expect(s.model.collapsedAt == t + secondsToWarning + warningToCollapse)   // T + 26
        #expect(s.model.collapsedAt!.timeIntervalSince(t + secondsToWarning) >= Double(promised))
        s.comeBack(at: t + 30)                                              // 7
        #expect(s.model.collapsedAt == t + 26)                              // 8
        #expect(s.model.collapsedAt! < s.clock.now)
        s.clock.now = s.t0 + 4 * 60; s.model.refresh()
        #expect(s.model.confirm(code: "1234"))
        #expect(s.model.shownResult?.outcome == .ruins)
    }

    @Test(arguments: [(25.5, false), (26.5, true)])
    func theRealLimitIs26SecondsAfterTheScreenLights(returnAfter: Double, collapses: Bool) async {
        let s = Scene(self)
        _ = s.startAndLock()
        let t = s.wakeLockScreen()
        s.clock.now = t + s.window
        await waitUntil { s.kinds.contains(.usedLockScreen) }
        await wait(0.05)
        s.comeBack(at: t + returnAfter)
        #expect((s.model.collapsedAt != nil) == collapses)
        if collapses { #expect(s.model.collapsedAt == t + 26) }
    }

    // MARK: - one notification per trip

    @Test func everyWarningSchedulesExactlyOneNotification() {
        #expect(Notifications.warningIDs == ["nudge"])               // left the app and lock screen
        #expect(Notifications.closedWarningIDs == ["closed"])        // app closed
    }

    // MARK: - the lock-screen warning rings as a system alarm and the app ends it

    /// A quick night with consent, locked, the lock screen used from T; the warning has rung (at T + 8).
    func ringingScene(keepAlive: any KeepAlive = NoKeepAlive()) async -> (Scene, FakeSystemAlarm, Date) {
        let alarm = FakeSystemAlarm(consent: .allowed)
        let s = Scene(self, alarm: alarm, keepAlive: keepAlive)
        _ = s.startAndLock()
        let t = s.wakeLockScreen()
        s.clock.now = t + s.window
        await waitUntil { s.kinds.contains(.usedLockScreen) }
        await wait(0.05)
        await s.model.systemAlarmIdle()
        return (s, alarm, t)
    }

    @Test func theWarningStillRingsAsASystemAlarmWithTheMorningAlarmSwitchedOff() async {
        let alarm = FakeSystemAlarm(consent: .allowed)
        let s = Scene(self, alarm: alarm)
        s.model.settings.usesSystemAlarm = false
        _ = s.startAndLock()
        let t = s.wakeLockScreen()
        s.clock.now = t + s.window
        await waitUntil { s.kinds.contains(.usedLockScreen) }
        await wait(0.05)
        await s.model.systemAlarmIdle()
        #expect(alarm.events.last == .ringWarning("alarm_alert.caf", 15))
        #expect(alarm.scheduled.isEmpty)                                    // no morning backup was set
    }

    @Test func theWarningRingsAsASystemAlarmWithTheAppsOwnSound() async {
        let (s, alarm, t) = await ringingScene()
        #expect(alarm.events.last == .ringWarning("alarm_alert.caf", 15))
        #expect(alarm.warningRings == 1 && alarm.warningStops == 0)
        #expect(s.model.lockWarningDeadline == t + 26)
    }

    @Test func theScreenGoingOffStopsTheWarningAndTheBuildingStands() async {
        let (s, alarm, t) = await ringingScene()
        s.clock.now = t + 12
        s.rig.monitor.dataProtectionChanged(locked: true)
        await s.model.systemAlarmIdle()
        #expect(alarm.warningStops == 1 && s.model.lockWarningDeadline == nil)
        s.clock.now = t + 40; s.model.refresh()
        #expect(s.model.collapsedAt == nil)
        #expect(alarm.warningStops == 1)
    }

    @Test func comingBackToTheAppStopsTheWarningAndTheBuildingStands() async {
        let (s, alarm, t) = await ringingScene()
        s.comeBack(at: t + 12)
        await s.model.systemAlarmIdle()
        #expect(alarm.warningStops == 1)
        #expect(s.model.collapsedAt == nil)
    }

    @Test func ifNothingHappensTheAppStopsTheWarningAtTheDeadlineAndTheBuildingCollapsesAtEighteenSeconds() async {
        let (s, alarm, t) = await ringingScene()
        s.clock.now = t + 25; s.model.refresh()
        await s.model.systemAlarmIdle()
        #expect(alarm.warningStops == 0)
        s.clock.now = t + 26; s.model.refresh()
        await s.model.systemAlarmIdle()
        #expect(alarm.warningStops == 1)
        #expect(s.model.collapsedAt == t + 26 && s.model.collapsedAt! <= s.clock.now)   // 8 + 3 + 15: the alarm rings to the collapse (B33)
        await s.model.systemAlarmIdle()
        #expect(alarm.warningStops == 1)
    }

    @Test func abandoningTheNightStopsTheWarning() async {
        let (s, alarm, _) = await ringingScene()
        s.model.abandonNight()
        await s.model.systemAlarmIdle()
        #expect(alarm.warningStops == 1)
    }

    @Test func theWarningNeverTouchesTheNightsOwnAlarm() async {
        let (s, alarm, t) = await ringingScene()
        let wakeAlarm = s.model.systemAlarmAt
        #expect(wakeAlarm != nil)
        s.clock.now = t + 12
        s.rig.monitor.dataProtectionChanged(locked: true)
        await s.model.systemAlarmIdle()
        #expect(alarm.scheduled == [wakeAlarm!])                            // scheduled once, at the start
        #expect(!alarm.events.drop { $0 != .ringWarning("alarm_alert.caf", 15) }.contains(.cancel))
        #expect(s.model.systemAlarmAt == wakeAlarm && s.model.safetyAlarmAt == nil)
    }

    @Test func noWarningAlarmAtTheWakeTimeInAPauseOrAfterACollapse() async {
        let alarm = FakeSystemAlarm(consent: .allowed)
        let (m, _) = model(at: date(5, 22, 25), alarm: alarm)
        m.refresh(); m.startNight()
        let wake = date(6, 6, 30)
        m.append(.usedLockScreen, at: wake)
        m.append(.usedLockScreen, at: wake + 60)
        m.append(.pauseStarted, at: wake - 180 * 60)
        m.append(.usedLockScreen, at: wake - 180 * 60 + 60)
        m.append(.locked, at: wake - 180 * 60 + 90)
        m.append(.leftApp, at: wake - 60 * 60)                              // never returned: collapsed 13 s later
        m.append(.usedLockScreen, at: wake - 60 * 60 + 60)
        await m.systemAlarmIdle()
        #expect(m.collapsedAt != nil)
        #expect(alarm.warningRings == 0)
        #expect(m.lockWarningDeadline == nil)
    }

    // MARK: - B28: the app stays alive while the warning rings

    @Test func theWarningCarriesTheSecondsTheOwnerHasLeft() async {
        let (_, alarm, _) = await ringingScene()
        #expect(alarm.events.contains(.ringWarning("alarm_alert.caf", 15)))
    }

    @Test func aLockScreenWarningBeginsExactlyOneKeepAliveThatEndsWhenTheScreenGoesOff() async {
        let ka = FakeKeepAlive()
        let (s, alarm, t) = await ringingScene(keepAlive: ka)
        #expect(ka.began == 1 && ka.open == 1)
        s.clock.now = t + 12
        s.rig.monitor.dataProtectionChanged(locked: true)
        await s.model.systemAlarmIdle()
        #expect(alarm.warningStops == 1 && ka.began == 1 && ka.open == 0)
    }

    @Test func theKeepAliveEndsWhenTheOwnerComesBack() async {
        let ka = FakeKeepAlive()
        let (s, _, t) = await ringingScene(keepAlive: ka)
        s.comeBack(at: t + 12)
        await s.model.systemAlarmIdle()
        #expect(ka.began == 1 && ka.open == 0)
    }

    @Test func theKeepAliveEndsAtTheDeadlineAfterTheStop() async {
        let ka = FakeKeepAlive()
        let (s, alarm, t) = await ringingScene(keepAlive: ka)
        s.clock.now = t + 25; s.model.refresh()
        await s.model.systemAlarmIdle()
        #expect(ka.open == 1 && alarm.warningStops == 0)
        s.clock.now = t + 26; s.model.refresh()
        await s.model.systemAlarmIdle()
        #expect(ka.began == 1 && ka.open == 0 && alarm.warningStops == 1)
    }

    @Test func theKeepAliveEndsWhenTheNightIsFinalised() async {
        let ka = FakeKeepAlive()
        let (s, _, _) = await ringingScene(keepAlive: ka)
        s.model.abandonNight()
        await s.model.systemAlarmIdle()
        #expect(ka.began == 1 && ka.open == 0)
    }

    @Test func everyWarningOfANightHasItsOwnKeepAliveAndEachIsEnded() async {
        let ka = FakeKeepAlive()
        let (s, _, t) = await ringingScene(keepAlive: ka)
        s.comeBack(at: t + 12)
        s.model.append(.usedLockScreen, at: t + 20)                        // a second trip (a second warning)
        await s.model.systemAlarmIdle()
        #expect(ka.began == 2 && ka.open == 1)
        s.comeBack(at: t + 24)
        await s.model.systemAlarmIdle()
        #expect(ka.began == 2 && ka.open == 0)
    }

    @Test func anExpiredKeepAliveIsEndedOnceAndNotTwice() async {
        let ka = FakeKeepAlive()
        let (s, _, t) = await ringingScene(keepAlive: ka)
        ka.expireLast()
        #expect(ka.open == 0)
        s.comeBack(at: t + 12)
        await s.model.systemAlarmIdle()
        #expect(ka.began == 1 && ka.ended.count == 1)
    }

    @Test func noKeepAliveWithoutAWarning() async {
        let ka = FakeKeepAlive()
        let alarm = FakeSystemAlarm(consent: .allowed)
        let (m, clock) = model(at: date(5, 22, 25), alarm: alarm, keepAlive: ka)
        m.refresh(); m.startNight()
        let wake = date(6, 6, 30)
        m.append(.usedLockScreen, at: date(5, 22, 28))                      // inside the setup time
        m.append(.locked, at: date(5, 22, 29))
        m.append(.pauseStarted, at: wake - 180 * 60)
        m.append(.usedLockScreen, at: wake - 180 * 60 + 60)                 // inside a pause
        m.append(.locked, at: wake - 180 * 60 + 90)
        m.append(.usedLockScreen, at: wake)                                 // at the wake time
        m.append(.locked, at: wake + 5)
        m.append(.leftApp, at: wake - 60 * 60)                              // collapses 13 s later
        m.append(.usedLockScreen, at: wake - 60 * 60 + 60)                  // after the collapse
        await m.systemAlarmIdle()
        #expect(ka.began == 0 && ka.open == 0)
    }

    // MARK: - the collapse notice (owner 2026-10-09: always)

    @Test func theCollapseNoticeTimeIsThePureDecision() {
        let (m, clock) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let rec = m.active!
        let grace = m.graceEnds!
        let log = rec.log
        let rules = rec.rules
        func at(_ d: Date, collapsed: Bool = false) -> Date? {
            Notifications.collapseNoticeTime(log: log, rules: rules, at: d, alreadyCollapsed: collapsed)
        }
        #expect(at(grace + 60) == grace + 60 + 18)                          // a full trip
        #expect(at(grace - 5) == nil)                                       // setup time
        #expect(at(grace + 60, collapsed: true) == nil)
        #expect(at(rec.wake) == nil && at(rec.wake + 60) == nil)            // wake time
        #expect(at(rec.wake - 10) == nil)                                   // the allowance would run past the wake time
        _ = clock
    }

    @Test func theCollapseNoticeIsImmediateWhenTheBudgetIsUsedUp() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let g = m.graceEnds!
        m.append(.leftApp, at: g + 60)
        m.append(.returned, at: g + 70)
        m.append(.leftApp, at: g + 100)
        m.append(.returned, at: g + 112)
        m.append(.leftApp, at: g + 200)
        m.append(.returned, at: g + 212)                                     // 34 s away: the 30 s are gone
        m.append(.leftApp, at: g + 300)
        #expect(m.collapseNoticeAt == g + 300)
        #expect(m.collapsedAt == g + 300)
    }

    @Test func theCollapseNoticeIsSetWithTheWarningAndWithdrawnWhenTheTripEndsInTime() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let g = m.graceEnds!
        m.append(.leftApp, at: g + 60)
        #expect(m.collapseNoticeAt == g + 78)
        m.append(.returned, at: g + 66)
        #expect(m.collapseNoticeAt == nil)
        m.append(.usedLockScreen, at: g + 100)
        #expect(m.collapseNoticeAt == g + 118)               // a lock-screen trip: 3 + 15 s
        m.append(.locked, at: g + 105)
        #expect(m.collapseNoticeAt == nil)
    }

    @Test func aCallOrAPauseWithdrawsTheCollapseNotice() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let g = m.graceEnds!
        m.append(.leftApp, at: g + 60)
        m.append(.callStarted, at: g + 62)
        #expect(m.collapseNoticeAt == nil)
        m.append(.callEnded, at: g + 70)
        m.append(.returned, at: g + 71)
        m.append(.pauseStarted, at: g + 100)
        m.append(.leftApp, at: g + 101)                                      // inside a pause: free, the notice waits for its end
        let ends = PausePolicy.activeUntil(m.active!.log, at: g + 102)!
        #expect(m.collapseNoticeAt == ends + 18)
    }

    @Test func theCollapseNoticeIsSetAgainWhenACallEndsWithTheOwnerStillOut() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let g = m.graceEnds!
        m.append(.leftApp, at: g + 60)
        m.append(.callStarted, at: g + 62)
        #expect(m.collapseNoticeAt == nil)
        m.append(.callEnded, at: g + 100)
        #expect(m.collapseNoticeAt != nil && m.collapseNoticeAt == m.collapsedAt)
        #expect(m.collapseNoticeAt! > g + 100)
        m.append(.returned, at: g + 105)
        #expect(m.collapseNoticeAt == nil)
        // the call ended and the owner had come back before: nothing to schedule
        m.append(.leftApp, at: g + 200)
        m.append(.callStarted, at: g + 201)
        m.append(.returned, at: g + 202)
        m.append(.callEnded, at: g + 210)
        #expect(m.collapseNoticeAt == nil)
    }

    @Test func theCollapseNoticeIsSetAgainWhenAPauseRunsOutWithTheOwnerStillOut() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let g = m.graceEnds!
        m.append(.leftApp, at: g + 60)
        m.append(.pauseStarted, at: g + 62)                                  // out when the pause starts
        let ends = PausePolicy.activeUntil(m.active!.log, at: g + 63)!
        #expect(m.collapseNoticeAt == ends + 18)
        m.append(.returned, at: g + 100)                                     // back inside the pause
        #expect(m.collapseNoticeAt == nil)
        m.append(.leftApp, at: g + 200)                                      // leaves inside the pause
        #expect(m.collapseNoticeAt == ends + 18)
        #expect(m.collapseNoticeAt == m.collapsedAt)
    }

    @Test func noCollapseNoticeAfterACollapseOrInTheSetup() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        let g = m.graceEnds!
        m.append(.leftApp, at: g - 30)
        #expect(m.collapseNoticeAt == nil)
        m.append(.returned, at: g - 20)
        m.append(.leftApp, at: g + 60)
        m.append(.leftApp, at: g + 100)                                      // already collapsed at g + 73
        #expect(m.collapseNoticeAt == g + 78)                                // unchanged: nothing new was set
    }

    @Test func finalisingTheNightClearsTheCollapseNotice() {
        let (m, _) = model(at: date(5, 22, 25))
        m.refresh(); m.startNight()
        m.append(.leftApp, at: m.graceEnds! + 60)
        m.abandonNight()
        #expect(m.collapseNoticeAt == nil)
    }

    @Test func theCollapseNoticeIsKindAndInBothLanguages() {
        #expect(Notifications.collapsedId == "collapsed" && Notifications.isTimeSensitive("collapsed"))
        let before = Lang.current
        defer { Lang.current = before }
        Lang.current = .sk
        #expect(L("😢 Tonight's building came down") == "😢 Dnešná stavba spadla")
        #expect(L("😕 Your nap was interrupted") == "😕 Odpočinok sa prerušil")
    }

    @Test func withoutConsentThereIsNoAlarmButTheWarningStillRunsItsTime() async {
        for consent in [SystemAlarmConsent.denied, .unavailable, .notAsked] {
            let alarm = FakeSystemAlarm(consent: consent)
            alarm.answer = .denied
            let (m, clock) = model(at: date(5, 22, 25), alarm: alarm)
            m.refresh(); m.startNight()
            await m.systemAlarmIdle()
            let t = date(6, 1)
            clock.now = t
            m.append(.usedLockScreen, at: t)
            await m.systemAlarmIdle()
            #expect(alarm.warningRings == 0, "\(consent)")
            #expect(m.nudgesSent == 1 && m.lastWarning == .lockScreen, "\(consent)")
            #expect(m.lockWarningDeadline == t + 18, "\(consent)")         // the app's own sound plays until the collapse moment
            clock.now = t + 18; m.refresh()
            #expect(m.lockWarningDeadline == nil && alarm.warningStops == 0, "\(consent)")
        }
    }
}

// MARK: - Gentle mode (owner 2026-10-09, "care instead of enforcement"): Strict mode is off

extension LockScreenTests {
    /// A quick night in gentle mode, locked; the user is recognised at T and the app stays away for 8 s.
    func gentleScene(alarm: FakeSystemAlarm, keepAlive: any KeepAlive = NoKeepAlive()) async -> (Scene, Date) {
        let s = Scene(self, alarm: alarm, keepAlive: keepAlive, strict: false)
        _ = s.startAndLock()
        let t = s.wakeLockScreen()
        s.clock.now = t + s.window
        await waitUntil { s.kinds.contains(.usedLockScreen) }
        await wait(0.05)
        await s.model.systemAlarmIdle()
        return (s, t)
    }

    @Test func gentleRecognisedAndAwayFor8SecondsIsOneCalmReminder() async {
        let alarm = FakeSystemAlarm(consent: .allowed), ka = FakeKeepAlive()
        let (s, t) = await gentleScene(alarm: alarm, keepAlive: ka)
        #expect(s.kinds.contains(.usedLockScreen))
        #expect(alarm.warningRings == 0 && ka.began == 0 && s.model.nudgesSent == 0)
        #expect(s.model.lockRemindersSent == 1 && s.model.collapseNoticeAt == nil)
        s.clock.now = t + 60; s.model.refresh()
        #expect(s.model.collapsedAt == nil)
        // the phone locks: the trip ends, the building stands, the night is complete at the wake-up
        s.rig.monitor.dataProtectionChanged(locked: true)
        #expect(s.model.collapsedAt == nil)
        s.rig.monitor.stop()
    }

    @Test func theModeIsFrozenWhenTheNightStarts() {
        let (g, _) = model(at: date(5, 22, 25), strict: false)
        g.refresh(); g.startNight()
        g.settings.strictMode = true                                         // switched on mid-night
        let wake = date(6, 6, 30)
        g.append(.usedLockScreen, at: wake - 120 * 60)
        #expect(g.nudgesSent == 0 && g.lockRemindersSent == 1 && g.collapsedAt == nil)
        #expect(g.active?.strictLockScreen == false)

        let (s, _) = model(at: date(5, 22, 25), strict: true)
        s.refresh(); s.startNight()
        s.settings.strictMode = false                                        // switched off mid-night
        s.append(.usedLockScreen, at: wake - 120 * 60)
        #expect(s.nudgesSent == 1 && s.lockRemindersSent == 0 && s.lastWarning == .lockScreen)
        #expect(s.active?.strictLockScreen == true)
    }

    @Test func aNapStoresTheModeToo() {
        let (m, _) = model(at: date(5, 13, 30), strict: false)
        m.refresh(); m.startNap()
        #expect(m.active?.strictLockScreen == false && m.active?.rules.lockScreenCollapses == false)
    }

    @Test func noGentleReminderInTheSetupInAPauseOrAfterTheWakeTime() {
        let (m, _) = model(at: date(5, 22, 25), strict: false)
        m.refresh(); m.startNight()
        let wake = date(6, 6, 30)
        m.append(.usedLockScreen, at: date(5, 22, 28))                       // inside the setup time
        m.append(.locked, at: date(5, 22, 29))
        m.append(.pauseStarted, at: wake - 180 * 60)
        m.append(.usedLockScreen, at: wake - 180 * 60 + 60)                  // inside a pause
        m.append(.locked, at: wake - 180 * 60 + 90)
        m.append(.usedLockScreen, at: wake + 60)                             // after the wake time
        #expect(m.lockRemindersSent == 0 && m.nudgesSent == 0)
        m.append(.locked, at: wake + 90)
    }

    @Test func aRecordWithoutTheStoredFlagIsStrict() {
        let r = NightRecord(window: NightWindow(key: NightKey(date: date(6, 6), calendar: .current), bedtime: date(5, 22, 30),
                                                wake: date(6, 6, 30)),
                            buildingId: "x", isDebug: false, setupGrace: 300)
        #expect(r.strictLockScreen == nil && r.rules.lockScreenCollapses)
        r.strictLockScreen = false
        #expect(!r.rules.lockScreenCollapses)
        r.strictLockScreen = true
        #expect(r.rules.lockScreenCollapses)
    }

    @Test func theBackupKeepsTheFlagAndAnOldBackupLoadsAsStrict() throws {
        let r = NightRecord(window: NightWindow(key: NightKey(date: date(6, 6), calendar: .current), bedtime: date(5, 22, 30),
                                                wake: date(6, 6, 30)),
                            buildingId: "x", isDebug: false, setupGrace: 300, strictLockScreen: false)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = NightRecord(backup: try d.decode(BackupFile.Night.self, from: try e.encode(r.backup)))
        #expect(back.strictLockScreen == false && !back.rules.lockScreenCollapses)
        // a file written before the field existed
        var json = try JSONSerialization.jsonObject(with: try e.encode(r.backup)) as! [String: Any]
        json.removeValue(forKey: "strictLockScreen")
        let old = NightRecord(backup: try d.decode(BackupFile.Night.self, from: try JSONSerialization.data(withJSONObject: json)))
        #expect(old.strictLockScreen == nil && old.rules.lockScreenCollapses)
        // the settings switch survives a round trip and older settings load as off
        var s = AppSettings(); s.strictMode = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(s)).strictMode)
        var o = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(AppSettings())) as! [String: Any]
        o.removeValue(forKey: "strictModeOn")
        #expect(!(try JSONDecoder().decode(AppSettings.self, from: try JSONSerialization.data(withJSONObject: o)).strictMode))
    }

    @Test func theNightDetailMarksAGentleLockScreenTripAsNotCounted() {
        let (m, _) = model(at: date(5, 22, 25), strict: false)
        m.refresh(); m.startNight()
        let wake = date(6, 6, 30)
        m.append(.usedLockScreen, at: wake - 120 * 60)
        m.append(.locked, at: wake - 120 * 60 + 300)
        let r = NightReport(log: m.active!.log, rules: m.active!.rules)
        #expect(r.nightTrips.count == 1 && r.nightTrips[0].notCounted && r.nightTrips[0].onLockScreen)
    }

    @Test func theLockReminderIsATimeSensitiveNightNotification() {
        #expect(Notifications.isTimeSensitive(Notifications.lockReminderId))
        #expect(Notifications.nightIds.contains(Notifications.lockReminderId))
    }
}
