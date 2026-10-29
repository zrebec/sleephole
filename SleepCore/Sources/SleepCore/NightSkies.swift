import Foundation

/// The four night skies a mystery box can give (step 11b5d): effects drawn in code on the app's living sky, at night
/// only. The ids are persisted forever – the table below never changes, new skies get new ids.
public enum NightSkyEffect: String, CaseIterable, Sendable {
    case shootingStars, northernLights, catConstellation, comet
}

/// A shooting star in flight; x / y are fractions of the sky's width / height, `start` is in clock seconds.
public struct ShootingStarShot: Equatable, Sendable {
    public var start: Double
    public var duration: Double
    public var x0, y0: Double       // where the head starts
    public var dx, dy: Double       // the way it travels in total (left and down)

    /// The head at `progress` 0…1 (unit coordinates).
    public func head(at progress: Double) -> (x: Double, y: Double) { (x0 + dx * progress, y0 + dy * progress) }
}

/// The cat constellation: stars and the faint lines between them, in a 0…1 box (y down).
public struct Constellation: Sendable {
    public struct Star: Equatable, Sendable { public var x, y, size: Double }
    public var stars: [Star]
    public var lines: [(Int, Int)]
}

public enum NightSkies {
    /// `BoxCatalog.ids(.sky)` in order → the effect.
    public static let table: [(id: String, effect: NightSkyEffect)] = [
        ("sky-01", .shootingStars), ("sky-02", .northernLights), ("sky-03", .catConstellation), ("sky-04", .comet),
    ]

    /// The effect of a sky id; nil for an unknown id (or nil).
    public static func effect(forId id: String?) -> NightSkyEffect? { table.first { $0.id == id }?.effect }

    // MARK: shooting stars

    /// One slot = 9 s; each slot holds one star starting 0…3 s into it, so two stars are 6…12 s apart.
    public static let slotLength = 9.0

    /// The star of a slot – deterministic (SplitMix from the slot number).
    public static func shot(slot: Int) -> ShootingStarShot {
        var g = SeededGenerator(seed: UInt64(bitPattern: Int64(slot)) &+ 0x5EED_5EED)
        func r(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &g) }
        return ShootingStarShot(start: Double(slot) * slotLength + r(0...3), duration: r(0.8...1.2),
                                x0: r(0.45...0.95), y0: r(0.03...0.16), dx: -r(0.25...0.40), dy: r(0.05...0.09))
    }

    /// The star in flight at `time` and how far along it is (0…1); nil between two stars.
    public static func activeShot(at time: Double) -> (shot: ShootingStarShot, progress: Double)? {
        let s = shot(slot: Int((time / slotLength).rounded(.down)))
        let p = (time - s.start) / s.duration
        return p >= 0 && p <= 1 ? (s, p) : nil
    }

    /// The frozen frame (Reduce Motion, a paused timeline): slot 0's star, halfway.
    public static var stillTime: Double { let s = shot(slot: 0); return s.start + s.duration * 0.5 }

    // MARK: comet

    /// The comet crosses the sky in 6 minutes, right to left, then starts again.
    public static let cometPeriod = 360.0
    public static let cometStill = 0.45

    /// The head at `time` (clock seconds), unit coordinates; the tail points back the way it came (up and right).
    public static func cometHead(at time: Double) -> (x: Double, y: Double) {
        let f = time / cometPeriod - (time / cometPeriod).rounded(.down)
        return (1.2 - 1.4 * f, 0.07 + 0.12 * f)
    }

    // MARK: the Cat constellation

    /// A cube cat: two ears, a square head, a body, a curled tail; the two eyes are small, unjoined stars.
    public static let cat = Constellation(
        stars: [
            .init(x: 0.18, y: 0.02, size: 1.3), .init(x: 0.22, y: 0.22, size: 1.0), .init(x: 0.62, y: 0.22, size: 1.0),
            .init(x: 0.66, y: 0.02, size: 1.3), .init(x: 0.62, y: 0.50, size: 1.1), .init(x: 0.22, y: 0.50, size: 1.1),
            .init(x: 0.85, y: 0.55, size: 1.0), .init(x: 0.88, y: 0.92, size: 1.2), .init(x: 0.28, y: 0.92, size: 1.2),
            .init(x: 0.98, y: 0.74, size: 0.9), .init(x: 0.96, y: 0.52, size: 0.9), .init(x: 0.84, y: 0.42, size: 1.1),
            .init(x: 0.34, y: 0.35, size: 0.6), .init(x: 0.50, y: 0.35, size: 0.6),
        ],
        lines: [(0, 1), (1, 2), (2, 3), (2, 4), (4, 5), (5, 1), (4, 6), (6, 7), (7, 8), (8, 5), (7, 9), (9, 10), (10, 11)])
}
