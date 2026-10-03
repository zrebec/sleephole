import SleepCore
import SwiftUI

// Phase UI-2 (owner 2026-10-02: "more animations, splash effects, a WOW when a house is finished").
// Everything is drawn in code (Canvas + TimelineView); Reduce Motion gets calm, shorter versions.

/// "Go to sleep" / "Nap" tapped: the night closes in like an iris, stars burst out, the moon pops up, then it fades
/// into the night screen. ~2.6 s, calls `done` at the end.
struct GoodNightSplash: View {
    let nap: Bool
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    static let duration = Motion.t(2.6)

    private struct Star { let angle, speed, size, delay: Double }
    private static let stars: [Star] = {
        var rng = SeededGenerator(seed: 99)
        return (0..<46).map { _ in
            Star(angle: .random(in: 0...(2 * .pi), using: &rng), speed: .random(in: 120...420, using: &rng),
                 size: .random(in: 2...6, using: &rng), delay: .random(in: 0...0.35, using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start) / Motion.pace     // the choreography below is in unpaced seconds
            let fadeOut = max(0, min(1, (t - (2.6 - 0.5)) / 0.5))
            GeometryReader { g in
                let centre = CGPoint(x: g.size.width / 2, y: g.size.height * 0.45)
                let reach = hypot(g.size.width, g.size.height)
                let iris = reduceMotion ? 1 : ease(min(1, t / 0.55))
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.18),
                                                      Color(red: 0.12, green: 0.10, blue: 0.30)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: reach * iris * 1.1, height: reach * iris * 1.1)
                        .position(centre)
                    if !reduceMotion {
                        Canvas { gc, _ in
                            for s in Self.stars {
                                let age = t - 0.3 - s.delay
                                guard age > 0, age < 1.6 else { continue }
                                let d = s.speed * (1 - exp(-age * 2.2))
                                let p = CGPoint(x: centre.x + cos(s.angle) * d, y: centre.y + sin(s.angle) * d)
                                let a = 1 - age / 1.6
                                gc.fill(Sparkle.path(at: p, size: s.size * 2), with: .color(.white.opacity(a)))
                            }
                        }
                    }
                    VStack(spacing: 12) {
                        Text(verbatim: nap ? "😴" : "🌙")
                            .font(.system(size: 96))
                            .scaleEffect(reduceMotion ? 1 : pop(t - 0.35))
                            .rotationEffect(.degrees(reduceMotion ? 0 : sin(t * 3) * 6))
                        Text(nap ? L("Have a nice rest") : L("Good night"))
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                            .opacity(min(1, max(0, (t - 0.6) / 0.4)))
                        Text(verbatim: "z Z z")
                            .font(.title2.bold())
                            .foregroundStyle(.white.opacity(0.6))
                            .offset(x: 30, y: reduceMotion ? 0 : -10 * sin(t * 2.5))
                            .opacity(min(1, max(0, (t - 1.0) / 0.4)))
                    }
                    .position(centre)
                }
            }
            .opacity(1 - fadeOut)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { done() }                 // never in the way: a tap skips it
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            done()
        }
    }

    private func ease(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    /// 0 → overshoot → 1 (a springy pop) for x = seconds since the pop started.
    private func pop(_ x: Double) -> Double {
        x > 0 ? 1 - exp(-x * 6) * cos(x * 14) : 0
    }
}

/// A four-pointed twinkle star.
enum Sparkle {
    static func path(at p: CGPoint, size s: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: p.x, y: p.y - s))
        path.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: p)
        return path
    }
}

/// The WOW behind a finished building: slowly turning golden rays + a soft glow.
struct SunRays: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                        with: .radialGradient(Gradient(colors: [.yellow.opacity(0.45), .orange.opacity(0.12), .clear]),
                                              center: c, startRadius: 0, endRadius: r))
                let rays = 14
                let turn = reduceMotion ? 0 : t * 0.25 / Motion.pace
                for i in 0..<rays {
                    let a = turn + Double(i) / Double(rays) * 2 * .pi
                    var p = Path()
                    p.move(to: c)
                    p.addArc(center: c, radius: r, startAngle: .radians(a - 0.09), endAngle: .radians(a + 0.09), clockwise: false)
                    p.closeSubpath()
                    gc.fill(p, with: .radialGradient(Gradient(colors: [.yellow.opacity(0.35), .clear]),
                                                     center: c, startRadius: r * 0.15, endRadius: r))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A one-shot burst of colourful twinkles (+ a gentle ongoing shimmer), starting `delay` s after it appears.
struct SparkleBurst: View {
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private struct Bit { let angle, speed, size, spin: Double; let color: Color }
    private static let bits: [Bit] = {
        var rng = SeededGenerator(seed: 5)
        let colors: [Color] = [.yellow, .orange, .pink, .white, .mint, .cyan]
        return (0..<56).map { _ in
            Bit(angle: .random(in: 0...(2 * .pi), using: &rng), speed: .random(in: 90...260, using: &rng),
                size: .random(in: 4...10, using: &rng), spin: .random(in: -4...4, using: &rng),
                color: colors.randomElement(using: &rng)!)
        }
    }()

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { ctx in
                let t = (ctx.date.timeIntervalSince(start) - delay) / Motion.pace
                Canvas { gc, size in
                    let c = CGPoint(x: size.width / 2, y: size.height * 0.55)
                    guard t > 0 else { return }
                    for b in Self.bits where t < 2.2 {
                        let d = b.speed * (1 - exp(-t * 2.5))
                        let p = CGPoint(x: c.x + cos(b.angle) * d, y: c.y + sin(b.angle) * d * 0.8 + 40 * t * t)
                        gc.fill(Sparkle.path(at: p, size: b.size * (1 - t / 2.4)), with: .color(b.color.opacity(1 - t / 2.2)))
                    }
                    for (i, b) in Self.bits.prefix(22).enumerated() {        // shimmer that stays
                        let a = (1 + sin(t * 3 + Double(i))) / 2
                        let p = CGPoint(x: c.x + cos(b.angle) * 120, y: c.y + sin(b.angle) * 90)
                        gc.fill(Sparkle.path(at: p, size: 5 * a), with: .color(.yellow.opacity(0.7 * a)))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Drops in from above and lands with a bounce (the finished building).
    func dropIn(delay: Double = 0.1) -> some View { modifier(DropIn(delay: delay)) }
}

private struct DropIn: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    func body(content: Content) -> some View {
        content
            .offset(y: landed || reduceMotion ? 0 : -140)
            .scaleEffect(landed || reduceMotion ? 1 : 0.5)
            .opacity(landed || reduceMotion ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: Motion.t(0.7), bounce: 0.45).delay(Motion.t(delay))) { landed = true }
            }
    }
}

/// Dust kicked up when the finished building lands: soft puffs rolling out to both sides along the ground.
struct DustPuff: View {
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private struct Puff { let dir, speed, size, rise: Double }
    private static let puffs: [Puff] = {
        var rng = SeededGenerator(seed: 21)
        return (0..<18).map { i in
            Puff(dir: i % 2 == 0 ? 1 : -1, speed: .random(in: 40...140, using: &rng),
                 size: .random(in: 14...30, using: &rng), rise: .random(in: 4...26, using: &rng))
        }
    }()

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { ctx in
                let t = (ctx.date.timeIntervalSince(start) - delay) / Motion.pace
                Canvas { gc, size in
                    guard t > 0, t < 1.6 else { return }
                    let ground = CGPoint(x: size.width / 2, y: size.height * 0.80)
                    var g = gc
                    g.addFilter(.blur(radius: 4))
                    for p in Self.puffs {
                        let d = p.speed * (1 - exp(-t * 2.4))
                        let r = p.size * (0.6 + t * 0.9)
                        let c = CGPoint(x: ground.x + p.dir * (30 + d), y: ground.y - p.rise * t)
                        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.6, width: 2 * r, height: 1.2 * r)),
                               with: .color(Color(red: 0.78, green: 0.70, blue: 0.58).opacity(0.55 * (1 - t / 1.6))))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
