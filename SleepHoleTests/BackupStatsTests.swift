import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

@MainActor
struct BackupStatsTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func store() -> ModelContainer {
        try! ModelContainer(for: NightRecord.self, UserProgress.self,
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func model(_ c: ModelContainer, at now: Date) -> (AppModel, FakeClock) {
        let clock = FakeClock(now)
        var s = AppSettings(); s.wakeCode = "1234"
        return (AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s,
                         servicesEnabled: false), clock)
    }

    func night(_ m: AppModel, _ clock: FakeClock, day: Int, confirmAfter: TimeInterval = 60) {
        clock.now = date(day, 22, 25); m.refresh(); m.startNight()
        clock.now = date(day + 1, 6, 30) + confirmAfter; m.refresh()
        if confirmAfter <= 3600 { m.confirm(code: "1234") } else { m.refresh() }
        m.acknowledgeResult()
    }

    func render<V: View>(_ view: V, _ m: AppModel) {
        let host = UIHostingController(rootView: view.environment(m).environment(sprites))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.15)
        window.isHidden = true
    }

    @Test func backupRoundTripRestoresEverything() throws {
        let a = store()
        let (m1, c1) = model(a, at: date(1, 12))
        for d in 1...4 { night(m1, c1, day: d) }
        m1.completeOnboarding()
        m1.settings.alarmSound = .ode
        let data = try m1.makeBackup().encoded()

        let b = store()
        let (m2, _) = model(b, at: date(9, 12))
        try m2.restore(try BackupFile.decode(data))
        #expect(m2.records().count == 4 && m2.builtNights == 4 && m2.coins == 400 + 50 + 50)   // + 2 achievements
        #expect(m2.onboardingDone && m2.settings.alarmSound == .ode)
        #expect(m2.townSnapshot?.buildings.map(\.buildingId) == m1.townSnapshot?.buildings.map(\.buildingId))
        #expect(m2.records().first?.log.has(.confirmedByCode) == true)
    }

    @Test func restoreIsRefusedDuringANightAndForNewerFiles() throws {
        let (m, clock) = model(store(), at: date(1, 22, 25))
        var b = m.makeBackup()
        b.version = BackupFile.currentVersion + 1
        #expect(throws: AppModel.BackupError.self) { try m.restore(b) }
        m.refresh(); m.startNight()
        #expect(throws: AppModel.BackupError.self) { try m.restore(m.makeBackup()) }
        #expect(AppModel.BackupError.nightRunning.errorDescription != nil && AppModel.BackupError.tooNew.errorDescription != nil)
        #expect(throws: (any Error).self) { try BackupFile.decode(Data("nope".utf8)) }
        _ = clock
    }

    @Test func autoBackupIsWrittenToDocuments() throws {
        let (m, _) = model(store(), at: date(1, 12))
        m.writeAutoBackup()
        let b = try BackupFile.decode(Data(contentsOf: BackupFile.autoBackupURL))
        #expect(b.version == BackupFile.currentVersion)
        _ = BackupDocument(data: try b.encoded())
    }

    @Test func statsAndScreens() {
        let (m, clock) = model(store(), at: date(1, 12))
        render(StatsView(), m)                                          // empty
        for d in 1...5 { night(m, clock, day: d) }                        // 5th night → level 2
        #expect(m.levelUp == nil)                                         // acknowledged
        let s = m.stats
        #expect(s.builtNights == 5 && s.coins == 500 && s.maxLevel == 2 && s.currentStreak == 5)
        #expect(s.averageStart == TimeOfDay(22, 25) && s.averageWake == TimeOfDay(6, 31))   // started 22:25, confirmed 6:31
        render(StatsView(), m)
        render(CalendarGrid(days: s.calendar), m)
        render(NightChart(points: s.series, bedtime: m.settings.schedule), m)
        render(LevelUpCard(level: 2) {}, m)
        render(ConfettiView(), m)
        let was12h = Fmt.systemUses12h
        defer { Fmt.systemUses12h = was12h }
        Fmt.systemUses12h = false
        #expect(NightChart.clock(1440 + 75) == "1:15" && NightChart.clock(-30) == "23:30")
        for o in [Outcome.complete, .unfinished, .ruins, .missed] { _ = CalendarGrid.color(o) }
        _ = CalendarGrid.color(nil)
    }

    @Test func levelUpCelebrationOnTheResultScreen() {
        let (m, clock) = model(store(), at: date(1, 12))
        for d in 1...4 { night(m, clock, day: d) }
        clock.now = date(5, 22, 25); m.refresh(); m.startNight()
        clock.now = date(6, 6, 31); m.refresh(); m.confirm(code: "1234")
        #expect(m.levelUp == 2)
        render(ResultView(), m)
    }

    @Test func nightDetailForEveryKindOfDay() {
        let (m, clock) = model(store(), at: date(1, 12))
        // night 1→2 with trips, screen checks and a code confirm
        clock.now = date(1, 22, 25); m.refresh(); m.startNight()
        clock.now = date(1, 22, 27); m.append(.leftApp)
        clock.now = date(1, 22, 29); m.append(.returned)
        clock.now = date(1, 22, 31); m.append(.locked)
        clock.now = date(2, 1, 0); m.append(.unlocked)
        clock.now = date(2, 1, 0) + 1; m.append(.returned)
        clock.now = date(2, 6, 30); m.refresh()
        clock.now = date(2, 6, 31); m.confirm(code: "1234"); m.acknowledgeResult()
        // afternoon nap on day 2, then a ruined night 2→3
        clock.now = date(2, 13, 30); m.startNap(); clock.now = date(2, 14, 0); m.refresh(); m.confirm(); m.acknowledgeResult()
        night(m, clock, day: 2, confirmAfter: 2 * 3600)
        let k2 = NightKey("2026-10-02")!, k3 = NightKey("2026-10-03")!, k9 = NightKey("2026-10-09")!
        #expect(m.nightRecord(for: k2) != nil && m.nightRecord(for: k9) == nil)
        #expect(m.napRecord(before: k3)?.isNap == true && m.napRecord(before: k2) == nil)
        #expect(m.townBuilding(for: k2)?.state == .complete && m.coinsEarned(for: k2) == 100)
        let r = NightReport(log: m.nightRecord(for: k2)!.log)
        #expect(r.setupTrips.count == 1 && r.screenChecks.count == 1 && r.confirmMethod == .code)
        for k in [k2, k3, k9] { render(NightDetail(key: k), m) }
        render(StatsView(), m)
        #expect(NightDetail.duration(nil) == "you didn't come back" && NightDetail.duration(181) == "3 min 1 s"
                && NightDetail.duration(8) == "8 s")
    }

    @Test func repairedRuinShowsInTheSheet() {
        let (m, clock) = model(store(), at: date(1, 12))
        night(m, clock, day: 1, confirmAfter: 2 * 3600)                   // ruins
        night(m, clock, day: 2)                                           // complete → repairs it
        let b = m.townSnapshot!.buildings[0]
        #expect(b.state == .complete && b.repairedLater)
        render(BuildingSheet(building: b), m)
    }
}
