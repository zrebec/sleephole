import AVFoundation
import Foundation
import SleepCore

/// Sound stories for falling asleep (owner 2026-09-30): like listening to someone play a survival game – the
/// axe, the pickaxe, footsteps, the first cave – and imagining what happens. Every chapter has a quiet bed loop
/// (`bed_<name>.caf`); on top of it `StoryTeller` invents random scenes from CC0 clips (Kenney + Freesound,
/// `st_<group>_<n>.caf`, made by tools/audio/make_stories.py), so no two nights sound the same.
enum StoryWorld: String, CaseIterable, Sendable {
    case forest, cave, workshop, journey

    /// The chapters in order; single-chapter worlds stay in their chapter all night.
    var chapters: [StoryChapter] {
        switch self {
        case .forest: [.cabin]
        case .cave: [.cave]
        case .workshop: [.carpentry]
        // owner 2026-09-30: "first the cabin in the woods, then the man looks for shelter from the wind, a cave…"
        case .journey: [.cabin, .carpentry, .wind, .storm, .lake, .after]
        }
    }
}

enum StoryChapter: String, CaseIterable, Sendable {
    case cabin, carpentry, cave, wind, storm, lake, after

    var bed: String {
        switch self {
        case .cabin: "bed_forest.caf"            // camp fire, crickets, a brook
        case .carpentry: "bed_workshop.caf"      // stove, crickets outside
        case .cave: "bed_cave.caf"               // drips
        case .wind: "bed_wind.caf"               // trees in the wind
        case .storm: "bed_storm.caf"             // rain + distant thunder
        case .lake: "bed_lake.caf"               // an underground lake
        case .after: "bed_after.caf"             // the rain fades, frogs, crickets
        }
    }

    /// Scene → weight (rare ones like the wolf or the horse have a small weight).
    var scenes: [String: Int] {
        switch self {
        case .cabin: ["arrive": 2, "chop": 3, "stack": 2, "build": 2, "inside": 2, "dog": 3, "chickens": 2,
                      "well": 2, "cat": 2, "owl": 2, "horse": 1, "leave": 1]
        case .carpentry: ["saw": 4, "plane": 3, "sand": 2, "nails": 3, "sweep": 2, "measure": 2, "floor": 1,
                          "pets": 2, "owl": 1]
        case .cave: ["enter": 2, "mine": 4, "tunnel": 2, "pebbles": 2, "drips": 2, "rest": 1]
        case .wind: ["leaves": 4, "creak": 2, "owl": 2, "wade": 2, "wolf": 1, "rest": 1]
        case .storm: ["thunder": 3, "hurry": 2, "shelter": 2, "rest": 1]
        case .lake: ["mine": 2, "pebbles": 2, "drips": 3, "wade": 2, "rest": 1, "tunnel": 1]
        case .after: ["drips": 3, "owl": 2, "creak": 1, "rest": 2]
        }
    }

    /// The first scene when the journey reaches this chapter (walking there).
    var opening: String? {
        switch self {
        case .carpentry: "toWorkshop"
        case .wind: "setOff"
        case .storm: "hurry"
        case .lake: "deeper"
        default: nil
        }
    }

    var reverb: (preset: AVAudioUnitReverbPreset, wet: Float) {
        switch self {
        case .cabin, .wind: (.mediumRoom, 10)
        case .carpentry: (.smallRoom, 22)
        case .storm: (.mediumHall, 25)
        case .cave, .lake: (.largeChamber, 45)
        case .after: (.mediumRoom, 15)
        }
    }

    /// The end of the journey is sleepy: long quiet stretches.
    var pauses: (short: ClosedRange<Double>, long: ClosedRange<Double>) {
        self == .after ? (25...60, 60...150) : (6...25, 40...90)
    }
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
    var chapter: StoryChapter
    var name: String
    var events: [StoryEvent]
    /// Quiet time after the last sound before the next scene begins.
    var pause: TimeInterval
    var length: TimeInterval { (events.map(\.at).max() ?? 0) + pause }
}

struct StoryTeller: Sendable {
    /// Clips per group, as written by tools/audio/make_stories.py.
    static let samples: [String: Int] = [
        // Kenney CC0 one-shots
        "mine": 5, "chop": 6, "log": 10, "plank": 5, "anvil": 5, "grass": 5, "wood": 5, "stone": 5, "snow": 5,
        "drip": 4, "rock": 9, "drag": 7, "pickup": 6, "creak": 3, "door": 6, "page": 3, "cloth": 6, "pot": 3,
        "tool": 3, "carve": 4,
        // clips cut from Freesound CC0 recordings (tools/audio/freesound.json)
        "saw": 10, "plane": 6, "sand": 3, "nail": 6, "sweep": 6, "floor": 4, "owl": 8, "dog": 6, "bark": 3,
        "chicken": 5, "purr": 4, "horse": 2, "wolf": 1, "wade": 2, "bucket": 1, "leaves": 6, "thunder": 5,
    ]

    /// A journey chapter lasts 10–20 min (owner 2026-09-30).
    static let chapterLength: ClosedRange<TimeInterval> = 600...1200

    let world: StoryWorld
    private(set) var chapterIndex = 0
    private(set) var lastScene: String?
    private var chapterLeft: TimeInterval?

    init(world: StoryWorld) { self.world = world }

    var chapter: StoryChapter { world.chapters[chapterIndex] }

    /// The next random scene – never the same one twice in a row; a journey moves to its next chapter after
    /// 10–20 min and starts it with the chapter's opening scene.
    mutating func next(using rng: inout SeededGenerator) -> StoryScene {
        if chapterLeft == nil { chapterLeft = Double.random(in: Self.chapterLength, using: &rng) }
        var name: String
        if let left = chapterLeft, left <= 0, chapterIndex < world.chapters.count - 1 {
            chapterIndex += 1
            chapterLeft = Double.random(in: Self.chapterLength, using: &rng)
            lastScene = nil
            name = chapter.opening ?? Self.pick(chapter.scenes, except: nil, using: &rng)
        } else {
            name = Self.pick(chapter.scenes, except: lastScene, using: &rng)
        }
        lastScene = name
        var b = Builder(rng: rng)
        b.compose(name)
        rng = b.rng
        let p = chapter.pauses
        let pause = Double.random(in: 0..<1, using: &rng) < 0.2 ? Double.random(in: p.long, using: &rng)
            : Double.random(in: p.short, using: &rng)
        let scene = StoryScene(chapter: chapter, name: name, events: b.events, pause: pause)
        chapterLeft? -= scene.length
        return scene
    }

    static func pick(_ weights: [String: Int], except: String?, using rng: inout SeededGenerator) -> String {
        let options = weights.filter { $0.key != except }.sorted { $0.key < $1.key }       // stable order for seeds
        var roll = Int.random(in: 0..<options.reduce(0) { $0 + $1.value }, using: &rng)
        for (name, w) in options {
            if roll < w { return name }
            roll -= w
        }
        return options.last!.key
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
            let index = i(0...(n - 1))
            let v = min(1, f(volume) * near)
            let p = max(-1, min(1, pan + f(-panJitter...panJitter)))
            events.append(StoryEvent(at: t, sample: "st_\(group)_\(index).caf", volume: v, pan: p))
        }

        mutating func wait(_ r: ClosedRange<Double>) { t += d(r) }

        /// Somewhere around the listener.
        mutating func place(nearness: ClosedRange<Float> = 0.55...0.95) {
            pan = f(-0.7...0.7)
            near = f(nearness)
        }

        /// Far away, to one side (animals in the night, thunder).
        mutating func far(_ nearness: ClosedRange<Float> = 0.2...0.45) {
            pan = f(0.5...0.95) * (chance(0.5) ? -1 : 1)
            near = f(nearness)
        }

        mutating func edge() -> Float { chance(0.5) ? -0.95 : 0.95 }

        /// Footsteps moving from `from` to `to` (pan), getting closer or farther.
        mutating func walk(_ group: String, steps: ClosedRange<Int>, from: Float, to: Float,
                           nearFrom: Float, nearTo: Float, pace: ClosedRange<Double> = 0.46...0.6) {
            let n = i(steps)
            let stride = d(pace)
            for k in 0..<n {
                let p = Float(k) / Float(max(1, n - 1))
                pan = from + (to - from) * p
                near = nearFrom + (nearTo - nearFrom) * p
                sound(group, 0.55...0.8, panJitter: 0.03)
                t += stride + d(-0.04...0.04)
            }
        }

        /// Long clips (a saw, rustling leaves, a purring cat) one after another with small gaps.
        mutating func clips(_ group: String, count: ClosedRange<Int>, gap: ClosedRange<Double>,
                            length: Double, volume: ClosedRange<Float> = 0.7...1) {
            for _ in 0..<i(count) {
                sound(group, volume, panJitter: 0.04)
                t += length
                wait(gap)
            }
        }

        /// `hits` blows with a working rhythm (an axe, a pickaxe, a hammer).
        mutating func work(_ group: String, hits: ClosedRange<Int>, every: ClosedRange<Double>,
                           volume: ClosedRange<Float> = 0.7...1, miss: (String, Double)? = nil) {
            for _ in 0..<i(hits) {
                if let miss, chance(miss.1) { sound(miss.0, 0.4...0.6) } else { sound(group, volume) }
                wait(every)
            }
        }

        // swiftlint:disable:next cyclomatic_complexity function_body_length
        mutating func compose(_ scene: String) {
            switch scene {
            // ── walking between places ──
            case "arrive":
                let target = f(-0.4...0.4), from = edge(), ground = chance(0.15) ? "snow" : "grass"
                walk(ground, steps: 8...18, from: from, to: target, nearFrom: 0.3, nearTo: 0.85)
            case "leave":
                place()
                let from = pan, to = edge(), nearFrom = near
                walk("grass", steps: 8...16, from: from, to: to, nearFrom: nearFrom, nearTo: 0.25)
            case "toWorkshop":
                let from = edge()
                walk("grass", steps: 6...12, from: from, to: 0, nearFrom: 0.4, nearTo: 0.8)
                sound("door", 0.5...0.7); wait(0.8...1.3)
                walk("wood", steps: 3...6, from: 0, to: f(-0.3...0.3), nearFrom: 0.8, nearTo: 0.85)
            case "setOff":
                place(nearness: 0.7...0.9)
                sound("door", 0.5...0.7); wait(1...2)
                let from = pan, to = edge()
                walk("grass", steps: 6...10, from: from, to: 0, nearFrom: 0.8, nearTo: 0.7)
                clips("leaves", count: 1...2, gap: 0...0.3, length: 4.5, volume: 0.5...0.7)
                walk("grass", steps: 4...8, from: 0, to: to, nearFrom: 0.7, nearTo: 0.35)
            case "hurry":
                far(0.25...0.4); sound("thunder", 0.6...0.9); wait(4...8)
                let from = edge()
                walk("grass", steps: 10...16, from: from, to: 0, nearFrom: 0.35, nearTo: 0.8, pace: 0.36...0.44)
                walk("stone", steps: 4...8, from: 0, to: f(-0.3...0.3), nearFrom: 0.8, nearTo: 0.85)
            case "deeper", "enter":
                let from = edge(), to = f(-0.3...0.3)
                walk("stone", steps: 10...20, from: from, to: to, nearFrom: 0.3, nearTo: 0.8)
            // ── 🌲 the cabin ──
            case "chop":
                place()
                for round in 0..<i(2...4) {
                    if round > 0 { wait(3...7) }
                    work("chop", hits: 3...7, every: 1.4...2.4, miss: ("log", 0.12))
                    if chance(0.5) {                                             // split pieces fall
                        for _ in 0..<i(2...4) { sound("log", 0.4...0.7); wait(0.12...0.25) }
                    }
                }
            case "stack":
                place()
                for _ in 0..<i(4...9) {
                    sound("log", 0.5...0.8)
                    wait(0.9...1.8)
                    if chance(0.3) {                                             // a few steps to the pile
                        for _ in 0..<i(2...3) { sound("grass", 0.4...0.6); wait(0.45...0.6) }
                    }
                }
            case "build":
                place()
                for burst in 0..<i(2...4) {
                    if burst > 0 { wait(2...5) }
                    work("plank", hits: 3...6, every: 0.32...0.5)
                }
                if chance(0.5) { wait(1...2); sound("tool", 0.5...0.7) }
            case "inside":
                place(nearness: 0.5...0.8)
                sound("door", 0.5...0.7); wait(0.8...1.4)
                for _ in 0..<i(3...6) { sound("wood", 0.5...0.7); wait(0.5...0.62) }
                if chance(0.6) { sound("floor", 0.4...0.6); wait(1...2) }
                for _ in 0..<i(1...2) { sound("pot", 0.4...0.7); wait(1.5...3) }
                if chance(0.5) { sound("cloth", 0.3...0.5); wait(2...4) }
                for _ in 0..<i(2...4) { sound("page", 0.3...0.5); wait(4...9) }
            case "dog":
                place(nearness: 0.5...0.85)
                clips("dog", count: 1...2, gap: 2...6, length: 5, volume: 0.5...0.8)
                if chance(0.35) { far(0.25...0.45); sound("bark", 0.6...0.9) }
            case "chickens":
                place(nearness: 0.35...0.6)
                clips("chicken", count: 1...3, gap: 1...5, length: 4.5, volume: 0.5...0.8)
            case "well":
                place(nearness: 0.5...0.8)
                for _ in 0..<i(3...6) { sound("grass", 0.4...0.6); wait(0.45...0.6) }
                sound("tool", 0.4...0.6); wait(1.5...3)                      // the chain / the handle
                sound("bucket", 0.6...0.9); wait(2...3)
                if chance(0.5) { sound("wade", 0.3...0.5) }
            case "cat":
                place(nearness: 0.7...0.95)
                clips("purr", count: 1...2, gap: 0.5...2, length: 7.5, volume: 0.5...0.75)
            case "owl":
                far(0.2...0.45)
                for _ in 0..<i(1...3) { sound("owl", 0.7...1); wait(3...8) }
            case "horse":
                far(0.25...0.4)
                sound("horse", 0.6...0.9)
            // ── 🔨 the carpentry workshop ──
            case "saw":
                place()
                clips("saw", count: 2...4, gap: 1.5...4, length: 5, volume: 0.7...1)
                if chance(0.5) { sound("log", 0.4...0.6) }                       // the cut piece drops
            case "plane":
                place()
                clips("plane", count: 2...4, gap: 1...3, length: 3.8, volume: 0.6...0.9)
                if chance(0.4) { wait(1...2); clips("sweep", count: 1...1, gap: 0...1, length: 4, volume: 0.4...0.6) }
            case "sand":
                place()
                clips("sand", count: 1...3, gap: 1.5...4, length: 4, volume: 0.5...0.8)
            case "nails":
                place()
                for burst in 0..<i(2...4) {
                    if burst > 0 { wait(2...5) }
                    if chance(0.5) { clips("nail", count: 1...2, gap: 0.5...1.5, length: 1.2) }
                    else { work("plank", hits: 3...6, every: 0.32...0.48) }
                }
            case "sweep":
                place(nearness: 0.6...0.9)
                clips("sweep", count: 1...3, gap: 0.5...2, length: 4, volume: 0.4...0.7)
            case "measure":
                place()
                for g in ["tool", "pickup", "page", "wood", "tool"].shuffled(using: &rng).prefix(3) {
                    sound(g, 0.4...0.7); wait(1...2.5)
                }
                if chance(0.5) { sound("carve", 0.4...0.6) }
            case "floor":
                place(nearness: 0.6...0.9)
                for _ in 0..<i(1...2) { sound("floor", 0.4...0.7); wait(1.5...4) }
            case "pets":
                place(nearness: 0.7...0.95)
                if chance(0.5) { clips("purr", count: 1...1, gap: 0...1, length: 7.5, volume: 0.4...0.7) }
                else { clips("dog", count: 1...1, gap: 0...1, length: 5, volume: 0.4...0.6) }
            // ── 🌬️ the wind / ⛈️ the storm ──
            case "leaves":
                let from = edge(), to = -from * 0.5
                pan = from; near = 0.4
                for k in 0..<i(2...3) {
                    pan = from + (to - from) * Float(k) / 2
                    near = 0.45 + 0.15 * Float(k)
                    sound("leaves", 0.6...0.8, panJitter: 0.03)
                    t += 4.5
                }
            case "creak":
                place(nearness: 0.3...0.6)
                for _ in 0..<i(1...3) { sound("creak", 0.5...0.8); wait(3...8) }
            case "wade":
                place(nearness: 0.5...0.8)
                clips("wade", count: 1...2, gap: 0.5...2, length: 5, volume: 0.5...0.8)
            case "wolf":
                far(0.15...0.25)
                sound("wolf", 0.6...0.8)
            case "thunder":
                for _ in 0..<i(1...2) { far(0.3...0.6); sound("thunder", 0.6...1); wait(10...25) }
            case "shelter":
                place(nearness: 0.7...0.9)
                sound("cloth", 0.4...0.6); wait(1...2)
                for _ in 0..<i(2...4) { sound("log", 0.3...0.5); wait(0.8...1.5) }     // dry sticks for a fire
                sound("pickup", 0.4...0.6)
            // ── ⛏️ the cave ──
            case "mine":
                place()
                for burst in 0..<i(2...5) {
                    if burst > 0 { wait(2...6) }
                    work("mine", hits: 3...8, every: 0.65...1.05)
                    if chance(0.6) {                                             // ore / stones fall
                        for _ in 0..<i(1...3) { sound("rock", 0.4...0.7); wait(0.15...0.4) }
                    }
                    if chance(0.4) { wait(0.5...1.2); sound("pickup", 0.5...0.7) }
                }
            case "tunnel":
                place(nearness: 0.4...0.7)
                work("mine", hits: 8...14, every: 0.8...1.0)
                wait(1...2); sound("drag", 0.5...0.8)
            case "pebbles":
                for _ in 0..<i(2...4) {
                    place(nearness: 0.2...0.45)
                    sound("rock", 0.6...1); wait(0.8...2.5)
                }
                if chance(0.5) { sound("drag", 0.4...0.7) }
            case "drips":
                for _ in 0..<i(3...7) {
                    place(nearness: 0.25...0.6)
                    sound("drip"); wait(0.8...3)
                }
            default:                                                            // "rest"
                place(nearness: 0.6...0.9)
                sound("cloth", 0.4...0.6); wait(1...2)
                sound("pickup", 0.4...0.6); wait(2...4)
                if chance(0.5) { sound("tool", 0.4...0.6) }
            }
        }
    }
}
