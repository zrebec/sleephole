import SleepCore
import SwiftUI

/// One knob for every decorative animation (owner 2026-10-02: "slow all animations down; the app must stay fully
/// responsive – no animation ever has to finish"). Durations and delays are multiplied, speeds divided.
enum Motion {
    static let pace = 1.6
    /// When a dropped-in building touches the ground (dust + sparkles start then).
    static let landing = (0.15 + 0.32) * pace

    /// Seconds → paced seconds.
    static func t(_ seconds: Double) -> Double { seconds * pace }
}

// Phase UI (owner 2026-10-02: "interesting features, very plain design"): a living sky behind the tabs, content on
// glass cards, the Today island. The sky follows the owner's schedule (`Sky.state`), drawn in code – sharp on any
// display, no image assets.

/// Sky colours for one moment: top / horizon, interpolated night ↔ day, warmed by the dawn/dusk glow.
struct SkyPalette {
    let top: Color
    let middle: Color
    let horizon: Color
    let cloud: Color
    let cloudOpacity: Double
    let starOpacity: Double

    private typealias RGB = (Double, Double, Double)

    init(_ s: SkyState, dark: Bool) {
        // light mode stays light even at night (black text must stay readable); dark mode stays deep
        let night: (RGB, RGB) = dark ? ((0.04, 0.05, 0.14), (0.11, 0.11, 0.28)) : ((0.40, 0.44, 0.74), (0.66, 0.66, 0.88))
        let day: (RGB, RGB) = dark ? ((0.08, 0.20, 0.42), (0.20, 0.34, 0.56)) : ((0.42, 0.68, 0.95), (0.80, 0.91, 0.99))
        let glow: (RGB, RGB) = dark ? ((0.30, 0.16, 0.34), (0.72, 0.38, 0.30)) : ((0.66, 0.58, 0.86), (1.00, 0.76, 0.58))
        func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t) }
        func color(_ c: RGB) -> Color { Color(red: c.0, green: c.1, blue: c.2) }
        let top = mix(mix(night.0, day.0, s.daylight), glow.0, s.glow * 0.45)
        let horizon = mix(mix(night.1, day.1, s.daylight), glow.1, s.glow * 0.85)
        self.top = color(top)
        self.middle = color(mix(top, horizon, 0.55))
        self.horizon = color(horizon)
        cloud = color(mix(dark ? (0.55, 0.60, 0.80) : (0.92, 0.93, 1.0), (1, 1, 1), s.daylight))
        cloudOpacity = dark ? 0.05 + 0.15 * s.daylight : 0.25 + 0.5 * s.daylight
        starOpacity = 1 - s.daylight
    }
}

/// The living sky: gradient that breathes slowly, sun or moon on its arc, twinkling stars, drifting clouds.
/// Animates only while visible and the app is active; with Reduce Motion it is a still picture.
struct LivingSky: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    /// Dev aid: `-skyTime 21:45` pins the sky's time of day (screenshots).
    static let pinnedTime: (Int, Int)? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-skyTime"), a.indices.contains(i + 1) else { return nil }
        let p = a[i + 1].split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }()

    static func state(at date: Date, schedule: Schedule) -> SkyState {
        var t = date
        if let (h, m) = pinnedTime {
            t = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
        }
        return Sky.state(at: t, schedule: schedule, calendar: .current)
    }

    var body: some View {
        let paused = !visible || scenePhase != .active || reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: paused)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let sky = Self.state(at: ctx.date, schedule: model.settings.schedule)
            let palette = SkyPalette(sky, dark: scheme == .dark)
            ZStack {
                gradient(palette, t: t)
                Canvas { gc, size in
                    SkyDrawing.stars(&gc, size: size, opacity: palette.starOpacity, t: t)
                    SkyDrawing.sunOrMoon(&gc, size: size, sky: sky)
                    SkyDrawing.clouds(&gc, size: size, palette: palette, t: t)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    private func gradient(_ p: SkyPalette, t: Double) -> some View {
        // the middle row sways a little – the sky "breathes"
        let s = t / Motion.pace
        let w = Float(sin(s * 0.21)) * 0.06, v = Float(cos(s * 0.17)) * 0.05
        return MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5 + v], [0.5 + w, 0.48 - v], [1, 0.5 - v],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: [
            p.top, p.top, p.top,
            p.middle, p.middle, p.middle,
            p.horizon, p.horizon, p.horizon,
        ])
    }
}

enum SkyDrawing {
    private struct Star { let x, y, size, phase: Double }
    private static let stars: [Star] = {
        var rng = SeededGenerator(seed: 42)
        return (0..<70).map { _ in
            Star(x: .random(in: 0...1, using: &rng), y: .random(in: 0...0.7, using: &rng),
                 size: .random(in: 1...2.4, using: &rng), phase: .random(in: 0...(2 * .pi), using: &rng))
        }
    }()

    private struct Cloud { let y, speed, scale, offset: Double; let puffs: [(dx: Double, dy: Double, r: Double)] }
    private static let clouds: [Cloud] = {
        var rng = SeededGenerator(seed: 7)
        func r(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
        var result: [Cloud] = []
        for i in 0..<5 {
            var puffs: [(dx: Double, dy: Double, r: Double)] = []
            for k in 0..<Int.random(in: 4...6, using: &rng) {
                let dx = Double(k) * 26 + r(-6...6)
                puffs.append((dx: dx, dy: r(-14...4), r: r(18...30)))
            }
            let y = 0.08 + Double(i) * 0.13 + r(-0.03...0.03)
            result.append(Cloud(y: y, speed: r(3...9), scale: r(0.6...1.2), offset: r(0...1), puffs: puffs))
        }
        return result
    }()

    static func stars(_ gc: inout GraphicsContext, size: CGSize, opacity: Double, t: Double) {
        guard opacity > 0.01 else { return }
        for s in stars {
            let a = opacity * (0.3 + 0.5 * (1 + sin(t / Motion.pace * 0.8 + s.phase)) / 2)
            let r = CGRect(x: s.x * size.width, y: s.y * size.height, width: s.size, height: s.size)
            gc.fill(Path(ellipseIn: r), with: .color(.white.opacity(a)))
        }
    }

    /// The sun from dawn to dusk, the moon at night; both travel a low arc from left to right.
    static func sunOrMoon(_ gc: inout GraphicsContext, size: CGSize, sky: SkyState) {
        let x = 40 + sky.arc * (size.width - 80)
        let y = size.height * (0.22 - 0.13 * sin(sky.arc * .pi))     // stays above most of the content
        if sky.phase == .night {
            let r = 22.0
            var moon = gc
            moon.addFilter(.shadow(color: .white.opacity(0.5), radius: 18))
            let disc = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            let bite = Path(ellipseIn: CGRect(x: x - r + 11, y: y - r - 6, width: 2 * r, height: 2 * r))
            moon.fill(disc.subtracting(bite), with: .color(Color(red: 1, green: 0.96, blue: 0.82)))
        } else {
            let r = 26.0, halo = 90.0
            let warm = Color(red: 1, green: 0.78 - 0.18 * sky.glow, blue: 0.40 - 0.15 * sky.glow)
            gc.fill(Path(ellipseIn: CGRect(x: x - halo, y: y - halo, width: 2 * halo, height: 2 * halo)),
                    with: .radialGradient(Gradient(colors: [warm.opacity(0.45), warm.opacity(0)]),
                                          center: CGPoint(x: x, y: y), startRadius: r * 0.6, endRadius: halo))
            gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(warm))
        }
    }

    static func clouds(_ gc: inout GraphicsContext, size: CGSize, palette: SkyPalette, t: Double) {
        let span = size.width + 260
        for c in clouds {
            let x = (c.offset * span + t / Motion.pace * c.speed).truncatingRemainder(dividingBy: span) - 180
            var path = Path()
            for p in c.puffs {
                let r = p.r * c.scale
                path.addEllipse(in: CGRect(x: x + p.dx * c.scale - r, y: c.y * size.height + p.dy * c.scale - r,
                                           width: 2 * r, height: 2 * r * 0.8))
            }
            gc.fill(path, with: .color(palette.cloud.opacity(palette.cloudOpacity)))
        }
    }
}

extension View {
    /// The living sky behind a tab; scroll views and forms show it through.
    func skyBackground() -> some View {
        scrollContentBackground(.hidden).background { LivingSky() }
    }

    /// A Liquid Glass card on iOS 26, frosted material before.
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(GlassCard(shape: RoundedRectangle(cornerRadius: cornerRadius), tint: tint))
    }

    func glassCapsule(tint: Color? = nil) -> some View {
        modifier(GlassCard(shape: Capsule(), tint: tint))
    }

    /// Big action buttons: glass on iOS 26, bordered before.
    @ViewBuilder
    func glassButton(prominent: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// Fades + slides in the first time it appears, `delay` seconds late (staggered cards).
    func appearIn(delay: Double) -> some View { modifier(AppearIn(delay: delay)) }

    /// Pops in with a bounce (the coins on the result screen).
    func popIn(delay: Double) -> some View { modifier(PopIn(delay: delay)) }
}

private struct PopIn: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.2)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: Motion.t(0.6), bounce: 0.55).delay(Motion.t(delay))) { shown = true }
            }
    }
}

private struct GlassCard<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(tint.map { .regular.tint($0.opacity(0.35)) } ?? .regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .background((tint ?? .clear).opacity(0.15), in: shape)
        }
    }
}

private struct AppearIn: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(duration: Motion.t(0.55), bounce: 0.25).delay(Motion.t(delay))) { shown = true }
            }
    }
}

/// The brown soil under a floating island: the left and right faces below the ground diamond's lower edges.
enum IslandEdge {
    static let leftSoil = Color(red: 0.55, green: 0.38, blue: 0.24)
    static let rightSoil = Color(red: 0.42, green: 0.28, blue: 0.18)
    static let meadow = Color(red: 0.45, green: 0.70, blue: 0.36)

    /// Points in a y-DOWN coordinate space; `depth` is how far the soil hangs.
    static func faces(left: CGPoint, bottom: CGPoint, right: CGPoint, depth: CGFloat) -> (Path, Path) {
        var l = Path(), r = Path()
        l.addLines([left, bottom, CGPoint(x: bottom.x, y: bottom.y + depth), CGPoint(x: left.x, y: left.y + depth * 0.55)])
        l.closeSubpath()
        r.addLines([bottom, right, CGPoint(x: right.x, y: right.y + depth * 0.55), CGPoint(x: bottom.x, y: bottom.y + depth)])
        r.closeSubpath()
        return (l, r)
    }
}
