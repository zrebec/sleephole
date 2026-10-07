import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// A system alarm that only writes down what the app asks of it. The REAL AlarmKit one is never created in tests –
/// nothing here (or anywhere in the simulator) can ring.
@MainActor
final class FakeSystemAlarm: SystemAlarm {
    enum Event: Equatable {
        case schedule(Date, String)
        case cancel
        case requestConsent
    }

    var consent: SystemAlarmConsent
    /// What the owner "answers" when asked.
    var answer: SystemAlarmConsent = .allowed
    /// false = the system refuses to schedule.
    var accepts = true
    private(set) var events: [Event] = []

    init(consent: SystemAlarmConsent) { self.consent = consent }

    var scheduled: [Date] { events.compactMap { if case .schedule(let date, _) = $0 { date } else { nil } } }
    var sounds: [String] { events.compactMap { if case .schedule(_, let file) = $0 { file } else { nil } } }
    var cancels: Int { events.filter { $0 == .cancel }.count }
    var requests: Int { events.filter { $0 == .requestConsent }.count }
    func forgetEvents() { events = [] }

    func requestConsent() async -> SystemAlarmConsent {
        events.append(.requestConsent)
        if consent == .notAsked { consent = answer }
        return consent
    }

    func schedule(at date: Date, soundFile: String) async -> Bool {
        events.append(.schedule(date, soundFile))
        return accepts && consent == .allowed
    }

    func cancel() { events.append(.cancel) }
}

/// Phase F6b: the system alarm behind the in-app alarm, driven by the real AppModel with a FakeClock and a fake alarm.
@MainActor
struct SystemAlarmTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    /// Bedtime 22:30, wake 6:30. The tests of one harness share a store and their own UserDefaults.
    final class Harness {
        let container: ModelContainer
        let clock: FakeClock
        let alarm: FakeSystemAlarm
        let defaults: UserDefaults
        let suite: String
        var model: AppModel!

        init(container: ModelContainer, clock: FakeClock, alarm: FakeSystemAlarm, defaults: UserDefaults, suite: String) {
            self.container = container; self.clock = clock; self.alarm = alarm; self.defaults = defaults; self.suite = suite
        }

        deinit { defaults.removePersistentDomain(forName: suite) }
    }

    func settings() -> AppSettings {
        var s = AppSettings()
        s.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        s.wakeCode = "1234"
        return s
    }

    func model(_ h: Harness, alarm: FakeSystemAlarm) -> AppModel {
        AppModel(context: h.container.mainContext, catalog: sprites.catalog, clock: h.clock, settings: settings(),
                 servicesEnabled: false, systemAlarm: alarm, defaults: h.defaults)
    }

    /// A model that has settled: its launch housekeeping is done and the fake's log is empty.
    func harness(consent: SystemAlarmConsent, at now: Date) async -> Harness {
        let suite = "sleephole-systemalarm-\(UUID().uuidString)"
        let h = Harness(container: try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self,
                                                       ScheduleChange.self, JokerRecord.self,
                                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true)),
                        clock: FakeClock(now), alarm: FakeSystemAlarm(consent: consent),
                        defaults: UserDefaults(suiteName: suite)!, suite: suite)
        h.model = model(h, alarm: h.alarm)
        await h.model.systemAlarmIdle()
        h.alarm.forgetEvents()
        return h
    }

    var wake: Date { date(6, 6, 30) }
    var alarmFile: String { AppSettings.AlarmSound.gentle.fileName }

    func startTonight(_ h: Harness) async {
        h.clock.now = date(5, 22, 25); h.model.refresh()
        #expect(h.model.phase == .canStart)
        h.model.startNight()
        await h.model.systemAlarmIdle()
    }

    // MARK: start

    @Test func consentGivenAStartedNightSchedulesWakePlus30sAndKeepsTheBackupNotifications() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile)])
        #expect(h.model.systemAlarmAt == wake + 30 && h.model.safetyAlarmAt == nil)
        #expect(h.model.backupNotificationsOn)                              // belt and braces: they are always scheduled
        #expect(h.alarm.requests == 0)
    }

    @Test func withoutConsentTheBackupNotificationsStayAsToday() async {
        for consent in [SystemAlarmConsent.denied, .unavailable] {
            let h = await harness(consent: consent, at: date(5, 12))
            await startTonight(h)
            #expect(h.alarm.events.isEmpty, "\(consent)")
            #expect(h.model.systemAlarmAt == nil && h.model.backupNotificationsOn, "\(consent)")
            h.clock.now = wake + 10; h.model.refresh()
            #expect(h.model.confirm(code: "1234"))                          // the night works as ever
            await h.model.systemAlarmIdle()
            #expect(h.model.shownResult?.outcome == .complete)
        }
    }

    @Test func consentNotAskedYetIsAskedOnceAndThenTheSystemAlarmIsScheduled() async {
        let h = await harness(consent: .notAsked, at: date(5, 12))
        h.clock.now = date(5, 22, 25); h.model.refresh()
        h.model.startNight()
        #expect(h.model.backupNotificationsOn)                              // the night starts as before
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.requestConsent, .schedule(wake + 30, alarmFile)])
        #expect(h.model.backupNotificationsOn)                              // the notifications stay next to it
        // a second night does not ask again
        h.model.abandonNight(); h.model.acknowledgeResult()
        h.clock.now = date(6, 22, 25); h.model.refresh(); h.model.startNight()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.requests == 1)
        #expect(h.alarm.scheduled.last == date(7, 6, 30) + 30)
    }

    @Test func aNoToTheQuestionLeavesOnlyTheBackupNotifications() async {
        let h = await harness(consent: .notAsked, at: date(5, 12))
        h.alarm.answer = .denied
        await startTonight(h)
        #expect(h.alarm.events == [.requestConsent])
        #expect(h.model.systemAlarmAt == nil && h.model.backupNotificationsOn)
    }

    @Test func aNightThatEndedBeforeTheAnswerSchedulesNothing() async {
        let h = await harness(consent: .notAsked, at: date(5, 12))
        h.clock.now = date(5, 22, 25); h.model.refresh()
        h.model.startNight()
        h.model.abandonNight()                                              // before the answer comes in
        await h.model.systemAlarmIdle()
        #expect(h.alarm.scheduled.isEmpty && h.model.systemAlarmAt == nil)
    }

    @Test func aRefusedAlarmLeavesTheBackupNotificationsAsTheyAre() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        h.alarm.accepts = false
        await startTonight(h)
        #expect(h.model.systemAlarmAt == nil)
        #expect(h.model.backupNotificationsOn)
    }

    // MARK: our alarm rings

    @Test func whenOurAlarmRingsTheSystemAlarmMovesBehindItExactlyOnce() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.clock.now = wake; h.model.refresh()
        #expect(h.model.phase == .alarm)
        h.model.alarmSoundStarted()
        h.clock.now = wake + 20
        h.model.alarmSoundStarted()                                         // a retry of the sound: no second move
        h.model.alarmSoundStarted()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile), .schedule(wake + 120, alarmFile)])
        #expect(h.model.systemAlarmAt == wake + 120 && !h.model.backupNotificationsOn)   // ours rings: they are cancelled
    }

    /// R4 follow-up: the app was dead, the system alarm rang (or rings), the owner opens SleepHole – never two alarms at
    /// once. Ours takes over, the system alarm is stopped and set again for the moment ours stops.
    @Test func anAlarmThatIsAlreadyDueIsStoppedWhenOursStartsAndSetAgainBehindOurs() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.clock.now = wake + 45; h.model.refresh()                          // the app was dead; the system alarm rang at +30
        h.model.alarmSoundStarted()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile), .cancel, .schedule(wake + 120, alarmFile)])
        #expect(h.model.systemAlarmAt == wake + 120 && h.model.safetyAlarmAt == nil)
        h.clock.now = wake + 60
        h.model.alarmSoundStarted()                                         // a retry of the sound: no second move
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.count == 3)

        // …and the new alarm is the usual one: confirming cancels it
        #expect(h.model.confirm(code: "1234"))
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.last == .cancel && h.model.systemAlarmAt == nil)
    }

    @Test func aDueAlarmIsOnlyStoppedWhenNoTimeIsLeftOfOurTwoMinutes() async {
        for secondsAfterWake in [119.5, 125] {
            let h = await harness(consent: .allowed, at: date(5, 12))
            await startTonight(h)
            h.clock.now = wake + secondsAfterWake; h.model.refresh()
            h.model.alarmSoundStarted()
            await h.model.systemAlarmIdle()
            #expect(h.alarm.events == [.schedule(wake + 30, alarmFile), .cancel], "\(secondsAfterWake)")   // nothing to set again
            #expect(h.model.systemAlarmAt == nil)
        }
    }

    @Test func aDueAlarmRightAtItsTimeIsStoppedToo() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.clock.now = wake + 30; h.model.refresh()                          // it rings this very second
        h.model.alarmSoundStarted()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile), .cancel, .schedule(wake + 120, alarmFile)])
    }

    @Test func withoutASystemAlarmNothingIsScheduledWhenOursStarts() async {
        let d = await harness(consent: .denied, at: date(5, 12))
        await startTonight(d)
        d.clock.now = wake; d.model.refresh()
        d.model.alarmSoundStarted()
        await d.model.systemAlarmIdle()
        #expect(d.alarm.events.isEmpty)
        // a night without consent that rings late: still nothing
        d.clock.now = wake + 45
        d.model.alarmSoundStarted()
        await d.model.systemAlarmIdle()
        #expect(d.alarm.events.isEmpty)
    }

    // MARK: confirm, abandon

    @Test func confirmingAtOrAfterTheWakeTimeCancelsTheSystemAlarm() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.clock.now = wake; h.model.refresh()
        h.model.alarmSoundStarted()
        h.clock.now = wake + 40
        #expect(h.model.confirm(code: "1234"))
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.last == .cancel)
        #expect(h.model.systemAlarmAt == nil && h.model.safetyAlarmAt == nil)
        #expect(h.model.shownResult?.outcome == .complete)
        #expect(!h.model.backupNotificationsOn)                             // the night is over: its notifications are gone
    }

    @Test func confirmingEarlyKeepsASafetyAlarmAtTheWakeTime() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.clock.now = date(6, 6, 5)                                         // wake − 25 min: confirming is open
        #expect(h.model.confirm())
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile), .schedule(wake, alarmFile)])
        #expect(h.model.safetyAlarmAt == wake)
        #expect(h.model.shownResult?.outcome == .complete)                  // the night itself is unaffected

        // a relaunch remembers it and leaves it alone
        let again = FakeSystemAlarm(consent: .allowed)
        let relaunched = model(h, alarm: again)
        await relaunched.systemAlarmIdle()
        #expect(relaunched.safetyAlarmAt == wake)
        #expect(again.events.isEmpty)

        relaunched.switchOffSafetyAlarm()
        await relaunched.systemAlarmIdle()
        #expect(again.events == [.cancel] && relaunched.safetyAlarmAt == nil)

        let third = FakeSystemAlarm(consent: .allowed)
        let afterOff = model(h, alarm: third)
        #expect(afterOff.safetyAlarmAt == nil)
    }

    @Test func theSafetyAlarmClearsItselfOnceItsTimeHasPassed() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.clock.now = date(6, 6, 5)
        h.model.confirm()
        await h.model.systemAlarmIdle()
        h.alarm.forgetEvents()
        h.clock.now = wake - 1; h.model.refresh()
        #expect(h.model.safetyAlarmAt == wake)
        h.clock.now = wake + 1; h.model.refresh()
        #expect(h.model.safetyAlarmAt == nil && h.model.systemAlarmAt == nil)
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.isEmpty)                                     // it is only forgotten: a ringing one is left alone
    }

    @Test func withoutConsentThereIsNoSafetyAlarm() async {
        let h = await harness(consent: .denied, at: date(5, 12))
        await startTonight(h)
        h.clock.now = date(6, 6, 5)
        #expect(h.model.confirm())
        await h.model.systemAlarmIdle()
        #expect(h.model.safetyAlarmAt == nil && h.alarm.scheduled.isEmpty)
    }

    @Test func abandoningTheNightCancelsTheSystemAlarm() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.clock.now = date(5, 23)
        h.model.abandonNight()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile), .cancel])
        #expect(h.model.systemAlarmAt == nil && h.model.safetyAlarmAt == nil)
    }

    // MARK: naps

    @Test func aNapSchedulesAndCancelsTheSameWayAndNeverLeavesASafetyAlarm() async {
        let h = await harness(consent: .allowed, at: date(8, 13, 30))
        h.model.refresh()
        h.model.startNap()
        await h.model.systemAlarmIdle()
        let napWake = h.model.active!.wake
        #expect(h.alarm.events == [.schedule(napWake + 30, alarmFile)])
        #expect(h.model.backupNotificationsOn)

        h.clock.now = napWake - 60
        #expect(!h.model.confirm())                                         // a nap can only be confirmed when it is over
        h.clock.now = napWake + 5
        #expect(h.model.confirm())
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.last == .cancel)
        #expect(h.model.safetyAlarmAt == nil && h.model.systemAlarmAt == nil)
        h.model.acknowledgeResult()

        // ending a nap early cancels too
        h.clock.now = date(9, 13, 30); h.model.refresh()
        h.model.startNap()
        h.model.abandonNight()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.last == .cancel && h.model.systemAlarmAt == nil)
    }

    // MARK: housekeeping

    @Test func aLeftoverSystemAlarmIsCancelledAtLaunchWhenNothingRuns() async {
        let suite = "sleephole-systemalarm-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(date(6, 6, 30), forKey: SystemAlarmMemory.atKey)         // remembered from an earlier run
        let h = Harness(container: try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self,
                                                       ScheduleChange.self, JokerRecord.self,
                                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true)),
                        clock: FakeClock(date(5, 12)), alarm: FakeSystemAlarm(consent: .allowed), defaults: defaults, suite: suite)
        let m = model(h, alarm: h.alarm)
        await m.systemAlarmIdle()
        #expect(h.alarm.events == [.cancel] && m.systemAlarmAt == nil)
        #expect(defaults.object(forKey: SystemAlarmMemory.atKey) == nil)
    }

    @Test func aNightThatWasRunningWhenTheAppWasKilledKeepsItsSystemAlarm() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        let again = FakeSystemAlarm(consent: .allowed)
        h.clock.now = date(6, 3)
        let relaunched = model(h, alarm: again)                             // a new process
        await relaunched.systemAlarmIdle()
        #expect(relaunched.active != nil)
        #expect(again.events.isEmpty && relaunched.systemAlarmAt == wake + 30)
        relaunched.refresh()
        await relaunched.systemAlarmIdle()
        #expect(again.events.isEmpty)                                       // the every-second refresh leaves it alone
    }

    @Test func aFinishedNightLeavesNothingBehindForTheEverySecondRefresh() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.model.abandonNight()
        await h.model.systemAlarmIdle()
        h.alarm.forgetEvents()
        h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.isEmpty)
    }

    @Test func ifTheSafetyAlarmIsRefusedTheNightsAlarmIsNotLeftBehind() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.alarm.accepts = false
        h.clock.now = date(6, 6, 5)
        #expect(h.model.confirm())
        await h.model.systemAlarmIdle()
        #expect(h.model.safetyAlarmAt == nil && h.model.systemAlarmAt == wake + 30)   // what the system still holds
        h.alarm.forgetEvents()
        h.model.refresh()                                                   // nobody waits for it: housekeeping cancels it
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.cancel] && h.model.systemAlarmAt == nil)
    }

    // MARK: test alarm (Settings → Developer → System alarm test)

    @Test func theTestAlarmIsSetFor20SecondsWithTheChosenSound() async {
        let h = await harness(consent: .allowed, at: date(8, 12))
        h.model.settings.alarmSound = .ode
        #expect(h.model.canTestSystemAlarm && h.model.testAlarmAt == nil)
        #expect(h.model.testSystemAlarm())
        await h.model.systemAlarmIdle()
        let at = date(8, 12) + 20
        #expect(h.alarm.events == [.schedule(at, AppSettings.AlarmSound.ode.fileName)])
        #expect(h.model.testAlarmAt == at)
        #expect(h.model.safetyAlarmAt == at)                                // Today shows it as a safety alarm meanwhile

        // another test replaces the waiting one
        h.clock.now = date(8, 12, 0) + 5
        #expect(h.model.canTestSystemAlarm && h.model.testSystemAlarm(after: 40))
        await h.model.systemAlarmIdle()
        #expect(h.alarm.scheduled == [at, date(8, 12) + 45] && h.model.testAlarmAt == date(8, 12) + 45)
        h.model.settings.alarmSound = .gentle
    }

    @Test func theTestAlarmIsRefusedWithoutConsentAndDuringANightOrNap() async {
        for consent in [SystemAlarmConsent.denied, .notAsked, .unavailable] {
            let h = await harness(consent: consent, at: date(8, 12))
            #expect(!h.model.canTestSystemAlarm && !h.model.testSystemAlarm(), "\(consent)")
            await h.model.systemAlarmIdle()
            #expect(h.alarm.events.isEmpty && h.model.testAlarmAt == nil && h.model.systemAlarmAt == nil, "\(consent)")
        }

        let night = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(night)
        night.alarm.forgetEvents()
        #expect(!night.model.canTestSystemAlarm && !night.model.testSystemAlarm())   // the night has its own alarm
        await night.model.systemAlarmIdle()
        #expect(night.alarm.events.isEmpty && night.model.testAlarmAt == nil)
        #expect(night.model.systemAlarmAt == wake + 30)                     // the night's alarm is untouched

        let nap = await harness(consent: .allowed, at: date(8, 13, 30))
        nap.model.refresh()
        nap.model.startNap()
        await nap.model.systemAlarmIdle()
        nap.alarm.forgetEvents()
        #expect(!nap.model.testSystemAlarm())
        await nap.model.systemAlarmIdle()
        #expect(nap.alarm.events.isEmpty && nap.model.testAlarmAt == nil)
    }

    @Test func cancellingTheTestAlarmCancelsIt() async {
        let h = await harness(consent: .allowed, at: date(8, 12))
        h.model.cancelTestSystemAlarm()                                     // nothing to cancel
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.isEmpty)

        h.model.testSystemAlarm()
        h.model.cancelTestSystemAlarm()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(date(8, 12) + 20, alarmFile), .cancel])
        #expect(h.model.testAlarmAt == nil && h.model.safetyAlarmAt == nil && h.model.systemAlarmAt == nil)
        #expect(h.model.canTestSystemAlarm)                                 // and it can be started again
    }

    @Test func housekeepingKeepsTheTestAlarmUntilItsTimeAndThenForgetsIt() async {
        let h = await harness(consent: .allowed, at: date(8, 12))
        h.model.testSystemAlarm()
        await h.model.systemAlarmIdle()
        h.alarm.forgetEvents()
        for second in [1.0, 10, 19] {
            h.clock.now = date(8, 12) + second; h.model.refresh()           // the every-second refresh
            await h.model.systemAlarmIdle()
            #expect(h.model.testAlarmAt == date(8, 12) + 20 && h.alarm.events.isEmpty, "\(second)")
        }
        h.clock.now = date(8, 12) + 21; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.model.testAlarmAt == nil && h.model.systemAlarmAt == nil && h.model.safetyAlarmAt == nil)
        #expect(h.alarm.events.isEmpty)                                     // only forgotten: a ringing alarm is left alone
    }

    @Test func aRelaunchedAppKeepsTheTestAlarmAsASafetyAlarm() async {
        let h = await harness(consent: .allowed, at: date(8, 12))
        h.model.testSystemAlarm()
        await h.model.systemAlarmIdle()
        let again = FakeSystemAlarm(consent: .allowed)
        h.clock.now = date(8, 12) + 5
        let relaunched = model(h, alarm: again)
        await relaunched.systemAlarmIdle()
        #expect(again.events.isEmpty && relaunched.safetyAlarmAt == date(8, 12) + 20)   // Today shows it
        #expect(relaunched.testAlarmAt == nil && !relaunched.canTestSystemAlarm)        // not mistaken for a new test
        relaunched.switchOffSafetyAlarm()                                   // the card's button cancels it
        await relaunched.systemAlarmIdle()
        #expect(again.events == [.cancel] && relaunched.safetyAlarmAt == nil)
    }

    @Test func aTestNeverReplacesARealSafetyAlarm() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        h.clock.now = date(6, 6, 5)
        h.model.confirm()                                                   // early: the safety alarm waits for the wake time
        await h.model.systemAlarmIdle()
        h.alarm.forgetEvents()
        #expect(h.model.safetyAlarmAt == wake)
        #expect(!h.model.canTestSystemAlarm && !h.model.testSystemAlarm())
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.isEmpty && h.model.safetyAlarmAt == wake && h.model.testAlarmAt == nil)
        h.model.cancelTestSystemAlarm()                                     // and the test's cancel button leaves it alone
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events.isEmpty && h.model.safetyAlarmAt == wake)
    }

    @Test func aRefusedTestAlarmLeavesNothingBehind() async {
        let h = await harness(consent: .allowed, at: date(8, 12))
        h.alarm.accepts = false
        h.model.testSystemAlarm()
        await h.model.systemAlarmIdle()
        #expect(h.model.testAlarmAt == nil && h.model.systemAlarmAt == nil && h.model.safetyAlarmAt == nil)
    }

    @Test func theTestScreenTextsInBothLanguages() {
        defer { Lang.current = .en }
        Lang.current = .en
        #expect(L("System alarm test") == "System alarm test" && L("Ring in 20 seconds") == "Ring in 20 seconds")
        #expect(L("Test alarm set for \("6:30:20")") == "Test alarm set for 6:30:20")
        Lang.current = .sk
        #expect(L("System alarm test") == "Test systémového budíka")
        #expect(L("Ring in 20 seconds") == "Zazvoniť o 20 sekúnd" && L("Cancel the test alarm") == "Zrušiť skúšobný budík")
        #expect(L("Test alarm set for \("6:30:20")") == "Skúšobný budík je nastavený na 6:30:20")
        #expect(L("While it waits, Today shows it as a safety alarm – switching that off cancels the test too.")
            == "Kým čaká, Dnes ho ukazuje ako poistný budík – jeho vypnutie zruší aj skúšku.")
        #expect(L("1. Tap “Ring in 20 seconds”.") == "1. Ťukni na „Zazvoniť o 20 sekúnd“.")
        #expect(L("4. “Stop” silences it; “Open SleepHole” opens the app.") == "4. „Stop“ ho stíši, „Otvoriť SleepHole“ otvorí appku.")
    }

    // MARK: which alarm the app runs with

    @Test func theSimulatorAndTheTestsNeverGetTheRealAlarm() {
        #if targetEnvironment(simulator)
        // the simulator build: no real AlarmKit object, whatever the arguments are
        #expect(SystemAlarms.forLaunch(args: [], underTest: false) is NoSystemAlarm)
        #expect(SystemAlarms.forLaunch(args: ["-mute"], underTest: false) is NoSystemAlarm)
        #expect(SystemAlarms.forLaunch(args: ["-systemAlarm", "bogus"], underTest: false) is NoSystemAlarm)
        #expect(!(SystemAlarms.forLaunch(args: ["-systemAlarm", "allowed"], underTest: false) is AlarmKitSystemAlarm))
        #endif
        #expect(SystemAlarms.forLaunch(args: ["-systemAlarm", "allowed"], underTest: true) is NoSystemAlarm)
        #expect(SystemAlarms.forLaunch(args: [], underTest: true) is NoSystemAlarm)
        // this very process is a test host
        #expect(SystemAlarms.isRunningTests)
        #expect(SystemAlarms.forLaunch() is NoSystemAlarm)
        let no = NoSystemAlarm()
        #expect(no.consent == .unavailable)
        // an AppModel built without a system alarm gets the do-nothing one
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let plain = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: FakeClock(date(5, 12)),
                             settings: settings(), servicesEnabled: false)
        #expect(plain.systemAlarm is NoSystemAlarm)
    }

    @Test func theScreenshotStandInOnlyReportsAConsent() async {
        #if targetEnvironment(simulator)
        for (arg, consent) in [("allowed", SystemAlarmConsent.allowed), ("denied", .denied), ("notAsked", .notAsked)] {
            let alarm = SystemAlarms.forLaunch(args: ["-systemAlarm", arg], underTest: false)
            #expect(alarm is SimulatedSystemAlarm && alarm.consent == consent, "\(arg)")
        }
        #endif
        let notAsked = SimulatedSystemAlarm(consent: .notAsked)
        #expect(await notAsked.schedule(at: Date() + 3600, soundFile: "x.caf") == false)
        #expect(await notAsked.requestConsent() == .allowed)
        #expect(await notAsked.schedule(at: Date() + 3600, soundFile: "x.caf"))
        #expect(notAsked.scheduledAt != nil)
        notAsked.cancel()
        #expect(notAsked.scheduledAt == nil)
        #expect(SimulatedSystemAlarm.consent(from: ["-systemAlarm"]) == nil)
        let denied = SimulatedSystemAlarm(consent: .denied)
        #expect(await denied.requestConsent() == .denied)
    }

    // MARK: texts + views

    @Test func theConsentRowTextsInBothLanguages() {
        defer { Lang.current = .en }
        Lang.current = .en
        #expect(SystemAlarmConsent.allowed.title == "On" && SystemAlarmConsent.denied.title == "Not allowed")
        #expect(SystemAlarmConsent.notAsked.title == "Not asked yet" && SystemAlarmConsent.unavailable.title == "Needs iOS 26")
        Lang.current = .sk
        #expect(SystemAlarmConsent.allowed.title == "Zapnutý" && SystemAlarmConsent.denied.title == "Nepovolený")
        #expect(SystemAlarmConsent.notAsked.title == "Zatiaľ nepovolený" && SystemAlarmConsent.unavailable.title == "Vyžaduje iOS 26")
        #expect(L("System alarm") == "Systémový budík" && L("Allow") == "Povoliť")
        #expect(L("I'm really up – switch it off") == "Som naozaj hore – vypnúť")
        #expect(L("Safety alarm at \("6:30")") == "Poistný budík o 6:30")
        Lang.current = .en
        #expect(L("Safety alarm at \("6:30")") == "Safety alarm at 6:30")
    }

    func render<V: View>(_ view: V, _ model: AppModel, dark: Bool = false) {
        let host = UIHostingController(rootView: view.environment(model).environment(sprites)
            .preferredColorScheme(dark ? .dark : .light))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.15)
        window.isHidden = true
    }

    @Test(arguments: AppLanguage.allCases) func theSafetyCardRendersOnTheResultAndOnToday(language: AppLanguage) async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        h.model.language = language
        defer { h.model.language = .en }
        await startTonight(h)
        h.clock.now = date(6, 6, 5)
        h.model.confirm()
        await h.model.systemAlarmIdle()
        #expect(h.model.phase == .result && h.model.safetyAlarmAt == wake)
        for dark in [false, true] {
            render(SafetyAlarmCard(at: wake), h.model, dark: dark)
            render(ResultView(), h.model, dark: dark)
        }
        h.model.acknowledgeResult()
        for dark in [false, true] { render(TodayView(), h.model, dark: dark) }   // Today with the card
        h.model.switchOffSafetyAlarm()
        render(TodayView(), h.model)                                              // and without it
    }

    @Test(arguments: [SystemAlarmConsent.allowed, .denied, .notAsked, .unavailable])
    func theSettingsRowRendersForEveryState(consent: SystemAlarmConsent) async {
        let h = await harness(consent: consent, at: date(5, 12))
        for language in AppLanguage.allCases {
            h.model.language = language
            for dark in [false, true] { render(SettingsView(), h.model, dark: dark) }
        }
        h.model.language = .en
    }

    @Test(arguments: [SystemAlarmConsent.allowed, .denied, .notAsked, .unavailable])
    func theTestScreenRendersForEveryState(consent: SystemAlarmConsent) async {
        let h = await harness(consent: consent, at: date(8, 12))
        for language in AppLanguage.allCases {
            h.model.language = language
            for dark in [false, true] { render(NavigationStack { SystemAlarmTestView() }, h.model, dark: dark) }
            if h.model.testSystemAlarm() {                                  // with a test alarm waiting
                await h.model.systemAlarmIdle()
                for dark in [false, true] { render(NavigationStack { SystemAlarmTestView() }, h.model, dark: dark) }
                h.model.cancelTestSystemAlarm()
            }
        }
        h.model.language = .en
    }

    @Test func theTestScreenRendersDuringANight() async {
        let h = await harness(consent: .allowed, at: date(5, 12))
        await startTonight(h)
        render(NavigationStack { SystemAlarmTestView() }, h.model)           // the ring button is disabled
    }
}
