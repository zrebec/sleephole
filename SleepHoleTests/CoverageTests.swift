import Foundation
import SleepCore
import SpriteKit
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// The remaining glue: launch arguments, the model WITH services (muted), town gestures, detection test.
@MainActor
struct CoverageTests {
    let sprites = SpriteLibrary.loadFromBundle()
    init() { AudioKeeper.muted = true }

    func container() -> ModelContainer {
        try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func launchArgumentsConfigureAndSeed() {
        let c = container()
        var s = AppSettings()
        AppModel.applyLaunchArguments(to: &s, context: c.mainContext,
                                      args: ["x", "-clearNights", "-bedtime", "21:00", "-wake", "04:30",
                                             "-ambience", "silence", "-seedNights", "12"])
        #expect(s.schedule.bedtime == TimeOfDay(21, 0) && s.schedule.wake == TimeOfDay(4, 30))
        #expect(s.ambience == .silence)
        let seeded = (try? c.mainContext.fetch(FetchDescriptor<NightRecord>())) ?? []
        #expect(seeded.count == 12 && seeded.allSatisfy(\.isFinalized))
        AppModel.applyLaunchArguments(to: &s, context: c.mainContext, args: ["x", "-ambience", "brown", "-bedtime", "bad"])
        #expect(s.ambience == .brownNoise && s.schedule.bedtime == TimeOfDay(21, 0))
        AppModel.applyLaunchArguments(to: &s, context: c.mainContext, args: ["x", "-clearNights"])
        #expect(((try? c.mainContext.fetch(FetchDescriptor<NightRecord>())) ?? []).isEmpty)
    }

    @Test func aNightWithRealServicesMuted() async {
        let c = container()
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 22, minute: 25))!
        let clock = FakeClock(start)
        var s = AppSettings()
        s.wakeCode = "1234"
        s.ambience = .silence
        let m = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s)
        m.refresh()
        m.startNight()
        #expect(m.audio.isRunning)
        m.settings.volume = 0.2                                              // live volume change
        m.append(.leftApp, at: start + 10 * 60)                              // after the grace → nudge
        m.append(.returned, at: start + 10 * 60 + 3)
        clock.now = cal.date(byAdding: .minute, value: 8 * 60 + 6, to: start)!   // wake + 1 min (22:25 + 8:06)
        m.refresh()
        #expect(m.phase == .alarm && m.audio.isAlarmRinging)
        #expect(m.confirm(code: "1234"))
        #expect(!m.audio.isRunning)
        m.acknowledgeResult()
        m.settings.schedule = Schedule(bedtime: TimeOfDay(23, 0), wake: TimeOfDay(7, 0))   // reschedules reminders
    }

    @Test func aResumedNightRestartsServicesAndLateAlarmIsShort() {
        let c = container()
        let cal = Calendar.current
        let bed = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 22, minute: 25))!
        let clock = FakeClock(bed)
        let m1 = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: AppSettings(),
                          servicesEnabled: false)
        m1.refresh(); m1.startNight()
        clock.now = cal.date(byAdding: .minute, value: 8 * 60 + 5 + 3, to: bed)!    // wake + 3 min: 2 min alarm over
        let m2 = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: AppSettings())
        #expect(m2.phase == .alarm && !m2.audio.isAlarmRinging)
        m2.abandonNight()
    }

    @Test func townGesturesAndSheet() {
        let catalog = sprites.catalog!
        let k = NightKey("2026-10-01")!
        let snap = TownBuilder.build(results: (0..<6).map {
            NightResult(key: k.adding(days: $0, calendar: .current), outcome: .complete, buildingId: "l1-house-a-0")
        }, catalog: catalog)
        let model = TownRender.build(snap, catalog: catalog, today: k, calendar: .current)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let scene = TownScene(size: view.bounds.size)
        scene.imageProvider = { sprites.image(for: $0) }
        view.presentScene(scene)
        scene.show(model, focus: nil)
        var tapped: [Int?] = []
        let co = TownSpriteView.Coordinator(onTap: { tapped.append($0) })
        co.scene = scene
        co.view = view
        let pan = UIPanGestureRecognizer(), pinch = UIPinchGestureRecognizer()
        let tap = UITapGestureRecognizer(), dbl = UITapGestureRecognizer()
        [pan, pinch, tap, dbl].forEach(view.addGestureRecognizer)
        co.pan(pan); co.pinch(pinch); co.tap(tap); co.doubleTap(dbl)
        #expect(tapped.count == 1)
        #expect(co.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: pinch))
        let bad = TownScene(size: .zero)
        #expect(bad.building(atView: .zero) == nil)

        let store = container()                                              // must outlive the models
        let appModel = AppModel(context: store.mainContext, catalog: catalog, clock: FakeClock(Date()),
                                settings: AppSettings(), servicesEnabled: false)
        let host = UIHostingController(rootView: BuildingSheet(building: snap.buildings[0])
            .environment(appModel).environment(sprites))
        host.view.layoutIfNeeded()
        var ruin = snap.buildings[1]; ruin.state = .ruins
        var unfinished = snap.buildings[2]; unfinished.state = .unfinished
        var later = snap.buildings[3]; later.completedLater = true
        for b in [ruin, unfinished, later] {
            let h = UIHostingController(rootView: BuildingSheet(building: b)
                .environment(appModel).environment(sprites))
            h.view.layoutIfNeeded()
        }
    }

    @Test func detectionTestController() async {
        let t = DetectionTest()
        t.log.clear()
        t.ambience = .silence
        t.start()
        #expect(t.night != nil && t.audio.isRunning)
        t.setVolume()
        t.monitor.callChanged(CallInfo(uuid: UUID(), isOutgoing: false, hasConnected: false, hasEnded: false))
        t.monitor.unlockCandidate()
        try? await Task.sleep(for: .seconds(5.5))
        t.stop()
        #expect(t.night == nil && !t.audio.isRunning)
        #expect(t.log.entries.contains { $0.text.contains("callStarted") })
        t.log.clear()
    }

    @Test func callsStartAndEnd() {
        let m = LifecycleMonitor()
        var events: [NightEventKind] = []
        m.onEvent = { k, _ in events.append(k) }
        let id = UUID()
        m.callChanged(CallInfo(uuid: id, isOutgoing: true, hasConnected: true, hasEnded: false))
        m.callChanged(CallInfo(uuid: id, isOutgoing: true, hasConnected: true, hasEnded: true))
        m.callChanged(CallInfo(uuid: UUID(), isOutgoing: false, hasConnected: false, hasEnded: true))
        #expect(events == [.callStarted, .callEnded])
    }
}
