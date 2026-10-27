import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// Phase SYNC, step S3: what Settings → iCloud says (the pure mapping from the engine's state to the status line, its
/// texts in both languages, the moment format) and that the section and the developer screen render in every state.
@MainActor
struct SyncStatusTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    // MARK: the pure mapping

    @Test func theStatusLineFollowsTheEnginesState() {
        let at = date(5, 9)
        // switched off: no line, whatever the engine knows
        for place in [SyncPlace.unknown, .available, .unavailable] {
            #expect(SyncStatus.of(enabled: false, place: place, error: "boom", lastSyncAt: at) == nil)
        }
        // iCloud cannot be used: that is the line, before anything else
        #expect(SyncStatus.of(enabled: true, place: .unavailable, error: nil, lastSyncAt: nil) == .unavailable)
        #expect(SyncStatus.of(enabled: true, place: .unavailable, error: "boom", lastSyncAt: at) == .unavailable)
        // usable but the last attempt failed: "couldn't sync", even after an earlier good sync
        #expect(SyncStatus.of(enabled: true, place: .available, error: "boom", lastSyncAt: nil) == .failed)
        #expect(SyncStatus.of(enabled: true, place: .available, error: "boom", lastSyncAt: at) == .failed)
        // usable and synced
        #expect(SyncStatus.of(enabled: true, place: .available, error: nil, lastSyncAt: at) == .synced(at))
        // nothing yet
        #expect(SyncStatus.of(enabled: true, place: .available, error: nil, lastSyncAt: nil) == .notYet)
        #expect(SyncStatus.of(enabled: true, place: .unknown, error: nil, lastSyncAt: nil) == .notYet)
    }

    // MARK: texts and the moment

    @Test func theStatusTextsAreTheReviewedOnesInBothLanguages() {
        let was = Lang.current, was12h = Fmt.systemUses12h
        defer { Lang.current = was; Fmt.systemUses12h = was12h }
        Fmt.systemUses12h = false
        let now = date(5, 20), today = date(5, 14, 5), earlier = date(3, 9, 7)

        Lang.current = .en
        #expect(SyncStatus.unavailable.text(now: now) == "iCloud isn't available. Sign in to iCloud and switch on iCloud Drive in the iPhone's Settings.")
        #expect(SyncStatus.failed.text(now: now) == "Couldn't sync just now. SleepHole will try again by itself.")
        #expect(SyncStatus.notYet.text(now: now) == "Not synced yet")
        #expect(SyncStatus.synced(today).text(now: now) == "Last synced: 14:05")
        #expect(SyncStatus.synced(earlier).text(now: now) == "Last synced: 10/3 9:07")

        Lang.current = .sk
        #expect(SyncStatus.unavailable.text(now: now) == "iCloud nie je dostupný. V Nastaveniach iPhonu sa prihlás do iCloudu a zapni iCloud Drive.")
        #expect(SyncStatus.failed.text(now: now) == "Teraz sa nepodarilo synchronizovať. SleepHole to skúsi znova sama.")
        #expect(SyncStatus.notYet.text(now: now) == "Zatiaľ nesynchronizované")
        #expect(SyncStatus.synced(today).text(now: now) == "Naposledy synchronizované: 14:05")
        #expect(SyncStatus.synced(earlier).text(now: now) == "Naposledy synchronizované: 3. 10. 9:07")
    }

    @Test func theSectionTextsAreTranslated() {
        let was = Lang.current
        defer { Lang.current = was }
        Lang.current = .sk
        #expect(L("iCloud") == "iCloud")
        #expect(L("Sync through iCloud") == "Synchronizovať cez iCloud")
        #expect(L("Your nights, coins and settings are kept in your own iCloud. The town is then the same on all your devices and comes back after you reinstall SleepHole. Nothing from Apple Health is stored there. Start and finish a night on the same device.")
                == "Tvoje noci, mince a nastavenia sa ukladajú do tvojho vlastného iCloudu. Mesto je potom rovnaké na všetkých tvojich zariadeniach a po preinštalovaní SleepHole sa vráti. Z Apple Zdravia sa tam neukladá nič. Noc začni aj dokonči na tom istom zariadení.")
    }

    @Test func theMomentIsTheClockTodayAndDayMonthAndClockOtherwise() {
        let was = Lang.current, was12h = Fmt.systemUses12h
        defer { Lang.current = was; Fmt.systemUses12h = was12h }
        let now = date(5, 20)
        Fmt.systemUses12h = false
        Lang.current = .en
        #expect(Fmt.moment(date(5, 0, 1), now: now) == "0:01" && Fmt.moment(date(5, 19, 59), now: now) == "19:59")
        #expect(Fmt.moment(date(4, 23, 59), now: now) == "10/4 23:59")
        Fmt.systemUses12h = true
        #expect(Fmt.moment(date(5, 14, 5), now: now).contains("2:05") && Fmt.moment(date(4, 14, 5), now: now).hasPrefix("10/4 "))
        Lang.current = .sk                                                           // always 24 h
        #expect(Fmt.moment(date(5, 14, 5), now: now) == "14:05" && Fmt.moment(date(4, 14, 5), now: now) == "4. 10. 14:05")
    }

    // MARK: rendering in every state

    /// A stand-in place: usable, unusable, or usable with a failing read.
    struct Place: SyncTransport {
        var available = true, failing = false
        struct Failure: Error {}
        func isAvailable() async -> Bool { available }
        func write(_ data: Data) async throws {}
        func readOthers() async throws -> [Data] { if failing { throw Failure() }; return [] }
        var changes: AsyncStream<Void> { AsyncStream { $0.finish() } }
    }

    func model(_ place: any SyncTransport, language: AppLanguage) -> AppModel {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, BoxRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        var s = AppSettings(); s.wakeCode = "1234"
        let m = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: FakeClock(date(5, 12)), settings: s,
                         servicesEnabled: false, defaults: UserDefaults(suiteName: "sleephole-status-\(UUID().uuidString)")!,
                         syncTransport: place, syncDelay: 3600)
        m.language = language
        return m
    }

    func render<V: View>(_ view: V, _ model: AppModel) {
        let host = UIHostingController(rootView: view.environment(model).environment(sprites))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.15)
        window.isHidden = true
    }

    @Test(arguments: AppLanguage.allCases) func theSectionRendersInEveryStateWithTheSwitchOnAndOff(language: AppLanguage) async {
        func status(_ m: AppModel) -> SyncStatus? {
            SyncStatus.of(enabled: m.settings.usesSync, place: m.sync.place, error: m.sync.lastSyncError, lastSyncAt: m.sync.lastSyncAt)
        }
        let expected: [(any SyncTransport, SyncStatus)] = [(Place(), .synced(date(5, 12))), (Place(available: false), .unavailable),
                                                           (Place(failing: true), .failed)]
        for (place, wanted) in expected {
            let m = model(place, language: language)
            defer { m.sync.stop() }
            render(Form { SyncSection() }, m)                                        // before the first attempt
            #expect(status(m) == .notYet)
            await m.sync.syncNow()
            render(Form { SyncSection() }, m)                                        // after it
            #expect(status(m) == wanted)
            m.settings.usesSync = false                                              // switched off: no status line
            render(Form { SyncSection() }, m)
            #expect(m.settings.syncOff == true && status(m) == nil)
            m.settings.usesSync = true
            #expect(m.settings.syncOff == nil && status(m) == wanted)
        }
    }

    @Test(arguments: AppLanguage.allCases) func settingsShowsTheSectionAfterAppleHealth(language: AppLanguage) {
        render(SettingsView(), model(Place(), language: language))
    }

    #if DEBUG
    @Test(arguments: AppLanguage.allCases) func theDeveloperScreenRendersAndNamesTheTransport(language: AppLanguage) async {
        let m = model(Place(failing: true), language: language)
        await m.sync.syncNow()
        m.sync.stop()
        render(NavigationStack { SyncTestView() }, m)
        #expect(SyncTestView.describe(NoSyncTransport()).0 == L("None") && SyncTestView.describe(NoSyncTransport()).1 == nil)
        let folder = FolderSyncTransport(folder: FileManager.default.temporaryDirectory, deviceId: "dev one")
        #expect(SyncTestView.describe(folder).1 == "dev_one.json")
        let cloud = ICloudSyncTransport(deviceId: "abc", container: FixedContainer(root: nil), listing: FakeListing())
        #expect(SyncTestView.describe(cloud).0 == "iCloud" && SyncTestView.describe(cloud).1 == "abc.json")
    }
    #endif
}
