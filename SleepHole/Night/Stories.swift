import Foundation
import SleepCore

/// Sound stories for falling asleep (owner 2026-09-30): like listening to someone play a survival game – the
/// axe, the pickaxe, footsteps, the first cave – and imagining what happens. A quiet bed loop plays all the time
/// (`bed_<world>.caf`); on top of it `StoryTeller` invents random scenes from the Kenney CC0 samples
/// (`st_<group>_<n>.caf`, made by tools/audio/make_stories.py), so no two nights sound the same.
enum StoryWorld: String, CaseIterable, Sendable {
    case forest, cave, workshop
}

/// One sound of a scene.
struct StoryEvent: Equatable, Sendable {
    /// Seconds from the start of the scene.
    var at: TimeInterval
    /// "st_chop_2.caf"
    var sample: String
    /// 0…1 (distance of the "person")
    var volume: Float
    /// -1 (left) … 1 (right)
    var pan: Float
}

struct StoryScene: Sendable {
    var name: String
    var events: [StoryEvent]
    /// Quiet time after the last sound before the next scene begins.
    var pause: TimeInterval
    var length: TimeInterval { (events.map(\.at).max() ?? 0) + pause }
}

struct StoryTeller: Sendable {
    /// Samples per group, as written by tools/audio/make_stories.py.
    static let samples: [String: Int] = [
        "mine": 5, "chop": 6, "log": 10, "plank": 5, "anvil": 5, "grass": 5, "wood": 5, "stone": 5, "snow": 5,
        "drip": 4, "rock": 9, "drag": 7, "pickup": 6, "creak": 3, "door": 6, "page": 3, "cloth": 6, "pot": 3,
        "tool": 3, "carve": 4,
    ]

    static let scenes: [StoryWorld: [String]] = [
        .forest: ["arrive", "chop", "stack", "build", "cabin", "leave"],
        .cave: ["enter", "mine", "tunnel", "pebbles", "drips", "rest"],
        .workshop: ["anvil", "carpentry", "carve", "tidy", "plans", "visitor"],
    ]

    let world: StoryWorld
    private(set) var lastScene: String?

    init(world: StoryWorld) { self.world = world }

    /// The next random scene – never the same one twice in a row.
    mutating func next(using rng: inout SeededGenerator) -> StoryScene {
        let options = Self.scenes[world]!.filter { $0 != lastScene }
        let name = options.randomElement(using: &rng)!
        lastScene = name
        var b = Builder(rng: rng)
        b.compose(name, world: world)
        rng = b.rng
        // mostly a short breather, sometimes a long quiet stretch – surprise is part of it
        let pause = Double.random(in: 0..<1, using: &rng) < 0.2 ? Double.random(in: 40...90, using: &rng)
            : Double.random(in: 6...25, using: &rng)
        return StoryScene(name: name, events: b.events, pause: pause)
    }

    /// Writes the events of one scene; `t` is the running clock, `pan`/`near` the position of the "person".
    private struct Builder {
        var rng: SeededGenerator
        var events: [StoryEvent] = []
        var t: TimeInterval = 0
        var pan: Float = 0
        var near: Float = 0.8

        mutating func d(_ r: ClosedRange<Double>) -> Double { Double.random(in: r, using: &rng) }
        mutating func f(_ r: ClosedRange<Float>) -> Float { Float.random(in: r, using: &rng) }
        mutating func i(_ r: ClosedRange<Int>) -> Int { Int.random(in: r, using: &rng) }
        mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }

        mutating func sound(_ group: String, _ volume: ClosedRange<Float> = 0.75...1, panJitter: Float = 0.08) {
            let n = StoryTeller.samples[group]!
            events.append(StoryEvent(at: t, sample: "st_\(group)_\(i(0...(n - 1))).caf",
                                     volume: min(1, f(volume) * near),
                                     pan: max(-1, min(1, pan + f(-panJitter...panJitter)))))
        }

        mutating func wait(_ r: ClosedRange<Double>) { t += d(r) }

        /// Somewhere around the listener.
        mutating func place(nearness: ClosedRange<Float> = 0.55...0.95) {
            pan = f(-0.7...0.7)
            near = f(nearness)
        }

        /// Footsteps moving from `from` to `to` (pan), getting closer or farther.
        mutating func walk(_ group: String, steps: ClosedRange<Int>, from: Float, to: Float,
                           nearFrom: Float, nearTo: Float) {
            let n = i(steps)
            let pace = d(0.46...0.6)
            for k in 0..<n {
                let p = Float(k) / Float(max(1, n - 1))
                pan = from + (to - from) * p
                near = nearFrom + (nearTo - nearFrom) * p
                sound(group, 0.55...0.8, panJitter: 0.03)
                t += pace + d(-0.04...0.04)
            }
        }

        /// `hits` blows with a working rhythm (e.g. an axe, a pickaxe, a hammer).
        mutating func work(_ group: String, hits: ClosedRange<Int>, every: ClosedRange<Double>,
                           volume: ClosedRange<Float> = 0.7...1, miss: (String, Double)? = nil) {
            for _ in 0..<i(hits) {
                if let miss, chance(miss.1) { sound(miss.0, 0.4...0.6) } else { sound(group, volume) }
                wait(every)
            }
        }

        mutating func edge() -> Float { chance(0.5) ? -0.95 : 0.95 }

        mutating func compose(_ scene: String, world: StoryWorld) {
            switch (world, scene) {
            // ── 🌲 a cabin in the woods ──
            case (.forest, "arrive"):
                let target = f(-0.4...0.4), from = edge(), ground = chance(0.15) ? "snow" : "grass"
                walk(ground, steps: 8...18, from: from, to: target, nearFrom: 0.3, nearTo: 0.85)
            case (.forest, "leave"):
                place()
                let from = pan, to = edge(), nearFrom = near
                walk("grass", steps: 8...16, from: from, to: to, nearFrom: nearFrom, nearTo: 0.25)
            case (.forest, "chop"):
                place()
                for round in 0..<i(2...4) {
                    if round > 0 { wait(3...7) }
                    work("chop", hits: 3...7, every: 1.4...2.4, miss: ("log", 0.12))
                    if chance(0.5) {                                             // split pieces fall
                        for _ in 0..<i(2...4) { sound("log", 0.4...0.7); wait(0.12...0.25) }
                    }
                }
            case (.forest, "stack"):
                place()
                for _ in 0..<i(4...9) {
                    sound("log", 0.5...0.8)
                    wait(0.9...1.8)
                    if chance(0.3) {                                             // a few steps to the pile
                        for _ in 0..<i(2...3) { sound("grass", 0.4...0.6); wait(0.45...0.6) }
                    }
                }
            case (.forest, "build"):
                place()
                for burst in 0..<i(2...4) {
                    if burst > 0 { wait(2...5) }
                    work("plank", hits: 3...6, every: 0.32...0.5)
                }
                if chance(0.5) { wait(1...2); sound("tool", 0.5...0.7) }
            case (.forest, "cabin"):
                place(nearness: 0.5...0.8)
                sound("door", 0.5...0.7); wait(0.8...1.4)
                for _ in 0..<i(3...6) { sound("wood", 0.5...0.7); wait(0.5...0.62) }
                if chance(0.6) { sound("creak", 0.4...0.6); wait(1...2) }
                for _ in 0..<i(1...2) { sound("pot", 0.4...0.7); wait(1.5...3) }
                if chance(0.5) { sound("cloth", 0.3...0.5); wait(2...4) }
                for _ in 0..<i(2...4) { sound("page", 0.3...0.5); wait(4...9) }
            // ── ⛏️ a cave ──
            case (.cave, "enter"):
                let from = edge(), to = f(-0.3...0.3)
                walk("stone", steps: 10...20, from: from, to: to, nearFrom: 0.3, nearTo: 0.8)
            case (.cave, "mine"):
                place()
                for burst in 0..<i(2...5) {
                    if burst > 0 { wait(2...6) }
                    work("mine", hits: 3...8, every: 0.65...1.05)
                    if chance(0.6) {                                             // ore / stones fall
                        for _ in 0..<i(1...3) { sound("rock", 0.4...0.7); wait(0.15...0.4) }
                    }
                    if chance(0.4) { wait(0.5...1.2); sound("pickup", 0.5...0.7) }
                }
            case (.cave, "tunnel"):
                place(nearness: 0.4...0.7)
                work("mine", hits: 8...14, every: 0.8...1.0)
                wait(1...2); sound("drag", 0.5...0.8)
            case (.cave, "pebbles"):
                for _ in 0..<i(2...4) {
                    place(nearness: 0.2...0.45)
                    sound("rock", 0.6...1); wait(0.8...2.5)
                }
                if chance(0.5) { sound("drag", 0.4...0.7) }
            case (.cave, "drips"):
                for _ in 0..<i(3...7) {
                    place(nearness: 0.25...0.6)
                    sound("drip"); wait(0.8...3)
                }
            case (.cave, "rest"):
                place(nearness: 0.6...0.9)
                sound("cloth", 0.4...0.6); wait(1...2)
                sound("pickup", 0.4...0.6); wait(2...4)
                if chance(0.5) { sound("tool", 0.4...0.6) }
            // ── 🔨 a workshop ──
            case (.workshop, "anvil"):
                place()
                for burst in 0..<i(2...4) {
                    if burst > 0 { wait(2...4) }
                    work("anvil", hits: 3...7, every: 0.38...0.55)
                }
                if chance(0.4) { wait(1...2); sound("pot", 0.4...0.6) }
            case (.workshop, "carpentry"):
                place()
                for burst in 0..<i(2...4) {
                    if burst > 0 { wait(2...5) }
                    work("plank", hits: 3...6, every: 0.32...0.48)
                }
            case (.workshop, "carve"):
                place(nearness: 0.6...0.9)
                for _ in 0..<i(3...6) {
                    sound("carve", 0.4...0.7)
                    wait(1.5...3)
                    if chance(0.25) { sound("cloth", 0.3...0.5); wait(1...2) }
                }
            case (.workshop, "tidy"):
                place()
                let count = i(3...5)
                let groups = ["tool", "pickup", "pot", "wood", "tool"].shuffled(using: &rng).prefix(count)
                for g in groups {
                    sound(g, 0.4...0.7); wait(1...2.5)
                }
            case (.workshop, "plans"):
                place(nearness: 0.6...0.9)
                if chance(0.6) { sound("creak", 0.4...0.6); wait(1...2) }
                for _ in 0..<i(2...5) { sound("page", 0.3...0.5); wait(3...7) }
            default:                                                            // (.workshop, "visitor")
                sound("door", 0.5...0.7); wait(0.8...1.4)
                let from = edge(), to = f(-0.3...0.3)
                walk("wood", steps: 4...8, from: from, to: to, nearFrom: 0.5, nearTo: 0.8)
                wait(2...5)
                sound("door", 0.4...0.6)
            }
        }
    }
}
