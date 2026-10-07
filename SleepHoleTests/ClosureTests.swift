import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// R4 (owner 2026-10-04): closing the app during a night / nap counts as leaving it – iOS tells the running app that it
/// is being terminated (`appWillTerminate`), the next launch ends the trip. A kill without the notice stays in the owner's
/// favour, and so does a phone restart (the boot time is later than the closure). Driven by the real AppModel with a
/// FakeClock; a second AppModel on the same store is "the relaunch". No notification is scheduled (`servicesEnabled:
/// false`) and no test night is ever started in the app itself.
@MainActor
struct ClosureTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m, second: s))!
    }

    /// Bedtime 22:30 (setup until 22:35 for a start at 22:25), wake 6:30.
    final class Harness {
        let container: ModelContainer
        let clock: FakeClock
        let suite: String
        let defaults: UserDefaults
        var model: AppModel!
        init(container: ModelContainer, clock: FakeClock, suite: String, defaults: UserDefaults) {
            self.container = container; self.clock = clock; self.suite = suite; self.defaults = defaults
        }
        deinit { defaults.removePersistentDomain(forName: suite) }
    }

    func settings() -> AppSettings {
        var s = AppSettings()
        s.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        s.wakeCode = "1234"
        return s
    }

    func newModel(_ h: Harness, boot: Date? = nil) -> AppModel {
        AppModel(context: h.container.mainContext, catalog: sprites.catalog, clock: h.clock, settings: settings(),
                 servicesEnabled: false, defaults: h.defaults, bootDate: { boot })
    }

    /// A model that has started tonight's night at 22:25 (setup until 22:35).
    func tonight(boot: Date? = nil) -> Harness {
        let suite = "sleephole-closure-\(UUID().uuidString)"
        let h = Harness(container: try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self,
                                                       ScheduleChange.self, JokerRecord.self,
                                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true)),
                        clock: FakeClock(date(5, 22, 25)), suite: suite, defaults: UserDefaults(suiteName: suite)!)
        h.model = newModel(h, boot: boot)
        h.model.refresh()
        h.model.startNight()
        return h
    }

    /// The process dies and the owner opens the app: a new AppModel on the same store at `time`.
    func relaunch(_ h: Harness, at time: Date, boot: Date? = nil) -> AppModel {
        h.clock.now = time
        h.model = newModel(h, boot: boot)
        return h.model
    }

    /// The owner swipes the app away at `closedAt` and opens it again `after` seconds later.
    func closeAndReopen(_ h: Harness, closedAt: Date, after: TimeInterval, boot: Date? = nil) -> AppModel {
        h.clock.now = closedAt
        h.model.appWillTerminate()
        return relaunch(h, at: closedAt + after, boot: boot)
    }

    // MARK: the termination notice

    @Test func closingTheAppAfterTheSetupIsLoggedAndWarnsLikeLeavingIt() {
        let h = tonight()
        h.clock.now = date(6, 2, 0)
        h.model.appWillTerminate()
        #expect(h.model.active?.log.has(.closedByOwner) == true)
        #expect(h.model.nudgesSent == 1 && h.model.lastNudgeSeconds == 10)            // "open it within 10 seconds"
        #expect(h.model.active?.log.openClosure == date(6, 2, 0))
        #expect(h.model.collapsedAt == date(6, 2, 0) + 13)                           // a trip that never ends collapses
    }

    @Test func theEventIsInTheStoreTheMomentTheNoticeReturns() {
        // another context on the same store sees it: it was saved synchronously, not "later"
        let h = tonight()
        h.clock.now = date(6, 2, 0)
        h.model.appWillTerminate()
        let other = ModelContext(h.container)
        let rec = try! other.fetch(FetchDescriptor<NightRecord>()).first!
        #expect(rec.log.events.last?.kind == .closedByOwner && rec.log.events.last?.at == date(6, 2, 0))
    }

    @Test func theBudgetShortensTheWarning() {
        let h = tonight()
        for i in 0..<2 {                                                // 2 × 12 s of 30 s used
            h.clock.now = date(6, 1, i); h.model.append(.leftApp)
            h.clock.now += 12; h.model.append(.returned)
        }
        h.clock.now = date(6, 2, 0)
        h.model.appWillTerminate()
        #expect(h.model.nudgesSent == 3 && h.model.lastNudgeSeconds == 3)            // 6 s left − the 3 s of detection
        #expect(h.model.collapsedAt == date(6, 2, 0) + 6)
    }

    @Test func noWarningDuringTheSetupButTheClosureCounts() {
        let h = tonight()
        let first = h.model!
        let m = closeAndReopen(h, closedAt: date(5, 22, 28), after: 7 * 60 + 5)      // setup until 22:35; back 22:35:05
        #expect(first.active?.log.has(.closedByOwner) == true && first.nudgesSent == 0)    // the setup warning covers it
        #expect(m.collapsedAt == nil)                                    // the setup time is free…
        #expect(m.awayBudgetUse()?.used == 5)                            // …the 5 s after its end are charged
        let late = tonight()
        let l = closeAndReopen(late, closedAt: date(5, 22, 28), after: 7 * 60 + 20)  // back 20 s after its end
        #expect(l.collapsedAt == date(5, 22, 35) + 13)
    }

    @Test func aClosureDuringAPauseTakesThePausePath() {
        let h = tonight()
        h.clock.now = date(6, 2, 0)
        h.model.startPause()
        #expect(h.model.pauseEnds() == date(6, 2, 10))
        let first = h.model!
        let m = closeAndReopen(h, closedAt: date(6, 2, 1), after: 5 * 60)
        #expect(first.nudgesSent == 0)                                   // no "closed" warning inside a pause
        #expect(first.active?.log.has(.closedByOwner) == true)
        #expect(m.collapsedAt == nil && m.awayBudgetUse()?.used == 0)
        // …and staying away after the pause ends collapses the building 13 s after it
        let late = tonight()
        late.clock.now = date(6, 2, 0); late.model.startPause()
        let l = closeAndReopen(late, closedAt: date(6, 2, 1), after: 9 * 60 + 20)    // back at 2:10:20
        #expect(l.collapsedAt == date(6, 2, 10) + 13)
    }

    @Test func leftThenClosedWarnsOnlyOnce() {
        let h = tonight()
        h.clock.now = date(6, 2, 0); h.model.append(.leftApp)
        #expect(h.model.nudgesSent == 1)
        let first = h.model!
        let m = closeAndReopen(h, closedAt: date(6, 2, 0, 2), after: 30)             // back 32 s after leaving
        #expect(first.nudgesSent == 1)                                   // the trip already carries its warning
        #expect(m.collapsedAt == date(6, 2, 0) + 13)                     // counted from the leaving
    }

    @Test func closingAfterTheBuildingCollapsedDoesNotWarnAgain() {
        let h = tonight()
        h.clock.now = date(6, 2, 0); h.model.append(.leftApp)
        h.clock.now += 60; h.model.append(.returned)                     // collapsed
        h.model.appWillTerminate()
        #expect(h.model.nudgesSent == 1)
    }

    @Test func nothingHappensAtOrAfterTheWakeTimeOrWithoutANight() {
        let h = tonight()
        h.clock.now = date(6, 6, 30)                                     // exactly the wake time
        h.model.appWillTerminate()
        h.clock.now = date(6, 6, 31)
        h.model.appWillTerminate()
        #expect(h.model.active?.log.has(.closedByOwner) == false && h.model.nudgesSent == 0)
        let log = h.model.active!.log
        #expect(log.openClosure == nil)

        // no night: nothing is appended anywhere, nothing crashes
        let suite = "sleephole-closure-idle-\(UUID().uuidString)"
        let idle = Harness(container: try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self,
                                                          ScheduleChange.self, JokerRecord.self,
                                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true)),
                           clock: FakeClock(date(5, 12)), suite: suite, defaults: UserDefaults(suiteName: suite)!)
        idle.model = newModel(idle)
        idle.model.appWillTerminate()
        #expect(idle.model.active == nil && idle.model.records().isEmpty && idle.model.nudgesSent == 0)
        // a night that is over (result screen) is no night either
        h.clock.now = date(6, 6, 30); h.model.refresh()
        #expect(h.model.confirm(code: "1234"))
        h.model.appWillTerminate()
        #expect(h.model.records().first?.log.has(.closedByOwner) == false)
    }

    // MARK: the relaunch

    @Test func openingTheAppWithinEightSecondsKeepsTheBuilding() {
        let h = tonight()
        let m = closeAndReopen(h, closedAt: date(6, 2, 0), after: 8)
        #expect(m.active != nil && m.phase == .building)
        #expect(m.collapsedAt == nil)
        #expect(m.awayBudgetUse()?.used == 8)
        let log = m.active!.log
        #expect(log.events.map(\.kind).suffix(2) == [.closedByOwner, .appLaunched])       // persisted, then answered
        #expect(log.openClosure == nil)
        h.clock.now = date(6, 6, 31); m.refresh()
        #expect(m.confirm(code: "1234"))
        #expect(m.shownResult?.outcome == .complete)
    }

    @Test func openingTheAppAfterAMinuteCollapsesTheBuilding() {
        let h = tonight()
        let m = closeAndReopen(h, closedAt: date(6, 2, 0), after: 60)
        #expect(m.collapsedAt == date(6, 2, 0) + 13)                     // at the same moment a 60 s trip would
        h.clock.now = date(6, 6, 31); m.refresh()
        #expect(m.confirm(code: "1234"))
        #expect(m.shownResult?.outcome == .ruins)
    }

    @Test func neverOpeningTheAppAgainRuinsTheNight() {
        let h = tonight()
        h.clock.now = date(6, 2, 0)
        h.model.appWillTerminate()
        h.clock.now = date(6, 12)                                        // opened at noon: the night is long over
        h.model = newModel(h)
        h.model.refresh()
        #expect(h.model.shownResult?.outcome == .ruins && h.model.active == nil)
    }

    @Test func openingTheAppInTheMorningAfterAClosureStillConfirmsButIsRuins() {
        let h = tonight()
        let m = closeAndReopen(h, closedAt: date(6, 2, 0), after: 4 * 3600 + 45 * 60)    // 6:45, the alarm time
        m.refresh()
        #expect(m.phase == .alarm && m.collapsedAt == date(6, 2, 0) + 13)
        #expect(m.confirm(code: "1234"))
        #expect(m.shownResult?.outcome == .ruins)
    }

    @Test func aPhoneRestartIsNotHeldAgainstTheOwner() {
        let h = tonight()
        let closedAt = date(6, 2, 0)
        // the phone booted after the notice: it was the restart (or a shutdown) that closed the app – even 3 hours later
        let m = closeAndReopen(h, closedAt: closedAt, after: 3 * 3600, boot: closedAt + 120)
        let kinds = m.active!.log.events.map(\.kind)
        #expect(kinds.suffix(3) == [.closedByOwner, .restartExcused, .appLaunched])
        #expect(m.collapsedAt == nil && m.awayBudgetUse()?.used == 0)
        #expect(m.nudgesSent == 0)
        h.clock.now = date(6, 6, 31); m.refresh()
        #expect(m.confirm(code: "1234"))
        #expect(m.shownResult?.outcome == .complete)
        #expect(NightReport(log: m.shownResult!.log).relaunches.count == 1)              // "The app restarted"
    }

    @Test func aBootBeforeTheClosureIsNoRestart() {
        let h = tonight()
        let closedAt = date(6, 2, 0)
        let m = closeAndReopen(h, closedAt: closedAt, after: 60, boot: date(5, 8, 0))    // the phone booted yesterday
        #expect(m.active!.log.has(.restartExcused) == false)
        #expect(m.collapsedAt == closedAt + 13)
        // an unknown boot time (sysctl failed) counts for nothing either
        let h2 = tonight()
        let m2 = closeAndReopen(h2, closedAt: closedAt, after: 60, boot: nil)
        #expect(m2.active!.log.has(.restartExcused) == false && m2.collapsedAt == closedAt + 13)
    }

    @Test func aDeathWithoutTheNoticeStaysInTheOwnersFavour() {
        // iOS killed the app for memory / it crashed: no termination notice, so no closure
        let h = tonight()
        _ = relaunch(h, at: date(6, 2, 0), boot: date(5, 8, 0))
        _ = relaunch(h, at: date(6, 3, 0))
        #expect(h.model.active?.log.has(.closedByOwner) == false)
        #expect(h.model.collapsedAt == nil && h.model.haptics.isEmpty)
        // …also when the app had just been left (the old rule: a relaunch wipes the unknown trip)
        h.clock.now = date(6, 3, 10); h.model.append(.leftApp)
        _ = relaunch(h, at: date(6, 3, 50))
        #expect(h.model.collapsedAt == nil)
    }

    @Test func theLogSurvivesIntoTheNewModelAndASecondClosureWorksToo() {
        let h = tonight()
        var m = closeAndReopen(h, closedAt: date(6, 1, 0), after: 5)
        let first = m.active!.log.events.map(\.kind)
        #expect(first.contains(.started) && first.suffix(2) == [.closedByOwner, .appLaunched])
        // a second closure of the same night: the budget is shared (5 s + 5 s)
        m = closeAndReopen(h, closedAt: date(6, 2, 0), after: 5)
        #expect(m.collapsedAt == nil && m.awayBudgetUse()?.used == 10)
        #expect(m.active!.log.events.filter { $0.kind == .closedByOwner }.count == 2)
        // two more of 12 s use up the 30 s of the night
        m = closeAndReopen(h, closedAt: date(6, 3, 0), after: 12)
        #expect(m.collapsedAt == nil && m.awayBudgetUse()?.used == 22)
        m = closeAndReopen(h, closedAt: date(6, 4, 0), after: 12)
        #expect(m.collapsedAt == date(6, 4, 0) + 8)
    }

    @Test func aNapIsClosedLikeANight() {
        let suite = "sleephole-closure-nap-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let h = Harness(container: try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self,
                                                       ScheduleChange.self, JokerRecord.self,
                                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true)),
                        clock: FakeClock(date(8, 13, 30)), suite: suite, defaults: defaults)
        h.model = newModel(h)
        h.model.refresh(); h.model.startNap()                            // setup 2 min, wake 14:00
        #expect(h.model.active?.isNap == true)
        h.clock.now = date(8, 13, 41)
        h.model.appWillTerminate()
        #expect(h.model.nudgesSent == 1 && h.model.active?.log.has(.closedByOwner) == true)
        let m = closeAndReopen(h, closedAt: date(8, 13, 41), after: 60)
        #expect(m.collapsedAt == date(8, 13, 41) + 13)
        h.clock.now = date(8, 14, 1); m.refresh()
        m.confirm()
        #expect(m.shownResult?.outcome == .ruins)
    }

    @Test func cameBackInTimeGetsTheReliefVibration() {
        let h = tonight()
        let m = closeAndReopen(h, closedAt: date(6, 2, 0), after: 6)
        #expect(m.haptics == [.relief])                                  // the "phew" of a warning answered in time
        // too late: collapsed, no relief
        let late = tonight()
        let l = closeAndReopen(late, closedAt: date(6, 2, 0), after: 60)
        #expect(l.haptics.isEmpty)
        // during the setup there was no warning, so no relief; the phone restart gets none either
        let setup = tonight()
        #expect(closeAndReopen(setup, closedAt: date(5, 22, 28), after: 5).haptics.isEmpty)
        let restart = tonight()
        #expect(closeAndReopen(restart, closedAt: date(6, 2, 0), after: 3600, boot: date(6, 2, 30)).haptics.isEmpty)
        // a plain relaunch (killed by iOS) is not a closure
        let plain = tonight()
        plain.clock.now = date(6, 2, 0)
        plain.model = newModel(plain)
        #expect(plain.model.haptics.isEmpty)
    }

    // MARK: the night story, the notice, the guide

    @Test func theNightStoryNamesTheClosure() {
        let h = tonight()
        let m = closeAndReopen(h, closedAt: date(6, 2, 0), after: 8)
        h.clock.now = date(6, 6, 31); m.refresh(); m.confirm(code: "1234")
        let r = NightReport(log: m.shownResult!.log)
        #expect(r.nightTrips.count == 1 && r.nightTrips[0].closedApp && r.nightTrips[0].duration == 8)
        #expect(r.relaunches.isEmpty && r.collapsedAt == nil)
        let key = NightKey(m.shownResult!.keyString)!
        m.acknowledgeResult()
        for language in AppLanguage.allCases {
            m.language = language
            render(NightDetail(key: key), m)
        }
        m.language = .en
        // never reopened: the line still renders ("you didn't come back")
        let h2 = tonight()
        h2.clock.now = date(6, 2, 0); h2.model.appWillTerminate()
        h2.clock.now = date(6, 12); h2.model = newModel(h2)                 // opened at noon: the night is long over
        let story = NightReport(log: h2.model.shownResult!.log)
        #expect(story.nightTrips.count == 1 && story.nightTrips[0].closedApp && story.nightTrips[0].end == nil)
        render(NightDetail(key: NightKey(h2.model.shownResult!.keyString)!), h2.model)
    }

    @Test func theTextsInBothLanguages() {
        defer { Lang.current = .en }
        Lang.current = .en
        #expect(L("⚠️ SleepHole was closed") == "⚠️ SleepHole was closed")
        #expect(L("Open it within \(10) seconds, or the building collapses 🏗️") == "Open it within 10 seconds, or the building collapses 🏗️")
        #expect(L("closed the app") == "closed the app")
        #expect(GuideText.night.hasSuffix("Closing SleepHole (swiping it away) counts like leaving it."))
        Lang.current = .sk
        #expect(L("⚠️ SleepHole was closed") == "⚠️ SleepHole sa zavrela")
        #expect(L("Open it within \(10) seconds, or the building collapses 🏗️") == "Otvor ju do 10 sekúnd, inak sa stavba zrúti 🏗️")
        #expect(L("closed the app") == "zavretá appka")
        #expect(GuideText.night.hasSuffix("Zavretie SleepHole (potiahnutím preč) sa počíta ako odchod z appky."))
        #expect(GuideText.night.contains("10 sekúnd") && GuideText.night.contains("30 sekúnd"))   // the rest of the rule is intact
    }

    @Test func theClosedNoticesAreNightNoticesAndTimeSensitive() {
        for id in ["closed", "closed-2"] {
            #expect(Notifications.nightIds.contains(id) && Notifications.isTimeSensitive(id), "\(id)")
        }
    }

    @Test func theMonitorCallsTheTerminationHookInPlace() {
        let monitor = LifecycleMonitor()
        var calls = 0
        monitor.onTerminate = { calls += 1 }
        monitor.start()
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        #expect(calls == 1)                                              // synchronously: the process dies right after
        monitor.stop()
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        #expect(calls == 1)
    }

    @Test func theRealBootTimeIsInThePast() {
        let boot = DeviceBoot.date()
        #expect(boot != nil && boot! < Date() && boot! > Date(timeIntervalSince1970: 1_400_000_000))
    }

    func render<V: View>(_ view: V, _ model: AppModel) {
        let host = UIHostingController(rootView: view.environment(model).environment(sprites))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.1)
        window.isHidden = true
    }
}
