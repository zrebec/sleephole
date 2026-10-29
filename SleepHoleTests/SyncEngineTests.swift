import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

#if DEBUG   // `FolderSyncTransport` and the launch arguments `-syncFolder` / `-syncDevice` exist in Debug builds only

/// Phase SYNC, step S2a: the transport seam, the plain-folder transport and the engine that reads, merges and writes at
/// the right moments. Two or three models that share ONE temporary folder through `FolderSyncTransport` are the
/// devices – no iCloud anywhere. Every device has its own store, clock and `UserDefaults` suite (the first-contact flag
/// lives there).
@MainActor
struct SyncEngineTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sleephole-sync-\(UUID().uuidString)", isDirectory: true)
    }

    /// Wraps a transport: counts the calls that got through and can be made to fail, stall or be unavailable.
    final class Spy: SyncTransport, @unchecked Sendable {
        struct Failure: Error, LocalizedError { var errorDescription: String? { "the place is not reachable" } }
        struct NotReady: Error, LocalizedError { var errorDescription: String? { "the place is not ready yet" } }
        struct State {
            var reads = 0, writes = 0
            /// Every call of `readOthers()`, failed or not; and how often the change signal was asked for.
            var readAttempts = 0, changesRequested = 0
            var available = true, failReads = false, failWrites = false
            /// The next N reads throw `NotReady` (a transport whose place is not ready yet), then they succeed.
            var notReadyReads = 0
            var readDelay: TimeInterval = 0
        }
        private let lock = NSLock()
        private var state = State()
        let inner: any SyncTransport

        init(_ inner: any SyncTransport) { self.inner = inner }

        var snapshot: State { lock.withLock { state } }
        var reads: Int { snapshot.reads }
        var writes: Int { snapshot.writes }
        func set(_ change: (inout State) -> Void) { lock.withLock { change(&state) } }

        func isAvailable() async -> Bool {
            if !snapshot.available { return false }
            return await inner.isAvailable()
        }

        func write(_ data: Data) async throws {
            if snapshot.failWrites { throw Failure() }
            try await inner.write(data)
            set { $0.writes += 1 }
        }

        func readOthers() async throws -> [Data] {
            set { $0.readAttempts += 1 }
            let s = snapshot
            if s.readDelay > 0 { try await Task.sleep(for: .seconds(s.readDelay)) }
            if s.failReads { throw Failure() }
            let notReady = lock.withLock { () -> Bool in
                guard state.notReadyReads > 0 else { return false }
                state.notReadyReads -= 1
                return true
            }
            if notReady { throw NotReady() }
            set { $0.reads += 1 }
            return try await inner.readOthers()
        }

        var changes: AsyncStream<Void> {
            self.set { $0.changesRequested += 1 }
            return inner.changes
        }
    }

    /// One device: its own store, clock, defaults and transport spy over the shared folder.
    @MainActor struct Device {
        let container: ModelContainer
        let model: AppModel
        let clock: FakeClock
        let spy: Spy
        let source: FakeSleepSource?
        var sync: SyncEngine { model.sync }
        var context: ModelContext { container.mainContext }
    }

    /// `syncDelay` is long by default so that local changes never start a sync behind the test's back; the tests that
    /// are about the delay pass 0. `firstRead: true` = this install has already made its first read of the sync place.
    /// `retryDelay` is long by default so that a failed sync never starts a try behind the test's back; the tests that
    /// are about the tries pass their own. `source` stands in for Apple Health (default: none), `health` switches it on.
    func device(_ folder: URL, id: String, at now: Date, code: String = "1234", syncDelay: TimeInterval = 3600,
                guideWait: TimeInterval = 4, firstRead: Bool = false, inner: (any SyncTransport)? = nil,
                syncOn: Bool = true, health: Bool = false, source: FakeSleepSource? = nil,
                protectedData: @escaping @MainActor () -> Bool = { true },
                retryDelay: @escaping (Int) -> TimeInterval = { _ in 3600 }) -> Device {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, BoxRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(now)
        var s = AppSettings(); s.wakeCode = code
        s.usesSync = syncOn
        s.usesHealth = health
        let spy = Spy(inner ?? FolderSyncTransport(folder: folder, deviceId: id, pollInterval: 0.05))
        // "no transport at all" is the real `NoSyncTransport` (the engine tells it by its type), not a spy around it
        let transport: any SyncTransport = inner is NoSyncTransport ? inner! : spy
        let model = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s,
                             servicesEnabled: false, sleepSource: source, protectedDataAvailable: protectedData,
                             defaults: UserDefaults(suiteName: "sleephole-engine-\(UUID().uuidString)")!,
                             syncTransport: transport, syncDelay: syncDelay, syncGuideWait: guideWait, syncRetryDelay: retryDelay)
        model.sync.firstReadDone = firstRead
        return Device(container: c, model: model, clock: clock, spy: spy, source: source)
    }

    /// A whole night started at 22:25 on `day` and confirmed a minute after the wake time (a complete night).
    func night(_ d: Device, day: Int) {
        d.clock.now = date(day, 22, 25); d.model.refresh(); d.model.startNight()
        d.clock.now = date(day + 1, 6, 30) + 60; d.model.refresh()
        d.model.confirm(code: d.model.settings.wakeCode)
        d.model.acknowledgeResult()
    }

    /// The content of the file the device would write now, without `exportedAt`.
    func content(_ d: Device) -> BackupFile {
        var f = d.model.makeSyncFile()
        f.exportedAt = .distantPast
        return f
    }

    func file(_ folder: URL, _ id: String) -> BackupFile? {
        (try? Data(contentsOf: folder.appendingPathComponent(id + ".json"))).flatMap { try? BackupFile.decodeSync($0) }
    }

    /// When the town name was last written (the profile's stamp, phase SYNC).
    func townNameStamp(_ d: Device) -> Date? {
        (try? d.context.fetch(FetchDescriptor<UserProgress>()))?.first?.townNameChangedAt
    }

    func stopAll(_ devices: Device...) { for d in devices { d.sync.stop() } }

    /// Waits (at most about 5 s) until `condition` holds.
    func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @MainActor final class Counter { var n = 0 }

    /// A thread-safe list of the numbers the engine asked its retry closure about.
    final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [Int] = []
        func add(_ n: Int) { lock.withLock { list.append(n) } }
        var values: [Int] { lock.withLock { list } }
    }

    /// "Is the phone unlocked?" for `protectedDataAvailable`.
    @MainActor final class Locked { var value = true }

    // MARK: 1 – a night travels, the devices come to rest

    @Test func aNightBuiltOnOneDeviceReachesTheOtherAndNobodyWritesForever() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12)), b = device(folder, id: "B", at: date(1, 12), code: "9999")
        defer { stopAll(a, b) }
        for day in 1...3 { night(a, day: day) }

        await a.sync.syncNow()
        #expect(a.spy.writes == 1 && a.sync.lastSyncError == nil && a.sync.lastSyncAt != nil)
        #expect(file(folder, "A")?.nights.count == 3)

        b.clock.now = a.clock.now; b.model.refresh()
        await b.sync.syncNow()
        #expect(b.model.records().count == 3)
        #expect(b.model.townSnapshot?.buildings.map(\.buildingId) == a.model.townSnapshot?.buildings.map(\.buildingId))
        #expect(b.model.builtNights == 3 && b.model.coins == a.model.coins && b.model.coins > 0)
        #expect(b.spy.writes == 1 && file(folder, "B") != nil)                       // B has its own file now

        await a.sync.syncNow()                                                       // A reads B's file: nothing new …
        #expect(a.spy.writes == 1)                                                   // … so A's file is NOT rewritten
        await b.sync.syncNow()
        await a.sync.syncNow()
        #expect(a.spy.writes == 1 && b.spy.writes == 1)
        #expect(content(a) == content(b))
    }

    // MARK: 2 – never during a night

    @Test func duringANightNothingIsReadOrWrittenAndTheOwedSyncRunsWhenItEnds() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12), syncDelay: 0)
        defer { stopAll(a) }
        a.clock.now = date(1, 22, 25); a.model.refresh(); a.model.startNight()
        #expect(a.model.active != nil)

        await a.sync.syncNow()                                                       // called by hand
        a.sync.noteLocalChange()                                                     // and by the saves of the night
        await a.sync.settled()
        #expect(a.spy.reads == 0 && a.spy.writes == 0)
        #expect(a.sync.isOwed)
        #expect(file(folder, "A") == nil)

        a.model.abandonNight()                                                       // the night is over
        await a.sync.settled()
        #expect(a.model.active == nil)
        #expect(a.spy.reads == 1 && a.spy.writes == 1 && !a.sync.isOwed)
        #expect(file(folder, "A")?.nights.count == 1)
    }

    // MARK: 3, 4 – first contact

    /// The stamp of an empty install at first contact: the reference date itself.
    let minimal = Date(timeIntervalSinceReferenceDate: 0)

    @Test func aSingleDeviceStampsItsSettingsAtItsFirstSync() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(2, 10))
        defer { stopAll(a) }
        a.model.settings.volume = 0.4
        #expect(a.model.settings.changedAt == nil && !a.sync.firstReadDone)         // before the first read: no stamp

        await a.sync.syncNow()
        #expect(a.sync.firstReadDone)
        #expect(a.model.settings.changedAt == minimal && a.model.settings.volume == 0.4)       // not "now" (A1)
        #expect(a.spy.writes == 1 && file(folder, "A")?.settings.changedAt == minimal)
        await a.sync.syncNow()
        #expect(a.spy.writes == 1)                                                   // the stamp was not a second change

        a.clock.now = date(2, 11); a.model.settings.volume = 0.6                      // from now on a change is stamped
        #expect(a.model.settings.changedAt == date(2, 11))
    }

    @Test func aNewDeviceTakesTheSettingsOfTheAccountInsteadOfOverwritingThem() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(2, 9), code: "1111")
        let b = device(folder, id: "B", at: date(2, 9), code: "2222")
        defer { stopAll(a, b) }
        a.model.settings.alarmSound = .ode
        a.model.settings.schedule.wake = TimeOfDay(7, 0)
        a.clock.now = date(2, 10)
        await a.sync.syncNow()                                                       // A's first contact: the minimal stamp
        #expect(a.model.settings.changedAt == minimal)

        // B was set up (the guide) before it ever read the sync place – LATER than A's stamp, but unstamped
        b.clock.now = date(2, 11)
        b.model.settings.schedule.bedtime = TimeOfDay(23, 30)
        b.model.settings.wakeCode = "9999"
        b.model.settings.usesHealth = true
        #expect(b.model.settings.changedAt == nil)

        await b.sync.syncNow()
        #expect(b.model.settings.wakeCode == "1111" && b.model.settings.alarmSound == .ode)
        #expect(b.model.settings.schedule == a.model.settings.schedule)
        #expect(b.model.settings.changedAt == minimal)                               // A's stamp, not a new one
        #expect(b.model.settings.usesHealth)                                         // the per-device switch stays
        a.model.refresh()
        #expect(b.model.window.wake == a.model.window.wake)

        await a.sync.syncNow()                                                       // A, at its next sync, keeps its own
        #expect(a.model.settings.wakeCode == "1111" && a.model.settings.alarmSound == .ode)
        #expect(a.model.settings.schedule.wake == TimeOfDay(7, 0) && a.model.settings.changedAt == minimal)
        #expect(a.spy.writes == 1)                                                   // B's file said the same: A writes nothing
    }

    @Test func afterTheFirstContactAChangeIsStampedAndReachesTheOtherDevice() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(2, 9)), b = device(folder, id: "B", at: date(2, 9))
        defer { stopAll(a, b) }
        await a.sync.syncNow()
        await b.sync.syncNow()                                                       // both have made their first read
        #expect(a.sync.firstReadDone && b.sync.firstReadDone)

        b.clock.now = date(2, 12); b.model.settings.volume = 0.55
        #expect(b.model.settings.changedAt == date(2, 12))
        await b.sync.syncNow()
        await a.sync.syncNow()
        #expect(a.model.settings.volume == 0.55 && a.model.settings.changedAt == date(2, 12))
        // A now holds B's change, so A's own file differs from what it wrote: it writes once more (that is how a third
        // device would learn of it too) – and then both are at rest
        #expect(a.spy.writes == 2 && b.spy.writes == 2)
        await b.sync.syncNow()
        await a.sync.syncNow()
        #expect(a.spy.writes == 2 && b.spy.writes == 2 && content(a) == content(b))
    }

    // MARK: 5 – files that cannot be used

    @Test func aFileThatIsNotJSONAndAFileFromANewerVersionAreIgnored() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let c = device(folder, id: "C", at: date(1, 12)), d = device(folder, id: "D", at: date(1, 12))
        let b = device(folder, id: "B", at: date(1, 12))
        defer { stopAll(b, c, d) }
        night(c, day: 1)
        night(d, day: 5)
        await c.sync.syncNow()
        // D's file says it comes from a newer version of the app
        var future = d.model.makeSyncFile()
        future.version = BackupFile.currentVersion + 1
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try future.encodedForSync().write(to: folder.appendingPathComponent("D.json"))
        try Data("this is not json".utf8).write(to: folder.appendingPathComponent("junk.json"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("empty.json"))           // JSON, but not a sync file
        try Data("hello".utf8).write(to: folder.appendingPathComponent("note.txt"))

        b.clock.now = date(7, 12)
        await b.sync.syncNow()
        #expect(b.sync.lastSyncError == nil && b.sync.lastSyncAt != nil)             // never an error for the user
        #expect(b.model.records().map(\.keyString) == ["2026-10-02"])                // only C's night
        #expect(b.spy.writes == 1)
    }

    // MARK: 6 – the switch

    @Test func withSyncSwitchedOffNothingIsReadOrWrittenAndTheSwitchStaysOnItsDevice() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(3, 9), syncDelay: 0, firstRead: true)
        let b = device(folder, id: "B", at: date(3, 9), firstRead: true)
        defer { stopAll(a, b) }
        #expect(a.model.settings.usesSync && a.model.settings.syncOff == nil)        // ON by default

        a.model.settings.usesSync = false
        a.model.settings.usesHealth = true
        #expect(a.model.settings.changedAt == nil)                                   // neither switch is a stamped change
        await a.sync.settled()
        await a.sync.syncNow()
        #expect(a.spy.reads == 0 && a.spy.writes == 0 && file(folder, "A") == nil)

        // the sync switch is not in a sync file (the Health switch's position is – B2), and a merge keeps the local ones
        let shared = a.model.makeSyncFile()
        #expect(shared.settings.syncOff == nil && shared.settings.healthOn == true)
        let text = String(decoding: try shared.encodedForSync(), as: UTF8.self)
        #expect(!text.contains("syncOff"))
        b.clock.now = date(3, 11); b.model.settings.alarmSound = .bowl               // a newer stamp than A has
        b.model.settings.usesSync = false; b.model.settings.usesHealth = true
        a.clock.now = date(3, 12)
        #expect(try a.model.mergeSync([b.model.makeSyncFile()]))
        #expect(a.model.settings.alarmSound == .bowl && !a.model.settings.usesSync && a.model.settings.usesHealth)
        b.model.settings.usesSync = true; b.model.settings.usesHealth = false
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]) == false)
        #expect(b.model.settings.usesSync && !b.model.settings.usesHealth)

        a.model.settings.usesSync = true                                             // switched on again: a sync follows
        await a.sync.settled()
        #expect(a.spy.reads == 1 && a.spy.writes == 1 && file(folder, "A") != nil)
        #expect(a.model.settings.changedAt == date(3, 11))                           // still B's stamp; switching is no change
    }

    // MARK: 7 – three devices, any order

    @Test func threeDevicesInAScrambledOrderEndWithEqualFilesAndStopWriting() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12)), b = device(folder, id: "B", at: date(1, 12))
        let c = device(folder, id: "C", at: date(1, 12))
        defer { stopAll(a, b, c) }
        for d in [a, c, b] { await d.sync.syncNow() }                                // the three first contacts
        night(a, day: 1); night(a, day: 2)
        night(b, day: 2); night(b, day: 3)                                           // night 2 exists on both A and B
        night(c, day: 4)
        c.model.settings.volume = 0.8                                                // stamped (after the night: the newest)
        b.model.renameTown("Hill")
        a.context.insert(CoinSpend(at: date(5, 9), amount: 40, reason: "x")); try a.context.save()

        for d in [c, a, b, b, a, c, a, c, b] { await d.sync.syncNow() }
        for _ in 0..<3 { for d in [b, a, c] { await d.sync.syncNow() } }             // rest: nobody has anything new
        let written = [a, b, c].map(\.spy.writes)
        for d in [c, b, a, b, c, a] { await d.sync.syncNow() }
        #expect([a, b, c].map(\.spy.writes) == written)                              // nothing is written any more

        #expect(content(a) == content(b) && content(b) == content(c))
        #expect(a.model.records().count == 4 && a.model.settings.volume == 0.8 && a.model.townName == "Hill")
        #expect(content(a).spends?.count == 1)
    }

    // MARK: 8 – the guide waits for the first read

    @Test func aFileWithAFinishedGuideMeansNoGuideOnAFreshDevice() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12)), b = device(folder, id: "B", at: date(1, 12))
        defer { stopAll(a, b) }
        a.model.completeOnboarding()
        await a.sync.syncNow()

        #expect(b.sync.holdsGuide && !b.model.onboardingDone)                        // waiting: no guide shown yet
        #expect(!b.model.needsGuide)
        await b.sync.launch()
        #expect(b.model.onboardingDone && !b.sync.holdsGuide && !b.model.needsGuide)
    }

    @Test func withoutAFileOrWithoutATransportTheGuideIsNeededAsBefore() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let alone = device(folder, id: "A", at: date(1, 12))
        let offline = device(folder, id: "B", at: date(1, 12))
        offline.spy.set { $0.available = false }
        let none = device(folder, id: "C", at: date(1, 12), inner: NoSyncTransport())
        defer { stopAll(alone, offline, none) }

        #expect(alone.sync.holdsGuide && offline.sync.holdsGuide)                    // a transport that may be there: wait …
        #expect(!none.sync.holdsGuide && none.model.needsGuide)                      // … none at all: no waiting
        await alone.sync.launch()
        await offline.sync.launch()
        #expect(!alone.sync.holdsGuide && alone.model.needsGuide && !alone.model.onboardingDone)
        #expect(!offline.sync.holdsGuide && offline.model.needsGuide)
        #expect(offline.spy.reads == 0)
    }

    @Test func theGuideNeverWaitsLongerThanTheLimit() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let slow = device(folder, id: "A", at: date(1, 12), guideWait: 0.1)
        slow.spy.set { $0.readDelay = 1.0 }
        defer { stopAll(slow) }
        let start = Date()
        let launching = Task { await slow.sync.launch() }
        while slow.sync.holdsGuide, Date().timeIntervalSince(start) < 3 { try await Task.sleep(for: .milliseconds(10)) }
        let waited = Date().timeIntervalSince(start)
        #expect(!slow.sync.holdsGuide && slow.model.needsGuide)                      // the guide may come
        #expect(waited < 0.8)                                                        // … long before the slow read ends
        await launching.value                                                        // which then goes on and finishes
        #expect(slow.spy.reads == 1 && slow.sync.lastSyncError == nil)
    }

    @Test func theGuideIsNotHeldWhenThereIsAlreadyAStoryOrSyncIsOff() throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let done = device(folder, id: "A", at: date(1, 12))
        done.model.completeOnboarding()
        done.sync.attach(done.model)
        #expect(!done.sync.holdsGuide)

        let withNight = device(folder, id: "B", at: date(1, 12))
        night(withNight, day: 1)
        withNight.sync.attach(withNight.model)
        #expect(!withNight.sync.holdsGuide && withNight.model.needsGuide)

        let off = device(folder, id: "C", at: date(1, 12))
        off.model.settings.usesSync = false
        off.sync.attach(off.model)
        #expect(!off.sync.holdsGuide && off.model.needsGuide)
        stopAll(done, withNight, off)
    }

    // MARK: 9 – local changes are gathered

    @Test func severalLocalChangesInARowGiveOneSync() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12), syncDelay: 0, firstRead: true)
        defer { stopAll(a) }
        for _ in 0..<5 { a.sync.noteLocalChange() }
        a.model.settings.volume = 0.3
        a.model.settings.volume = 0.35
        a.model.settings.alarmSound = .bowl
        await a.sync.settled()
        #expect(a.spy.reads == 1 && a.spy.writes == 1)

        a.model.settings.volume = 0.5                                                // a later change is a sync of its own
        await a.sync.settled()
        #expect(a.spy.reads == 2 && a.spy.writes == 2)

        a.sync.noteAppActive()                                                       // becoming active: right away, no change
        await a.sync.settled()
        #expect(a.spy.reads == 3 && a.spy.writes == 2)
    }

    @Test func aChangeOfAnotherDeviceStartsASyncThroughTheTransportsChangeSignal() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12)), b = device(folder, id: "B", at: date(1, 12))
        defer { stopAll(a, b) }
        await a.sync.launch()                                                        // A watches the folder
        night(b, day: 1)
        await b.sync.syncNow()                                                       // B's file appears
        try await eventually { !a.model.records().isEmpty }
        #expect(a.model.records().count == 1)
    }

    // MARK: 10 – errors

    @Test func aTransportThatThrowsLeavesTheStoreAloneAndTheNextGoodSyncClearsTheError() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12)), b = device(folder, id: "B", at: date(1, 12))
        defer { stopAll(a, b) }
        night(a, day: 1)
        await a.sync.syncNow()

        b.spy.set { $0.failReads = true }
        let before = b.model.makeBackup()
        await b.sync.syncNow()
        #expect(b.sync.lastSyncError == "the place is not reachable" && b.sync.lastSyncAt == nil)
        #expect(b.model.records().isEmpty && b.spy.writes == 0 && !b.sync.firstReadDone)
        #expect(b.model.makeBackup().nights == before.nights && b.model.settings.changedAt == nil)

        b.spy.set { $0.failReads = false; $0.failWrites = true }                     // reading works, writing does not
        await b.sync.syncNow()
        #expect(b.sync.lastSyncError != nil && b.spy.writes == 0)
        #expect(b.model.records().count == 1)                                        // what was read is kept

        b.spy.set { $0.failWrites = false }
        await b.sync.syncNow()                                                       // and the write is retried
        #expect(b.sync.lastSyncError == nil && b.sync.lastSyncAt != nil && b.spy.writes == 1)
        #expect(file(folder, "B")?.nights.count == 1)
    }

    // MARK: 11 – what Settings shows (the place's state, the count of files, the status line)

    @Test func theEngineRemembersWhetherThePlaceWasUsableAndHowManyFilesItRead() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12)), b = device(folder, id: "B", at: date(1, 12))
        defer { stopAll(a, b) }
        func status(_ d: Device) -> SyncStatus? {
            SyncStatus.of(enabled: d.model.settings.usesSync, place: d.sync.place, error: d.sync.lastSyncError,
                          lastSyncAt: d.sync.lastSyncAt)
        }

        // before the first attempt nothing is known
        #expect(b.sync.place == .unknown && b.sync.othersRead == 0 && status(b) == .notYet)

        await a.sync.syncNow()                                                       // alone: usable, no other file
        #expect(a.sync.place == .available && a.sync.othersRead == 0)
        guard case .synced = status(a) else { Issue.record("expected a synced status"); return }

        night(a, day: 1)
        await a.sync.syncNow()
        await b.sync.syncNow()                                                       // reads A's one file
        #expect(b.sync.place == .available && b.sync.othersRead == 1)
        #expect(status(b) == .synced(b.clock.now))

        // the place goes away: the state says so, the last good values stay, the status is "not available"
        let reads = b.sync.othersRead, at = b.sync.lastSyncAt
        b.spy.set { $0.available = false }
        await b.sync.syncNow()
        #expect(b.sync.place == .unavailable && b.sync.lastSyncAt == at && b.sync.othersRead == reads)
        #expect(status(b) == .unavailable)

        // back, but reading fails: usable, an error, the status is "couldn't sync" (and never the error's text)
        b.spy.set { $0.available = true; $0.failReads = true }
        await b.sync.syncNow()
        #expect(b.sync.place == .available && b.sync.lastSyncError != nil && status(b) == .failed)

        // and everything is fine again
        b.spy.set { $0.failReads = false }
        b.clock.now = date(2, 12)
        await b.sync.syncNow()
        #expect(b.sync.place == .available && b.sync.lastSyncError == nil && status(b) == .synced(date(2, 12)))
    }

    @Test func aDeviceWithoutATransportReportsThePlaceAsUnavailableAndSwitchedOffTouchesNothing() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let none = device(folder, id: "N", at: date(1, 12), inner: NoSyncTransport())
        let off = device(folder, id: "O", at: date(1, 12))
        defer { stopAll(none, off) }
        await none.sync.syncNow()
        #expect(none.sync.place == .unavailable && none.sync.lastSyncAt == nil)

        off.model.settings.usesSync = false
        await off.sync.syncNow()                                                     // switched off: the engine never looks
        #expect(off.sync.place == .unknown && off.spy.reads == 0)
        #expect(SyncStatus.of(enabled: off.model.settings.usesSync, place: off.sync.place, error: nil, lastSyncAt: nil) == nil)
    }

    // MARK: the folder transport and the helpers

    @Test func theFolderTransportWritesOneFilePerDeviceAndReadsOnlyTheOthers() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = FolderSyncTransport(folder: folder, deviceId: "A"), b = FolderSyncTransport(folder: folder, deviceId: "B")
        #expect(try await a.readOthers().isEmpty)                                    // no folder yet: nothing, no error
        #expect(await a.isAvailable())
        try await a.write(Data("one".utf8))
        try await b.write(Data("two".utf8))
        try await a.write(Data("three".utf8))                                        // replaces A's file
        try Data("x".utf8).write(to: folder.appendingPathComponent("note.txt"))
        #expect(try await a.readOthers().map { String(decoding: $0, as: UTF8.self) } == ["two"])
        #expect(try await b.readOthers().map { String(decoding: $0, as: UTF8.self) } == ["three"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }.sorted()
                == ["A.json", "B.json"])
        // a device id becomes a file name: nothing that could leave the folder
        #expect(FolderSyncTransport(folder: folder, deviceId: "../x y").deviceId == "___x_y")
        #expect(!(await NoSyncTransport().isAvailable()))
    }

    @Test(.timeLimit(.minutes(1))) func theFolderTransportSignalsOnlyChangesOfOtherDevices() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = FolderSyncTransport(folder: folder, deviceId: "A", pollInterval: 0.05)
        let b = FolderSyncTransport(folder: folder, deviceId: "B", pollInterval: 0.05)
        let seen = Counter()
        let stream = a.changes
        let counting = Task { @MainActor in for await _ in stream { seen.n += 1 } }
        defer { counting.cancel() }

        try await a.write(Data("own".utf8))                                          // its own file is no change
        try await Task.sleep(for: .milliseconds(400))
        #expect(seen.n == 0)
        try await b.write(Data("one".utf8))
        try await eventually { seen.n > 0 }
        #expect(seen.n == 1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(seen.n == 1)                                                         // no change, no signal
        try await b.write(Data("longer than before".utf8))
        try await eventually { seen.n > 1 }
        #expect(seen.n == 2)
    }

    @Test func theDeviceIdIsRandomAndStablePerInstall() throws {
        let one = UserDefaults(suiteName: "sleephole-device-\(UUID().uuidString)")!
        let two = UserDefaults(suiteName: "sleephole-device-\(UUID().uuidString)")!
        let id = SyncDevice.id(defaults: one, vendorId: "V1")
        #expect(!id.isEmpty && SyncDevice.id(defaults: one, vendorId: "V1") == id && SyncDevice.id(defaults: two, vendorId: "V1") != id)
    }

    @Test func aRestoreOntoANewPhoneGetsANewDeviceIdAndTheSamePhoneKeepsItsId() throws {
        let defaults = UserDefaults(suiteName: "sleephole-device-\(UUID().uuidString)")!
        let id = SyncDevice.id(defaults: defaults, vendorId: "V1")
        #expect(SyncDevice.id(defaults: defaults, vendorId: "V1") == id)                // the same phone
        #expect(SyncDevice.id(defaults: defaults, vendorId: nil) == id)                 // early after a reboot: nothing changes
        #expect(SyncDevice.id(defaults: defaults, vendorId: "") == id)
        #expect(SyncDevice.id(defaults: defaults, vendorId: "V1") == id)                // … and the stored vendor stayed

        let restored = SyncDevice.id(defaults: defaults, vendorId: "V2")                // the defaults came back on another phone
        #expect(restored != id)
        #expect(SyncDevice.id(defaults: defaults, vendorId: "V2") == restored)
        #expect(SyncDevice.id(defaults: defaults, vendorId: nil) == restored)

        // an id made while no vendor id was available adopts the first one that is seen – then it is bound to it
        let late = UserDefaults(suiteName: "sleephole-device-\(UUID().uuidString)")!
        let lateId = SyncDevice.id(defaults: late, vendorId: nil)
        #expect(SyncDevice.id(defaults: late, vendorId: "V1") == lateId)
        #expect(SyncDevice.id(defaults: late, vendorId: "V2") != lateId)
    }

    @Test func launchArgumentsPickTheTransportAndTestsAndTheSimulatorGetNone() throws {
        let one = UserDefaults(suiteName: "sleephole-device-\(UUID().uuidString)")!
        let id = SyncDevice.id(defaults: one, vendorId: "V1")
        #expect(SyncTransports.forLaunch(args: ["x"], defaults: one, vendorId: "V1") is NoSyncTransport)    // hosted tests
        #if targetEnvironment(simulator)
        #expect(SyncTransports.forLaunch(args: ["x"], defaults: one, underTest: false, vendorId: "V1") is NoSyncTransport)
        #expect(!SyncTransports.usesICloud)
        #else
        #expect(SyncTransports.forLaunch(args: ["x"], defaults: one, underTest: false, vendorId: "V1") is ICloudSyncTransport)
        #endif
        let folder = SyncTransports.forLaunch(args: ["-syncFolder", "/tmp/shared"], defaults: one, vendorId: "V1") as? FolderSyncTransport
        #expect(folder?.deviceId == id && folder?.folder.path == "/tmp/shared")
        let named = SyncTransports.forLaunch(args: ["-syncDevice", "phone", "-syncFolder", "/tmp/shared"], defaults: one, vendorId: "V1")
        #expect((named as? FolderSyncTransport)?.deviceId == "phone")
    }

    // MARK: a transport that is not ready is no first contact

    @Test func aTransportThatIsNotReadyYetStampsNothingAndTheLaterReadTakesTheAccountsSettings() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(2, 9), code: "1111")
        let b = device(folder, id: "B", at: date(2, 9), code: "2222", guideWait: 0.1)
        defer { stopAll(a, b) }
        a.model.settings.alarmSound = .ode
        a.model.settings.schedule.wake = TimeOfDay(7, 0)
        a.clock.now = date(2, 10)
        await a.sync.syncNow()                                                       // the account holds A's stamped settings
        #expect(a.model.settings.changedAt == minimal)

        // B's place answers "not ready" after a while (iCloud's listing has not arrived): longer than the guide waits
        b.spy.set { $0.readDelay = 0.5; $0.notReadyReads = 1 }
        let start = Date()
        let launching = Task { await b.sync.launch() }
        while b.sync.holdsGuide, Date().timeIntervalSince(start) < 3 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!b.sync.holdsGuide && b.model.needsGuide)                            // released at the limit …
        #expect(Date().timeIntervalSince(start) < 0.45)                              // … not when the read gave up
        #expect(!b.sync.firstReadDone)

        // the user goes through the guide meanwhile – LATER than A's stamp, but this install has not read yet
        b.clock.now = date(2, 11)
        b.model.settings.schedule.bedtime = TimeOfDay(23, 30)
        b.model.settings.wakeCode = "9999"
        b.model.completeOnboarding()
        #expect(b.model.settings.changedAt == nil)

        await launching.value                                                        // the read gives up: "not ready"
        #expect(b.sync.lastSyncError == "the place is not ready yet" && b.sync.lastSyncAt == nil)
        #expect(!b.sync.firstReadDone && b.model.settings.changedAt == nil)          // no first contact, nothing stamped
        #expect(b.spy.writes == 0 && file(folder, "B") == nil && b.model.settings.wakeCode == "9999")

        b.spy.set { $0.readDelay = 0 }
        b.sync.noteAppActive()                                                       // the place is ready: the next sync
        await b.sync.settled()
        #expect(b.sync.firstReadDone && b.sync.lastSyncError == nil && b.sync.lastSyncAt != nil)
        #expect(b.model.settings.wakeCode == "1111" && b.model.settings.alarmSound == .ode)    // the account's win …
        #expect(b.model.settings.schedule.wake == TimeOfDay(7, 0) && b.model.settings.schedule.bedtime == a.model.settings.schedule.bedtime)
        #expect(b.model.settings.changedAt == minimal)                               // … with A's stamp, not a new one
        #expect(b.spy.writes == 1 && file(folder, "B")?.settings.wakeCode == "1111")
    }

    @Test func aTransportThatIsNotReadyReleasesTheGuideAtOnceAndIsNoFirstContactEither() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let b = device(folder, id: "B", at: date(2, 9))                              // the guide would wait 4 s
        defer { stopAll(b) }
        b.spy.set { $0.notReadyReads = 2 }
        let start = Date()
        await b.sync.launch()
        #expect(Date().timeIntervalSince(start) < 1 && !b.sync.holdsGuide && b.model.needsGuide)
        #expect(!b.sync.firstReadDone && b.sync.lastSyncError != nil && b.spy.writes == 0)
        b.model.settings.volume = 0.2
        #expect(b.model.settings.changedAt == nil)                                   // still unstamped

        await b.sync.syncNow()                                                       // the second "not ready"
        #expect(!b.sync.firstReadDone && b.model.settings.changedAt == nil)
        await b.sync.syncNow()                                                       // ready, and the account is empty
        #expect(b.sync.firstReadDone && b.model.settings.changedAt == minimal && b.spy.writes == 1)
    }

    // MARK: the iCloud transport under the engine (a temporary folder stands in for the container)

    @Test func twoDevicesThroughTheICloudTransportOverAFolderAndAListingThatArrivesLate() async throws {
        let root = tempFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let sync = root.appendingPathComponent(ICloudSyncTransport.folderName, isDirectory: true)
        func transport(_ id: String, gathered: Bool = true) -> (ICloudSyncTransport, FakeListing) {
            let listing = FakeListing(folder: sync); listing.gathered = gathered
            return (ICloudSyncTransport(deviceId: id, container: FixedContainer(root: root), listing: listing,
                                        gatherWait: 0.05, downloadWait: 0.05, pollInterval: 0.01), listing)
        }
        let (tA, _) = transport("A"), (tB, listingB) = transport("B", gathered: false)
        let a = device(root, id: "A", at: date(2, 9), code: "1111", inner: tA)
        let b = device(root, id: "B", at: date(2, 9), code: "2222", inner: tB)
        defer { stopAll(a, b) }
        a.model.settings.alarmSound = .ode
        a.clock.now = date(2, 10)
        night(a, day: 2)
        a.clock.now = date(4, 10)
        await a.sync.syncNow()
        #expect(a.spy.writes == 1 && FileManager.default.fileExists(atPath: sync.appendingPathComponent("A.json").path))

        b.clock.now = date(4, 11)
        b.model.settings.wakeCode = "9999"                                           // the guide, before B ever read
        await b.sync.syncNow()                                                       // the listing has not arrived
        #expect(b.sync.lastSyncError == ICloudSyncError.listingNotReady.errorDescription)
        #expect(!b.sync.firstReadDone && b.model.settings.changedAt == nil && b.model.records().isEmpty && b.spy.writes == 0)

        listingB.gathered = true
        await b.sync.syncNow()
        #expect(b.sync.lastSyncError == nil && b.sync.firstReadDone)
        #expect(b.model.records().count == 1 && b.model.settings.wakeCode == "1111" && b.model.settings.alarmSound == .ode)
        #expect(b.spy.writes == 1 && FileManager.default.fileExists(atPath: sync.appendingPathComponent("B.json").path))
        await a.sync.syncNow()
        await b.sync.syncNow()
        #expect(a.spy.writes == 1 && b.spy.writes == 1 && content(a) == content(b))
    }

    // MARK: A1 – first contact never makes a fresh install "the newest"

    @Test func theFirstContactStampCountsFinalizedRealNightsAndNapsOnly() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12))
        defer { stopAll(a) }
        #expect(a.model.firstContactStamp() == Date(timeIntervalSinceReferenceDate: 0))      // an empty install
        night(a, day: 1); night(a, day: 2)
        #expect(a.model.firstContactStamp() == Date(timeIntervalSinceReferenceDate: 2))
        // a nap counts, a debug night and a night that is still running do not
        a.clock.now = date(3, 13, 5); a.model.refresh(); a.model.startNap()
        a.model.abandonNight(); a.model.acknowledgeResult()
        let naps = a.model.records().filter { $0.isNap && $0.isFinalized }.count
        a.clock.now = date(4, 12); a.model.refresh()
        a.model.startTestNight(minutes: 1, grace: 1); a.model.startNight()
        a.model.abandonNight(); a.model.acknowledgeResult(); a.model.cancelFastNight()
        a.clock.now = date(4, 22, 25); a.model.refresh(); a.model.startNight()
        #expect(a.model.active != nil)
        #expect(a.model.firstContactStamp() == Date(timeIntervalSinceReferenceDate: Double(2 + naps)))
    }

    @Test func anEmptyFirstReadStampsTheMinimalDateAndAFreshInstallNeverBecomesTheNewest() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 9))                              // an install with 3 nights
        let b = device(folder, id: "B", at: date(5, 9))                              // the iCloud listing was empty for it …
        defer { stopAll(a, b) }
        for day in 1...3 { night(a, day: day) }
        a.clock.now = date(5, 9); a.model.refresh()
        a.model.settings.alarmSound = .ode; a.model.settings.wakeCode = "1111"      // unstamped: A has not read yet
        #expect(a.model.settings.changedAt == nil)
        await b.sync.syncNow()                                                       // … so its first contact finds nothing
        #expect(b.model.settings.changedAt == minimal && b.sync.firstReadDone)       // "older than any real change", not now
        #expect(file(folder, "B")?.settings.changedAt == minimal)

        // the real phone arrives afterwards and is NOT overwritten by the fresh install's defaults
        await a.sync.syncNow()
        #expect(a.model.settings.alarmSound == .ode && a.model.settings.wakeCode == "1111")
        #expect(a.model.settings.changedAt == Date(timeIntervalSinceReferenceDate: 3))
        await b.sync.syncNow()                                                       // and the fresh one takes A's
        #expect(b.model.settings.alarmSound == .ode && b.model.settings.wakeCode == "1111")
        #expect(b.model.settings.changedAt == Date(timeIntervalSinceReferenceDate: 3))
    }

    @Test(arguments: [true, false]) func theMoreEstablishedDeviceWinsWhicheverReadsFirst(establishedFirst: Bool) async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let established = device(folder, id: "E", at: date(5, 9), code: "1111")
        let fresh = device(folder, id: "F", at: date(5, 9), code: "2222")
        defer { stopAll(established, fresh) }
        for day in 1...3 { night(established, day: day) }
        established.clock.now = date(5, 9); established.model.refresh()
        established.model.settings.alarmSound = .ode
        fresh.model.settings.alarmSound = .bowl                                      // both unstamped, different settings

        // the order of the two first contacts, and then everybody syncs once more
        for d in establishedFirst ? [established, fresh] : [fresh, established] { await d.sync.syncNow() }
        for d in [established, fresh, established] { await d.sync.syncNow() }
        for d in [established, fresh] {
            #expect(d.model.settings.alarmSound == .ode && d.model.settings.wakeCode == "1111")
            #expect(d.model.settings.changedAt == Date(timeIntervalSinceReferenceDate: 3))
        }
        #expect(content(established) == content(fresh))
    }

    @Test func aRealChangeBeatsEveryFirstContactStampOfEitherDevice() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let established = device(folder, id: "E", at: date(5, 9)), fresh = device(folder, id: "F", at: date(5, 9))
        defer { stopAll(established, fresh) }
        for day in 1...3 { night(established, day: day) }
        await fresh.sync.syncNow(); await established.sync.syncNow()                 // two first contacts: ref+0 and ref+3
        #expect(fresh.model.settings.changedAt == minimal)
        #expect(established.model.settings.changedAt == Date(timeIntervalSinceReferenceDate: 3))

        fresh.clock.now = date(6, 10); fresh.model.settings.volume = 0.25             // the user changes something on the FRESH one
        #expect(fresh.model.settings.changedAt == date(6, 10))
        await fresh.sync.syncNow(); await established.sync.syncNow()
        #expect(established.model.settings.volume == 0.25 && established.model.settings.changedAt == date(6, 10))
        established.clock.now = date(6, 11); established.model.settings.volume = 0.5  // and then on the established one
        await established.sync.syncNow(); await fresh.sync.syncNow()
        #expect(fresh.model.settings.volume == 0.5 && fresh.model.settings.changedAt == date(6, 11))
    }

    @Test func aReadWithAFileThatCannotBeUsedIsNoFirstContact() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 9)), b = device(folder, id: "B", at: date(5, 9))
        defer { stopAll(a, b) }
        a.model.settings.alarmSound = .ode
        b.model.settings.volume = 0.2
        // one file does not decode, another comes from a newer version of the app
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("this is not json".utf8).write(to: folder.appendingPathComponent("junk.json"))
        var future = a.model.makeSyncFile()
        future.version = BackupFile.currentVersion + 1
        try future.encodedForSync().write(to: folder.appendingPathComponent("Z.json"))

        await b.sync.syncNow()
        #expect(b.sync.lastSyncError == nil)                                         // never an error for the user
        #expect(!b.sync.firstReadDone && b.model.settings.changedAt == nil)          // … and no first contact: no stamp
        await b.sync.syncNow()
        #expect(!b.sync.firstReadDone && b.model.settings.changedAt == nil)          // the next sync tries again, same result

        // the junk goes away: the next sync is the first contact
        try FileManager.default.removeItem(at: folder.appendingPathComponent("junk.json"))
        await b.sync.syncNow()
        #expect(!b.sync.firstReadDone)                                               // the newer version's file is still there
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Z.json"))
        await b.sync.syncNow()
        #expect(b.sync.firstReadDone && b.model.settings.changedAt == minimal)
    }

    // MARK: A3 – a failed sync is tried again by the engine itself

    @Test func theStandardDelaysGrowAndThenRepeatEveryFiveMinutes() {
        #expect((0..<6).map(SyncEngine.standardRetryDelay) == [10, 30, 120, 300, 300, 300])
    }

    @Test(.timeLimit(.minutes(1))) func aFailedSyncIsTriedAgainWithGrowingDelaysUntilItGetsThrough() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let asked = Asked()
        let a = device(folder, id: "A", at: date(5, 9), retryDelay: { n in asked.add(n); return 0.03 * Double(n + 1) })
        defer { stopAll(a) }
        night(a, day: 1)
        a.spy.set { $0.failReads = true }
        await a.sync.syncNow()                                                       // the first failure schedules the first retry
        #expect(a.sync.lastSyncError != nil && a.sync.isRetrying && a.sync.retryAttempt == 1)

        try await eventually { a.spy.snapshot.readAttempts >= 5 }
        #expect(a.spy.snapshot.readAttempts >= 5 && a.spy.reads == 0)
        let before = asked.values
        #expect(before.count >= 4 && before.prefix(4) == [0, 1, 2, 3])               // ever-longer delays: 0, 1, 2, 3 failures so far

        a.spy.set { $0.failReads = false }                                           // the place is back
        try await eventually { a.sync.lastSyncError == nil }
        #expect(a.sync.lastSyncError == nil && a.sync.lastSyncAt != nil && a.spy.writes == 1)
        #expect(!a.sync.isRetrying && a.sync.retryAttempt == 0)                      // a good sync ends the series
        let attempts = a.spy.snapshot.readAttempts
        try await Task.sleep(for: .milliseconds(300))
        #expect(a.spy.snapshot.readAttempts == attempts)                             // and nothing is tried any more
    }

    @Test(.timeLimit(.minutes(1))) func theTriesStopWhenTheSwitchIsTurnedOffOrTheEngineStops() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 9), retryDelay: { _ in 0.05 })
        let b = device(folder, id: "B", at: date(5, 9), retryDelay: { _ in 0.05 })
        defer { stopAll(a, b) }
        for d in [a, b] { d.spy.set { $0.failReads = true }; await d.sync.syncNow() }
        try await eventually { a.spy.snapshot.readAttempts >= 3 && b.spy.snapshot.readAttempts >= 3 }

        a.model.settings.usesSync = false                                            // the switch
        b.sync.stop()                                                                // the engine
        #expect(!a.sync.isRetrying && !b.sync.isRetrying && a.sync.retryAttempt == 0)
        await a.sync.settled(); await b.sync.settled()                               // a try that had already begun finishes
        let (ra, rb) = (a.spy.snapshot.readAttempts, b.spy.snapshot.readAttempts)
        try await Task.sleep(for: .milliseconds(300))
        #expect(a.spy.snapshot.readAttempts == ra && b.spy.snapshot.readAttempts == rb)

        // a failure that comes while the switch is off schedules nothing (a read that was already running)
        let c = device(folder, id: "C", at: date(5, 9), retryDelay: { _ in 0.05 })
        defer { stopAll(c) }
        c.spy.set { $0.failReads = true; $0.readDelay = 0.15 }
        let running = Task { await c.sync.syncNow() }
        try await Task.sleep(for: .milliseconds(40))
        c.model.settings.usesSync = false
        await running.value
        #expect(!c.sync.isRetrying && c.spy.snapshot.readAttempts == 1)
    }

    @Test(.timeLimit(.minutes(1))) func neverATryDuringANightTheSyncIsOwedInstead() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 22, 25), retryDelay: { _ in 0.05 })
        defer { stopAll(a) }
        // a read that fails while a night starts: no try is scheduled, the sync is owed
        a.spy.set { $0.failReads = true; $0.readDelay = 0.15 }
        let running = Task { await a.sync.syncNow() }
        try await Task.sleep(for: .milliseconds(40))
        a.model.refresh(); a.model.startNight()
        #expect(a.model.active != nil)
        await running.value
        #expect(!a.sync.isRetrying && a.sync.isOwed)

        // a try that was already pending when the night began does not touch the transport
        a.model.abandonNight(); a.model.acknowledgeResult()
        a.spy.set { $0.readDelay = 0 }
        await a.sync.syncNow()                                                       // fails again: a try is pending
        #expect(a.sync.isRetrying)
        a.clock.now = date(6, 22, 25); a.model.refresh(); a.model.startNight()
        #expect(a.model.active != nil)
        let attempts = a.spy.snapshot.readAttempts
        try await Task.sleep(for: .milliseconds(300))
        #expect(a.spy.snapshot.readAttempts == attempts && a.sync.isOwed)
    }

    // MARK: A6 – with the switch off nothing runs

    @Test(.timeLimit(.minutes(1))) func withTheSwitchOffTheTransportIsNeitherReadNorWatchedUntilItIsSwitchedOn() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 9), syncDelay: 0, syncOn: false)
        let b = device(folder, id: "B", at: date(5, 9))
        defer { stopAll(a, b) }
        night(b, day: 1)
        await b.sync.syncNow()

        await a.sync.launch()                                                        // off: no read, no subscription
        #expect(a.spy.snapshot.readAttempts == 0 && a.spy.snapshot.changesRequested == 0 && !a.sync.isWatching)
        night(b, day: 2); await b.sync.syncNow()                                     // the other device's file changes …
        try await Task.sleep(for: .milliseconds(300))
        #expect(a.spy.snapshot.readAttempts == 0 && a.model.records().isEmpty)       // … and the off device never looks

        a.model.settings.usesSync = true                                             // switched on: watching starts, a sync follows
        #expect(a.spy.snapshot.changesRequested == 1 && a.sync.isWatching)
        try await eventually { a.model.records().count == 2 }
        #expect(a.model.records().count == 2)

        a.model.settings.usesSync = false                                            // switched off again: the watcher ends
        #expect(!a.sync.isWatching)
        let reads = a.spy.snapshot.readAttempts
        night(b, day: 3); await b.sync.syncNow()
        try await Task.sleep(for: .milliseconds(300))
        #expect(a.spy.snapshot.readAttempts == reads && a.model.records().count == 2)
        a.model.settings.usesSync = true                                             // and on again: a new subscription
        #expect(a.spy.snapshot.changesRequested == 2 && a.sync.isWatching)
        try await eventually { a.model.records().count == 3 }
        #expect(a.model.records().count == 3)
    }

    @Test func switchingOnBeforeTheLaunchWatchesNothingYetAndTheLaunchStartsIt() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 9), syncOn: false)
        defer { stopAll(a) }
        a.model.settings.usesSync = true
        #expect(!a.sync.isWatching)                                                  // the app has not launched the engine yet
        await a.sync.launch()
        #expect(a.sync.isWatching && a.spy.snapshot.changesRequested == 1)
    }

    // MARK: A7 – one encode per quiet sync

    @Test func aQuietSyncEncodesOnceAndWritesNothing() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 9))
        defer { stopAll(a) }
        night(a, day: 1)
        await a.sync.syncNow()
        #expect(a.spy.writes == 1 && a.sync.encodes == 2)                            // the comparable form, then the real file
        for round in 1...3 {
            await a.sync.syncNow()
            #expect(a.spy.writes == 1 && a.sync.encodes == 2 + round)                // one encode, no write
        }
        night(a, day: 2)
        await a.sync.syncNow()
        #expect(a.spy.writes == 2 && a.sync.encodes == 7)                            // a change: both again
    }

    // MARK: B1 / B2 – Apple Health after a sync

    @Test(.timeLimit(.minutes(1))) func aNightThatArrivesThroughASyncGetsItsSleepValuesAtOnceWhenHealthIsOn() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let src = FakeSleepSource()
        let a = device(folder, id: "A", at: date(5, 9))
        let b = device(folder, id: "B", at: date(5, 9), health: true, source: src)
        let off = device(folder, id: "O", at: date(5, 9), source: FakeSleepSource())
        defer { stopAll(a, b, off) }
        night(a, day: 1); night(a, day: 2)
        await a.sync.syncNow()
        b.clock.now = date(5, 9); b.model.refresh(); off.clock.now = date(5, 9); off.model.refresh()

        await off.sync.syncNow()                                                     // Health off: the source is never asked
        try await Task.sleep(for: .milliseconds(100))
        #expect(off.model.records().count == 2 && off.source?.asked.isEmpty == true && !off.model.settings.usesHealth)

        await b.sync.syncNow()                                                       // merges two nights, Health is on
        #expect(b.model.records().count == 2)
        try await eventually { b.model.records().allSatisfy { $0.sleepReadAt != nil } }
        #expect(b.model.records().allSatisfy { $0.sleepReadAt != nil } && src.asked.count == 2)
        #expect(!b.model.makeSyncFile().nights.contains { $0.sleepReadAt != nil })    // and still never into a sync file

        await b.sync.syncNow()                                                       // nothing new: nothing is asked again
        try await Task.sleep(for: .milliseconds(100))
        #expect(src.asked.count == 2)
    }

    @Test(.timeLimit(.minutes(1))) func theReadAfterAMergeWaitsForANightToEndAndForTheUnlockedPhone() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let src = FakeSleepSource()
        let locked = Locked()
        let a = device(folder, id: "A", at: date(5, 9))
        let b = device(folder, id: "B", at: date(5, 9), health: true, source: src, protectedData: { locked.value })
        defer { stopAll(a, b) }
        night(a, day: 1)
        await a.sync.syncNow()
        b.clock.now = date(5, 9); b.model.refresh()
        locked.value = false                                                         // the phone is locked
        await b.sync.syncNow()
        try await Task.sleep(for: .milliseconds(150))
        #expect(b.model.records().count == 1 && src.asked.isEmpty)                   // a no-op while locked
        locked.value = true
        await b.model.refreshSleepIfIdle()                                           // the ordinary later read still finds it
        #expect(src.asked.count == 1)
    }

    @Test(.timeLimit(.minutes(1))) func aNewInstallTakesTheHealthSwitchOnceAtFirstContact() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 9), health: true)
        let src = FakeSleepSource()
        let b = device(folder, id: "B", at: date(5, 9), source: src)
        defer { stopAll(a, b) }
        night(a, day: 1)
        await a.sync.syncNow()
        #expect(file(folder, "A")?.settings.healthOn == true)                        // the position travels …
        #expect(file(folder, "A")?.nights.allSatisfy { $0.sleepReadAt == nil } == true)   // … the sleep values never

        b.clock.now = date(5, 9); b.model.refresh()
        #expect(!b.model.settings.usesHealth)
        await b.sync.syncNow()                                                       // first contact
        try await eventually { b.model.settings.usesHealth && src.accessAsked == 1 }
        #expect(b.model.settings.usesHealth && src.accessAsked == 1)                 // the iOS sheet is asked once …
        try await eventually { b.model.records().allSatisfy { $0.sleepReadAt != nil } }
        #expect(b.model.records().allSatisfy { $0.sleepReadAt != nil })              // … and the values are read
        #expect(b.model.settings.changedAt == Date(timeIntervalSinceReferenceDate: 1))   // A's first-contact stamp: switching is no stamped change

        // from now on the switch is this device's own: turned off, it stays off through every later sync
        b.model.settings.usesHealth = false
        for _ in 0..<3 { await b.sync.syncNow(); await a.sync.syncNow() }
        try await Task.sleep(for: .milliseconds(150))
        #expect(!b.model.settings.usesHealth && src.accessAsked == 1)
    }

    @Test(.timeLimit(.minutes(1))) func aLaterMergeNeverTakesTheHealthSwitchAndAFileWithItOffNeverSwitchesItOff() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let on = device(folder, id: "ON", at: date(5, 9), health: true)
        let offSrc = FakeSleepSource()
        let off = device(folder, id: "OFF", at: date(5, 9), firstRead: true, source: offSrc)        // first contact is behind it
        let plain = device(folder, id: "PL", at: date(5, 9))                                          // Health off everywhere
        let onSrc = FakeSleepSource()
        let keeps = device(folder, id: "KEEPS", at: date(5, 9), health: true, source: onSrc)        // fresh, switch on
        defer { stopAll(on, off, plain, keeps) }
        await on.sync.syncNow()
        await plain.sync.syncNow()                                                   // a file with the switch OFF
        #expect(file(folder, "ON")?.settings.healthOn == true && file(folder, "PL")?.settings.healthOn == nil)

        // not at first contact: no adoption
        await off.sync.syncNow()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!off.model.settings.usesHealth && offSrc.accessAsked == 0)

        // a device with it on stays on, even at first contact with a file that has it off
        await keeps.sync.syncNow()
        try await Task.sleep(for: .milliseconds(150))
        #expect(keeps.sync.firstReadDone && keeps.model.settings.usesHealth)
        #expect(onSrc.accessAsked == 0)                                              // it was already on: nothing is asked again
    }

    @Test(.timeLimit(.minutes(1))) func anEstablishedDeviceKeepsItsHealthSwitchOffAtFirstContact() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 9), health: true)
        let src = FakeSleepSource()
        let established = device(folder, id: "E", at: date(5, 9), source: src)        // the switch is off, maybe on purpose
        let napper = device(folder, id: "N", at: date(5, 9), source: FakeSleepSource())
        defer { stopAll(a, established, napper) }
        night(a, day: 1)
        await a.sync.syncNow()
        #expect(file(folder, "A")?.settings.healthOn == true)

        night(established, day: 1)                                                   // one finalized night of its own: n > 0
        established.clock.now = date(5, 9); established.model.refresh()
        #expect(established.model.establishedNights == 1 && !established.sync.firstReadDone)
        await established.sync.syncNow()                                             // its first contact, the file has Health ON
        try await Task.sleep(for: .milliseconds(200))
        #expect(established.sync.firstReadDone && !established.model.settings.usesHealth && src.accessAsked == 0)
        for _ in 0..<2 { await established.sync.syncNow(); await a.sync.syncNow() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!established.model.settings.usesHealth && src.accessAsked == 0)

        // a nap of its own counts as well; a debug night does not
        napper.clock.now = date(5, 13, 5); napper.model.refresh(); napper.model.startNap()
        napper.model.abandonNight(); napper.model.acknowledgeResult()
        #expect(napper.model.establishedNights == 1)
        await napper.sync.syncNow()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!napper.model.settings.usesHealth)
    }

    @Test(.timeLimit(.minutes(1))) func theHealthSwitchIsNotTakenWhereHealthCannotBeRead() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 9), health: true)
        let src = FakeSleepSource()
        src.available = false                                                        // an iPad, a restricted device …
        let b = device(folder, id: "B", at: date(5, 9), source: src)
        let none = device(folder, id: "N", at: date(5, 9))                           // … or no source at all
        defer { stopAll(a, b, none) }
        await a.sync.syncNow()
        await b.sync.syncNow(); await none.sync.syncNow()
        try await Task.sleep(for: .milliseconds(150))
        #expect(b.sync.firstReadDone && !b.model.settings.usesHealth && src.accessAsked == 0)
        #expect(none.sync.firstReadDone && !none.model.settings.usesHealth)
    }

    @Test func switchingHealthOnOrOffIsNoStampedChangeButTheFileLearnsOfIt() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let src = FakeSleepSource()
        let a = device(folder, id: "A", at: date(5, 9), syncDelay: 0, firstRead: true, source: src)
        defer { stopAll(a) }
        await a.sync.syncNow()
        #expect(a.spy.writes == 1 && file(folder, "A")?.settings.healthOn == nil)
        await a.model.setHealth(on: true)
        await a.sync.settled()
        #expect(a.model.settings.changedAt == nil)                                   // not a setting that wins merges
        #expect(a.spy.writes == 2 && file(folder, "A")?.settings.healthOn == true)   // the next file says so
        await a.model.setHealth(on: false)
        await a.sync.settled()
        #expect(a.spy.writes == 3 && file(folder, "A")?.settings.healthOn == nil && a.model.settings.changedAt == nil)
    }

    // MARK: A4 – the guide that another device finished, adopted by any sync

    @Test(.timeLimit(.minutes(1))) func aGuideFinishedElsewhereIsAnnouncedWhenAnySyncAdoptsItAndNeverWhenTheUserFinishesIt() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(5, 9)), b = device(folder, id: "B", at: date(5, 9), firstRead: true)
        let own = device(folder, id: "O", at: date(5, 9))
        defer { stopAll(a, b, own) }
        let announced = Counter(), ownAnnounced = Counter()
        b.model.onGuideAdoptedBySync = { announced.n += 1 }
        own.model.onGuideAdoptedBySync = { ownAnnounced.n += 1 }
        await b.sync.syncNow()                                                       // nothing finished anywhere yet
        try await Task.sleep(for: .milliseconds(80))
        #expect(!b.model.onboardingDone && announced.n == 0)

        a.model.completeOnboarding()                                                 // A finishes the guide; B's NEXT sync (not the first) adopts it
        await a.sync.syncNow()
        await b.sync.syncNow()
        try await eventually { announced.n == 1 }
        #expect(b.model.onboardingDone && announced.n == 1)
        await a.sync.syncNow(); await b.sync.syncNow()
        try await Task.sleep(for: .milliseconds(80))
        #expect(announced.n == 1)                                                    // once

        own.model.completeOnboarding()                                               // the guide the user goes through himself
        await own.sync.syncNow()
        try await Task.sleep(for: .milliseconds(80))
        #expect(ownAnnounced.n == 0)                                                 // asks by itself – never twice
    }

    // MARK: A2 at the app level – a correction of one run survives the older copy of another device

    @Test func aCorrectedNightIsNotUndoneByTheOlderBetterCopyOfAnotherDevice() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12), firstRead: true), b = device(folder, id: "B", at: date(1, 12), firstRead: true)
        defer { stopAll(a, b) }
        night(a, day: 1); night(a, day: 2)
        await a.sync.syncNow(); await b.sync.syncNow()
        #expect(b.model.records().count == 2 && content(a) == content(b))

        // B's copy of the second night is corrected: one more event, a lower outcome (what `-revokeForgiveness` does)
        let rb = b.model.records().first { $0.keyString == "2026-10-03" }!
        rb.append(.forgivenessRevoked, at: date(5, 9))
        rb.outcomeRaw = Outcome.ruins.rawValue
        try b.context.save()
        let corrected = b.model.makeSyncFile().nights.first { $0.keyString == "2026-10-03" }!

        await b.sync.syncNow()                                                       // B writes the corrected copy
        a.clock.now = date(5, 9); a.model.refresh()
        await a.sync.syncNow()                                                       // A holds the older, "better" copy
        await b.sync.syncNow()                                                       // … B reads A's again
        for d in [a, b] {
            let n = d.model.makeSyncFile().nights.first { $0.keyString == "2026-10-03" }!
            #expect(n == corrected && n.outcomeRaw == Outcome.ruins.rawValue)
        }
        #expect(content(a) == content(b))
        #expect(a.model.builtNights == 1 && b.model.builtNights == 1)                // the town follows the correction
    }

    @Test func twoDifferentRunsOfTheSameNightStillKeepTheBetterOutcomeWhateverTheirEvents() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12), firstRead: true), b = device(folder, id: "B", at: date(1, 12), firstRead: true)
        defer { stopAll(a, b) }
        night(a, day: 1); night(b, day: 1)
        let ra = a.model.records()[0], rb = b.model.records()[0]
        rb.startedAt = ra.startedAt! + 60                                            // another RUN of the night …
        rb.append(.forgivenessRevoked, at: date(5, 9))                               // … with a longer log …
        rb.outcomeRaw = Outcome.ruins.rawValue                                       // … and a worse outcome
        try b.context.save()
        await a.sync.syncNow(); await b.sync.syncNow()
        await a.sync.syncNow(); await b.sync.syncNow()
        for d in [a, b] { #expect(d.model.makeSyncFile().nights[0].outcomeRaw == Outcome.complete.rawValue) }
        #expect(content(a) == content(b))
    }

    // MARK: A5 – a restore stamps the town name

    @Test func aRestoreStampsTheRestoredTownNameSoItWinsTheNextMerge() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(3, 10), firstRead: true), b = device(folder, id: "B", at: date(3, 10), firstRead: true)
        defer { stopAll(a, b) }
        a.model.renameTown("Old")                                                    // stamped 3rd, 10:00
        let backup = a.model.makeBackup()
        b.clock.now = date(5, 10); b.model.renameTown("Newer")                       // another device renamed later
        a.clock.now = date(6, 10)
        try a.model.restore(backup)                                                  // the user restores the old backup
        #expect(a.model.townName == "Old")
        #expect(townNameStamp(a) == date(6, 10))     // stamped with the moment of the restore

        try a.model.mergeSync([b.model.makeSyncFile()])                              // B's 5th-day rename does not undo it
        #expect(a.model.townName == "Old" && townNameStamp(a) == date(6, 10))
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]))                     // B takes the restored name
        #expect(a.model.townName == "Old" && b.model.townName == "Old" && townNameStamp(b) == date(6, 10))

        // a backup without a name clears the name and its stamp (B12: the backup is the whole truth)
        var nameless = a.model.makeBackup()
        nameless.townName = nil
        a.clock.now = date(7, 10)
        try a.model.restore(nameless)
        #expect(a.model.customTownName == nil)
        #expect(townNameStamp(a) == nil)
    }
}

#endif
