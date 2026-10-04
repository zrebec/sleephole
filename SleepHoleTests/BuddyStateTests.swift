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
        let images = BuddyView.Pose.allCases.map { UIImage(named: $0.imageName) }
        #expect(images.count == 8 && images.allSatisfy { $0 != nil })
        let sizes = images.compactMap { $0?.size }
        #expect(Set(sizes.map { "\($0.width)x\($0.height)" }).count == 1)             // the bed never jumps
        let pixels = images.compactMap { $0?.cgImage }.map { CGSize(width: $0.width, height: $0.height) }
        #expect(pixels.allSatisfy { $0 == BuddyView.canvas })                         // 860 × 974 px
        #expect(abs(sizes[0].width / sizes[0].height - BuddyView.aspect) < 0.001)
        #expect(UIImage(named: ["buddy", "cat"].joined(separator: "-")) == nil)       // the old turned-away cat is gone
    }

    /// Fraction of the canvas height that is empty above the drawing (rows whose alpha is ≤ 8 / 255).
    func emptyTop(_ image: UIImage) -> Double {
        let cg = image.cgImage!
        let (w, h) = (cg.width, cg.height)
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        for row in 0..<h where (0..<w).contains(where: { data[(row * w + $0) * 4 + 3] > 8 }) {
            return Double(row) / Double(h)
        }
        return 1
    }

    /// `headroom` is the empty top of every frame except the two arched backs – only those draw above the layout box.
    @Test func headroomIsTheEmptyTopOfTheFramesThatAreNotArched() {
        for pose in BuddyView.Pose.allCases {
            let top = emptyTop(UIImage(named: pose.imageName)!)
            if pose == .arch1 || pose == .arch2 {
                #expect(top < BuddyView.headroom - 0.05, "\(pose) must use the headroom")
            } else {
                #expect(top >= BuddyView.headroom - 0.002, "\(pose) reaches above the layout box")
                if [.awake, .blink, .happy, .wink].contains(pose) {         // the standing frames define the headroom
                    #expect(top < BuddyView.headroom + 0.01, "\(pose) leaves unused room above")
                }
            }
        }
        #expect(abs(BuddyView.boxAspect - BuddyView.canvas.width / (BuddyView.canvas.height * (1 - BuddyView.headroom))) < 1e-9)
        #expect(BuddyView.boxAspect > BuddyView.aspect)                              // the box is shorter than the canvas
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


// MARK: - tap reactions (plan P2b)

@MainActor
struct BuddyReactionViewTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))!
    }

    func makeModel() -> (AppModel, ModelContainer) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var s = AppSettings()
        s.wakeCode = "1234"
        let m = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: FakeClock(date(5, 12)), settings: s,
                         servicesEnabled: false)
        return (m, c)
    }

    /// Hosts a view in a window (hide it when done). Hosted windows are in a background scene, so `animates` forces the
    /// buddy's animations on / off.
    func host<V: View>(_ view: V, animates: Bool?, probe: BuddyProbe) -> (UIHostingController<AnyView>, UIWindow) {
        let root = AnyView(view.environment(sprites).environment(\.buddyAnimates, animates).environment(\.buddyProbe, probe))
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        return (host, window)
    }

    /// Waits without blocking the main actor (the views' tasks only run while the test awaits), nudging layout.
    /// Only for "let it run" waits: never wait a FIXED time and then expect an end state – the views' own
    /// `Task.sleep`s drift when the whole suite runs under load (use `pump(_:until:timeout:)`).
    func pump(_ host: UIViewController, for seconds: TimeInterval) async {
        let end = Date() + seconds
        while Date() < end {
            try? await Task.sleep(for: .milliseconds(30))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
    }

    /// Pumps in 30 ms steps until `condition` holds (true) or `timeout` real seconds have passed (false). The timeout
    /// is only a safety net for a real failure – make it several times what the thing should take.
    @discardableResult
    func pump(_ host: UIViewController, until condition: () -> Bool, timeout: TimeInterval = 10) async -> Bool {
        let end = Date() + timeout
        while !condition() {
            if Date() >= end { return false }
            try? await Task.sleep(for: .milliseconds(30))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        return true
    }

    /// A generous limit for a reaction to play out: several times its paced duration.
    func limit(_ r: BuddyReaction) -> TimeInterval { BuddyView.timeline(r).pacedDuration * 4 + 4 }

    // MARK: static timelines

    @Test(arguments: BuddyReaction.allCases) func everyTimelineStartsAndEndsAwakeAndIsShort(r: BuddyReaction) {
        let t = BuddyView.timeline(r)
        #expect(t.start == .awake && t.end == .awake)
        #expect(!t.steps.isEmpty && t.steps.dropLast().allSatisfy { $0.pose != .awake })   // awake only at the very end
        #expect(t.steps.allSatisfy { $0.fade > 0 && $0.hold >= 0 })
        #expect(t.duration > 0.5 && t.duration < 3)
        #expect(t.pacedDuration < 3 * Motion.pace)
        #expect(abs(t.pacedDuration - t.duration * Motion.pace) < 1e-9)
    }

    @Test func theTimelinesAreWhatTheOwnerAsked() {
        let purr = BuddyView.timeline(.purr)
        #expect(purr.steps.map(\.pose) == [.happy, .awake])
        #expect(purr.steps[0].fade == 0.15 && purr.steps[0].hold == 1.8 && purr.steps[0].wobble)
        #expect(purr.steps[1].fade == 0.2)
        let arch = BuddyView.timeline(.arch)
        #expect(arch.steps.map(\.pose) == [.arch1, .arch2, .arch1, .awake])
        #expect(arch.steps.map(\.fade) == [0.2, 0.2, 0.2, 0.2])
        #expect(arch.steps[1].hold == 0.8 && arch.steps.filter { $0.wobble }.isEmpty)
        let wink = BuddyView.timeline(.wink)
        #expect(wink.steps.map(\.pose) == [.wink, .awake])
        #expect(wink.steps[0].fade == 0.12 && wink.steps[0].hold == 0.7 && wink.steps[1].fade == 0.15)
        #expect(purr.holdPose == .happy && arch.holdPose == .arch2 && wink.holdPose == .wink)
    }

    // MARK: rendering

    @Test(arguments: BuddyReaction.allCases) func rendersEveryReactionsHoldFrame(r: BuddyReaction) {
        let probe = BuddyProbe()
        let (host, window) = host(BuddyView(state: .awake, cloud: true, onPet: { nil }, hold: r).frame(width: 250),
                                  animates: nil, probe: probe)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.1)
        window.isHidden = true
    }

    @Test func aTappableBuddyAndAPlainOneRender() {
        let probe = BuddyProbe()
        let (host, window) = host(VStack {
            BuddyView(state: .awake, cloud: true, onPet: { .purr }).frame(width: 250)
            BuddyView(state: .asleep, onPet: { .arch }).frame(width: 150)
            BuddyView(state: .awake).frame(width: 150)
        }, animates: nil, probe: probe)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.1)
        window.isHidden = true
    }

    // MARK: taps

    /// Three taps give purr → arched back → wink, a fourth starts again; taps during a reaction are ignored; the
    /// model plays each reaction's vibration; the frames follow the timelines.
    @Test func tapsCycleThroughTheThreeReactions() async {
        let (m, _container) = makeModel()
        _ = _container
        let probe = BuddyProbe()
        let (host, window) = host(BuddyView(state: .awake, cloud: true, onPet: { m.petBuddy() }).frame(width: 250),
                                  animates: true, probe: probe)
        await pump(host, until: { probe.tap != nil })
        #expect(probe.tap != nil)

        probe.tap?()
        probe.tap?()                                                       // during the reaction: ignored
        probe.tap?()
        await pump(host, until: { probe.reaction == .purr })
        #expect(probe.reaction == .purr && m.haptics == [.purr])
        await pump(host, until: { probe.reaction == nil && probe.poses.count >= 2 }, timeout: limit(.purr))
        #expect(probe.reaction == nil)
        #expect(probe.poses == [.happy, .awake])

        probe.tap?()
        await pump(host, until: { probe.reaction == .arch })
        #expect(probe.reaction == .arch && m.haptics == [.purr, .pet])
        await pump(host, until: { probe.reaction == nil && probe.poses.count >= 6 }, timeout: limit(.arch))
        #expect(probe.reaction == nil)
        #expect(probe.poses == [.happy, .awake, .arch1, .arch2, .arch1, .awake])

        probe.tap?()
        await pump(host, until: { probe.reaction == .wink })
        #expect(probe.reaction == .wink && m.haptics == [.purr, .pet, .pet])
        await pump(host, until: { probe.reaction == nil && probe.poses.count >= 8 }, timeout: limit(.wink))
        #expect(probe.reaction == nil)
        #expect(probe.poses.suffix(2) == [.wink, .awake])

        probe.tap?()
        await pump(host, until: { probe.reaction == .purr })
        #expect(probe.reaction == .purr && m.haptics == [.purr, .pet, .pet, .purr])   // the cycle starts again
        #expect(probe.reactions == [.purr, .arch, .wink, .purr])
        window.isHidden = true
    }

    /// Reduce Motion / no animations: the frames swap without crossfades and are still shown for their time.
    @Test func withoutAnimationsTheFramesSwapAndAreHeldForTheirTime() async {
        var queue: [BuddyReaction] = [.wink, .arch]
        var calls = 0
        let probe = BuddyProbe()
        let (host, window) = host(BuddyView(state: .awake, onPet: { calls += 1; return queue.isEmpty ? nil : queue.removeFirst() })
            .frame(width: 250), animates: false, probe: probe)
        await pump(host, until: { probe.tap != nil })
        probe.tap?()
        await pump(host, until: { probe.reaction == .wink && !probe.poses.isEmpty })
        #expect(probe.reaction == .wink && probe.poses == [.wink])         // straight to the hold frame
        await pump(host, until: { probe.reaction == nil && probe.poses.count >= 2 }, timeout: limit(.wink))
        #expect(probe.reaction == nil && probe.poses == [.wink, .awake])
        probe.tap?()
        await pump(host, until: { probe.reaction == .arch })
        #expect(probe.reaction == .arch && calls == 2)
        await pump(host, until: { probe.reaction == nil && probe.poses.count >= 6 }, timeout: limit(.arch))
        #expect(probe.reaction == nil && probe.poses == [.wink, .awake, .arch1, .arch2, .arch1, .awake])
        window.isHidden = true
    }

    /// A tap while the cat sleeps or changes state is ignored (`onPet` is not called); falling asleep during a
    /// reaction cancels it and the normal transition runs.
    @Test func onlyAnAwakeRestingCatIsPetted() async {
        final class Box { var state = BuddyState.awake }
        struct Wrapper: View {
            let box: Box
            let onPet: () -> BuddyReaction?
            @State private var state = BuddyState.awake
            var body: some View {
                BuddyView(state: state, onPet: onPet).frame(width: 200)
                    .task {
                        while !Task.isCancelled {
                            state = box.state
                            try? await Task.sleep(for: .milliseconds(30))
                        }
                    }
            }
        }
        let box = Box()
        var calls = 0
        let probe = BuddyProbe()
        let (host, window) = host(Wrapper(box: box, onPet: { calls += 1; return .purr }), animates: true, probe: probe)
        await pump(host, until: { probe.tap != nil })
        probe.tap?()
        await pump(host, until: { probe.reaction == .purr })
        #expect(calls == 1 && probe.reaction == .purr)

        box.state = .asleep                                                // falls asleep during the purr
        await pump(host, until: { probe.reaction == nil })
        #expect(probe.reaction == nil)                                     // cancelled
        await pump(host, until: { probe.poses.last == .asleep }, timeout: BuddyView.stepDuration * 8 + 4)
        #expect(probe.poses.last == .asleep)                               // the normal awake → mid → asleep ran
        probe.tap?()
        #expect(calls == 1)                                                // asleep: ignored

        box.state = .awake
        await pump(host, until: { probe.poses.last == .mid }, timeout: BuddyView.stepDuration * 8 + 4)   // in the transition
        probe.tap?()
        #expect(calls == 1)
        await pump(host, until: { probe.poses.last == .awake }, timeout: BuddyView.stepDuration * 8 + 4)
        #expect(probe.poses.last == .awake)
        // The last frame is shown ~50 ms before the cat counts as resting again – tap until the tap is accepted.
        await pump(host, until: { probe.tap?(); return calls == 2 })       // resting awake again
        #expect(calls == 2)
        window.isHidden = true
    }

    @Test func aNilAnswerPlaysNothing() async {
        let probe = BuddyProbe()
        let (host, window) = host(BuddyView(state: .awake, onPet: { nil }).frame(width: 200), animates: true, probe: probe)
        await pump(host, until: { probe.tap != nil })
        probe.tap?()
        await pump(host, for: 0.3)                                         // nothing may happen: a fixed wait is right
        #expect(probe.reaction == nil && probe.poses.isEmpty)
        window.isHidden = true
    }

    @Test func aPlainBuddyIsNotTappable() async {
        let probe = BuddyProbe()
        let (host, window) = host(BuddyView(state: .awake).frame(width: 200), animates: true, probe: probe)
        await pump(host, until: { probe.tap != nil })
        probe.tap?()
        await pump(host, for: 0.3)                                         // nothing may happen: a fixed wait is right
        #expect(probe.reaction == nil && probe.poses.isEmpty)               // no onPet: the tap does nothing
        window.isHidden = true
    }

    /// Today: the cat is the hero and a tap pets it – the Town tab is no longer opened from there.
    @Test func todayShowsTheCatAndATapPetsIt() async {
        let (m, _container) = makeModel()
        _ = _container
        let probe = BuddyProbe()
        let (host, window) = host(HomeView().environment(m), animates: true, probe: probe)
        await pump(host, until: { probe.tap != nil })
        #expect(probe.tap != nil)
        probe.tap?()
        await pump(host, until: { probe.reaction == .purr })
        #expect(probe.reaction == .purr && m.haptics == [.purr])
        #expect(m.townRequest == 0)                                        // the old island's tap opened the Town tab
        window.isHidden = true
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
