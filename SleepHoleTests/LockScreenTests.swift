import Foundation
import SleepCore
import SwiftData
import Testing
import UIKit
@testable import SleepHole

/// The lit-lock-screen detection (camera from the lock screen) and the "no warning after the wake time" rule.
@MainActor
struct LockScreenTests {
    @MainActor final class FakeMotion: HandMotion {
        var held = false
        var running = false
        var starts = 0, stops = 0
        func start() { running = true; starts += 1 }
        func stop() { running = false; stops += 1 }
        func isHeld() -> Bool { running && held }
        func describe() -> String { "active=\(held ? 11 : 0)/12 tilt=0.0° samples=1" }
    }

    @MainActor final class Rig {
        let monitor = LifecycleMonitor()
        let motion = FakeMotion()
        var events: [NightEventKind] = []
        var raw: [String] = []
        var active = false
        var protectedData = true
        init() {
            monitor.screenWindow = .milliseconds(150)
            monitor.unlockWindow = .milliseconds(150)
            monitor.heldWindow = .milliseconds(300)
            monitor.heldInterval = .milliseconds(50)
            monitor.motion = motion
            monitor.isAppActive = { [unowned self] in active }
            monitor.isProtectedDataAvailable = { [unowned self] in protectedData }
            monitor.onEvent = { [unowned self] k, _ in events.append(k) }
            monitor.onRaw = { [unowned self] t in raw.append(t) }
        }
    }

    func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    @Test func aLitScreenForTheWholeWindowIsUsingTheLockScreen() async {
        let r = Rig()
        r.monitor.screenChanged(blanked: false)
        await wait(0.4)
        #expect(r.events == [.screenOn, .usedLockScreen])
        r.monitor.screenChanged(blanked: true)
        #expect(r.events == [.screenOn, .usedLockScreen, .screenOff, .locked])
        #expect(r.raw.contains { $0.hasPrefix("screen on for") })
    }

    @Test func aGlanceIsFree() async {
        let r = Rig()
        r.monitor.screenChanged(blanked: false)
        await wait(0.05)
        r.monitor.screenChanged(blanked: true)
        await wait(0.3)
        #expect(r.events == [.screenOn, .screenOff])
    }

    @Test func withoutFaceIdOnlyTheFactIsLogged() async {
        let r = Rig()
        r.monitor.dataProtectionChanged(locked: true)
        r.events.removeAll()
        r.monitor.screenChanged(blanked: false)
        await wait(0.4)
        #expect(r.events == [.screenOn])
        #expect(r.raw.contains { $0.contains("recognised=false") })
    }

    @Test func dataLockedByTheNotificationWhileTheFlagStillSaysAvailableIsNoTrip() async {
        let r = Rig()
        r.protectedData = true                                    // the flag lags several seconds behind a lock
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.screenChanged(blanked: false)
        await wait(0.4)
        #expect(!r.events.contains(.usedLockScreen))
        #expect(r.raw.contains { $0.contains("protectedData=true") && $0.contains("recognised=false") })
    }

    @Test func recognisedByTheNotificationIsATrip() async {
        let r = Rig()
        r.protectedData = false                                   // the flag is no longer what decides
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.screenChanged(blanked: false)
        r.monitor.dataProtectionChanged(locked: false)            // Face ID recognised the owner
        await wait(0.4)
        #expect(r.events == [.dataLocked, .screenOn, .ownerRecognised, .usedLockScreen])
    }

    @Test func protectedDataEventsOnlyOnAChange() {
        let r = Rig()
        r.monitor.dataProtectionChanged(locked: false)            // already unlocked: nothing
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.dataProtectionChanged(locked: false)
        r.monitor.dataProtectionChanged(locked: false)            // twice in a row, as measured
        #expect(r.events == [.dataLocked, .ownerRecognised])
        #expect(r.raw.filter { $0 == "protectedDataDidBecomeAvailable" }.count == 3)
    }

    @Test func screenOnAndOffArePairedAndOnlyWhileTheAppIsNotActive() {
        let r = Rig()
        r.monitor.screenChanged(blanked: false)
        r.monitor.screenChanged(blanked: false)                   // a second "on" adds nothing
        r.monitor.screenChanged(blanked: true)
        r.monitor.screenChanged(blanked: true)                    // an "off" without an open "on" adds nothing
        #expect(r.events == [.screenOn, .screenOff])
        let a = Rig()
        a.active = true
        a.monitor.screenChanged(blanked: false)
        a.monitor.screenChanged(blanked: true)
        #expect(a.events.isEmpty)
    }

    @Test func aScreenCycleWithoutATripGivesNoLocked() {
        let r = Rig()
        r.monitor.unlockCandidate()                               // → .unlocked
        r.events.removeAll()
        r.monitor.screenChanged(blanked: false)
        r.monitor.screenChanged(blanked: true)
        #expect(r.events == [.screenOn, .screenOff])              // no trip open: no .locked
    }

    @Test func comingBackBeforeTheWindowEndsIsNothing() async {
        let r = Rig()
        r.monitor.screenChanged(blanked: false)
        await wait(0.05)
        r.active = true
        r.monitor.stop()                                          // cancels like didBecomeActive does
        await wait(0.3)
        #expect(r.events == [.screenOn])
    }

    @Test func theAppBecomingActiveInTheWindowCancelsIt() async {
        let r = Rig()
        r.monitor.start()
        r.monitor.screenChanged(blanked: false)
        await wait(0.05)
        r.active = true
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await wait(0.3)
        r.monitor.stop()
        #expect(!r.events.contains(.usedLockScreen))
    }

    @Test func aScreenOnWhileTheAppIsActiveSchedulesNothing() async {
        let r = Rig()
        r.active = true
        r.monitor.screenChanged(blanked: false)
        await wait(0.4)
        #expect(r.events.isEmpty && !r.raw.contains { $0.hasPrefix("screen on for") })
    }

    @Test func lockSignalAndScreenOffTogetherGiveOneLocked() async {
        let r = Rig()
        r.monitor.start()
        r.monitor.screenChanged(blanked: false)
        await wait(0.4)
        NotificationCenter.default.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        r.monitor.screenChanged(blanked: true)
        await wait(0.1)
        r.monitor.stop()
        #expect(r.events.filter { $0 == .locked }.count == 1)
        #expect(r.events.filter { $0 == .usedLockScreen }.count == 1)
        #expect(r.events.filter { $0 == .screenOff }.count == 1)    // (the lock signal came first here: .locked, then .screenOff)
    }

    @Test func theUnlockPathAndTheScreenPathReportOnce() async {
        let r = Rig()
        r.monitor.screenChanged(blanked: false)
        r.monitor.unlockCandidate()
        await wait(0.5)
        // both paths fire at the same moment: the lit screen reports the lock-screen trip, the unlock then reports the
        // real leave inside it (owner 2026-10-09: unlocking into another app is a leave even after lock-screen use) –
        // never two of the same kind
        #expect(r.events.filter { $0 == .usedLockScreen }.count <= 1 && r.events.filter { $0 == .leftApp }.count <= 1)
        #expect(r.events.contains { $0 == .leftApp || $0 == .usedLockScreen })
        #expect(r.events.contains(.unlocked))
        // the other way round: the unlock path first, then a screen cycle
        let r2 = Rig()
        r2.monitor.unlockCandidate()
        await wait(0.3)
        r2.monitor.screenChanged(blanked: false)
        await wait(0.3)
        #expect(r2.events.filter { $0 == .leftApp || $0 == .usedLockScreen }.count == 1)
    }

    @Test func whenAlreadyAwayTheScreenAddsNoLeftApp() async {
        let r = Rig()
        r.monitor.unlockCandidate()                               // → .unlocked, then a trip after the window
        await wait(0.3)
        r.monitor.screenChanged(blanked: false)
        await wait(0.3)
        r.monitor.screenChanged(blanked: true)
        #expect(r.events.filter { $0 == .leftApp || $0 == .usedLockScreen }.count == 1)
        #expect(r.events.filter { $0 == .locked }.count == 1)    // the screen going off ends the trip, once
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
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
            rig.monitor.screenChanged(blanked: true)
            return graceEnds
        }
        /// Step 4: the owner wakes the lock screen at `clock.now + 10` and Face ID recognises him (or not).
        func wakeLockScreen(recognised: Bool) -> Date {
            clock.now += 10
            let t = clock.now
            rig.monitor.screenChanged(blanked: false)
            if recognised { rig.monitor.dataProtectionChanged(locked: false) }
            return t
        }
        /// Step 7: back in the app at `at`.
        func comeBack(at: Date) {
            clock.now = at
            rig.monitor.unlockCandidate()
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
        s.rig.monitor.screenChanged(blanked: true)
        #expect(s.model.nudgesSent == 0)
        #expect(s.model.collapsedAt == nil)
        let t = s.wakeLockScreen(recognised: true)                          // 4
        s.clock.now = t + s.window                                          // 5
        await wait(0.4)
        #expect(s.kinds.contains(.usedLockScreen))
        let secondsToWarning = 8.0, promised = 10, warningToCollapse = 13.0  // 6
        #expect(s.window == secondsToWarning)
        #expect(s.model.nudgesSent == 1)
        #expect(s.model.lastWarning == .lockScreen)
        #expect(s.model.lastNudgeSeconds == promised)
        #expect(s.model.collapsedAt == t + secondsToWarning + warningToCollapse)   // T + 21
        #expect(s.model.collapsedAt!.timeIntervalSince(t + secondsToWarning) >= Double(promised))
        s.comeBack(at: t + 25)                                              // 7
        #expect(s.model.collapsedAt == t + 21)                              // 8
        #expect(s.model.collapsedAt! < s.clock.now)
        s.clock.now = s.t0 + 4 * 60; s.model.refresh()
        #expect(s.model.confirm(code: "1234"))
        #expect(s.model.shownResult?.outcome == .ruins)
    }

    @Test(arguments: [(20.5, false), (21.5, true)])
    func theRealLimitIs21SecondsAfterTheScreenLights(returnAfter: Double, collapses: Bool) async {
        let s = Scene(self)
        _ = s.startAndLock()
        let t = s.wakeLockScreen(recognised: true)
        s.clock.now = t + s.window
        await wait(0.4)
        s.comeBack(at: t + returnAfter)
        #expect((s.model.collapsedAt != nil) == collapses)
        if collapses { #expect(s.model.collapsedAt == t + 21) }
    }

    @Test func faceIdRecognisingTheOwnerAfterTheWindowStartsTheTripAtTheRecognition() async {
        let s = Scene(self)
        _ = s.startAndLock()
        let t = s.wakeLockScreen(recognised: false)                         // lit, Face ID has not seen him
        s.clock.now = t + s.window
        await wait(0.4)
        #expect(s.kinds == [.dataLocked, .screenOn])                        // a lit screen alone is only logged
        s.clock.now = t + 20
        s.rig.monitor.dataProtectionChanged(locked: false)                  // recognised later (tap on "Share")
        #expect(s.kinds == [.dataLocked, .screenOn, .ownerRecognised, .usedLockScreen])
        #expect(s.model.nudgesSent == 1 && s.model.lastWarning == .lockScreen)
        #expect(s.model.collapsedAt == t + 20 + 13)                         // staying on collapses the building
        s.clock.now = t + 40
        s.comeBack(at: t + 40)
        #expect(s.model.collapsedAt == t + 33)
    }

    @Test func aRecognitionInsideTheWindowGivesExactlyOneTrip() async {
        let r = Rig()
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.screenChanged(blanked: false)
        r.monitor.dataProtectionChanged(locked: false)
        await wait(0.4)
        #expect(r.events.filter { $0 == .usedLockScreen }.count == 1)
    }

    @Test func aRecognitionAfterTheScreenWentOffIsNothing() async {
        let r = Rig()
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.screenChanged(blanked: false)
        await wait(0.4)
        r.monitor.screenChanged(blanked: true)
        r.monitor.dataProtectionChanged(locked: false)
        #expect(!r.events.contains(.usedLockScreen))
        #expect(r.events == [.dataLocked, .screenOn, .screenOff, .ownerRecognised])
    }

    // MARK: - a lit lock screen in a hand counts, recognised or not (owner 2026-10-09)

    @Test func litForTwelveSecondsInAHandWithoutFaceIdWarnsAndCollapses() async {
        let s = Scene(self)
        _ = s.startAndLock()
        s.rig.motion.held = true
        let t = s.wakeLockScreen(recognised: false)
        s.clock.now = t + 12
        await wait(0.6)
        #expect(s.kinds == [.dataLocked, .screenOn, .usedLockScreen])
        #expect(s.model.nudgesSent == 1 && s.model.lastWarning == .lockScreen)
        #expect(s.model.collapsedAt == t + 12 + 13)
        #expect(s.rig.raw.contains { $0.hasPrefix("lit 12 s") && $0.contains("held=true") })
        s.comeBack(at: t + 26)                                    // a second after the 13 s are over
        #expect(s.model.collapsedAt == t + 25 && s.model.collapsedAt! <= s.clock.now)
    }

    @Test func theScreenGoingOffInTimeSavesTheBuildingInTheHeldCase() async {
        let s = Scene(self)
        _ = s.startAndLock()
        s.rig.motion.held = true
        let t = s.wakeLockScreen(recognised: false)
        s.clock.now = t + 12
        await wait(0.6)
        s.clock.now = t + 20
        s.rig.monitor.screenChanged(blanked: true)
        s.clock.now = t + 60; s.model.refresh()
        #expect(s.model.collapsedAt == nil)
        #expect(s.kinds.suffix(2) == [.screenOff, .locked])
    }

    @Test func aLitScreenThatIsNotHeldIsNothing() async {
        let r = Rig()
        r.monitor.dataProtectionChanged(locked: true)
        r.events.removeAll()
        r.monitor.screenChanged(blanked: false)
        await wait(1.0)                                           // ~14 checks
        #expect(r.events == [.screenOn])
        let checks = r.raw.filter { $0.hasPrefix("lit 12 s") }
        #expect(checks.count >= 8 && checks.allSatisfy { $0.contains("held=false") && $0.contains("active=0/12") })   // every check is logged
        #expect(r.motion.running)                                 // still watching while the screen stays lit
    }

    @Test func pickedUpLaterWhileStillLitFiresOnceItIsHeld() async {
        let r = Rig()
        r.monitor.dataProtectionChanged(locked: true)
        r.events.removeAll()
        r.monitor.screenChanged(blanked: false)
        await wait(0.5)
        #expect(r.events == [.screenOn])
        r.motion.held = true
        await wait(0.3)
        #expect(r.events == [.screenOn, .usedLockScreen])
        await wait(0.3)
        #expect(r.events.filter { $0 == .usedLockScreen }.count == 1)
        #expect(!r.motion.running)
    }

    @Test func aPassiveWakeSwitchedOffEarlyIsNothingAndTheSensorIsStopped() async {
        let r = Rig()
        r.motion.held = true
        r.monitor.screenChanged(blanked: false)
        #expect(r.motion.running && r.motion.starts == 1)
        await wait(0.1)
        r.monitor.screenChanged(blanked: true)
        #expect(!r.motion.running)
        await wait(0.5)
        #expect(r.events == [.screenOn, .screenOff])
    }

    @Test func recognisedEarlyTheEightSecondPathFiresAndThereIsNoSecondEvent() async {
        let r = Rig()
        r.motion.held = true
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.screenChanged(blanked: false)
        r.monitor.dataProtectionChanged(locked: false)
        await wait(0.2)                                           // the 8 s path has fired (150 ms)
        #expect(r.events.filter { $0 == .usedLockScreen }.count == 1)
        #expect(!r.motion.running)                                // the trip is open: the sensor is off
        await wait(0.5)                                           // past the 12 s point
        #expect(r.events.filter { $0 == .usedLockScreen }.count == 1)
    }

    @Test func recognisedBetweenTheTwoWindowsTheLatePathFiresAndThereIsNoSecondEvent() async {
        let r = Rig()
        r.motion.held = true
        r.monitor.dataProtectionChanged(locked: true)
        r.monitor.screenChanged(blanked: false)
        await wait(0.2)                                           // after the 8 s, before the 12 s
        #expect(!r.events.contains(.usedLockScreen))
        r.monitor.dataProtectionChanged(locked: false)
        #expect(r.events.filter { $0 == .usedLockScreen }.count == 1)
        await wait(0.5)
        #expect(r.events.filter { $0 == .usedLockScreen }.count == 1)
    }

    @Test func theSensorRunsOnlyWhileTheLockScreenIsLitAndNoTripIsOpen() async {
        // not started while the app is active
        let a = Rig()
        a.active = true
        a.monitor.screenChanged(blanked: false)
        #expect(a.motion.starts == 0)
        // stopped when the app becomes active
        let b = Rig()
        b.monitor.start()
        b.monitor.screenChanged(blanked: false)
        #expect(b.motion.running)
        b.active = true
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #expect(!b.motion.running)
        b.monitor.stop()
        // stopped with the monitor
        let c = Rig()
        c.monitor.screenChanged(blanked: false)
        c.monitor.stop()
        #expect(!c.motion.running)
        await wait(0.5)
        #expect(!c.events.contains(.usedLockScreen))
        // not started while a trip is open
        let d = Rig()
        d.monitor.unlockCandidate()
        await wait(0.3)
        d.monitor.screenChanged(blanked: false)
        #expect(d.motion.starts == 0)
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
        let t = s.wakeLockScreen(recognised: true)
        s.clock.now = t + s.window
        await wait(0.4)
        await s.model.systemAlarmIdle()
        return (s, alarm, t)
    }

    @Test func theWarningRingsAsASystemAlarmWithTheAppsOwnSound() async {
        let (s, alarm, t) = await ringingScene()
        #expect(alarm.events.last == .ringWarning("alarm_alert.caf", 10))
        #expect(alarm.warningRings == 1 && alarm.warningStops == 0)
        #expect(s.model.lockWarningDeadline == t + 18)
    }

    @Test func theScreenGoingOffStopsTheWarningAndTheBuildingStands() async {
        let (s, alarm, t) = await ringingScene()
        s.clock.now = t + 12
        s.rig.monitor.screenChanged(blanked: true)
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

    @Test func ifNothingHappensTheAppStopsTheWarningAtTheDeadlineAndTheBuildingCollapsesAtThirteenSeconds() async {
        let (s, alarm, t) = await ringingScene()
        s.clock.now = t + 17; s.model.refresh()
        await s.model.systemAlarmIdle()
        #expect(alarm.warningStops == 0)
        s.clock.now = t + 18; s.model.refresh()
        await s.model.systemAlarmIdle()
        #expect(alarm.warningStops == 1)
        s.clock.now = t + 20; s.model.refresh()
        #expect(s.model.collapsedAt! > s.clock.now)                         // not yet
        s.clock.now = t + 21; s.model.refresh()
        #expect(s.model.collapsedAt == t + 21 && s.model.collapsedAt! <= s.clock.now)   // 8 + 13, as ever
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
        s.rig.monitor.screenChanged(blanked: true)
        await s.model.systemAlarmIdle()
        #expect(alarm.scheduled == [wakeAlarm!])                            // scheduled once, at the start
        #expect(!alarm.events.drop { $0 != .ringWarning("alarm_alert.caf", 10) }.contains(.cancel))
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
        #expect(alarm.events.contains(.ringWarning("alarm_alert.caf", 10)))
    }

    @Test func aLockScreenWarningBeginsExactlyOneKeepAliveThatEndsWhenTheScreenGoesOff() async {
        let ka = FakeKeepAlive()
        let (s, alarm, t) = await ringingScene(keepAlive: ka)
        #expect(ka.began == 1 && ka.open == 1)
        s.clock.now = t + 12
        s.rig.monitor.screenChanged(blanked: true)
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
        s.clock.now = t + 17; s.model.refresh()
        await s.model.systemAlarmIdle()
        #expect(ka.open == 1 && alarm.warningStops == 0)
        s.clock.now = t + 18; s.model.refresh()
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
        #expect(at(grace + 60) == grace + 60 + 13)                          // a full trip
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
        #expect(m.collapseNoticeAt == g + 73)
        m.append(.returned, at: g + 66)
        #expect(m.collapseNoticeAt == nil)
        m.append(.usedLockScreen, at: g + 100)
        #expect(m.collapseNoticeAt == g + 113)
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
        #expect(m.collapseNoticeAt == ends + 13)
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
        #expect(m.collapseNoticeAt == ends + 13)
        m.append(.returned, at: g + 100)                                     // back inside the pause
        #expect(m.collapseNoticeAt == nil)
        m.append(.leftApp, at: g + 200)                                      // leaves inside the pause
        #expect(m.collapseNoticeAt == ends + 13)
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
        #expect(m.collapseNoticeAt == g + 73)                                // unchanged: nothing new was set
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
            #expect(m.lockWarningDeadline == t + 10, "\(consent)")         // the app's own sound would play for 10 s
            clock.now = t + 10; m.refresh()
            #expect(m.lockWarningDeadline == nil && alarm.warningStops == 0, "\(consent)")
        }
    }
}

// MARK: - Gentle mode (owner 2026-10-09, "care instead of enforcement"): Strict mode is off

extension LockScreenTests {
    /// A quick night in gentle mode, locked; the lock screen is lit from T and held for 12 s (or Face ID done at 8 s).
    func gentleScene(recognised: Bool, alarm: FakeSystemAlarm, keepAlive: any KeepAlive = NoKeepAlive()) async -> (Scene, Date) {
        let s = Scene(self, alarm: alarm, keepAlive: keepAlive, strict: false)
        _ = s.startAndLock()
        let t = s.wakeLockScreen(recognised: recognised)
        if recognised {
            s.clock.now = t + s.window
            await wait(0.4)
        } else {
            s.rig.motion.held = true
            s.clock.now = t + 12
            await wait(0.9)
        }
        await s.model.systemAlarmIdle()
        return (s, t)
    }

    @Test func gentleTwelveSecondsHeldIsLoggedAndMetWithOneCalmReminder() async {
        let alarm = FakeSystemAlarm(consent: .allowed), ka = FakeKeepAlive()
        let (s, t) = await gentleScene(recognised: false, alarm: alarm, keepAlive: ka)
        #expect(s.kinds.contains(.usedLockScreen))
        #expect(alarm.warningRings == 0 && ka.began == 0)
        #expect(s.model.nudgesSent == 0 && s.model.lastWarning == nil && s.model.lockWarningDeadline == nil)
        #expect(s.model.lockRemindersSent == 1)
        #expect(s.model.collapsedAt == nil && s.model.collapseNoticeAt == nil)
        s.clock.now = t + 72; s.model.refresh()                             // a minute later
        #expect(s.model.collapsedAt == nil)
        #expect(s.model.awayBudgetUse(at: s.clock.now)?.used == 0)
        #expect(s.model.awayBudgetState(at: s.clock.now) == .fine)
        s.rig.monitor.stop()
    }

    @Test func gentleFaceIDEightSecondPathIsTheSame() async {
        let alarm = FakeSystemAlarm(consent: .allowed), ka = FakeKeepAlive()
        let (s, t) = await gentleScene(recognised: true, alarm: alarm, keepAlive: ka)
        #expect(s.kinds.contains(.usedLockScreen))
        #expect(alarm.warningRings == 0 && ka.began == 0 && s.model.nudgesSent == 0)
        #expect(s.model.lockRemindersSent == 1 && s.model.collapseNoticeAt == nil)
        s.clock.now = t + 60; s.model.refresh()
        #expect(s.model.collapsedAt == nil)
        // the screen goes off: the trip ends, the building stands, the night is complete at the wake-up
        s.rig.monitor.screenChanged(blanked: true)
        #expect(s.model.collapsedAt == nil)
        s.rig.monitor.stop()
    }

    @Test func gentleUnlockingIntoAnotherAppIsALeaveAndCollapsesByTheNormalRule() async {
        let alarm = FakeSystemAlarm(consent: .allowed)
        let (s, t) = await gentleScene(recognised: true, alarm: alarm)
        #expect(s.model.collapsedAt == nil)
        s.clock.now = t + 20
        s.rig.monitor.unlockCandidate()                                      // unlocked, another app, never back
        await wait(0.4)
        #expect(s.kinds.contains(.leftApp))
        #expect(s.model.nudgesSent == 1 && s.model.lastWarning == .comeBack)
        #expect(s.model.collapsedAt == t + 20 + 13)
        s.rig.monitor.stop()
    }

    @Test func strictUnlockingAfterTheLockScreenTripSendsNoSecondWarning() async {
        let alarm = FakeSystemAlarm(consent: .allowed)
        let s = Scene(self, alarm: alarm)
        _ = s.startAndLock()
        let t = s.wakeLockScreen(recognised: true)
        s.clock.now = t + s.window
        await wait(0.4)
        #expect(s.model.nudgesSent == 1 && s.model.lastWarning == .lockScreen)
        s.clock.now = t + 12
        s.rig.monitor.unlockCandidate()
        await wait(0.4)
        #expect(s.kinds.contains(.leftApp))
        #expect(s.model.nudgesSent == 1 && s.model.lastWarning == .lockScreen)       // the trip was warned about already
        #expect(s.model.collapsedAt == t + 8 + 13)                                  // counted from the lock screen
        s.rig.monitor.stop()
    }

    @Test func aLeaveThatIsAlreadyReportedGetsNoSecondLeftApp() async {
        let s = Scene(self, strict: false)
        _ = s.startAndLock()
        s.clock.now += 10
        s.rig.monitor.screenChanged(blanked: false)                          // lit, not recognised
        s.rig.monitor.unlockCandidate()                                      // unlocked, another app
        await wait(0.4)
        s.rig.monitor.unlockCandidate()                                      // again: the trip is a real leave now
        await wait(0.4)
        #expect(s.kinds.filter { $0 == .leftApp }.count == 1)
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
