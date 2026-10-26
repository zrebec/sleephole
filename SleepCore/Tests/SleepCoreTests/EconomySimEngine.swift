import Foundation
@testable import SleepCore

// Economy simulation engine (build 11, step 11b1). Test-only: the box rules live here until step 11b3 moves them
// into SleepCore. Everything is deterministic: a run is a pure function of (profile, policy, variant, run index).

// MARK: - Profiles

struct SimProfile: Sendable {
    let name: String
    /// Cumulative night odds: complete, then unfinished, ruins; the rest is missed.
    let complete: Double, unfinished: Double, ruins: Double
    /// P(pauses >= 1, >= 2, >= 3) on a started night.
    let pauseAtLeast: (Double, Double, Double)
    /// (calm hours, probability) – must sum to 1.
    let calm: [(Int, Double)]
    let napComplete: Double, napUnfinished: Double
    /// Silver joker: months of the year (index from the start month, 0 = Nov 2026) in which the user is willing to buy.
    let silverMonths: Set<Int>
    /// Months (index) in which the user pays the 2 000 schedule unlock (retried daily until affordable).
    let unlockMonths: Set<Int>
    /// Reroll chance of the 1st / 2nd draw when tonight's level < the unlocked maximum.
    let reroll1: Double, reroll2: Double

    static let perfect = SimProfile(name: "perfect", complete: 1, unfinished: 0, ruins: 0,
                                    pauseAtLeast: (0, 0, 0), calm: [(7, 1)], napComplete: 1, napUnfinished: 0,
                                    silverMonths: [], unlockMonths: [], reroll1: 0.5, reroll2: 0.25)
    static let typical = SimProfile(name: "typical", complete: 0.85, unfinished: 0.07, ruins: 0.05,
                                    pauseAtLeast: (0.10, 0.02, 0), calm: [(7, 0.5), (6, 0.3), (5, 0.15), (4, 0.05)],
                                    napComplete: 0.45, napUnfinished: 0.05,
                                    silverMonths: [2, 5, 8, 11], unlockMonths: [5], reroll1: 0.30, reroll2: 0.15)
    static let weak = SimProfile(name: "weak", complete: 0.65, unfinished: 0.12, ruins: 0.13,
                                 pauseAtLeast: (0.25, 0.08, 0.02), calm: (3...7).map { ($0, 0.2) },
                                 napComplete: 0.15, napUnfinished: 0.05,
                                 silverMonths: [1, 3, 5, 7, 9, 11], unlockMonths: [2, 8], reroll1: 0.10, reroll2: 0.05)
    static let all = [perfect, typical, weak]
}

// MARK: - Box rules (owner's answers 2026-10-25)

enum SimBoxRules {
    static let floor = 400
    static let maxPerMonth = 9

    /// Share of the balance by the month's box number (1-based): 1–3 → 20 %, 4–6 → 40 %, 7–9 → 60 %; nil after the 9th.
    static func percent(boxNumber n: Int) -> Int? {
        switch n {
        case 1...3: 20
        case 4...6: 40
        case 7...9: 60
        default: nil
        }
    }

    /// The price of the month's box number `n` at `balance`: max(400, tier % of the balance) rounded down to 10;
    /// nil when no such box exists (the 10th) or the balance does not reach the price.
    static func price(balance: Int, boxNumber n: Int) -> Int? {
        guard let pct = percent(boxNumber: n) else { return nil }
        let price = max(floor, balance * pct / 100) / 10 * 10
        return balance >= price ? price : nil
    }

    /// What may be bought this morning: one box a day, only after a complete real night, within the month's limit.
    static func offer(balance: Int, boxesThisMonth: Int, boughtToday: Bool, afterCompleteNight: Bool) -> Int? {
        guard afterCompleteNight, !boughtToday else { return nil }
        return price(balance: balance, boxNumber: boxesThisMonth + 1)
    }
}

enum SimCollection: Int, CaseIterable, Sendable {
    case postcard, decoration, accessory, nightSky
    var size: Int { [30, 12, 6, 4][rawValue] }
    var label: String { ["postcards", "decorations", "accessories", "sky effects"][rawValue] }
}

enum SimBoxContent: Equatable, Sendable {
    case coins(tenths: Int)          // a multiple of the price paid, in tenths (5 = 0.5x)
    case luckyNight
    case collectible(SimCollection)
    case bronze, silver
}

/// An odds table in tenths of a percent (the sum is 1000).
struct SimOddsVariant: Sendable {
    let name: String
    let table: [(SimBoxContent, Int)]
    /// C-new: a collectible draw picks an item not owned yet while the collection is incomplete.
    var preferNew = false
    /// C-new-reserve: a box is offered only if the balance after paying stays >= 1 000 (one silver joker).
    var reserve = false
    var sum: Int { table.reduce(0) { $0 + $1.1 } }

    func roll(_ permille: Int) -> SimBoxContent {
        var acc = 0
        for (c, w) in table { acc += w; if permille < acc { return c } }
        return table.last!.0
    }

    static let A = SimOddsVariant(name: "A", table: [
        (.coins(tenths: 5), 250), (.coins(tenths: 10), 100), (.coins(tenths: 20), 40), (.coins(tenths: 100), 5),
        (.luckyNight, 80), (.collectible(.postcard), 250), (.collectible(.decoration), 120),
        (.collectible(.accessory), 60), (.collectible(.nightSky), 60), (.bronze, 33), (.silver, 2)])
    static let B = SimOddsVariant(name: "B", table: [
        (.coins(tenths: 5), 320), (.coins(tenths: 10), 120), (.coins(tenths: 20), 50), (.coins(tenths: 100), 8),
        (.luckyNight, 80), (.collectible(.postcard), 200), (.collectible(.decoration), 90),
        (.collectible(.accessory), 50), (.collectible(.nightSky), 50), (.bronze, 30), (.silver, 2)])
    static let C = SimOddsVariant(name: "C", table: [
        (.coins(tenths: 5), 320), (.coins(tenths: 10), 120), (.coins(tenths: 20), 50), (.coins(tenths: 30), 8),
        (.luckyNight, 80), (.collectible(.postcard), 200), (.collectible(.decoration), 90),
        (.collectible(.accessory), 50), (.collectible(.nightSky), 50), (.bronze, 30), (.silver, 2)])
}

extension SimOddsVariant {
    static let CNew = SimOddsVariant(name: "C-new", table: C.table, preferNew: true)
    /// D = C-new-reserve with a larger collectible share (accessories 7 %, sky 5 %, bronze 3 %).
    static let D = SimOddsVariant(name: "D", table: [
        (.coins(tenths: 5), 250), (.coins(tenths: 10), 100), (.coins(tenths: 20), 40), (.coins(tenths: 30), 8),
        (.luckyNight, 80), (.collectible(.postcard), 250), (.collectible(.decoration), 120),
        (.collectible(.accessory), 70), (.collectible(.nightSky), 50), (.bronze, 30), (.silver, 2)],
        preferNew: true, reserve: true)
    static let CNewReserve = SimOddsVariant(name: "C-new-reserve", table: C.table, preferNew: true, reserve: true)
}

// MARK: - A fast twin of BuildingPicker

/// `BuildingPicker.pick` rebuilds a Set and a Dictionary of the whole history on every call, which is too slow for
/// millions of simulated nights in a debug build. This twin keeps those incrementally and consumes the random
/// generator in exactly the same way; an always-on test proves it returns the same buildings as the real picker.
struct SimFastPicker {
    private let levels: [[CatalogEntry]]
    private let l1: [CatalogEntry]
    private(set) var history: [String] = []
    private var built = Set<String>()
    private var lastUse: [String: Int] = [:]

    init(catalog: Catalog) {
        levels = (1...4).map { BuildingPicker.candidates(level: $0, catalog: catalog) }
        l1 = catalog.buildable(level: 1)
    }

    mutating func append(_ id: String) {
        lastUse[id] = history.count
        built.insert(id)
        history.append(id)
    }

    func pick<G: RandomNumberGenerator>(maxLevel: Int, excluding: Set<String> = [], rng: inout G) -> CatalogEntry {
        let recent = Set(history.suffix(3)).union(excluding)
        var order = Array(1...max(1, min(4, maxLevel)))
        order.shuffle(using: &rng)
        for level in order {
            let candidates = levels[level - 1].filter { !recent.contains($0.id) }
            guard !candidates.isEmpty else { continue }
            let fresh = candidates.filter { !built.contains($0.id) }
            if !fresh.isEmpty { return fresh.randomElement(using: &rng)! }
            let oldest = candidates.map { lastUse[$0.id] ?? -1 }.min()!
            return candidates.filter { (lastUse[$0.id] ?? -1) == oldest }.randomElement(using: &rng)!
        }
        return (l1.filter { !excluding.contains($0.id) }.randomElement(using: &rng)) ?? l1.randomElement(using: &rng)!
    }
}

// MARK: - Configuration and results

struct SimConfig: Sendable {
    var profile: SimProfile
    /// Boxes per month the buyer wants: 0 (P0), 3 (P3), 6 (P6), 9 (P9).
    var boxesPerMonth: Int
    var variant: SimOddsVariant?
    var rerolls: Bool
    var nights = 365
}

let simCheckpoints = [30, 100, 365]
let simStart = NightKey(year: 2026, month: 11, day: 1)

/// Counters up to a checkpoint (cumulative).
struct SimSnap: Sendable, Equatable {
    var balance = 0
    // earned
    var building = 0, undisturbed = 0, calm = 0, streak = 0, nap = 0, achievement = 0
    var boxCoins = 0                  // prizes + duplicates + the lucky-night extra
    // spent
    var pauses = 0, silver = 0, unlock = 0, reroll = 0, boxPaid = 0
    var boxes = 0, luckyWon = 0, luckyPaid = 0, jokersWon = 0, jokersUsed = 0, rerolls = 0, silversBought = 0, silverWanted = 0
    var below400 = false
    var largestPrize = 0
    /// Mean end-of-day balance over the last 100 nights up to the checkpoint (all of them at night 30).
    var avgBalance = 0.0
    /// Lowest end-of-day balance after night 30 up to the checkpoint (-1 = none yet).
    var lowestAfter30 = -1
    var owned = [0, 0, 0, 0]
    var completeNight: [Int?] = [nil, nil, nil, nil]
    var completeMonth: [Int?] = [nil, nil, nil, nil]
}

/// Per-night trace for the equivalence test.
struct SimTrace: Sendable {
    var raw: [Outcome] = []
    var final: [Outcome] = []
    var pauses: [Int] = []
    var calm: [Int] = []
    var building: [String?] = []
    var nightCoins: [Int] = []        // base + streak + undisturbed + calm (the ledger's part)
    var achievementCoins: [Int] = []
    var napOutcome: [Outcome?] = []
    var silverStarts: [Int] = []
}

struct SimRun: Sendable {
    var snaps: [SimSnap] = []
    var trace: SimTrace?
}

// MARK: - Seeds

func simSeed(_ parts: [String]) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in parts.joined(separator: "|").utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
    return h
}

/// Precomputed calendar: night keys for 366 days and the month index (0 = Nov 2026) of each.
struct SimCalendar: Sendable {
    let keys: [NightKey]
    let month: [Int]
    init(days: Int = 365) {
        var k = simStart
        var keys: [NightKey] = []
        for _ in 0..<days { keys.append(k); k = k.adding(days: 1, calendar: bratislava) }
        self.keys = keys
        month = keys.map { ($0.year - 2026) * 12 + $0.month - 11 }
    }
}

// MARK: - The simulation

func simulate(_ cfg: SimConfig, run runIndex: Int, catalog: Catalog, calendar cal: SimCalendar, trace wantTrace: Bool = false) -> SimRun {
    let p = cfg.profile
    // events are common across policies / variants of one profile (paired comparison); buildings and boxes get the full seed
    var ev = SeededGenerator(seed: simSeed(["events", p.name, "\(runIndex)"]))
    var rng = SeededGenerator(seed: simSeed(["world", p.name, "P\(cfg.boxesPerMonth)", cfg.variant?.name ?? "-",
                                             "\(runIndex)"]))
    var tr = SimTrace()
    var s = SimSnap()
    var out = SimRun()

    var bal = 0
    var run = 0, built = 0
    var picker = SimFastPicker(catalog: catalog)
    var ach = Set<Achievement>()
    var bronzeMonth = Set<Int>()          // months whose own bronze is used
    var silverMonthUsed = Set<Int>()
    var silverEnd = -1                    // last day index covered by a bought / box silver
    var unlockPaid = Set<Int>()
    var pendingLucky = 0
    var boxesIn: [Int: Int] = [:]         // month index → boxes bought
    var heldBronze = -1, heldSilver = -1  // month index until which the extra joker is valid (-1 = none)
    var owned = [Set<Int>](repeating: [], count: 4)
    var below400 = false
    var largest = 0
    var daily: [Int] = []
    var lowest = Int.max

    func spend(_ x: Int) { bal -= x }

    for i in 0..<cfg.nights {
        let m = cal.month[i]
        // fixed number of draws per day, whatever happens
        let uNap = Double.random(in: 0..<1, using: &ev)
        let uNight = Double.random(in: 0..<1, using: &ev)
        let uPause = Double.random(in: 0..<1, using: &ev)
        let uCalm = Double.random(in: 0..<1, using: &ev)
        let uR1 = Double.random(in: 0..<1, using: &ev)
        let uR2 = Double.random(in: 0..<1, using: &ev)
        var dayAch = 0

        func unlock(_ a: Achievement) {
            if ach.insert(a).inserted { bal += a.reward; s.achievement += a.reward; dayAch += a.reward }
        }

        // nap (13:00–15:00 of this day)
        var napOutcome: Outcome?
        if uNap < p.napComplete { napOutcome = .complete } else if uNap < p.napComplete + p.napUnfinished { napOutcome = .unfinished }
        if let n = napOutcome {
            let c = NapPlan.reward(n)
            bal += c; s.nap += c
            if n == .complete { unlock(.firstNap) }
        }

        // the paid schedule unlock (retried daily within its month)
        if p.unlockMonths.contains(m), !unlockPaid.contains(m), bal >= SchedulePolicy.unlockPrice {
            spend(SchedulePolicy.unlockPrice); s.unlock += SchedulePolicy.unlockPrice; unlockPaid.insert(m)
        }

        // the night
        let raw: Outcome
        if uNight < p.complete { raw = .complete }
        else if uNight < p.complete + p.unfinished { raw = .unfinished }
        else if uNight < p.complete + p.unfinished + p.ruins { raw = .ruins }
        else { raw = .missed }
        let started = raw != .missed

        // setup: the building, rerolls, pauses (all paid from the balance at the evening)
        var drawn: CatalogEntry?
        var pauses = 0
        if started {
            let maxLevel = Progression.unlockedMaxLevel(builtBefore: built)
            var tonight: [String] = []
            var e = picker.pick(maxLevel: maxLevel, rng: &rng)
            tonight.append(e.id)
            if cfg.rerolls {
                for (n, u, chance) in [(0, uR1, p.reroll1), (1, uR2, p.reroll2)] {
                    guard e.level < maxLevel, u < chance, let price = Reroll.price(drawsMade: n), bal >= price else { break }
                    spend(price); s.reroll += price; s.rerolls += 1
                    e = picker.pick(maxLevel: maxLevel, excluding: Set(tonight), rng: &rng)
                    tonight.append(e.id)
                }
            }
            drawn = e
            let want = uPause < p.pauseAtLeast.2 ? 3 : uPause < p.pauseAtLeast.1 ? 2 : uPause < p.pauseAtLeast.0 ? 1 : 0
            for number in 1...max(1, want) where number <= want {
                let price = PausePolicy.price(number: number)
                guard bal >= price else { break }
                spend(price); s.pauses += price; pauses = number
            }
        }

        // the verdict, jokers
        var final = raw
        if raw == .ruins || raw == .missed {
            var used = false
            if i <= silverEnd {
                used = true                                            // an active silver covers it, run or not
            } else if run > 0 {
                if !bronzeMonth.contains(m) { bronzeMonth.insert(m); used = true }              // the month's own bronze
                else if heldBronze >= m { heldBronze = -1; used = true; s.jokersUsed += 1 }   // a box bronze
                else if p.silverMonths.contains(m), !silverMonthUsed.contains(m) {
                    if heldSilver >= m {
                        heldSilver = -1; s.jokersUsed += 1
                        silverMonthUsed.insert(m); silverEnd = i + 2; used = true; tr.silverStarts.append(i)
                    } else if bal < JokerTier.silver.price {
                        s.silverWanted += 1                      // wanted, but not affordable
                    } else {
                        spend(JokerTier.silver.price); s.silver += JokerTier.silver.price; s.silversBought += 1
                        silverMonthUsed.insert(m); silverEnd = i + 2; used = true; tr.silverStarts.append(i)
                    }
                }
            }
            if used { final = .excused } else { run = 0 }
        }

        var coins = 0, calmHours = 0
        if final.isBuildNight, let e = drawn {
            let level = e.level
            let base = Economy.reward(final, level: level)
            var streak = 0
            if final == .complete { run += 1; if run % Economy.streakBonusEvery == 0 { streak = Economy.streakBonus } }
            let undisturbed = final == .complete && pauses == 0 ? PausePolicy.undisturbedBonus : 0
            var acc = 0.0
            for (h, pr) in p.calm { acc += pr; if uCalm < acc { calmHours = h; break } }
            if calmHours == 0 { calmHours = p.calm.last!.0 }
            let calmBonus = calmHours * Economy.calmHourBonus
            coins = base + streak + undisturbed + calmBonus
            bal += coins
            s.building += base; s.streak += streak; s.undisturbed += undisturbed; s.calm += calmBonus
            built += 1
            picker.append(e.id)
            // the lucky night doubles the next complete night (the extra is the night's coins once more)
            if final == .complete, pendingLucky > 0 {
                pendingLucky -= 1; bal += coins; s.boxCoins += coins; s.luckyPaid += 1
            }
            // achievements, same order of checks as `Achievements.unlocked`
            unlock(.firstBuilding)
            for (n, a) in [(3, Achievement.streak3), (7, .streak7), (30, .streak30)] where run >= n { unlock(a) }
            for (n, a) in [(10, Achievement.built10), (50, .built50), (100, .built100)] where built >= n { unlock(a) }
            switch e.level {
            case 2: unlock(.firstLevel2)
            case 3: unlock(.firstLevel3)
            case 4: unlock(.firstSkyscraper)
            default: break
            }
        } else if final == .ruins || final == .missed {
            run = 0
            if final == .ruins, let e = drawn { picker.append(e.id) }     // a ruin keeps its id in the history
        }

        // the morning box
        if cfg.boxesPerMonth > 0, let v = cfg.variant, final == .complete {
            let k = cfg.boxesPerMonth
            let mm = cal.month[i]            // the night key is the MORNING date: the box is bought on cal.keys[i]
            let already = boxesIn[mm, default: 0]
            if already < k, let price = SimBoxRules.offer(balance: bal, boxesThisMonth: already, boughtToday: false,
                                                          afterCompleteNight: true),
               !v.reserve || bal - price >= JokerTier.silver.price {
                spend(price); s.boxPaid += price; s.boxes += 1; boxesIn[mm] = already + 1
                switch v.roll(Int.random(in: 0..<1000, using: &rng)) {
                case .coins(let tenths):
                    let prize = price * tenths / 10
                    bal += prize; s.boxCoins += prize; largest = max(largest, prize)
                case .luckyNight:
                    pendingLucky += 1; s.luckyWon += 1
                case .collectible(let c):
                    var item = Int.random(in: 0..<c.size, using: &rng)
                    if v.preferNew, owned[c.rawValue].count < c.size {
                        let missing = (0..<c.size).filter { !owned[c.rawValue].contains($0) }
                        item = missing[Int.random(in: 0..<missing.count, using: &rng)]
                    }
                    if owned[c.rawValue].insert(item).inserted {
                        if owned[c.rawValue].count == c.size {
                            s.completeNight[c.rawValue] = i + 1; s.completeMonth[c.rawValue] = mm + 1
                        }
                    } else { let d = price / 4; bal += d; s.boxCoins += d }
                case .bronze:
                    if heldBronze >= mm { let d = price / 4; bal += d; s.boxCoins += d }
                    else { heldBronze = mm + 1; s.jokersWon += 1 }
                case .silver:
                    if heldSilver >= mm { let d = price / 4; bal += d; s.boxCoins += d }
                    else { heldSilver = mm + 1; s.jokersWon += 1 }
                }
            }
        }

        if i + 1 > 30 { lowest = min(lowest, bal); if bal < SimBoxRules.floor { below400 = true } }
        daily.append(bal)
        if wantTrace {
            tr.raw.append(raw); tr.final.append(final); tr.pauses.append(pauses); tr.calm.append(calmHours)
            tr.building.append(started ? drawn?.id : nil)
            tr.nightCoins.append(coins); tr.achievementCoins.append(dayAch); tr.napOutcome.append(napOutcome)
        }
        if simCheckpoints.contains(i + 1) {
            var snap = s
            snap.balance = bal; snap.below400 = below400; snap.largestPrize = largest
            let window = daily.suffix(100)
            snap.avgBalance = Double(window.reduce(0, +)) / Double(window.count)
            snap.lowestAfter30 = lowest == Int.max ? -1 : lowest
            snap.owned = owned.map(\.count)
            out.snaps.append(snap)
        }
    }
    if wantTrace { out.trace = tr }
    return out
}

// MARK: - Parallel batch

final class SimResultSlots<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T?]
    init(count: Int) { items = Array(repeating: nil, count: count) }
    func set(_ i: Int, _ v: T) { lock.lock(); items[i] = v; lock.unlock() }
    var values: [T] { items.map { $0! } }
}

func simulateBatch(_ cfg: SimConfig, runs: Int, catalog: Catalog, calendar: SimCalendar) -> [SimRun] {
    let box = SimResultSlots<SimRun>(count: runs)
    DispatchQueue.concurrentPerform(iterations: runs) { r in
        box.set(r, simulate(cfg, run: r, catalog: catalog, calendar: calendar))
    }
    return box.values
}
