import SwiftUI
import SleepCore

/// The four night skies from mystery boxes (step 11b5d), drawn on `LivingSky`'s canvas right after the stars. All of
/// them are scaled by the stars' opacity, so they appear at dusk and are gone by day. `time` is the effect clock in
/// unpaced seconds; `still` is the frozen frame for Reduce Motion / a paused timeline.
enum NightSkyDrawing {
    /// Dev aid: `-skyClock 12.5` pins the effect clock, `-skyClock still` shows the frozen frame (screenshots).
    static let pinnedClock: Double? = {
        guard let v = DevArgs.value(after: "-skyClock") else { return nil }
        return v == "still" ? Double.infinity : Double(v)
    }()

    static func draw(_ effect: NightSkyEffect, _ gc: inout GraphicsContext, size: CGSize, opacity: Double, t: Double, still: Bool) {
        guard opacity > 0.01 else { return }
        let frozen = still || pinnedClock == .infinity
        let time = frozen ? 0 : (pinnedClock ?? t / Motion.pace)
        switch effect {
        case .shootingStars: shootingStar(&gc, size: size, opacity: opacity, time: frozen ? NightSkies.stillTime : time)
        case .northernLights: aurora(&gc, size: size, opacity: opacity, time: time)
        case .catConstellation: catConstellation(&gc, size: size, opacity: opacity, time: time)
        case .comet: comet(&gc, size: size, opacity: opacity, time: frozen ? NightSkies.cometStill * NightSkies.cometPeriod : time)
        }
    }

    /// A bright head with a fading tail; the star fades in and out over its flight.
    static func shootingStar(_ gc: inout GraphicsContext, size: CGSize, opacity: Double, time: Double) {
        guard let (shot, p) = NightSkies.activeShot(at: time) else { return }
        let fade = sin(p * .pi)                                          // 0 → 1 → 0
        let h = shot.head(at: p)
        let head = CGPoint(x: h.x * size.width, y: h.y * size.height)
        let tailEnd = shot.head(at: max(0, p - 0.5))
        let tail = CGPoint(x: tailEnd.x * size.width, y: tailEnd.y * size.height)
        let a = opacity * fade
        var path = Path()
        path.move(to: head)
        path.addLine(to: tail)
        gc.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(1.0 * a), .white.opacity(0)]),
                                              startPoint: head, endPoint: tail),
                  style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        var glow = gc
        glow.addFilter(.shadow(color: .white.opacity(0.9 * a), radius: 8))
        glow.fill(Path(ellipseIn: CGRect(x: head.x - 2.2, y: head.y - 2.2, width: 4.4, height: 4.4)), with: .color(.white.opacity(a)))
    }

    /// Soft green / teal / violet curtains near the top, waving slowly; a light blur keeps them airy.
    static func aurora(_ gc: inout GraphicsContext, size: CGSize, opacity: Double, time: Double) {
        let curtains: [(base: Double, hue: Color, speed: Double, phase: Double, amp: Double)] = [
            (0.05, Color(red: 0.25, green: 0.95, blue: 0.55), 0.11, 0, 20),
            (0.09, Color(red: 0.15, green: 0.85, blue: 0.80), 0.08, 2.1, 24),
            (0.02, Color(red: 0.62, green: 0.45, blue: 0.95), 0.06, 4.0, 16),
        ]
        var layer = gc
        layer.addFilter(.blur(radius: 10))
        for c in curtains {
            let baseY = c.base * size.height
            let height = size.height * 0.11
            var top: [CGPoint] = []
            let n = 14
            for i in 0...n {
                let x = size.width * Double(i) / Double(n)
                let y = baseY + c.amp * sin(x / 90 + time * c.speed + c.phase) + 10 * sin(x / 37 - time * c.speed * 1.7)
                top.append(CGPoint(x: x, y: y))
            }
            var path = Path()
            path.move(to: top[0])
            for p in top.dropFirst() { path.addLine(to: p) }
            path.addLine(to: CGPoint(x: size.width, y: baseY + height))
            path.addLine(to: CGPoint(x: 0, y: baseY + height))
            path.closeSubpath()
            let shimmer = 0.85 + 0.15 * sin(time * 0.2 + c.phase)
            layer.fill(path, with: .linearGradient(
                Gradient(colors: [c.hue.opacity(0.28 * opacity * shimmer), c.hue.opacity(0)]),
                startPoint: CGPoint(x: 0, y: baseY - c.amp), endPoint: CGPoint(x: 0, y: baseY + height)))
        }
    }

    /// Where the cat constellation sits: the upper right, above the semicircle's top (y 160 pt), right of the large
    /// title, 92 pt wide and 78 pt high, 10 pt from the right edge (clear of the Town header card).
    static func catRect(in size: CGSize) -> CGRect {
        let w = 92.0, h = 78.0
        return CGRect(x: size.width - w - 10, y: 54, width: w, height: h)
    }

    static func catConstellation(_ gc: inout GraphicsContext, size: CGSize, opacity: Double, time: Double) {
        let c = NightSkies.cat, r = catRect(in: size)
        func point(_ s: Constellation.Star) -> CGPoint { CGPoint(x: r.minX + s.x * r.width, y: r.minY + s.y * r.height) }
        var lines = Path()
        for (a, b) in c.lines {
            lines.move(to: point(c.stars[a]))
            lines.addLine(to: point(c.stars[b]))
        }
        gc.stroke(lines, with: .color(.white.opacity(0.22 * opacity)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        var glow = gc
        glow.addFilter(.shadow(color: .white.opacity(0.7 * opacity), radius: 4))
        for (i, s) in c.stars.enumerated() {
            let twinkle = 0.75 + 0.25 * sin(time * 0.9 + Double(i) * 1.7)
            let d = 2.6 * s.size
            let p = point(s)
            glow.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                      with: .color(.white.opacity(0.95 * opacity * twinkle)))
        }
    }

    /// A glowing head and a long soft tail, drifting right to left over six minutes.
    static func comet(_ gc: inout GraphicsContext, size: CGSize, opacity: Double, time: Double) {
        let h = NightSkies.cometHead(at: time)
        let head = CGPoint(x: h.x * size.width, y: h.y * size.height)
        let len = 190.0
        let dir = CGVector(dx: 0.96, dy: -0.28)                          // the tail trails up and to the right
        let end = CGPoint(x: head.x + dir.dx * len, y: head.y + dir.dy * len)
        let n = CGVector(dx: -dir.dy, dy: dir.dx)                        // the tail's normal
        var tail = Path()
        tail.move(to: CGPoint(x: head.x + n.dx * 3.5, y: head.y + n.dy * 3.5))
        tail.addLine(to: end)
        tail.addLine(to: CGPoint(x: head.x - n.dx * 3.5, y: head.y - n.dy * 3.5))
        tail.closeSubpath()
        var soft = gc
        soft.addFilter(.blur(radius: 2.5))
        soft.fill(tail, with: .linearGradient(Gradient(colors: [Color(red: 0.75, green: 0.92, blue: 1).opacity(0.7 * opacity),
                                                                Color(red: 0.75, green: 0.92, blue: 1).opacity(0)]),
                                              startPoint: head, endPoint: end))
        let halo = 26.0
        gc.fill(Path(ellipseIn: CGRect(x: head.x - halo, y: head.y - halo, width: 2 * halo, height: 2 * halo)),
                with: .radialGradient(Gradient(colors: [Color(red: 0.8, green: 0.95, blue: 1).opacity(0.5 * opacity), .clear]),
                                      center: head, startRadius: 1, endRadius: halo))
        gc.fill(Path(ellipseIn: CGRect(x: head.x - 3.2, y: head.y - 3.2, width: 6.4, height: 6.4)), with: .color(.white.opacity(opacity)))
    }
}
