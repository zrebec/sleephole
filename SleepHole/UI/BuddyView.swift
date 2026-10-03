import SleepCore
import SwiftUI

/// The sleep buddy (plan P2, owner 2026-10-03): a Kenney Cube Pets cat on a camp bed that is turned towards the owner.
/// Awake it looks at him (breathing slowly, blinking now and then); asleep its head is down, its eyes are closed and
/// a slow "z Z z" drifts up. A change of state plays awake → drowsy → asleep (or back) as short crossfades.
///
/// The four frames share one canvas, so the bed stays on the same pixel and frames can be swapped without jitter.
/// Battery (bug B8): no timeline – the breathing and the "z Z z" are implicit repeating animations, and `body` is
/// only re-evaluated by the few state changes below (a blink every 4–7 s, a transition).
struct BuddyView: View {
    let state: BuddyState
    /// The little white cloud under the bed (Today: the bed floats in the sky next to the island).
    var cloud = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.buddyAnimates) private var buddyAnimates

    /// The rendered frames (`buddy-cat-<name>` in the asset catalog).
    enum Pose: String {
        case awake, blink, mid, asleep
        var imageName: String { "buddy-cat-\(rawValue)" }
    }

    /// The frame that is fully shown, and the next one that fades in over it.
    @State private var base: Pose
    @State private var top: Pose = .mid
    @State private var topOpacity = 0.0
    @State private var stepStart = Date.distantPast
    /// The state the cat rests in; nil while it changes (nothing idles then).
    @State private var resting: BuddyState?
    /// Which breathing is shown (kept during a transition so the old one goes on until the new state is reached).
    @State private var breathing: BuddyState
    @State private var blinking = false
    @State private var onScreen = false

    /// Seconds between two blinks (a range, picked at random). A variable so the tests do not have to wait.
    static var blinkDelay: ClosedRange<Double> = 4...7
    /// One crossfade step (awake → mid, mid → asleep …).
    static var stepDuration: Double { Motion.t(0.45) }
    /// Width / height of the canvas of the frames.
    static let aspect = 617.0 / 637.0

    init(state: BuddyState, cloud: Bool = false) {
        self.state = state
        self.cloud = cloud
        // the first appearance shows the right frame directly, without a transition
        _base = State(initialValue: state == .awake ? .awake : .asleep)
        _resting = State(initialValue: state)
        _breathing = State(initialValue: state)
    }

    private struct LoopKey: Hashable {
        let state: BuddyState
        let animated: Bool
    }

    /// Animations run only while the cat is on the screen, the app is in the foreground and Reduce Motion is off.
    /// (`buddyAnimates` lets the tests run them in a hosted window, where the scene phase is `.background`.)
    private var animated: Bool { onScreen && (buddyAnimates ?? (scenePhase == .active)) && !reduceMotion }

    var body: some View {
        let shown: Pose = base == .awake && blinking ? .blink : base
        BreathingStack(asleep: breathing == .asleep, still: !animated) {
            ZStack {
                Image(shown.imageName).resizable().aspectRatio(Self.aspect, contentMode: .fit)
                Image(top.imageName).resizable().aspectRatio(Self.aspect, contentMode: .fit).opacity(topOpacity)
            }
        }
        .background(alignment: .bottom) {
            if cloud { BuddyCloud() }
        }
        .overlay {
            GeometryReader { g in
                if resting == .asleep {
                    SleepZs(width: g.size.width, height: g.size.height, animated: animated)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: Motion.t(0.5)), value: resting)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state == .awake ? L("Your cat is looking at you") : L("Your sleepy cat"))
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .task(id: LoopKey(state: state, animated: animated)) {
            await settle(to: state, animated: animated)
            guard animated, !Task.isCancelled, resting == .awake else { return }
            await blinkLoop()
        }
    }

    // MARK: - state changes

    private func withoutAnimation(_ change: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }

    /// Brings the frames to `target`: straight away, or awake → mid → asleep (and back) as crossfades.
    private func settle(to target: BuddyState, animated: Bool) async {
        blinking = false
        // an interrupted fade: keep whichever frame was more visible
        if topOpacity > 0 {
            let done = Date().timeIntervalSince(stepStart) / Self.stepDuration
            withoutAnimation {
                if done >= 0.5 { base = top }
                topOpacity = 0
            }
            await frameBreak()
            if Task.isCancelled { return }
        }
        let goal: Pose = target == .awake ? .awake : .asleep
        if base == goal {
            resting = target
            breathing = target
            return
        }
        guard animated else {
            withoutAnimation { base = goal; resting = target; breathing = target }
            return
        }
        resting = nil
        for step in [Pose.mid, goal] where step != base {
            top = step
            stepStart = Date()
            withAnimation(.easeInOut(duration: Self.stepDuration)) { topOpacity = 1 }
            try? await Task.sleep(for: .seconds(Self.stepDuration))
            if Task.isCancelled { return }
            withoutAnimation { base = step; topOpacity = 0 }
            await frameBreak()
            if Task.isCancelled { return }
        }
        resting = target
        breathing = target
    }

    /// Lets the screen draw the reset (opacity 0) before the next fade starts – otherwise the value goes 1 → 0 → 1
    /// inside one update, SwiftUI sees no change and the next step would not animate.
    private func frameBreak() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    /// A blink every 4–7 s: the closed-eyes frame for ~0.15–0.2 s. Cancelled with the view.
    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: Self.blinkDelay)))
            if Task.isCancelled { break }
            blinking = true
            try? await Task.sleep(for: .milliseconds(Int.random(in: 150...200)))
            blinking = false
        }
        blinking = false
    }
}

private struct BuddyAnimatesKey: EnvironmentKey { static let defaultValue: Bool? = nil }

extension EnvironmentValues {
    /// nil = follow the scene phase; true / false forces the buddy's animations on / off (tests).
    var buddyAnimates: Bool? {
        get { self[BuddyAnimatesKey.self] }
        set { self[BuddyAnimatesKey.self] = newValue }
    }
}

/// The cat's slow breathing: a repeating implicit animation (no timeline) – deeper and slower when it sleeps.
/// A new depth first eases back to rest, then starts its own repeat (changing a running repeat in place would not
/// restart it).
private struct BreathingStack<Content: View>: View {
    let asleep: Bool
    let still: Bool
    @ViewBuilder let content: Content
    /// 0 = resting … 1 = the deepest breath in.
    @State private var level = 0.0

    private struct Key: Hashable { let asleep, still: Bool }

    var body: some View {
        content
            .scaleEffect(x: 1 + 0.014 * level, y: 1 + 0.035 * level, anchor: .bottom)
            .task(id: Key(asleep: asleep, still: still)) {
                if level > 0 {
                    withAnimation(.easeInOut(duration: 0.5)) { level = 0 }
                    try? await Task.sleep(for: .seconds(0.5))
                }
                guard !still, !Task.isCancelled else { return }
                // one breath in + out: ~5 s awake, ~7 s asleep (before the pace)
                let half = (asleep ? 3.5 : 2.5) * Motion.pace
                withAnimation(.easeInOut(duration: half).repeatForever(autoreverses: true)) { level = asleep ? 1 : 0.55 }
            }
            .onDisappear {                                  // a hidden tab must not keep animating
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { level = 0 }
            }
    }
}

/// "z Z z" drifting up from the sleeping head, three letters one third of a cycle apart. Each letter is two repeating
/// implicit animations (rise, fade in and out) started once – nothing is redrawn per frame.
private struct SleepZs: View {
    let width: CGFloat
    let height: CGFloat
    let animated: Bool

    /// One letter's whole life, in seconds (paced: slower than the old 4.8 s).
    static var cycle: Double { 3.6 * Motion.pace }

    var body: some View {
        // the head's top-right corner on the asleep frame
        let origin = CGPoint(x: width * 0.50, y: height * 0.30)
        ZStack(alignment: .topLeading) {
            if animated {
                ForEach(0..<3, id: \.self) { i in
                    ZLetter(index: i, width: width)
                }
            } else {
                Text(verbatim: "z Z z")
                    .font(.system(size: max(13, width * 0.14), weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .indigo.opacity(0.6), radius: 2)
                    .offset(y: -height * 0.12)
            }
        }
        .offset(x: origin.x, y: origin.y)
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

private struct ZLetter: View {
    let index: Int
    let width: CGFloat
    @State private var rise = 0.0
    @State private var fade = 0.0

    var body: some View {
        let size = max(13, width * 0.14) * (index == 1 ? 1.2 : 1)
        Text(verbatim: index == 1 ? "Z" : "z")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .indigo.opacity(0.6), radius: 2)
            .scaleEffect(0.75 + 0.55 * rise)
            .offset(x: width * 0.14 * rise + CGFloat(index) * 2, y: -width * 0.34 * rise)
            .opacity(fade)
            .task {
                // stagger the three letters, then loop: the rise restarts while the letter is invisible
                try? await Task.sleep(for: .seconds(SleepZs.cycle * Double(index) / 3))
                if Task.isCancelled { return }
                withAnimation(.linear(duration: SleepZs.cycle).repeatForever(autoreverses: false)) { rise = 1 }
                withAnimation(.easeInOut(duration: SleepZs.cycle / 2).repeatForever(autoreverses: true)) { fade = 1 }
            }
    }
}

/// A small white cloud to sleep on, drawn relative to the width of the cat: it floats in the same sky as the island.
private struct BuddyCloud: View {
    var body: some View {
        GeometryReader { g in
            let k = g.size.width / 112                     // the shapes below were drawn for a 112 pt wide cat
            ZStack {
                Ellipse().frame(width: 54 * k, height: 34 * k).offset(x: -42 * k, y: 4 * k)
                Ellipse().frame(width: 70 * k, height: 46 * k).offset(x: -10 * k, y: -4 * k)
                Ellipse().frame(width: 64 * k, height: 42 * k).offset(x: 26 * k, y: -2 * k)
                Ellipse().frame(width: 50 * k, height: 32 * k).offset(x: 54 * k, y: 6 * k)
                Capsule().frame(width: 140 * k, height: 26 * k).offset(y: 10 * k)
            }
            .foregroundStyle(.white.opacity(0.94))
            .position(x: g.size.width * 0.46, y: g.size.height * 0.93)
        }
        .accessibilityHidden(true)
    }
}
