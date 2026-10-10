import Foundation
import SleepCore
import SwiftData
import SwiftUI
import UIKit
import Testing
@testable import SleepHole

/// Phase HEALTH, step H1: reading a night's sleep through the replaceable source and storing it. A fake source stands in
/// for Apple Health; the clock is a FakeClock, nothing sleeps for real.
final class FakeSleepSource: SleepSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _asked: [(from: Date, to: Date)] = []
    private var _samples: [SleepSample] = []
    private var _throws = false
    var available = true
    var name: String { "fake" }
    var isAvailable: Bool { available }
    var asked: [(from: Date, to: Date)] { lock.lock(); defer { lock.unlock() }; return _asked }
    var samples: [SleepSample] {
        get { lock.lock(); defer { lock.unlock() }; return _samples }
        set { lock.lock(); _samples = newValue; lock.unlock() }
    }
    var failing: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _throws }
        set { lock.lock(); _throws = newValue; lock.unlock() }
    }
    private var _access = 0
    var accessAsked: Int { lock.lock(); defer { lock.unlock() }; return _access }
    func requestAccess() async -> Bool { countAccess(); return true }
    private func countAccess() { lock.lock(); _access += 1; lock.unlock() }
    func samples(from: Date, to: Date) async throws -> [SleepSample] {
        let (fail, result) = record(from, to)
        if fail { throw SleepSourceFailure.failed }
        return result
    }
    private func record(_ from: Date, _ to: Date) -> (Bool, [SleepSample]) {
        lock.lock(); defer { lock.unlock() }
        _asked.append((from, to))
        return (_throws, _samples)
    }
    enum SleepSourceFailure: Error { case failed }
}

@MainActor
struct HealthTests {
    static var kept: [ModelContainer] = []
    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h, minute: m))!
    }

    /// The model, the clock and the store. Nights: 10th→11th (real), a debug night and a nap.
    func setup(catalog: Catalog? = nil, health: Bool = true, source: FakeSleepSource = FakeSleepSource(), protectedData: @escaping @MainActor () -> Bool = { true }) -> (AppModel, FakeClock, FakeSleepSource, ModelContext) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        Self.kept.append(c)
        let clock = FakeClock(date(11, 9))
        var s = AppSettings()
        s.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        s.usesHealth = health
        let m = AppModel(context: c.mainContext, catalog: catalog, clock: clock, settings: s, servicesEnabled: false,
                         sleepSource: source, protectedDataAvailable: protectedData)
        return (m, clock, source, c.mainContext)
    }

    /// A finalized night: bedtime 22:30 of `day`, wake 6:30 of the next day.
    @discardableResult
    func night(_ ctx: ModelContext, day: Int, debug: Bool = false, nap: Bool = false, confirmed: Bool = true) -> NightRecord {
        let w = NightWindow(key: NightKey(date: date(day + 1, 6), calendar: .current), bedtime: date(day, 22, 30),
                            wake: date(day + 1, 6, 30))
        let r = NightRecord(window: w, buildingId: "x", isDebug: debug, setupGrace: 300, isNap: nap)
        r.append(.started, at: date(day, 22, 25))
        if confirmed { r.append(.confirmed, at: date(day + 1, 6, 28)) }
        r.outcomeRaw = Outcome.complete.rawValue
        r.finalizedAt = date(day + 1, 6, 31)
        ctx.insert(r)
        return r
    }

    func sleep(_ day: Int, from: (Int, Int) = (23, 0), to: (Int, Int) = (6, 0)) -> [SleepSample] {
        [SleepSample(start: date(day, from.0, from.1), end: date(day + 1, to.0, to.1), stage: .core, source: "Watch")]
    }

    @Test func withTheSwitchOffTheSourceIsNeverAsked() async {
        let (m, clock, src, ctx) = setup(health: false)
        night(ctx, day: 10)
        await m.refreshSleep(now: clock.now)
        #expect(src.asked.isEmpty)
        // and an unavailable source is not asked either
        let (m2, c2, src2, ctx2) = setup()
        src2.available = false
        night(ctx2, day: 10)
        await m2.refreshSleep(now: c2.now)
        #expect(src2.asked.isEmpty)
    }

    @Test func everyFinalizedRealNightIsReadOnceAndStored() async throws {
        let (m, clock, src, ctx) = setup()
        src.samples = sleep(10) + sleep(11)
        let a = night(ctx, day: 10)
        let b = night(ctx, day: 11, confirmed: false)         // 11th → 12th
        night(ctx, day: 9, debug: true)
        night(ctx, day: 8, nap: true)
        await m.refreshSleep(now: clock.now)
        #expect(src.asked.count == 2)
        #expect(a.fellAsleepAt == date(10, 23) && a.sleepEndedAt == date(11, 6) && a.asleepSeconds == 7 * 3600)
        #expect(a.awakeSeconds == 0 && a.sleepSourceName == "Watch" && a.sleepReadAt == clock.now)
        // the window ends at the confirmation, or three hours after wake when there was none
        let first = src.asked.first { $0.from == date(10, 22, 25) }
        #expect(first?.to == date(11, 6, 28))
        let second = src.asked.first { $0.from == date(11, 22, 25) }
        #expect(second?.to == date(12, 9, 30))
        #expect(b.sleepReadAt == clock.now)
        // the result carries the new facts
        #expect(a.result?.fellAsleepAt == date(10, 23) && a.result?.asleepSeconds == 7 * 3600)
    }

    @Test func aSecondCallWithinTheHourAsksNothing() async {
        let (m, clock, src, ctx) = setup()
        src.samples = sleep(10)
        night(ctx, day: 10)
        await m.refreshSleep(now: clock.now)
        clock.advance(59 * 60)
        await m.refreshSleep(now: clock.now)
        #expect(src.asked.count == 1)
    }

    @Test func aRecentNightIsReadAgainAfterAnHourAndAnOldOneNever() async {
        let (m, clock, src, ctx) = setup()
        src.samples = sleep(10)
        let r = night(ctx, day: 10)
        await m.refreshSleep(now: clock.now)                         // 11th 9:00, before wake + 3 days
        clock.advance(3601)
        await m.refreshSleep(now: clock.now)
        #expect(src.asked.count == 2)
        clock.now = date(15, 9)                                      // beyond wake (11th 6:30) + 3 days
        await m.refreshSleep(now: clock.now)                         // still read once more: the last read was early
        #expect(src.asked.count == 3 && r.sleepReadAt == date(15, 9))
        clock.advance(5 * 3600)
        await m.refreshSleep(now: clock.now)
        #expect(src.asked.count == 3)                                // the last read was after wake + 3 days: done for good
    }

    @Test func nothingFoundStoresOnlyTheReadTimeAndClearsOlderValues() async {
        let (m, clock, src, ctx) = setup()
        src.samples = sleep(10)
        let r = night(ctx, day: 10)
        await m.refreshSleep(now: clock.now)
        #expect(r.asleepSeconds != nil)
        src.samples = []
        clock.advance(3601)
        await m.refreshSleep(now: clock.now)
        #expect(r.fellAsleepAt == nil && r.sleepEndedAt == nil && r.asleepSeconds == nil && r.awakeSeconds == nil
                && r.sleepSourceName == nil && r.sleepReadAt == clock.now)
    }

    @Test func aNightReadUnderAnOldRuleVersionIsReadOnceMore() async {
        let (m, clock, src, ctx) = setup()
        src.samples = sleep(10)
        let r = night(ctx, day: 10)
        r.sleepReadAt = clock.now.addingTimeInterval(-60)             // read a minute ago, rule version nil
        r.fellAsleepAt = date(10, 23); r.asleepSeconds = 1
        #expect(r.sleepRuleVersion == nil)
        await m.refreshSleep(now: clock.now)
        #expect(src.asked.count == 1 && r.sleepRuleVersion == SleepAnalysis.ruleVersion && r.asleepSeconds == 7 * 3600)
        await m.refreshSleep(now: clock.now)                           // now the ordinary rule: not again within the hour
        #expect(src.asked.count == 1)
        // a very old night is read again too when its version differs
        r.sleepReadAt = date(30, 9); r.sleepRuleVersion = SleepAnalysis.ruleVersion - 1
        clock.now = date(30, 9).addingTimeInterval(60)
        await m.refreshSleep(now: clock.now)
        #expect(src.asked.count == 2 && r.sleepRuleVersion == SleepAnalysis.ruleVersion)
    }

    @Test func thePerSourceListIsStoredAndDecodes() async {
        let (m, clock, src, ctx) = setup()
        src.samples = sleep(10) + [SleepSample(start: date(10, 23), end: date(11, 2), stage: .asleep, source: "Some App")]
        let r = night(ctx, day: 10)
        await m.refreshSleep(now: clock.now)
        #expect(r.sleepSources.map(\.name) == ["Some App", "Watch"])
        #expect(r.sleepSources[0].asleepSeconds == 3 * 3600 && !r.sleepSources[0].hasStages)
        #expect(r.sleepSources[1].asleepSeconds == 7 * 3600)
        #expect(r.sleepSourceName == "Watch")
    }

    @Test func aNilSummaryStillStoresTheListAndTheVersion() async {
        let (m, clock, src, ctx) = setup()
        src.samples = [SleepSample(start: date(10, 23), end: date(10, 23, 10), stage: .asleep, source: "Some App")]
        let r = night(ctx, day: 10)
        await m.refreshSleep(now: clock.now)
        #expect(r.asleepSeconds == nil && r.sleepSourceName == nil && r.sleepRuleVersion == SleepAnalysis.ruleVersion)
        #expect(r.sleepSources.count == 1 && r.sleepSources[0].asleepSeconds == 600)    // below minAsleep, still listed
        src.samples = []
        clock.advance(3601)
        await m.refreshSleep(now: clock.now)
        #expect(r.sleepSourcesData != nil && r.sleepSources.isEmpty && r.sleepRuleVersion == SleepAnalysis.ruleVersion)
    }

    @Test func theBackupCarriesTheSourcesAndTheVersion() throws {
        let (_, _, _, ctx) = setup()
        let r = night(ctx, day: 10)
        r.sleepSourcesData = try JSONEncoder().encode([SleepAnalysis.SourceSummary(
            name: "Some App", asleepSeconds: 3600, fellAsleepAt: date(10, 23), wokeAt: date(11, 1), awakeSeconds: 0,
            hasStages: false)])
        r.sleepRuleVersion = 2
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = NightRecord(backup: try d.decode(BackupFile.Night.self, from: try e.encode(r.backup)))
        #expect(back.sleepRuleVersion == 2 && back.sleepSources == r.sleepSources && back.sleepSources.count == 1)
        var json = try JSONSerialization.jsonObject(with: try e.encode(r.backup)) as! [String: Any]
        json.removeValue(forKey: "sleepSourcesData"); json.removeValue(forKey: "sleepRuleVersion")
        let old = NightRecord(backup: try d.decode(BackupFile.Night.self, from: try JSONSerialization.data(withJSONObject: json)))
        #expect(old.sleepSourcesData == nil && old.sleepRuleVersion == nil && old.sleepSources.isEmpty)
    }

    @Test func aThrowingSourceChangesNothing() async {
        let (m, clock, src, ctx) = setup()
        src.samples = sleep(10)
        let r = night(ctx, day: 10)
        await m.refreshSleep(now: clock.now)
        let read = r.sleepReadAt
        src.failing = true
        clock.advance(3601)
        await m.refreshSleep(now: clock.now)
        #expect(r.asleepSeconds == 7 * 3600 && r.sleepReadAt == read)
        // a night never read stays unread
        let (m2, c2, s2, ctx2) = setup()
        s2.failing = true
        let fresh = night(ctx2, day: 10)
        await m2.refreshSleep(now: c2.now)
        #expect(fresh.sleepReadAt == nil && fresh.asleepSeconds == nil)
    }

    @Test func theBackupKeepsTheFieldsAndAnOldBackupLoads() throws {
        let (_, _, _, ctx) = setup()
        let r = night(ctx, day: 10)
        r.fellAsleepAt = date(10, 23); r.sleepEndedAt = date(11, 6); r.asleepSeconds = 25_200; r.awakeSeconds = 600
        r.sleepSourceName = "Watch"; r.sleepReadAt = date(11, 9)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = NightRecord(backup: try d.decode(BackupFile.Night.self, from: try e.encode(r.backup)))
        #expect(back.fellAsleepAt == r.fellAsleepAt && back.sleepEndedAt == r.sleepEndedAt && back.asleepSeconds == 25_200
                && back.awakeSeconds == 600 && back.sleepSourceName == "Watch" && back.sleepReadAt == r.sleepReadAt)
        var json = try JSONSerialization.jsonObject(with: try e.encode(r.backup)) as! [String: Any]
        for k in ["fellAsleepAt", "sleepEndedAt", "asleepSeconds", "awakeSeconds", "sleepSourceName", "sleepReadAt"] {
            json.removeValue(forKey: k)
        }
        let old = NightRecord(backup: try d.decode(BackupFile.Night.self, from: try JSONSerialization.data(withJSONObject: json)))
        #expect(old.fellAsleepAt == nil && old.asleepSeconds == nil && old.sleepReadAt == nil)
    }

    @Test func theSettingsSwitchRoundTripsAndOlderSettingsLoadAsOff() throws {
        var s = AppSettings(); s.usesHealth = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(s)).usesHealth)
        var o = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(AppSettings())) as! [String: Any]
        o.removeValue(forKey: "healthOn")
        let old = try JSONDecoder().decode(AppSettings.self, from: try JSONSerialization.data(withJSONObject: o))
        #expect(!old.usesHealth && old.healthOn == nil)
    }

    @Test func theSimulatedSourceProducesASummary() async throws {
        let from = date(10, 22, 25), to = date(11, 6, 28)
        let src = SimulatedSleepSource(fallAsleepMinutes: 20)
        let samples = try await src.samples(from: from, to: to)
        #expect(try await src.samples(from: from, to: to) == samples)               // deterministic
        let r = try #require(SleepAnalysis.summary(samples: samples, from: from, to: to))
        #expect(r.source == "Simulated" && r.hasStages && r.fellAsleepAt == from.addingTimeInterval(src.minutes(for: from) * 60))
        #expect(r.wokeAt == to.addingTimeInterval(-5 * 60) && r.awakeSeconds == 8 * 60)
        let nights = (0..<14).map { src.minutes(for: from.addingTimeInterval(Double($0) * 86_400)) }
        #expect(Set(nights).count > 8 && nights.allSatisfy { $0 >= 5 && $0 <= 95 })       // varies, within 20 - 15 ... 20 + 75
        #expect(SimulatedSleepSource(fallAsleepMinutes: 1).minutes(for: from) >= 3)       // never below 3 minutes
        #expect(AppModel.launchSleepSource(args: ["-sleepSim", "25"]) is SimulatedSleepSource)
        #expect(AppModel.launchSleepSource(args: ["-x"]) == nil)
    }

    // MARK: step H2 – the switch, the safe moments, the night's detail

    @Test func healthKitValuesMapToStages() {
        #expect(HealthKitSleepSource.stage(forValue: 0) == .inBed)
        #expect(HealthKitSleepSource.stage(forValue: 1) == .asleep)
        #expect(HealthKitSleepSource.stage(forValue: 2) == .awake)
        #expect(HealthKitSleepSource.stage(forValue: 3) == .core)
        #expect(HealthKitSleepSource.stage(forValue: 4) == .deep)
        #expect(HealthKitSleepSource.stage(forValue: 5) == .rem)
        #expect(HealthKitSleepSource.stage(forValue: 99) == nil)          // a future value is skipped
    }

    @Test func turningTheSwitchOnAsksForAccessThenReads() async {
        let (m, _, src, ctx) = setup(health: false)
        src.samples = sleep(10)
        let r = night(ctx, day: 10)
        await m.setHealth(on: true)
        #expect(m.settings.usesHealth && src.accessAsked == 1)
        #expect(r.fellAsleepAt == date(10, 23))
    }

    @Test func turningTheSwitchOffDeletesNothing() async {
        let (m, _, src, ctx) = setup()
        src.samples = sleep(10)
        let r = night(ctx, day: 10)
        await m.refreshSleep(now: m.clock.now)
        await m.setHealth(on: false)
        #expect(!m.settings.usesHealth && src.accessAsked == 0)
        #expect(r.fellAsleepAt == date(10, 23) && r.asleepSeconds == 7 * 3600)
    }

    @Test func theStatusCountsNightsWithData() async {
        let (m, _, src, ctx) = setup()
        night(ctx, day: 9)
        night(ctx, day: 10)
        night(ctx, day: 8, debug: true)
        #expect(m.sleepStatus.withData == 0 && m.sleepStatus.total == 2 && !m.sleepStatus.anyRead)
        src.samples = sleep(10)                                          // only the 10th → 11th night overlaps
        await m.refreshSleep(now: m.clock.now)
        #expect(m.sleepStatus.withData == 1 && m.sleepStatus.total == 2 && m.sleepStatus.anyRead)
    }

    @Test func readingWaitsForALockedPhoneAndForARunningNight() async {
        var unlocked = false
        let (m, clock, src, ctx) = setup(catalog: SpriteLibrary.loadFromBundle().catalog, protectedData: { unlocked })
        src.samples = sleep(10)
        night(ctx, day: 10)
        await m.refreshSleepIfIdle()
        #expect(src.asked.isEmpty)                                       // locked
        unlocked = true
        clock.now = date(11, 22, 25)                                     // the start window of tonight
        m.refresh()
        m.startNight()
        #expect(m.active != nil)
        await m.refreshSleepIfIdle()
        #expect(src.asked.isEmpty)                                       // a night is running
        m.abandonNight()
        await m.refreshSleepIfIdle()
        #expect(src.asked.count >= 1)
    }

    @Test func theDetailLinesFollowTheSwitchAndTheStoredValues() async {
        let (m, _, src, ctx) = setup()
        src.samples = sleep(10, from: (22, 55))
        let r = night(ctx, day: 10)                                      // build started 22:25
        #expect(NightDetail.sleepLines(r, on: true) == .hidden)         // not read yet
        await m.refreshSleep(now: m.clock.now)
        guard case let .values(fell, slept, source) = NightDetail.sleepLines(r, on: true) else { Issue.record("no values"); return }
        #expect(fell.hasSuffix("(after 30 min)") && slept == "7 h 5 min" && source == "Watch")
        #expect(NightDetail.sleepLines(r, on: false) == .hidden)
        src.samples = []
        await m.refreshSleep(now: date(11, 11))
        #expect(NightDetail.sleepLines(r, on: true) == .none)
    }

    @Test func theSourceCaptionNeedsAStoredSourceName() async {
        let (m, _, src, ctx) = setup()
        src.samples = sleep(10)
        let r = night(ctx, day: 10)
        await m.refreshSleep(now: m.clock.now)
        guard case let .values(_, _, source) = NightDetail.sleepLines(r, on: true) else { Issue.record("no values"); return }
        #expect(source == "Watch")
        r.sleepSourceName = nil
        guard case let .values(_, _, none) = NightDetail.sleepLines(r, on: true) else { Issue.record("no values"); return }
        #expect(none == nil)
    }

    @Test func onlyAnAppleBundleIdentifierIsFirstParty() {
        #expect(HealthKitSleepSource.isFirstParty(bundleIdentifier: "com.apple.health.ABC"))
        #expect(!HealthKitSleepSource.isFirstParty(bundleIdentifier: "com.example.sleeper"))
        #expect(!HealthKitSleepSource.isFirstParty(bundleIdentifier: "xcom.apple.fake"))
        #expect(!HealthKitSleepSource.isFirstParty(bundleIdentifier: ""))
    }

    @Test func aNightStoredUnderVersionTwoIsReadOnceMore() async {
        let (m, clock, src, ctx) = setup()
        src.samples = sleep(10)
        let r = night(ctx, day: 10)
        r.sleepReadAt = clock.now.addingTimeInterval(-60); r.sleepRuleVersion = 2
        r.fellAsleepAt = date(10, 23); r.asleepSeconds = 1
        await m.refreshSleep(now: clock.now)
        #expect(src.asked.count == 1 && r.sleepRuleVersion == 3 && r.asleepSeconds == 7 * 3600)
        await m.refreshSleep(now: clock.now)
        #expect(src.asked.count == 1)
    }

    @Test func minutesToSleepNeverGoNegative() {
        #expect(NightDetail.minutesToSleep(started: date(10, 23), fellAsleep: date(10, 22)) == 0)
        #expect(NightDetail.minutesToSleep(started: nil, fellAsleep: date(10, 22)) == 0)
        #expect(NightDetail.minutesToSleep(started: date(10, 22), fellAsleep: date(10, 22, 29) + 40) == 30)
    }

    @Test func theDetailAndSettingsRender() async {
        let (m, _, src, ctx) = setup()
        src.samples = sleep(10)
        night(ctx, day: 10)
        await m.refreshSleep(now: m.clock.now)
        let sprites = SpriteLibrary.loadFromBundle()
        for view in [AnyView(NightDetail(key: NightKey(date: date(11, 6), calendar: .current))), AnyView(SettingsView())] {
            let host = UIHostingController(rootView: view.environment(m).environment(sprites))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            window.isHidden = true
        }
    }
}
