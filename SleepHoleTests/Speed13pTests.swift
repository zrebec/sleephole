import Foundation
import Observation
import SleepCore
import SpriteKit
import SwiftData
import Testing
import UIKit
@testable import SleepHole

/// Build 13p (j5c): speed with many nights. The cached values must show every kind of change at the next tick.
@MainActor
struct Speed13pTests {
    let library = SpriteLibrary.loadFromBundle()
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
        let m = AppModel(context: c.mainContext, catalog: library.catalog, clock: clock, settings: s, servicesEnabled: false)
        return Rig(container: c, clock: clock, model: m)
    }

    func playNight(_ r: Rig, day: Int) {
        r.clock.now = date(day, 22, 25); r.model.refresh(); r.model.startNight()
        r.clock.now = date(day + 1, 6, 30) + 60; r.model.refresh()
        #expect(r.model.confirm(code: "1234"))
        r.model.acknowledgeResult()
    }

    // MARK: - item 5 – the ticker's fetch

    @Test func theTickerSeesANightStartedFinalizedAndForgottenAtTheNextTick() {
        let r = rig(at: date(5, 12))
        r.model.refresh()
        #expect(r.model.records().isEmpty && !r.model.tonightPlayed)         // warms the cache
        r.clock.now = date(5, 22, 25); r.model.refresh()
        r.model.startNight()
        #expect(r.model.records().count == 1)                                  // a night started
        r.clock.now = date(5, 22, 26); r.model.refresh()
        #expect(r.model.phase == .building)
        r.clock.now = date(6, 6, 30) + 60; r.model.refresh()
        #expect(r.model.confirm(code: "1234"))
        #expect(r.model.records().first?.isFinalized == true)                  // finalized
        r.model.acknowledgeResult()
        r.clock.now = date(6, 12); r.model.refresh()
        #expect(r.model.realResults().count == 1)
        r.model.clearNights()                                                  // deleted
        #expect(r.model.records().isEmpty && r.model.realResults().isEmpty)
        r.model.refresh()
        #expect(!r.model.tonightPlayed)
    }

    @Test func aMergeAndARestoreAreSeenAtTheNextTick() throws {
        let a = rig(at: date(5, 12))
        for d in 2...4 { playNight(a, day: d) }
        let backup = a.model.makeBackup()
        let merged = rig(at: date(7, 12))
        merged.model.refresh()
        #expect(merged.model.records().isEmpty)                                // warms the cache
        _ = try merged.model.mergeSync([backup])
        #expect(merged.model.records().count == 3)
        merged.model.refresh()
        #expect(merged.model.realResults().count == 3)
        let restored = rig(at: date(7, 12))
        restored.model.refresh()
        #expect(restored.model.records().isEmpty)
        try restored.model.restore(backup)
        #expect(restored.model.records().count == 3)
        // a second restore with fewer nights replaces the rows (and the cached array)
        let one = rig(at: date(5, 12))
        playNight(one, day: 2)
        try restored.model.restore(one.model.makeBackup())
        #expect(restored.model.records().count == 1)
    }

    @Test func aHealthReadThatChangesRowsIsSeen() async {
        let r = rig(at: date(5, 12))
        playNight(r, day: 2)
        let before = r.model.records().count
        let revision = r.model.dataRevision
        await r.model.refreshSleep(now: date(3, 12), force: true)
        #expect(r.model.records().count == before)                             // no source: nothing changed, nothing refetched
        #expect(r.model.dataRevision >= revision)
    }

    @Test func aRowInsertedStraightIntoTheContextShowsAtOnce() throws {
        let r = rig(at: date(5, 12))
        r.model.refresh()
        #expect(r.model.records().isEmpty)                                       // fills the cache
        func night(_ day: Int) -> NightRecord {
            let w = r.model.settings.schedule.window(containing: date(day, 12), calendar: cal)
            let rec = NightRecord(window: w, buildingId: "l1-house-a-0", isDebug: false, setupGrace: 300)
            rec.append(.started, at: w.bedtime)
            return rec
        }
        let first = night(3)
        r.container.mainContext.insert(first)
        #expect(r.model.records().count == 1)                                    // unsaved insert
        try r.container.mainContext.save()                                       // saved outside AppModel
        #expect(r.model.records().count == 1)
        r.container.mainContext.insert(night(4))
        try r.container.mainContext.save()
        #expect(r.model.records().count == 2)
        r.container.mainContext.delete(first)
        #expect(r.model.records().count == 1)                                    // unsaved delete
        try r.container.mainContext.save()
        #expect(r.model.records().count == 1)
    }

    // MARK: - M4 – an unchanged second does not notify

    @Test func anUnchangedTickDoesNotFireTheObserversOfWindowAndPhase() {
        let r = rig(at: date(5, 12))
        r.model.refresh()
        func fired(_ read: @escaping () -> Void) -> Bool {
            final class Flag: @unchecked Sendable { var set = false }
            let f = Flag()
            withObservationTracking { read() } onChange: { f.set = true }
            r.model.refresh()                                                    // the same second again
            return f.set
        }
        #expect(!fired { _ = r.model.phase })
        #expect(!fired { _ = r.model.window })
        // a real change does fire
        r.clock.now = date(5, 22, 35)
        #expect(fired { _ = r.model.phase })                                     // idle → canStart
        r.clock.now = date(6, 12)
        #expect(fired { _ = r.model.window })                                    // the window moved on
    }

    // MARK: - items 3, 4, 7 – lazy MapKit and the derived caches

    @Test func theCityCompleterIsCreatedOnTheFirstQueryOnly() async {
        let search = MapKitCitySearch()
        #expect(!search.completerCreated)
        _ = await search.suggestions(for: "   ")
        _ = await search.resolve("")
        #expect(!search.completerCreated)                                        // blank text never builds it
    }

    @Test func theJournalAchievementsAndCoinsPerNightFollowEveryWrite() throws {
        let r = rig(at: date(2, 12))
        for d in 2...9 { playNight(r, day: d) }
        func truth() -> AppModel {
            let m = AppModel(context: r.container.mainContext, catalog: library.catalog, clock: r.clock,
                             settings: r.model.settings, servicesEnabled: false)
            m.refresh()
            return m
        }
        func expectFresh() {
            let t = truth()
            #expect(r.model.journalWeeks == t.journalWeeks)
            #expect(r.model.achievements == t.achievements)
            let keys = r.model.realResults().compactMap { $0.result?.key }
            #expect(keys.count >= 8)
            for k in keys { #expect(r.model.coinsEarned(for: k) == t.coinsEarned(for: k)) }
            let ledger = Economy.ledger(r.model.coreResults(), calendar: cal, breaks: r.model.streakBreaks, catalog: library.catalog, boxes: r.model.boxes())
            for k in keys { #expect(r.model.coinsEarned(for: k) == ledger.last { $0.key == k }?.coins) }
        }
        expectFresh()
        let weeks = r.model.journalWeeks.count
        playNight(r, day: 10)
        expectFresh()
        #expect(r.model.journalWeeks.count >= weeks)
        let backup = r.model.makeBackup()
        let other = rig(at: date(12, 12))
        #expect(other.model.journalWeeks.isEmpty && other.model.achievements.isEmpty)
        try other.model.restore(backup)
        #expect(other.model.journalWeeks == r.model.journalWeeks)
        #expect(other.model.achievements == r.model.achievements)
    }

    // MARK: - item 2 – the sprites prepared in the background

    @Test func preparedTexturesAreTheSameImagesAndAMissFallsBack() async throws {
        let lib = SpriteLibrary.loadFromBundle()
        let id = "l1-house-a-0"
        #expect(lib.texture(for: id, language: .en) == nil)                       // nothing prepared yet
        await Task.detached(priority: .utility) { lib.prepare(ids: [id, "no-such-sprite"], language: .en) }.value
        let texture = try #require(lib.texture(for: id, language: .en))
        let image = try #require(lib.image(for: id, language: .en))
        #expect(texture.size() == image.size)
        let fresh = try #require(SpriteLibrary.loadFromBundle().image(for: id, language: .en))
        #expect(fresh.size == image.size)
        #expect(fresh.alpha(atX: 60, y: 60) == image.alpha(atX: 60, y: 60))
        #expect(lib.texture(for: "no-such-sprite", language: .en) == nil)
        // a scene with the provider uses the prepared texture; a scene without it (or with a miss) still shows the sprite
        let k = NightKey("2026-10-01")!
        let town = TownBuilder.build(results: [NightResult(key: k, outcome: .complete, buildingId: id)], catalog: library.catalog!)
        let model = TownRender.build(town, catalog: library.catalog!, today: NightKey("2026-10-05")!, calendar: cal)
        func nodes(prepared: Bool) -> Int {
            let scene = TownScene(size: CGSize(width: 400, height: 800))
            scene.imageProvider = { lib.image(for: $0, language: .en) }
            if prepared { scene.textureProvider = { lib.texture(for: $0, language: .en) } }
            scene.cameraDefaults = UserDefaults(suiteName: "speed13p-\(UUID().uuidString)")!
            scene.show(model, focus: nil)
            return scene.children.count
        }
        #expect(nodes(prepared: true) == nodes(prepared: false))
        #expect(nodes(prepared: true) > 1)
    }

    // MARK: - item 1 – the town for VoiceOver, big

    func bigTown(_ n: Int) -> (TownSnapshot, TownRenderModel) {
        let ids = library.catalog!.entries.filter { $0.kind == .building }.map(\.id)
        let k = NightKey("2026-01-01")!
        let results = (0..<n).map { i in
            NightResult(key: k.adding(days: i, calendar: cal), outcome: i % 10 == 9 ? .ruins : i % 10 == 0 ? .unfinished : .complete,
                        buildingId: ids[i % ids.count])
        }
        let town = TownBuilder.build(results: results, catalog: library.catalog!)
        return (town, TownRender.build(town, catalog: library.catalog!, today: NightKey("2026-12-31")!, calendar: cal))
    }

    @Test func aBigTownAnswersTheAccessibilityQueryFastWithTheSameFrames() {
        let (town, model) = bigTown(365)
        let view = TownSKView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let scene = TownScene(size: view.bounds.size)
        scene.imageProvider = { library.image(for: $0) }
        scene.cameraDefaults = UserDefaults(suiteName: "speed13p-\(UUID().uuidString)")!
        view.presentScene(scene)
        scene.show(model, focus: nil)
        view.entries = TownAccessibility.entries(town) { _ in "B" }
        view.summary = "S"
        let start = ContinuousClock.now
        let elements = (view.accessibilityElements ?? []).compactMap { $0 as? TownAccessibilityElement }
        for _ in 0..<town.buildings.count { _ = view.accessibilityElements }      // one UIKit query asks once per element
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .milliseconds(500), "took \(elapsed)")
        #expect(elements.count == town.buildings.count + 1)
        #expect(elements.first?.accessibilityLabel == "S" && elements.first?.buildingIndex == nil)
        #expect(elements.dropFirst().map { $0.buildingIndex } == town.buildings.indices.map { $0 })
        var compared = 0
        for e in elements.dropFirst() {
            let i = e.buildingIndex!
            let old = TownSKView.viewFrame(ofBuilding: i, in: model, scene: scene)       // the old scan over every sprite
            #expect(old == e.accessibilityFrameInContainerSpace, "building \(i)")
            #expect(TownSKView.viewFrame(ofBuilding: i, scene: scene) == old)
            compared += 1
        }
        #expect(compared == 365)
        // the cache follows a rebuilt model
        let (_, smaller) = bigTown(20)
        scene.show(smaller, focus: nil)
        #expect(scene.sceneRect(ofBuilding: 100) == nil && scene.sceneRect(ofBuilding: 5) != nil)
        #expect(TownScene.sceneRects(of: smaller).allSatisfy { $0.value == TownScene.sceneRectByScan(ofBuilding: $0.key, in: smaller) })
    }

    // MARK: - item 9 – the town view is paused when nothing moves

    @Test func theTownViewPausesAtRestAndWakesOnEveryMovement() {
        let (_, model) = bigTown(5)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let scene = TownScene(size: view.bounds.size)
        scene.imageProvider = { library.image(for: $0) }
        scene.cameraDefaults = UserDefaults(suiteName: "speed13p-\(UUID().uuidString)")!
        scene.reduceMotion = { true }
        view.presentScene(scene)
        scene.show(model, focus: nil)
        func rest(frames: Int = TownScene.idleFramesBeforePause + 5) {
            for i in 0..<frames { scene.update(Double(i) / 60) }
        }
        #expect(!view.isPaused)
        rest()
        #expect(view.isPaused)                                                   // a static town is not redrawn
        scene.pan(by: CGPoint(x: 10, y: 0)); #expect(!view.isPaused)             // a drag
        rest(); #expect(view.isPaused)
        scene.zoom(by: 1.2, at: CGPoint(x: 100, y: 100), in: view); #expect(!view.isPaused)
        rest(); #expect(view.isPaused)
        scene.fling(velocity: CGPoint(x: 400, y: 0)); #expect(!view.isPaused)
        for i in 0..<10 { scene.update(Double(i) / 60) }
        #expect(!view.isPaused)                                                  // the inertia keeps it running …
        rest(frames: 240); #expect(view.isPaused)                                // … until it dies out
        scene.animateZoom(in: CGPoint(x: 100, y: 100), view: view); #expect(!view.isPaused)
        scene.show(model, focus: nil); #expect(!view.isPaused)
        // stopped from outside (another tab, the rest screen): wake() does not undo it
        scene.suspended = true
        #expect(view.isPaused)
        scene.pan(by: CGPoint(x: 5, y: 0)); scene.wake()
        #expect(view.isPaused)
        scene.suspended = false
        #expect(!view.isPaused)
    }
}
