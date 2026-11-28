import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// W7 (build 14b2): the Settings switch "Apple Watch buzz before the alarm" arms the silent pre-alarm on every real night
/// (never a nap, never without AlarmKit consent), and rule 12 – nothing counts between the pre-alarm and the wake time.
/// Driven by the real AppModel with a FakeClock, a fake alarm and a counting keep-alive (see `SystemAlarmTests`).
@MainActor
struct WatchBuzzTests {
    let base = SystemAlarmTests()
    var alarmFile: String { base.alarmFile }
    /// Bedtime 22:30, wake 06:30; a night started at 22:25 has its setup until 22:35.
    var wake: Date { base.wake }
    var fire: Date { wake - 25 }

    func harness(consent: SystemAlarmConsent = .allowed, switchOn: Bool = true, keepAlive: any KeepAlive = NoKeepAlive(),
                 strict: Bool = true) async -> SystemAlarmTests.Harness {
        let h = await base.harness(consent: consent, at: base.date(5, 12), keepAlive: keepAlive)
        h.model.settings.usesWatchBuzz = switchOn
        h.model.settings.strictMode = strict
        h.model.preAlarmKeepAliveOverride = true
        return h
    }

    func diagLines(_ h: SystemAlarmTests.Harness) -> [String] {
        let rec = h.model.active ?? h.model.shownResult
        return ((rec?.diagLog.entries ?? []) + h.model.diag.buffer).map { "\($0.k) \($0.v ?? "")" }
    }

    // MARK: the setting

    @Test func theSwitchIsOffByDefaultAndAnOldFileDecodesAsOff() throws {
        #expect(!AppSettings().usesWatchBuzz && AppSettings().watchBuzzOn == nil)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any])
        json.removeValue(forKey: "watchBuzzOn")
        let old = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!old.usesWatchBuzz)
        var on = AppSettings(); on.usesWatchBuzz = true
        #expect(on.watchBuzzOn == true)
        on.usesWatchBuzz = false
        #expect(on.watchBuzzOn == nil)
    }

    // MARK: scheduling

    @Test func aRealNightWithTheSwitchOnSchedulesOnceAtWakeMinus25sAndMarksTheNight() async {
        let h = await harness()
        await base.startTonight(h)
        #expect(h.alarm.events == [.schedulePre(fire), .schedule(wake + 30, alarmFile)])      // the backup is unchanged
        #expect(h.model.preAlarmAt == fire)
        #expect(h.model.active?.preAlarmAt == fire)                                           // rule 12's marker
        #expect(h.model.active?.rules.excusedFrom == fire)
        #expect(diagLines(h).contains("prealarm schedule at=wake-25s ok=1"))
        h.clock.now = base.date(5, 23); h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.preSchedules.count == 1)
    }

    @Test func withTheSwitchOffThereIsNoPreAlarmAndNoMarker() async {
        let h = await harness(switchOn: false)
        await base.startTonight(h)
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile)])
        #expect(h.model.preAlarmAt == nil && h.model.active?.preAlarmAt == nil && h.model.active?.rules.excusedFrom == nil)
        #expect(!diagLines(h).contains { $0.hasPrefix("prealarm") })
    }

    @Test func anEarlyStartGetsOneToo() async {
        let h = await harness()
        h.clock.now = base.date(5, 20, 30); h.model.refresh()                                  // bedtime − 2 h: "go to sleep early"
        #expect(h.model.canStartEarly)
        h.model.startNight(early: true)
        await h.model.systemAlarmIdle()
        #expect(h.model.active != nil && h.alarm.preSchedules == [fire])
        #expect(h.model.active?.preAlarmAt == fire)
    }

    @Test func aNapNeverGetsOne() async {
        let h = await harness()
        h.clock.now = base.date(8, 13, 30); h.model.refresh()
        h.model.startNap()
        await h.model.systemAlarmIdle()
        #expect(h.model.active?.isNap == true)
        #expect(h.alarm.preSchedules.isEmpty && h.model.preAlarmAt == nil && h.model.active?.preAlarmAt == nil)
        #expect(h.model.active?.rules.excusedFrom == nil)
    }

    @Test(arguments: [SystemAlarmConsent.denied, .notAsked, .unavailable])
    func withoutConsentThereIsNoPreAlarmAndANightStartDoesNotAsk(consent: SystemAlarmConsent) async {
        let h = await harness(consent: consent)
        h.model.settings.usesSystemAlarm = false                                               // so that nothing else asks
        await base.startTonight(h)
        #expect(h.alarm.preSchedules.isEmpty && h.alarm.requests == 0 && h.model.preAlarmAt == nil)
        #expect(h.model.active?.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm skip why=consent"))
    }

    @Test func aRefusedPreAlarmMarksNothing() async {
        let h = await harness()
        h.alarm.accepts = false
        await base.startTonight(h)
        #expect(h.model.preAlarmAt == nil && h.model.active?.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm schedule at=wake-25s ok=0"))
    }

    @Test func itDoesNotDependOnTheBackupSwitch() async {
        let h = await harness()
        h.model.settings.usesSystemAlarm = false
        await base.startTonight(h)
        #expect(h.alarm.events == [.schedulePre(fire)])
        #expect(h.model.active?.preAlarmAt == fire)
    }

    @Test func theBackupOnWithTheSwitchOffSchedulesOnlyTheBackup() async {
        let h = await harness(switchOn: false)
        await base.startTonight(h)
        #expect(h.alarm.events == [.schedule(wake + 30, alarmFile)])
    }

    // MARK: the switch during a night

    @Test func theSwitchOnMidNightSchedulesAndOffEndsOnlyThePreAlarmAndDropsTheMarker() async {
        let h = await harness(switchOn: false)
        await base.startTonight(h)
        h.alarm.forgetEvents()
        h.clock.now = base.date(5, 23); h.model.refresh()
        h.model.setWatchBuzz(on: true)
        await h.model.systemAlarmIdle()
        #expect(h.model.settings.usesWatchBuzz && h.alarm.events == [.schedulePre(fire)])
        #expect(h.model.active?.preAlarmAt == fire)
        h.model.setWatchBuzz(on: false)
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedulePre(fire), .endPre])                               // never `.cancel`: the backup stays
        #expect(!h.model.settings.usesWatchBuzz && h.model.preAlarmAt == nil)
        #expect(h.model.active?.preAlarmAt == nil && h.model.active?.rules.excusedFrom == nil)  // it had not fired: no excused seconds
        #expect(diagLines(h).contains("prealarm end why=switchedOff"))
        #expect(h.model.systemAlarmAt == wake + 30)
    }

    @Test func switchedOffAfterTheFireTimeTheMarkerStays() async {
        let h = await harness()
        await base.startTonight(h)
        h.clock.now = fire + 5; h.model.refresh()
        h.model.setWatchBuzz(on: false)
        await h.model.systemAlarmIdle()
        #expect(h.model.active?.preAlarmAt == fire)                                            // it has fired: part of what the night was
    }

    @Test func theSwitchOnTooLateSchedulesNothing() async {
        let h = await harness(switchOn: false)
        await base.startTonight(h)
        h.alarm.forgetEvents()
        h.clock.now = wake - 20; h.model.refresh()
        h.model.setWatchBuzz(on: true)
        await h.model.systemAlarmIdle()
        #expect(h.alarm.preSchedules.isEmpty && h.model.active?.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm skip why=late"))
    }

    @Test func theSwitchOnWithNoNightRunningOnlySetsTheSetting() async {
        let h = await harness(switchOn: false)
        h.model.setWatchBuzz(on: true)
        await h.model.systemAlarmIdle()
        #expect(h.model.settings.usesWatchBuzz && h.alarm.events.isEmpty)
    }

    @Test func switchingOnAsksConsentFirstAndADenialKeepsItOff() async {
        let h = await harness(consent: .notAsked, switchOn: false)
        h.alarm.answer = .denied
        h.model.setWatchBuzz(on: true)
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.requestConsent] && !h.model.settings.usesWatchBuzz)
        let ok = await harness(consent: .notAsked, switchOn: false)
        ok.model.setWatchBuzz(on: true)
        await ok.model.systemAlarmIdle()
        #expect(ok.alarm.events == [.requestConsent] && ok.model.settings.usesWatchBuzz)
    }

    @Test func switchingOnWhenDeniedStaysOffAndAsksNothing() async {
        let h = await harness(consent: .denied, switchOn: false)
        h.model.setWatchBuzz(on: true)
        await h.model.systemAlarmIdle()
        #expect(!h.model.settings.usesWatchBuzz && h.alarm.events.isEmpty)
    }

    @Test func theAnswerComesAfterTheNightHasStartedAndStillSchedules() async {
        let h = await harness(consent: .notAsked, switchOn: false)
        h.model.settings.usesSystemAlarm = false
        await base.startTonight(h)
        h.model.setWatchBuzz(on: true)
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.requestConsent, .schedulePre(fire)])
    }

    // MARK: ending

    @Test func ourAlarmEndsItWhenAudibleAndTheMarkerStays() async {
        let h = await harness()
        await base.startTonight(h)
        h.alarm.forgetEvents()
        h.clock.now = wake; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre])
        #expect(h.model.preAlarmAt == nil && h.model.active?.preAlarmAt == fire)
        #expect(diagLines(h).contains("prealarm end why=ours"))
    }

    @Test func ourInaudibleAlarmEndsItBeforeTheAtOnceMove() async {
        let h = await harness()
        await base.startTonight(h)
        h.model.setMediaVolume(0)
        h.alarm.forgetEvents()
        h.clock.now = wake; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre, .schedule(wake + SystemAlarmPlan.atOnce, alarmFile)])
    }

    @Test func movingTheBackupBehindOursLeavesAWaitingPreAlarmAlone() async {
        let h = await harness()
        await base.startTonight(h)
        h.alarm.forgetEvents()
        h.clock.now = wake - 10; h.model.refresh()
        h.model.alarmSoundStarted()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.schedule(wake + 120, alarmFile)])
        #expect(h.model.preAlarmAt == fire)
    }

    @Test func confirmingEarlyEndsItAndKeepsTheSafetyAlarm() async {
        let h = await harness()
        await base.startTonight(h)
        h.alarm.forgetEvents()
        h.clock.now = wake - 20 * 60; h.model.refresh()
        #expect(h.model.confirm(code: "1234"))
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre, .schedule(wake, alarmFile)])
        #expect(h.model.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm end why=confirmed"))
    }

    @Test func abandoningEndsIt() async {
        let h = await harness()
        await base.startTonight(h)
        h.alarm.forgetEvents()
        h.clock.now = base.date(5, 23)
        h.model.abandonNight()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre, .cancel])
        #expect(h.model.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm end why=abandoned"))
    }

    @Test func aRelaunchAfterTheWakeEndsAnOrphanedOneOnTheFirstRefresh() async {
        let h = await harness()
        await base.startTonight(h)
        h.clock.now = wake; h.model.refresh()
        await h.model.systemAlarmIdle()
        SystemAlarmMemory(defaults: h.defaults).preAt = fire                                    // the memory still holds it
        h.alarm.forgetEvents()
        h.clock.now = wake + 5
        let again = base.model(h, alarm: h.alarm)
        await again.systemAlarmIdle()
        #expect(again.preAlarmAt == nil && h.alarm.events == [.endPre])
        #expect(again.active?.preAlarmAt == fire)                                               // the marker came back with the night
    }

    @Test func aRelaunchBeforeTheFireTimeKeepsItAndSchedulesNothingTwice() async {
        let h = await harness()
        await base.startTonight(h)
        h.alarm.forgetEvents()
        h.clock.now = base.date(5, 23)
        var s = base.settings(); s.usesWatchBuzz = true
        let again = AppModel(context: h.container.mainContext, catalog: base.sprites.catalog, clock: h.clock, settings: s,
                             servicesEnabled: false, systemAlarm: h.alarm, keepAlive: NoKeepAlive(), defaults: h.defaults)
        await again.systemAlarmIdle()
        #expect(again.preAlarmAt == fire && again.active?.preAlarmAt == fire)
        #expect(h.alarm.events.isEmpty)
    }

    @Test func theConsentTakenAwayEndsItAndDropsTheMarker() async {
        let h = await harness()
        await base.startTonight(h)
        h.alarm.forgetEvents()
        h.alarm.consent = .denied
        h.clock.now = base.date(5, 23); h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre])
        #expect(h.model.preAlarmAt == nil && h.model.active?.preAlarmAt == nil)
        #expect(diagLines(h).contains("prealarm end why=consent"))
        #expect(SystemAlarmMemory(defaults: h.defaults).preAt == nil)
    }

    // MARK: the keep-alive in a real night

    @Test func theKeepAliveOfARealNightBeginsAndAlwaysEnds() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka)
        await base.startTonight(h)
        h.clock.now = wake - 29; h.model.refresh()
        #expect(ka.began == 0)
        h.clock.now = wake - 28; h.model.refresh()
        #expect(ka.began == 1 && ka.open == 1)
        h.clock.now = wake; h.model.refresh()
        h.model.alarmSoundStarted()
        #expect(ka.began == 1 && ka.open == 0)
    }

    @Test func anExpiredKeepAliveOfARealNightIsClosed() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka)
        await base.startTonight(h)
        h.clock.now = wake - 28; h.model.refresh()
        ka.expireLast()
        #expect(ka.open == 0)
        h.clock.now = wake - 10; h.model.refresh()
        #expect(ka.began == 1 && ka.open == 0)
    }

    @Test func theKeepAliveEndsWithTheSwitchAndWithTheNight() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka)
        await base.startTonight(h)
        h.clock.now = wake - 26; h.model.refresh()
        #expect(ka.open == 1)
        h.model.setWatchBuzz(on: false)
        #expect(ka.open == 0)
        let ka2 = FakeKeepAlive()
        let g = await harness(keepAlive: ka2)
        await base.startTonight(g)
        g.clock.now = wake - 26; g.model.refresh()
        g.model.abandonNight()
        await g.model.systemAlarmIdle()
        #expect(ka2.began == 1 && ka2.open == 0)
    }

    @Test func aNightWithTheSwitchOffBeginsNoKeepAlive() async {
        let ka = FakeKeepAlive()
        let h = await harness(switchOn: false, keepAlive: ka)
        await base.startTonight(h)
        h.clock.now = wake - 26; h.model.refresh()
        #expect(ka.began == 0)
    }

    // MARK: rule 12 – nothing counts from the pre-alarm to the wake time

    @Test func aLeaveAfterThePreAlarmWarnsNothingAndCollapsesNothing() async {
        let h = await harness()
        await base.startTonight(h)
        h.clock.now = fire + 5; h.model.append(.leftApp)
        #expect(h.model.nudgesSent == 0 && h.model.collapseNoticeAt == nil && h.model.lockWarningDeadline == nil)
        #expect(h.model.lastWarning == nil)
        #expect(diagLines(h).contains("warn held why=prealarm kind=leftApp"))
        h.clock.now = wake; h.model.refresh()                                                   // still out at the wake time
        #expect(h.model.collapsedAt == nil)
    }

    @Test func theSameLeaveOnAnUnmarkedNightWarnsAndCollapsesAsToday() async {
        let h = await harness(switchOn: false)
        await base.startTonight(h)
        h.clock.now = fire + 5; h.model.append(.leftApp)
        #expect(h.model.nudgesSent == 1 && h.model.collapseNoticeAt == fire + 5 + 18)
        h.clock.now = wake; h.model.refresh()
        #expect(h.model.collapsedAt == fire + 5 + 18)
    }

    @Test func aRecognisedPhoneUseAfterThePreAlarmIsHeldInStrictAndGentleMode() async {
        for strict in [true, false] {
            let h = await harness(strict: strict)
            await base.startTonight(h)
            h.clock.now = fire + 5; h.model.append(.usedLockScreen)
            #expect(h.model.nudgesSent == 0 && h.model.lockRemindersSent == 0 && h.model.lockWarningDeadline == nil, "strict=\(strict)")
            #expect(h.model.collapseNoticeAt == nil && h.alarm.warningRings == 0, "strict=\(strict)")
            h.clock.now = wake; h.model.refresh()
            #expect(h.model.collapsedAt == nil, "strict=\(strict)")
        }
    }

    @Test func aClosedAppAfterThePreAlarmCountsNothing() async {
        let h = await harness()
        await base.startTonight(h)
        h.clock.now = fire + 5; h.model.append(.closedByOwner)
        #expect(h.model.nudgesSent == 0 && h.model.collapseNoticeAt == nil)
        h.clock.now = wake + 3                                                                   // opened after the alarm
        let again = base.model(h, alarm: h.alarm)
        await again.systemAlarmIdle()
        #expect(again.collapsedAt == nil)
    }

    @Test func aTripThatStartsBeforeThePreAlarmGetsItsWarningButNoCollapseNoticeInTheExcusedSeconds() async {
        let h = await harness()
        await base.startTonight(h)
        h.clock.now = fire - 10; h.model.append(.leftApp)                                        // 18 s would end at fire + 8
        #expect(h.model.nudgesSent == 1)                                                         // before the fire time: as today
        #expect(h.model.collapseNoticeAt == nil)                                                 // the trip is cut at the fire time
        h.clock.now = wake; h.model.refresh()
        #expect(h.model.collapsedAt == nil)
    }

    @Test func aTripLongEnoughToCollapseBeforeThePreAlarmStillGetsItsNotice() async {
        let h = await harness()
        await base.startTonight(h)
        h.clock.now = fire - 60; h.model.append(.leftApp)
        #expect(h.model.collapseNoticeAt == fire - 60 + 18)
        #expect(h.model.collapsedAt == fire - 60 + 18)
    }

    @Test func aWarningPendingWhenThePreAlarmFiresIsWithdrawn() async {
        // the marker appears after the trip began (the switch went on in the middle of the trip's seconds): what was set for
        // later is withdrawn at the fire time
        let h = await harness(switchOn: false)
        await base.startTonight(h)
        h.clock.now = fire - 10; h.model.append(.leftApp)
        #expect(h.model.nudgesSent == 1 && h.model.collapseNoticeAt == fire - 10 + 18)
        h.model.active?.preAlarmAt = fire                                                        // rule 12 starts to apply
        h.clock.now = fire; h.model.refresh()
        #expect(h.model.collapseNoticeAt == nil)
        #expect(diagLines(h).contains("warn withdrawn why=prealarm"))
        #expect(diagLines(h).contains("notice collapse cancelled why=prealarm"))
    }

    @Test func aRingingLockWarningStopsAtThePreAlarm() async {
        let h = await harness(switchOn: false)
        await base.startTonight(h)
        h.clock.now = fire - 10; h.model.append(.usedLockScreen)
        await h.model.systemAlarmIdle()
        #expect(h.model.lockWarningDeadline != nil && h.alarm.warningRings == 1)
        h.model.active?.preAlarmAt = fire
        h.clock.now = fire; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.model.lockWarningDeadline == nil && h.alarm.warningStops >= 1)
        #expect(diagLines(h).contains("warn lock end why=prealarm"))
    }

    @Test func aLockWarningStartedBeforeThePreAlarmNeverRingsIntoIt() async {
        let h = await harness()
        await base.startTonight(h)
        h.clock.now = fire - 10; h.model.append(.usedLockScreen)
        #expect(h.model.lockWarningDeadline == fire)                                              // cut at the fire time, not +18 s
    }

    @Test func aNightWithoutTheMarkerIsJudgedExactlyAsBefore() async {
        let h = await harness(switchOn: false)
        await base.startTonight(h)
        h.clock.now = wake - 20; h.model.append(.leftApp)
        #expect(h.model.nudgesSent == 1)
        h.clock.now = wake; h.model.refresh()
        #expect(h.model.collapsedAt == wake - 2)                                                  // 18 s from the leave, as today
    }

    // MARK: 14b3 – no pre-alarm while SleepHole is open on screen

    @Test func inFrontAtTheKeepAliveMomentTheWaitingPreAlarmEndsAndLeavesNoMarker() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka)
        await base.startTonight(h)
        h.model.rest.appActive = { true }
        h.alarm.forgetEvents()
        h.clock.now = wake - 28; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre])                                                      // the backup alarm is untouched
        #expect(h.model.preAlarmAt == nil && h.model.active?.preAlarmAt == nil && h.model.active?.rules.excusedFrom == nil)
        #expect(ka.began == 0)
        #expect(diagLines(h).contains("prealarm skip why=inFront"))
        h.clock.now = wake - 27; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(h.alarm.events == [.endPre] && ka.began == 0)                                     // decided once
    }

    @Test func inTheBackgroundTheKeepAliveBeginsAndTheMarkerStays() async {
        let ka = FakeKeepAlive()
        let h = await harness(keepAlive: ka)
        await base.startTonight(h)
        h.model.rest.appActive = { false }
        h.clock.now = wake - 28; h.model.refresh()
        await h.model.systemAlarmIdle()
        #expect(ka.began == 1)
        #expect(h.model.preAlarmAt == fire && h.model.active?.preAlarmAt == fire)
        #expect(!diagLines(h).contains("prealarm skip why=inFront"))
        h.model.rest.appActive = { true }                                                        // opened later: nothing changes
        h.clock.now = fire + 1; h.model.refresh()
        #expect(h.model.active?.preAlarmAt == fire && ka.began == 1)
    }

    @Test func aTripOnANightWhoseSkippedPreAlarmNeverFiredCountsAsOnAnUnmarkedNight() async {
        let h = await harness()
        await base.startTonight(h)
        h.model.rest.appActive = { true }
        h.clock.now = wake - 28; h.model.refresh()
        await h.model.systemAlarmIdle()
        h.clock.now = wake - 20; h.model.append(.leftApp)
        #expect(h.model.nudgesSent == 1)
        h.clock.now = wake; h.model.refresh()
        #expect(h.model.collapsedAt == wake - 2)                                                  // 18 s from the leave, no excuse
    }
}
