import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// B8: `coins`, `streak`, `stats` and the joker state are cached; every kind of change must show at once. The truth is
/// a second model over the same store (a cold cache) at the same time.
@MainActor
struct DerivedCacheTests {
    let catalog = SpriteLibrary.loadFromBundle().catalog!
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    struct Rig {
        let container: ModelContainer
        let clock: FakeClock
        let model: AppModel
    }

    func rig(at now: Date) -> Rig {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self, BoxRecord.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(now)
        var s = AppSettings()
        s.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        s.wakeCode = "1234"
        let m = AppModel(context: c.mainContext, catalog: catalog, clock: clock, settings: s, servicesEnabled: false)
        return Rig(container: c, clock: clock, model: m)
    }

    /// A model with a cold cache over the same store and clock.
    func cold(_ r: Rig) -> AppModel {
        var s = r.model.settings
        s.wakeCode = "1234"
        let m = AppModel(context: r.container.mainContext, catalog: catalog, clock: r.clock, settings: s, servicesEnabled: false)
        m.refresh()
        return m
    }

    func playNight(_ r: Rig, day: Int) {
        r.clock.now = date(day, 22, 25); r.model.refresh(); r.model.startNight()
        r.clock.now = date(day + 1, 6, 30) + 60; r.model.refresh()
        #expect(r.model.confirm(code: "1234"))
        r.model.acknowledgeResult()
    }

    /// The cached values equal a cold model's, and the cache answers the same twice.
    func expectFresh(_ r: Rig, sourceLocation: SourceLocation = #_sourceLocation) {
        let truth = cold(r)
        #expect(r.model.coins == truth.coins, sourceLocation: sourceLocation)
        #expect(r.model.coinsEarned == truth.coinsEarned, sourceLocation: sourceLocation)
        #expect(r.model.coinsSpent == truth.coinsSpent, sourceLocation: sourceLocation)
        #expect(r.model.streak == truth.streak, sourceLocation: sourceLocation)
        #expect(r.model.stats == truth.stats, sourceLocation: sourceLocation)
        #expect(r.model.jokerState.uses.count == truth.jokerState.uses.count, sourceLocation: sourceLocation)
        #expect(r.model.coins == r.model.coins && r.model.streak == r.model.streak, sourceLocation: sourceLocation)
    }

    @Test func aFinalizedNightShowsAtOnce() {
        let r = rig(at: date(5, 12))
        for d in 2...4 { playNight(r, day: d) }
        expectFresh(r)
        let (coins, streak, nights) = (r.model.coins, r.model.streak, r.model.stats.completeNights)
        playNight(r, day: 5)
        #expect(r.model.coins > coins && r.model.streak == streak + 1 && r.model.stats.completeNights == nights + 1)
        expectFresh(r)
    }

    @Test func aNapShowsAtOnce() {
        let r = rig(at: date(5, 14, 0))
        let before = r.model.coins
        r.model.startNap()
        r.clock.now = date(5, 14, 24); r.model.refresh()
        #expect(r.model.confirm(code: "1234"))
        #expect(r.model.coins >= before + 50)               // the nap's 50 (and maybe a first-nap achievement)
        expectFresh(r)
    }

    @Test func aJokerAndACoinSpendShowAtOnce() {
        let r = rig(at: date(5, 12))
        for d in 2...12 { playNight(r, day: d) }
        r.clock.now = date(13, 12); r.model.refresh()
        let coins = r.model.coins
        #expect(coins >= 1000)
        expectFresh(r)
        r.model.useJoker(.silver)
        #expect(r.model.coins == coins - 1000 && r.model.jokerState.uses.count == 1)
        expectFresh(r)
        let unlocked = r.model.unlockSchedule()                        // a spend of its own (2 000 🪙) when it is locked
        expectFresh(r)
        _ = unlocked
    }

    @Test func aScheduleChangeThatBreaksTheStreakShowsAtOnce() {
        let r = rig(at: date(2, 12))
        for d in 2...8 { playNight(r, day: d) }
        r.clock.now = date(9, 12); r.model.refresh()
        let streak = r.model.streak
        #expect(streak == 7)
        var s = r.model.settings.schedule
        s.wake = TimeOfDay(6, 0)
        _ = r.model.applySchedule(s)
        expectFresh(r)
        for d in 9...30 { playNight(r, day: d) }                        // runs into the lock; the change must be stable
        s.wake = TimeOfDay(5, 30)
        _ = r.model.applySchedule(s)
        expectFresh(r)
    }

    @Test func theDayRollingOverShowsAtOnce() {
        let r = rig(at: date(5, 12))
        for d in 2...5 { playNight(r, day: d) }
        r.clock.now = date(6, 12); r.model.refresh()
        #expect(r.model.streak == 4)
        // two days without a night: the cached streak must fall without any write to the store
        r.clock.now = date(8, 12); r.model.refresh()
        #expect(r.model.streak == cold(r).streak)
        #expect(r.model.streak < 4)
        r.clock.now = date(9, 12)                                       // even before refresh() moves the window
        #expect(r.model.stats == cold(r).stats)
    }

    @Test func aBackupRestoreAndAMergeShowAtOnce() throws {
        let a = rig(at: date(5, 12))
        for d in 2...6 { playNight(a, day: d) }
        let backup = a.model.makeBackup()
        let b = rig(at: date(7, 12))
        #expect(b.model.coins == 0 && b.model.streak == 0)              // warm the cache of the empty model
        try b.model.restore(backup)
        #expect(b.model.coins == a.model.coins && b.model.streak == a.model.streak)
        expectFresh(b)
        let c = rig(at: date(7, 12))
        #expect(c.model.coins == 0)
        _ = try c.model.mergeSync([backup])
        #expect(c.model.coins == a.model.coins && c.model.streak == a.model.streak)
        expectFresh(c)
    }

    @Test func theBackupDocumentBuildsItsDataOnlyOnExport() throws {
        let r = rig(at: date(5, 12))
        for d in 2...3 { playNight(r, day: d) }
        final class Counter: @unchecked Sendable { var n = 0 }
        let calls = Counter()
        let m = r.model
        let doc = BackupDocument { calls.n += 1; return (try? m.makeBackup().encoded()) ?? Data() }
        #expect(calls.n == 0)                                             // building the item (a render of Settings) costs nothing
        let data = doc.data
        #expect(calls.n == 1)
        let file = try BackupFile.decode(data)
        #expect(file.nights.count == 2 && file.version == BackupFile.currentVersion)
        let direct = try m.makeBackup().encoded()
        let a = try BackupFile.decode(direct)
        #expect(a.nights.count == file.nights.count && a.spends?.count == file.spends?.count)
        #expect(BackupDocument(data: direct).data == direct)
    }
}
