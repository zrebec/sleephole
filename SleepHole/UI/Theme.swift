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
// glass cards, the Today island. The sky follows the owner's schedule (`Sky.state(at:schedule:calendar:)`) – or, once
// a city is set in Settings, the real sun and moon above it (`Sky.state(at:place:)`). Drawn in code – sharp on any
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

/// The real sky above a city, computed at most once a minute (the view asks 20× a second and one call searches the
/// rising and setting – ≈ 60 µs).
@MainActor
enum RealSky {
    private static var cache: (minute: Int, place: GeoPoint, state: SkyState)?
    /// How many times the real state was actually computed (tests).
    private(set) static var computations = 0

    static func state(at date: Date, place: GeoPoint) -> SkyState {
        let minute = Int((date.timeIntervalSince1970 / 60).rounded(.down))
        if let c = cache, c.minute == minute, c.place == place { return c.state }
        let state = Sky.state(at: Date(timeIntervalSince1970: Double(minute) * 60), place: place)
        cache = (minute, place, state)
        computations += 1
        return state
    }

    static func reset() { cache = nil }
}

/// Dev aid for screenshots: `-skyArc 0.3`, `-skyBody sun|moon|none`, `-skyMoon 0.5` force the arc, the body and the
/// moon's illuminated fraction of the drawn state (the colours still follow the time – pin it with `-skyTime`).
struct SkyOverrides: Equatable {
    var arc: Double?
    var body: SkyBody?
    var moon: Double?

    init(arc: Double? = nil, body: SkyBody? = nil, moon: Double? = nil) {
        self.arc = arc
        self.body = body
        self.moon = moon
    }

    init(args: [String]) {
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        arc = value("-skyArc").flatMap(Double.init).map { min(1, max(0, $0)) }
        body = value("-skyBody").flatMap { SkyBody(rawValue: $0) }
        moon = value("-skyMoon").flatMap(Double.init).map { min(1, max(0, $0)) }
    }

    static let launch = SkyOverrides(args: ProcessInfo.processInfo.arguments)

    func apply(to s: SkyState) -> SkyState {
        guard arc != nil || body != nil || moon != nil else { return s }
        var look = s.moon
        if let moon { look = MoonLook(illuminated: moon, litOnRight: s.moon?.litOnRight ?? true) }
        return SkyState(phase: s.phase, daylight: s.daylight, glow: s.glow, arc: arc ?? s.arc,
                        body: body ?? s.body, moon: look)
    }
}

/// The living sky: gradient that breathes slowly, sun or moon on its arc, twinkling stars, drifting clouds.
/// Animates only while visible and the app is active; with Reduce Motion it is a still picture.
/// `semicircle` (Today): with a city set, the body travels a true half circle with a faint dotted track.
/// `showsBody` false (Stats, Settings – B7): gradient, stars and clouds only, so the sun never sits behind a title.
struct LivingSky: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    let semicircle: Bool
    let showsBody: Bool

    init(semicircle: Bool = false, showsBody: Bool = true) {
        self.semicircle = semicircle
        self.showsBody = showsBody
    }

    /// The sky behind the Stats and Settings tabs: no sun or moon (it would shine through the large title).
    static var backdrop: LivingSky { LivingSky(showsBody: false) }

    /// Dev aid: `-skyTime 21:45` pins the sky's time of day (screenshots).
    static let pinnedTime: (Int, Int)? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-skyTime"), a.indices.contains(i + 1) else { return nil }
        let p = a[i + 1].split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }()

    /// The sky now: the real one above the city when there is one (cached per minute), else the schedule's.
    static func state(at date: Date, settings: AppSettings, overrides: SkyOverrides = .launch) -> SkyState {
        var t = date
        if let (h, m) = pinnedTime {
            t = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
        }
        let state = settings.city.map { RealSky.state(at: t, place: $0.place) }
            ?? Sky.state(at: t, schedule: settings.schedule, calendar: .current)
        return overrides.apply(to: state)
    }

    var body: some View {
        let paused = !visible || scenePhase != .active || reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: paused)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let sky = Self.state(at: ctx.date, settings: model.settings)
            let palette = SkyPalette(sky, dark: scheme == .dark)
            let round = semicircle && model.settings.city != nil
            ZStack {
                gradient(palette, t: t)
                Canvas { gc, size in
                    SkyDrawing.stars(&gc, size: size, opacity: palette.starOpacity, t: t)
                    if round && showsBody { SkyDrawing.track(&gc, size: size, dark: scheme == .dark, daylight: sky.daylight) }
                    if showsBody { SkyDrawing.sunOrMoon(&gc, size: size, sky: sky, semicircle: round) }
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

    // MARK: the body on its way

    /// Today's semicircle spans the screen from left to right (owner 2026-10-04: the sun in the middle means noon –
    /// never shrink or move it): centre x = the middle of the screen, centre y = 310 pt from the top, radius 150 pt
    /// (less on a narrow screen, so the ends stay 44 pt from the edges).
    static let semicircleCentreY: CGFloat = 310
    static func semicircle(width: CGFloat) -> (centre: CGPoint, radius: CGFloat) {
        (CGPoint(x: width / 2, y: semicircleCentreY), min(150, width / 2 - 44))
    }

    /// Rises at the left end (arc 0), is at the top at 0.5 and sets at the right end (arc 1).
    static func semicirclePoint(arc: Double, width: CGFloat) -> CGPoint {
        let (c, r) = semicircle(width: width)
        return CGPoint(x: c.x - r * cos(.pi * arc), y: c.y - r * sin(.pi * arc))
    }

    /// Today's low flat arc (no city) and the Town tab's: starts right of the large title (140 pt from the left edge,
    /// B7) and ends 40 pt from the right edge; stays above most of the content.
    static let flatMargins = (left: CGFloat(140), right: CGFloat(40))
    static func flatPoint(arc: Double, size: CGSize) -> CGPoint {
        let (left, right) = flatMargins
        return CGPoint(x: left + arc * (size.width - left - right), y: size.height * (0.22 - 0.13 * sin(arc * .pi)))
    }

    /// The faint dotted half circle the body travels on Today (also a rough clock).
    static func track(_ gc: inout GraphicsContext, size: CGSize, dark: Bool, daylight: Double) {
        var path = Path()
        for i in 0...72 {
            let p = semicirclePoint(arc: Double(i) / 72, width: size.width)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        // white on a dark or night sky; on the light daytime sky a deep blue stays visible (and faint)
        let color: Color = dark || daylight < 0.5 ? .white.opacity(0.22 + (dark ? 0 : 0.12))
            : Color(red: 0.16, green: 0.28, blue: 0.55).opacity(0.26)
        gc.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [0.1, 8]))
    }

    /// The sun from dawn to dusk or the moon (with its real phase when the sky knows it), nothing when both are
    /// down; they travel a low flat arc – or Today's semicircle – from left to right.
    static func sunOrMoon(_ gc: inout GraphicsContext, size: CGSize, sky: SkyState, semicircle: Bool = false) {
        let p = semicircle ? semicirclePoint(arc: sky.arc, width: size.width) : flatPoint(arc: sky.arc, size: size)
        switch sky.body {
        case .none: return
        case .moon: moon(&gc, at: p, look: sky.moon)
        case .sun:
            let (x, y) = (p.x, p.y)
            let r = 26.0, halo = 90.0
            let warm = Color(red: 1, green: 0.78 - 0.18 * sky.glow, blue: 0.40 - 0.15 * sky.glow)
            gc.fill(Path(ellipseIn: CGRect(x: x - halo, y: y - halo, width: 2 * halo, height: 2 * halo)),
                    with: .radialGradient(Gradient(colors: [warm.opacity(0.45), warm.opacity(0)]),
                                          center: CGPoint(x: x, y: y), startRadius: r * 0.6, endRadius: halo))
            gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(warm))
        }
    }

    static let moonColor = Color(red: 1, green: 0.96, blue: 0.82)
    static let moonRadius = 22.0

    /// `look` nil = the old schedule sky's decorative crescent.
    private static func moon(_ gc: inout GraphicsContext, at p: CGPoint, look: MoonLook?) {
        let r = moonRadius
        let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        var glowing = gc
        glowing.addFilter(.shadow(color: .white.opacity(0.5), radius: 18))
        guard let look else {
            let bite = Path(ellipseIn: CGRect(x: p.x - r + 11, y: p.y - r - 6, width: 2 * r, height: 2 * r))
            glowing.fill(disc.subtracting(bite), with: .color(moonColor))
            return
        }
        gc.fill(disc, with: .color(moonColor.opacity(0.12)))           // the dark part hints the round shape
        guard look.illuminated >= 0.03 else { return }
        glowing.fill(litPart(centre: p, radius: r, illuminated: look.illuminated, litOnRight: look.litOnRight),
                     with: .color(moonColor))
    }

    /// The lit part of the moon: the half disc on the lit side, minus (crescent, < 0.5) or plus (gibbous, > 0.5) a half
    /// ellipse of x-radius r·|1 − 2·illuminated| – nothing at 0, the half disc at 0.5, the whole disc at 1.
    static func litPart(centre c: CGPoint, radius r: Double, illuminated f: Double, litOnRight: Bool) -> Path {
        let side = litOnRight ? 1.0 : -1.0
        let a = r * abs(1 - 2 * f)
        let bulge = f < 0.5 ? 1.0 : -1.0              // the terminator bows toward the lit side (crescent) or away
        let n = 48
        var path = Path()
        for i in 0...n {                              // the outer limb on the lit side, top → bottom
            let t = -Double.pi / 2 + Double.pi * Double(i) / Double(n)
            let q = CGPoint(x: c.x + side * r * cos(t), y: c.y + r * sin(t))
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        for i in 0...n {                              // the terminator, bottom → top
            let t = Double.pi / 2 - Double.pi * Double(i) / Double(n)
            path.addLine(to: CGPoint(x: c.x + side * bulge * a * cos(t), y: c.y + r * sin(t)))
        }
        path.closeSubpath()
        return path
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
    /// The living sky behind a tab, without the sun or moon (B7: never behind a title); scroll views and forms show
    /// it through.
    func skyBackground() -> some View {
        scrollContentBackground(.hidden).background { LivingSky.backdrop }
    }

    /// A Liquid Glass card on iOS 26, frosted material before.
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(GlassCard(shape: RoundedRectangle(cornerRadius: cornerRadius), tint: tint))
    }

    func glassCapsule(tint: Color? = nil) -> some View {
        modifier(GlassCard(shape: Capsule(), tint: tint))
    }

    /// Big action buttons: glass on iOS 26, bordered before. Disabled ones get a calm solid look of their own (B7) –
    /// apply `.disabled(…)` AFTER this modifier, so it can read the environment.
    func glassButton(prominent: Bool) -> some View { modifier(GlassButton(prominent: prominent)) }

    /// A caption inside a card or capsule: the primary colour at 72 % – `.secondary` is too weak on a light card (B7).
    func cardCaption() -> some View { foregroundStyle(Color.cardCaption) }

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

/// What sits under every glass card and capsule (B7, owner 2026-10-03: "on the light sky the transparency bothers quite
/// a lot"): a calm backing, so the text is equally readable over the day sky, the night sky and a cloud. Fully opaque
/// with Reduce Transparency (or the dev launch argument `-solidCards`, for screenshots).
enum CardBacking {
    static func solidRequested(_ args: [String]) -> Bool { args.contains("-solidCards") }
    static let solidLaunch = solidRequested(ProcessInfo.processInfo.arguments)
    /// Fully opaque: the system's Reduce Transparency, or the dev launch argument `-solidCards`.
    static func isSolid(reduceTransparency: Bool, launchSolid: Bool = solidLaunch) -> Bool {
        reduceTransparency || launchSolid
    }
    static let lightOpacity = 0.78
    static let darkOpacity = 0.72
    /// A tint laid over the backing (streak, coins, tinted cards).
    static let tintOpacity = 0.25
    static let darkColor = Color(red: 0.07, green: 0.09, blue: 0.18)

    static func color(dark: Bool) -> Color { dark ? darkColor : .white }
    static func opacity(dark: Bool, solid: Bool) -> Double { solid ? 1 : dark ? darkOpacity : lightOpacity }
    /// The thin edge line of the backing (the glass draws its own highlight on iOS 26).
    static func edge(dark: Bool) -> Color { .white.opacity(dark ? 0.12 : 0.35) }
}

extension Color {
    /// Captions inside cards.
    static let cardCaption = Color.primary.opacity(0.72)

    /// Coloured text on a light card or sky (B7): the system yellow / green / orange are only 1.3–2.5 : 1 on white, so
    /// light mode gets deeper shades; dark mode keeps the system colours.
    static let readableYellow = adaptive(light: (0.55, 0.37, 0.0), dark: .systemYellow)
    static let readableGreen = adaptive(light: (0.0, 0.50, 0.20), dark: .systemGreen)
    static let readableOrange = adaptive(light: (0.74, 0.34, 0.0), dark: .systemOrange)

    private static func adaptive(light: (Double, Double, Double), dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark
            : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1) })
    }
}

private struct GlassCard<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let solid = CardBacking.isSolid(reduceTransparency: reduceTransparency)
        let backing = ZStack {
            shape.fill(CardBacking.color(dark: dark).opacity(CardBacking.opacity(dark: dark, solid: solid)))
            if let tint { shape.fill(tint.opacity(CardBacking.tintOpacity)) }
        }
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape).background { backing }
        } else {
            content.background { backing }.overlay { shape.strokeBorder(CardBacking.edge(dark: dark), lineWidth: 1) }
        }
    }
}

/// Big buttons (B7): the system's glass / bordered look while enabled; a plain solid fill and a clearly readable label
/// while disabled – no glass on glass, and no system dimming (a custom style is not dimmed).
private struct GlassButton: ViewModifier {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if !isEnabled {
            content.buttonStyle(CalmDisabledButtonStyle())
        } else if #available(iOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}

/// The disabled big button: black at 7 % (light) / white at 10 % (dark) over the card, the label `.primary` at 55 %.
struct CalmDisabledButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.controlSize) private var controlSize

    static let labelOpacity = 0.55
    static func fill(dark: Bool) -> Color { dark ? .white.opacity(0.10) : .black.opacity(0.07) }

    func makeBody(configuration: Configuration) -> some View {
        let fill = Self.fill(dark: scheme == .dark)
        let large = controlSize == .large || controlSize == .extraLarge       // same size as the glass button
        configuration.label
            .foregroundStyle(Color.primary.opacity(Self.labelOpacity))
            .padding(.horizontal, large ? 16 : 14).padding(.vertical, large ? 15.5 : 7)
            .background {
                if #available(iOS 26.0, *) { Capsule().fill(fill) } else { RoundedRectangle(cornerRadius: 12).fill(fill) }
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
