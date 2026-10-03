import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// The sleep buddy (plan P2): the model feeds `Buddy.state` from the running night, `BuddyView` draws it.
@MainActor
struct BuddyStateTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m, second: s))!
    }

    /// The container must outlive the model (ModelContext does not retain it).
    func makeModel(at now: Date) -> (AppModel, FakeClock, ModelContainer) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let clock = FakeClock(now)
        var s = AppSettings()
        s.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        s.wakeCode = "1234"
        let m = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s, servicesEnabled: false)
        return (m, clock, c)
    }

    func render<V: View>(_ view: V, for seconds: TimeInterval = 0.15) {
        let host = UIHostingController(rootView: view.environment(sprites))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + seconds)
        window.isHidden = true
    }

    /// Waits `seconds` WITHOUT blocking the main actor (tasks of the views only run while the test awaits – a nested
    /// `RunLoop.run` starves them), nudging the hosting view every 30 ms to flush SwiftUI's pending updates (a hosted
    /// window is in a background scene – nothing is redrawn until it is asked to lay out).
    func pump(_ host: UIViewController, for seconds: TimeInterval) async {
        let end = Date() + seconds
        while Date() < end {
            try? await Task.sleep(for: .milliseconds(30))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
    }

    // MARK: the model helper

    @Test func awakeOnTodayAndThroughTheWholeNight() {
        let (m, clock, _container) = makeModel(at: date(5, 12))
        _ = _container
        #expect(AppModel.forcedBuddyState == nil)
        #expect(m.buddyState() == .awake)                                   // Today, nothing running
        clock.now = date(5, 22, 25); m.refresh()
        #expect(m.phase == .canStart && m.buddyState() == .awake)
        m.startNight()
        #expect(m.graceEnds == date(5, 22, 35))
        #expect(m.buddyState() == .awake)                                   // setup
        #expect(m.buddyState(at: date(5, 22, 34, 59)) == .awake)
        #expect(m.buddyState(at: date(5, 22, 35)) == .asleep)               // the setup is over
        clock.now = date(5, 23); m.refresh()
        #expect(m.buddyState() == .asleep)
        clock.now = date(6, 2, 0); m.startPause()
        #expect(m.pauseEnds() == date(6, 2, 10))
        #expect(m.buddyState() == .awake)                                   // a pause
        #expect(m.buddyState(at: date(6, 2, 9, 59)) == .awake)
        #expect(m.buddyState(at: date(6, 2, 10)) == .asleep)                // and asleep again
        clock.now = date(6, 2, 30)
        #expect(m.buddyState() == .asleep)
        clock.now = date(6, 6, 10); m.refresh()
        #expect(m.active?.window.canConfirm(at: clock.now) == true)
        #expect(m.buddyState() == .asleep)                                  // early-confirm window: still asleep
        clock.now = date(6, 6, 30); m.refresh()
        #expect(m.phase == .alarm)
        #expect(m.buddyState() == .awake)                                   // the alarm
        #expect(m.confirm(code: "1234"))
        m.acknowledgeResult()
        #expect(m.buddyState() == .awake)                                   // Today again
    }

    @Test func aCollapsedNightStillShowsTheCatAsleep() {
        let (m, clock, _container) = makeModel(at: date(5, 22, 25))
        _ = _container
        m.refresh(); m.startNight()
        clock.now = date(5, 23, 30); m.append(.leftApp)
        clock.now += 30; m.append(.returned)
        #expect(m.collapsedAt != nil)
        clock.now = date(6, 1, 0)
        #expect(m.buddyState() == .asleep)                                  // the cat never judges
        clock.now = date(6, 6, 30); m.refresh()
        #expect(m.phase == .alarm && m.buddyState() == .awake)              // the alarm still wakes it
    }

    @Test func aNapFollowsTheSameRule() {
        let (m, clock, _container) = makeModel(at: date(5, 13, 30))
        _ = _container
        m.startNap()
        #expect(m.graceEnds == date(5, 13, 32))
        #expect(m.buddyState() == .awake)                                   // 2 min of setup
        clock.now = date(5, 13, 33)
        #expect(m.buddyState() == .asleep)
        clock.now = date(5, 14, 0); m.refresh()
        #expect(m.phase == .alarm && m.buddyState() == .awake)
    }

    // MARK: assets

    @Test func everyFrameIsInTheAssetCatalogOnOneCanvas() {
        let sizes = ["awake", "blink", "mid", "asleep"].map { UIImage(named: "buddy-cat-\($0)")?.size }
        #expect(sizes.allSatisfy { $0 != nil })
        #expect(Set(sizes.compactMap { $0 }.map { "\($0.width)x\($0.height)" }).count == 1)    // the bed never jumps
        let size = sizes[0]!
        #expect(abs(size.width / size.height - BuddyView.aspect) < 0.001)
        #expect(UIImage(named: ["buddy", "cat"].joined(separator: "-")) == nil)       // the old turned-away cat is gone
    }

    // MARK: rendering

    @Test(arguments: [BuddyState.awake, .asleep]) func rendersBothStates(state: BuddyState) {
        render(BuddyView(state: state).frame(width: 130))
        render(BuddyView(state: state, cloud: true).frame(width: 130))
    }

    /// A change of state plays awake → mid → asleep and back (also when it is interrupted half-way), a blink swaps
    /// the frame for a moment, the z's rise. A hosted window's scene phase is `.background`, so the animations are
    /// forced on; the changes come from a script inside the view.
    @Test func aChangeOfStateCrossfades() async {
        let was = BuddyView.blinkDelay
        BuddyView.blinkDelay = 0.05...0.1
        defer { BuddyView.blinkDelay = was }
        let script: [(BuddyState, Double)] = [(.awake, 0.6), (.asleep, 0.4),    // interrupted half-way …
                                              (.awake, 0.3), (.asleep, 2.0),    // … by the owner picking the phone up
                                              (.awake, 2.0)]                    // and back
        let host = UIHostingController(rootView: BuddyScript(steps: script).environment(sprites)
            .environment(\.buddyAnimates, true))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        await pump(host, for: script.map(\.1).reduce(0, +) + 0.3)
        window.isHidden = true
    }

    @Test func staysStillWhenAnimationsAreOff() async {
        let script: [(BuddyState, Double)] = [(.awake, 0.2), (.asleep, 0.4)]   // jumps straight to the asleep frame
        let host = UIHostingController(rootView: BuddyScript(steps: script).environment(sprites)
            .environment(\.buddyAnimates, false))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        await pump(host, for: 0.8)
        window.isHidden = true
    }

    @Test func napAndNightScreensShowTheBuddy() {
        let (m, clock, _container) = makeModel(at: date(5, 13, 30))
        _ = _container
        render(NapResting(progress: 0.3).environment(m))
        render(NapResting(progress: 0.3, buddy: .awake).environment(m))
        render(ConstructionSite(buildingId: "l1-house-a-0", progress: 0.5, buddy: .asleep).environment(m))
        render(ConstructionSite(buildingId: "l1-house-a-0", progress: 0.5, resting: true, buddy: .awake).environment(m))
        render(AlarmView().environment(m))
        m.startNap()
        render(TodayView().environment(m))                                  // nap, setup: awake cat
        clock.now = date(5, 13, 40); m.refresh()
        render(TodayView().environment(m))                                  // nap, resting: asleep cat
        m.append(.leftApp); clock.now += 30; m.append(.returned)
        render(TodayView().environment(m))                                  // interrupted nap: asleep cat
    }
}

/// Shows the buddy and walks it through (state, seconds) steps.
private struct BuddyScript: View {
    let steps: [(BuddyState, Double)]
    @State private var state = BuddyState.awake

    var body: some View {
        BuddyView(state: state, cloud: true).frame(width: 130)
            .task {
                for (next, seconds) in steps {
                    state = next
                    try? await Task.sleep(for: .seconds(seconds))
                }
            }
    }
}
