import SleepCore
import SwiftUI

/// The sleep buddy (plan P2, owner 2026-10-03): a Kenney Cube Pets cat on a camp bed that is turned towards the owner.
/// Awake it looks at him (breathing slowly, blinking now and then); asleep its head is down, its eyes are closed and
/// a slow "z Z z" drifts up. A change of state plays awake → drowsy → asleep (or back) as short crossfades.
///
/// Plan P2b (owner 2026-10-03 evening): on Today the cat is the hero and answers taps – a purr (happy face, hearts),
/// an arched back, a wink – three reactions in a cycle (`BuddyReaction`), each a short timeline of frames.
///
/// The eight frames share one canvas, so the bed stays on the same pixel and frames can be swapped without jitter.
/// The canvas is tall only because of the arched back's tail: the view's LAYOUT box leaves out the empty top of the
/// canvas (`headroom`), and only the arch frames draw above it (not clipped).
/// Battery (bug B8): no timeline – the breathing and the "z Z z" are implicit repeating animations, and `body` is
/// only re-evaluated by the few state changes below (a blink every 4–7 s, a transition, a reaction).
struct BuddyView: View {
    let state: BuddyState
    /// The little white cloud under the bed (Today: the bed floats in the sky).
    var cloud = false
    /// Set = the cat answers taps (Today, the sound test). It is called for a tap that is accepted – the cat rests
    /// awake, nothing is playing – and returns the reaction to play (nil = none). Nil = not tappable.
    var onPet: (() -> BuddyReaction?)?
    /// Dev aid / tests: shows this reaction's hold frame (hearts, sparkle) without playing anything.
    var hold: BuddyReaction?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.buddyAnimates) private var buddyAnimates
    @Environment(\.buddyProbe) private var probe

    /// The rendered frames (`buddy-cat-<name>` in the asset catalog).
    enum Pose: String, Equatable, CaseIterable {
        case awake, blink, mid, asleep
        case happy                                  // eyes closed as "^ ^"
        case wink                                   // one eye closed, head tilted
        case arch1 = "arch-1", arch2 = "arch-2"     // standing tall on stretched legs, tail puffed: half / full
        var imageName: String { "buddy-cat-\(rawValue)" }
    }

    /// The frame that is fully shown, and the next one that fades in over it.
    @State private var base: Pose
    @State private var top: Pose = .mid
    @State private var topOpacity = 0.0
    @State private var stepStart = Date.distantPast
    /// The length of the fade that is on (a transition step or a reaction step).
    @State private var stepLength = BuddyView.stepDuration
    /// The state the cat rests in; nil while it changes (nothing idles then).
    @State private var resting: BuddyState?
    /// Which breathing is shown (kept during a transition so the old one goes on until the new state is reached).
    @State private var breathing: BuddyState
    @State private var blinking = false
    @State private var onScreen = false
    /// The reaction that is playing (nil = the cat rests) and the task that plays it.
    @State private var reaction: BuddyReaction?
    @State private var reactionTask: Task<Void, Never>?
    /// The purr's tiny wobble (degrees / scale).
    @State private var wobbleAngle = 0.0
    @State private var wobbleScale = 1.0

    /// Seconds between two blinks (a range, picked at random). A variable so the tests do not have to wait.
    static var blinkDelay: ClosedRange<Double> = 4...7
    /// One crossfade step (awake → mid, mid → asleep …).
    static var stepDuration: Double { Motion.t(0.45) }

    // MARK: the canvas

    /// Size of the canvas of the frames in pixels, and its width / height.
    static let canvas = CGSize(width: 860, height: 974)
    static let aspect = canvas.width / canvas.height
    /// The fraction of the canvas height that is empty above the tallest frame that is not an arched back
    /// (`awake`, `blink`, `happy`, `wink`: the tail tip at pixel row 159 of 974). Only `arch-1` / `arch-2` use it.
    static let headroom = 159.0 / 974.0
    /// Width / height of the layout box: the canvas without its empty top.
    static let boxAspect = canvas.width / (canvas.height * (1 - headroom))

    /// Places on the canvas, normalized (x from the left, y from the top), measured on the renders of 2026-10-03.
    enum Spot {
        /// Top centre of the head (awake): the hearts start here.
        static let head = CGPoint(x: 0.3023, y: 0.2557)
        /// Right next to the closed eye of the wink frame, up and to the right of it.
        static let sparkle = CGPoint(x: 0.5, y: 0.40)
        /// Top-right corner of the cube (asleep): "z Z z" starts here.
        static let sleepZs = CGPoint(x: 0.4965, y: 0.3429)
        /// Where the bed touches the ground (cat + bed look centred on this x).
        static let bed = CGPoint(x: 0.3592, y: 0.8339)
        /// The visual centre of cat + bed (the bed's corners span x 0.01…0.73): Today centres this on the screen.
        static let centreX = 0.37
        /// The cloud's centre: under the bed, a little right of it (the bed's right half hangs over the shadow; the
        /// cloud's own mass sits 0.04 right of this point). 0.4255 was the old canvas' look; 0.37 balances it on Today.
        static let cloud = CGPoint(x: 0.37, y: 0.9415)
        /// The cube is 323 of 860 px wide.
        static let catWidth = 0.376
    }

    init(state: BuddyState, cloud: Bool = false, onPet: (() -> BuddyReaction?)? = nil, hold: BuddyReaction? = nil) {
        self.state = state
        self.cloud = cloud
        self.onPet = onPet
        self.hold = hold
        // the first appearance shows the right frame directly, without a transition
        _base = State(initialValue: hold.map { Self.timeline($0).holdPose } ?? (state == .awake ? .awake : .asleep))
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

    /// The owner may pet the cat now.
    private var tappable: Bool { onPet != nil && state == .awake }

    var body: some View {
        Color.clear
            .aspectRatio(Self.boxAspect, contentMode: .fit)
            .overlay {
                GeometryReader { g in canvas(width: g.size.width, boxHeight: g.size.height) }
            }
            .contentShape(Rectangle())                      // the layout box is the tap area
            .onTapGesture { tap() }
            .allowsHitTesting(onPet != nil)                 // a plain buddy stays a decoration (the night is calm)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state == .awake ? L("Your cat is looking at you") : L("Your sleepy cat"))
            .accessibilityAddTraits(tappable ? .isButton : [])
            .accessibilityHint(tappable ? L("Tap to pet your cat") : "")
            .accessibilityAction(.default) { tap() }
            .onAppear { onScreen = true; probe?.tap = { tap() } }
            .onDisappear { onScreen = false; cancelReaction(resetPose: true) }
            .onChange(of: state) { _, new in
                if new != .awake { cancelReaction(resetPose: false) }       // the normal transition takes over
                probe?.tap = { tap() }
            }
            .onChange(of: animated) { _, now in
                if !now { cancelReaction(resetPose: state == .awake) }
            }
            .onChange(of: reaction) { _, new in probe?.reactionChanged(new) }
            .onChange(of: base) { _, new in probe?.poseChanged(new) }
            .task(id: LoopKey(state: state, animated: animated)) {
                guard hold == nil else { return }
                await settle(to: state, animated: animated)
                guard animated, !Task.isCancelled, resting == .awake else { return }
                await blinkLoop()
            }
    }

    /// The whole canvas, bottom-aligned to the layout box (`boxHeight` is shorter by the headroom), so that only the
    /// arch frames reach above it.
    @ViewBuilder
    private func canvas(width w: CGFloat, boxHeight: CGFloat) -> some View {
        let h = w / Self.aspect
        let shown: Pose = base == .awake && blinking ? .blink : base
        ZStack(alignment: .topLeading) {
            if cloud { BuddyCloud(width: w, height: h) }
            BreathingStack(asleep: breathing == .asleep, still: !animated) {
                ZStack {
                    Image(shown.imageName).resizable().frame(width: w, height: h)
                    Image(top.imageName).resizable().frame(width: w, height: h).opacity(topOpacity)
                }
            }
            .rotationEffect(.degrees(wobbleAngle), anchor: UnitPoint(x: Spot.head.x, y: 0.8))
            .scaleEffect(wobbleScale, anchor: UnitPoint(x: Spot.head.x, y: 0.8))
            decorations(width: w, height: h)
            ZStack {
                if resting == .asleep {
                    SleepZs(width: w, height: h, animated: animated).transition(.opacity)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .animation(.easeInOut(duration: Motion.t(0.5)), value: resting)
            .allowsHitTesting(false)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .offset(y: boxHeight - h)
    }

    /// Hearts of the purr, the wink's sparkle (the reaction that is playing, or the held one).
    @ViewBuilder
    private func decorations(width w: CGFloat, height h: CGFloat) -> some View {
        let showing = hold ?? (animated ? reaction : nil)
        Group {
            switch showing {
            case .purr: PurrHearts(width: w, height: h, still: hold != nil)
            case .wink: WinkSparkle(width: w, height: h, still: hold != nil)
            case .arch, nil: EmptyView()
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: - taps and reactions

    private func tap() {
        // only while the cat rests awake: not in a transition, not during a reaction, not asleep
        guard let onPet, hold == nil, state == .awake, resting == .awake, reaction == nil, topOpacity == 0 else { return }
        guard let r = onPet() else { return }
        start(r)
    }

    private func start(_ r: BuddyReaction) {
        blinking = false
        reaction = r
        reactionTask = Task {
            await play(r)
            guard !Task.isCancelled else { return }
            reaction = nil
            reactionTask = nil
        }
    }

    /// Stops a running reaction (the cat falls asleep, the app goes to the background, the view disappears).
    /// `resetPose`: also jump back to the awake frame (otherwise a transition takes over from the shown one).
    private func cancelReaction(resetPose: Bool) {
        reactionTask?.cancel()
        reactionTask = nil
        guard reaction != nil else { return }
        reaction = nil
        withoutAnimation {
            wobbleAngle = 0
            wobbleScale = 1
            if resetPose, resting == .awake { base = .awake; topOpacity = 0 }
        }
    }

    /// Plays a reaction's timeline: for every step a crossfade to its pose, then the hold. Without animations
    /// (Reduce Motion, tests) the frames swap and the fade time is added to the hold, so every frame is still shown.
    private func play(_ r: BuddyReaction) async {
        let fades = animated
        for step in Self.timeline(r).steps {
            var wait = Motion.t(step.hold)
            if fades {
                top = step.pose
                stepLength = Motion.t(step.fade)
                stepStart = Date()
                withAnimation(.easeInOut(duration: stepLength)) { topOpacity = 1 }
                try? await Task.sleep(for: .seconds(stepLength))
                if Task.isCancelled { return }
                withoutAnimation { base = step.pose; topOpacity = 0 }
                await frameBreak()
                if Task.isCancelled { return }
                wait -= 0.05
            } else {
                withoutAnimation { base = step.pose }
                wait += Motion.t(step.fade)
            }
            if step.wobble, fades { await wobble(for: wait) } else { try? await Task.sleep(for: .seconds(max(0, wait))) }
            if Task.isCancelled { return }
        }
    }

    /// The purr: the cat rocks a little (±2°, 1.03×) for `seconds`, then eases back while the next frame fades in.
    private func wobble(for seconds: Double) async {
        withAnimation(.easeOut(duration: Motion.t(0.15))) { wobbleScale = 1.03 }
        let half = Motion.t(0.2)
        var left = seconds
        var direction = 1.0
        while left > 0.01 {
            let d = min(half, left)
            withAnimation(.easeInOut(duration: d)) { wobbleAngle = 2 * direction }
            try? await Task.sleep(for: .seconds(d))
            if Task.isCancelled { return }
            direction = -direction
            left -= d
        }
        withAnimation(.easeOut(duration: Motion.t(0.2))) { wobbleAngle = 0; wobbleScale = 1 }
    }

    // MARK: reaction timelines (static data – the tests check them)

    /// One step of a reaction: fade to `pose` over `fade` seconds, then show it for `hold` more seconds
    /// (both before `Motion.pace`). `wobble`: the cat rocks a little while it is held.
    struct Step: Equatable {
        let pose: Pose
        let fade: Double
        var hold: Double = 0
        var wobble = false
    }

    struct Timeline: Equatable {
        /// The frame the reaction starts from.
        let start: Pose
        let steps: [Step]
        /// The frame it ends on (the cat is at rest again).
        var end: Pose { steps.last?.pose ?? start }
        /// Seconds before `Motion.pace`.
        var duration: Double { steps.reduce(0) { $0 + $1.fade + $1.hold } }
        /// What the reaction really takes (paced).
        var pacedDuration: Double { Motion.t(duration) }
        /// The frame that is shown the longest: the one a still screenshot shows.
        var holdPose: Pose { steps.max { $0.hold < $1.hold }?.pose ?? start }
    }

    static func timeline(_ r: BuddyReaction) -> Timeline {
        switch r {
        case .purr:
            Timeline(start: .awake, steps: [Step(pose: .happy, fade: 0.15, hold: 1.8, wobble: true),
                                            Step(pose: .awake, fade: 0.2)])
        case .arch:
            Timeline(start: .awake, steps: [Step(pose: .arch1, fade: 0.2),
                                            Step(pose: .arch2, fade: 0.2, hold: 0.8),
                                            Step(pose: .arch1, fade: 0.2),
                                            Step(pose: .awake, fade: 0.2)])
        case .wink:
            Timeline(start: .awake, steps: [Step(pose: .wink, fade: 0.12, hold: 0.7),
                                            Step(pose: .awake, fade: 0.15)])
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
            let done = Date().timeIntervalSince(stepStart) / max(0.01, stepLength)
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
        stepLength = Self.stepDuration
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

    /// A blink every 4–7 s: the closed-eyes frame for ~0.15–0.2 s (never during a reaction). Cancelled with the view.
    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: Self.blinkDelay)))
            if Task.isCancelled { break }
            guard reaction == nil else { continue }
            blinking = true
            try? await Task.sleep(for: .milliseconds(Int.random(in: 150...200)))
            blinking = false
        }
        blinking = false
    }
}

extension BuddyView {
    /// Shifts a buddy sideways so that cat + bed (not the canvas) are centred in the space it was given.
    /// Call it on the buddy after its width is set. Visual only – the layout is unchanged.
    static func centred<V: View>(_ view: V) -> some View {
        view.visualEffect { content, proxy in
            content.offset(x: (0.5 - Spot.centreX) * proxy.size.width)
        }
    }
}

private struct BuddyAnimatesKey: EnvironmentKey { static let defaultValue: Bool? = nil }
private struct BuddyProbeKey: EnvironmentKey { static let defaultValue: BuddyProbe? = nil }

extension EnvironmentValues {
    /// nil = follow the scene phase; true / false forces the buddy's animations on / off (tests).
    var buddyAnimates: Bool? {
        get { self[BuddyAnimatesKey.self] }
        set { self[BuddyAnimatesKey.self] = newValue }
    }

    /// Test hook: see `BuddyProbe`.
    var buddyProbe: BuddyProbe? {
        get { self[BuddyProbeKey.self] }
        set { self[BuddyProbeKey.self] = newValue }
    }
}

/// Test hook (hosted tests cannot tap): a `BuddyView` that finds one in its environment hands it its tap handler and
/// reports every reaction and every frame that became the shown one. Nothing in the app uses it.
@MainActor
final class BuddyProbe {
    /// The view's tap, exactly what a tap on it does.
    var tap: (() -> Void)?
    private(set) var reaction: BuddyReaction?
    private(set) var reactions: [BuddyReaction] = []
    private(set) var poses: [BuddyView.Pose] = []

    func reactionChanged(_ r: BuddyReaction?) {
        reaction = r
        if let r { reactions.append(r) }
    }

    func poseChanged(_ p: BuddyView.Pose) { poses.append(p) }
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
    let width: CGFloat          // the canvas
    let height: CGFloat
    let animated: Bool

    /// One letter's whole life, in seconds (paced: slower than the old 4.8 s).
    static var cycle: Double { 3.6 * Motion.pace }
    /// The letters are sized by the cat, which is 0.376 of the canvas wide (0.397 on the old canvas).
    static let unit = 0.133

    var body: some View {
        // the head's top-right corner on the asleep frame
        let origin = CGPoint(x: width * BuddyView.Spot.sleepZs.x, y: height * BuddyView.Spot.sleepZs.y)
        ZStack(alignment: .topLeading) {
            if animated {
                ForEach(0..<3, id: \.self) { i in
                    ZLetter(index: i, width: width)
                }
            } else {
                Text(verbatim: "z Z z")
                    .font(.system(size: max(13, width * Self.unit), weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .indigo.opacity(0.6), radius: 2)
                    .offset(y: -width * Self.unit)
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
        let size = max(13, width * SleepZs.unit) * (index == 1 ? 1.2 : 1)
        Text(verbatim: index == 1 ? "Z" : "z")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .indigo.opacity(0.6), radius: 2)
            .scaleEffect(0.75 + 0.55 * rise)
            .offset(x: width * SleepZs.unit * rise + CGFloat(index) * 2, y: -width * 0.32 * rise)
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

/// Three small hearts that rise from the top of the head while the cat purrs, one after the other, fading out.
/// `still`: the held frame of a screenshot – the three hearts frozen half-way.
private struct PurrHearts: View {
    let width: CGFloat          // the canvas
    let height: CGFloat
    let still: Bool

    /// Horizontal start (fraction of the width – the tail stands right above the head's centre, so the hearts keep
    /// to its sides), size factor.
    private static let hearts: [(dx: Double, size: Double)] = [(-0.12, 0.9), (0.15, 1.1), (-0.05, 1.0)]

    var body: some View {
        ForEach(0..<Self.hearts.count, id: \.self) { i in
            Heart(index: i, dx: Self.hearts[i].dx * width, size: width * 0.085 * Self.hearts[i].size, rise: width * 0.24,
                  at: CGPoint(x: width * BuddyView.Spot.head.x, y: height * BuddyView.Spot.head.y), still: still)
        }
    }

    private struct Heart: View {
        let index: Int
        let dx: CGFloat
        let size: CGFloat
        let rise: CGFloat
        let at: CGPoint
        let still: Bool
        @State private var risen = 0.0
        @State private var opacity = 0.0

        var body: some View {
            let frozen = [0.45, 0.7, 0.25][index]                 // still: how far each heart has come
            Text(verbatim: "♥")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.62))
                .shadow(color: .white.opacity(0.7), radius: 1.5)
                .scaleEffect(0.6 + 0.4 * min(1, (still ? frozen : risen) * 4))
                .opacity(still ? 0.9 - 0.4 * frozen : opacity)
                .position(x: at.x + dx, y: at.y - rise * (still ? frozen : risen))
                .task {
                    guard !still else { return }
                    let life = Motion.t(1.1)
                    try? await Task.sleep(for: .seconds(Motion.t(0.3) * Double(index)))
                    if Task.isCancelled { return }
                    withAnimation(.easeOut(duration: life)) { risen = 1 }
                    withAnimation(.easeIn(duration: life * 0.15)) { opacity = 0.95 }
                    try? await Task.sleep(for: .seconds(life * 0.45))
                    if Task.isCancelled { return }
                    withAnimation(.easeOut(duration: life * 0.55)) { opacity = 0 }
                }
        }
    }
}

/// One sparkle that pops next to the closed eye of the wink: it grows with a little overshoot, turns and fades.
private struct WinkSparkle: View {
    let width: CGFloat          // the canvas
    let height: CGFloat
    let still: Bool
    @State private var pop = 0.0
    @State private var turn = 0.0

    private struct Star: Shape {
        func path(in rect: CGRect) -> Path {
            Sparkle.path(at: CGPoint(x: rect.midX, y: rect.midY), size: min(rect.width, rect.height) / 2)
        }
    }

    var body: some View {
        let size = width * 0.11
        ZStack {
            Star().fill(.yellow.opacity(0.55)).frame(width: size * 1.5, height: size * 1.5).blur(radius: size * 0.12)
            Star().fill(.white).frame(width: size, height: size)
        }
        .shadow(color: .orange.opacity(0.5), radius: 2)
        .rotationEffect(.degrees(still ? 0 : turn))
        .scaleEffect(still ? 1 : pop)
        .opacity(still ? 1 : min(1, pop * 1.5))
        .position(x: width * BuddyView.Spot.sparkle.x, y: height * BuddyView.Spot.sparkle.y)
        .task {
            guard !still else { return }
            withAnimation(.spring(response: Motion.t(0.22), dampingFraction: 0.45)) { pop = 1 }
            withAnimation(.easeOut(duration: Motion.t(0.7))) { turn = 50 }
            try? await Task.sleep(for: .seconds(Motion.t(0.5)))
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: Motion.t(0.3))) { pop = 0 }
        }
    }
}

/// A small white cloud to sleep on, drawn relative to the width of the canvas: it floats in the same sky as the
/// rest of Today.
private struct BuddyCloud: View {
    let width: CGFloat          // the canvas
    let height: CGFloat

    var body: some View {
        // the shapes below were drawn for a 112 pt wide cat on the old canvas, where it was 0.397 of the width
        let k = width * BuddyView.Spot.catWidth / (112 * 0.397)
        ZStack {
            Ellipse().frame(width: 54 * k, height: 34 * k).offset(x: -42 * k, y: 4 * k)
            Ellipse().frame(width: 70 * k, height: 46 * k).offset(x: -10 * k, y: -4 * k)
            Ellipse().frame(width: 64 * k, height: 42 * k).offset(x: 26 * k, y: -2 * k)
            Ellipse().frame(width: 50 * k, height: 32 * k).offset(x: 54 * k, y: 6 * k)
            Capsule().frame(width: 140 * k, height: 26 * k).offset(y: 10 * k)
        }
        .foregroundStyle(.white.opacity(0.94))
        .position(x: width * BuddyView.Spot.cloud.x, y: height * BuddyView.Spot.cloud.y)
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}
