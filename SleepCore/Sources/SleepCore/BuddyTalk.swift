import Foundation

/// One sentence of the sleep buddy (owner 2026-10-14, phase TALK). The core decides WHICH sentences apply and in
/// which order; the app turns each case into a localized text.
public enum BuddyLine: Equatable, Sendable {
    // tier 1 – last night (the morning after only)
    case movedIn(buildingId: String, people: Int)
    case newSight(buildingId: String)
    case waiting(buildingId: String)
    case dayOff
    case streakSafe
    // tier 2 – bedtime
    case bedtimeSoon(Date)
    // tier 3 – streak
    case week
    case streak(Int)
    case newStreak
    // tier 4 – the town and what the residents say
    case size(TownSize, people: Int)
    case nextSize(missing: Int, TownSize)
    case firstNeighbours
    case parks(Int)
    case library
    case museum
    case tallest
    case noFireStation, noHospital, noPolice, noSchool, noTownHall
    case fireStation, hospital
    // tier 5 – everyday chatter
    case chatter(Int)
    case tonight

    /// Number of everyday chatter sentences (`chatter(0..<count)`).
    public static let chatterCount = 4

    public var tier: Int {
        switch self {
        case .movedIn, .newSight, .waiting, .dayOff, .streakSafe: 1
        case .bedtimeSoon: 2
        case .week, .streak, .newStreak: 3
        case .size, .nextSize, .firstNeighbours, .parks, .library, .museum, .tallest,
             .noFireStation, .noHospital, .noPolice, .noSchool, .noTownHall, .fireStation, .hospital: 4
        case .chatter, .tonight: 5
        }
    }
}

extension TownSize {
    /// Fewest residents of this size (inverse of `TownSize.of(residents:)`).
    public var minResidents: Int {
        switch self {
        case .hamlet: 0
        case .village: 100
        case .smallTown: 1_000
        case .town: 5_000
        case .city: 20_000
        case .bigCity: 100_000
        case .metropolis: 500_000
        }
    }

    /// The next bigger size, nil for the biggest.
    public var next: TownSize? {
        let all = TownSize.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
}

public struct BuddyTalkInput: Sendable {
    /// The last finalized REAL night (no debug night, no nap) with what it produced.
    public struct LastNight: Sendable {
        public let key: NightKey
        public let outcome: Outcome
        public let buildingId: String?
        public let residents: Int
        public init(key: NightKey, outcome: Outcome, buildingId: String?, residents: Int) {
            self.key = key; self.outcome = outcome; self.buildingId = buildingId; self.residents = residents
        }
    }

    public var now: Date
    public var calendar: Calendar
    public var town: TownSnapshot
    public var lastNight: LastNight?
    public var streak: Int
    public var bestStreak: Int
    public var builtNights: Int
    public var unlockedMaxLevel: Int
    public var nextBedtime: Date?

    public init(now: Date, calendar: Calendar, town: TownSnapshot, lastNight: LastNight?, streak: Int,
                bestStreak: Int, builtNights: Int, unlockedMaxLevel: Int, nextBedtime: Date?) {
        self.now = now; self.calendar = calendar; self.town = town; self.lastNight = lastNight
        self.streak = streak; self.bestStreak = bestStreak; self.builtNights = builtNights
        self.unlockedMaxLevel = unlockedMaxLevel; self.nextBedtime = nextBedtime
    }
}

public enum BuddyTalk {
    /// "Bedtime is soon" window.
    public static let bedtimeLead: TimeInterval = 2 * 3600

    /// The ordered sentences of the day: by tier, shuffled inside a tier from a generator seeded with the DAY
    /// (same day → same order on every device). The first one is the sentence of the day.
    public static func lines(_ input: BuddyTalkInput) -> [BuddyLine] {
        let today = NightKey(date: input.now, calendar: input.calendar)
        var rng = SeededGenerator(seed: Population.fnv1a64("buddy|\(today.description)"))
        let candidates = candidateLines(input, today: today)
        var out: [BuddyLine] = []
        for tier in 1...5 {
            out += shuffled(candidates.filter { $0.tier == tier }, &rng)
        }
        return out
    }

    /// The index after `index`, wrapping around to the first sentence.
    public static func next(after index: Int, count: Int) -> Int {
        count <= 0 ? 0 : (index + 1) % count
    }

    static func candidateLines(_ i: BuddyTalkInput, today: NightKey) -> [BuddyLine] {
        var c: [BuddyLine] = []
        let standing = i.town.buildings.filter { $0.state != .ruins }
        let people = Population.total(i.town)

        // tier 1 – only on the morning after the last real night
        if let n = i.lastNight, n.key == today {
            switch n.outcome {
            case .complete:
                if let id = n.buildingId {
                    c.append(n.residents > 0 ? .movedIn(buildingId: id, people: n.residents) : .newSight(buildingId: id))
                }
            case .unfinished:
                if let id = n.buildingId { c.append(.waiting(buildingId: id)) }
            case .ruins: c.append(.dayOff)
            case .excused: c.append(.streakSafe)
            case .missed: break
            }
        }
        // tier 2
        if let b = i.nextBedtime, b > i.now, b.timeIntervalSince(i.now) <= bedtimeLead { c.append(.bedtimeSoon(b)) }
        // tier 3
        if i.streak >= 7, i.streak % 7 == 0 { c.append(.week) }
        if i.streak >= 2 { c.append(.streak(i.streak)) }
        if i.streak == 0, i.bestStreak > 0 { c.append(.newStreak) }
        // tier 4
        if people > 0 {
            let size = TownSize.of(residents: people)
            c.append(.size(size, people: people))
            if let nxt = size.next { c.append(.nextSize(missing: nxt.minResidents - people, nxt)) }
        }
        if i.builtNights <= 5 { c.append(.firstNeighbours) }
        let parks = standing.filter { $0.buildingId.hasPrefix("l2-park") }.count
        if parks >= 1 { c.append(.parks(parks)) }
        if standing.contains(where: { $0.buildingId.hasPrefix("l2-library") }) { c.append(.library) }
        if standing.contains(where: { $0.buildingId.hasPrefix("l2-museum") }) { c.append(.museum) }
        if standing.contains(where: { $0.buildingId.hasPrefix("l4-") }) { c.append(.tallest) }
        let has = { (id: String) in standing.contains { $0.buildingId == id } }
        if i.unlockedMaxLevel >= 3 {
            if !has("l3-firestation") { c.append(.noFireStation) } else { c.append(.fireStation) }
            if !has("l3-hospital") { c.append(.noHospital) } else { c.append(.hospital) }
            if !has("l3-police") { c.append(.noPolice) }
            if !has("l3-school") { c.append(.noSchool) }
            if !has("l3-townhall") { c.append(.noTownHall) }
        } else {
            // present services are mentioned whatever the level (they can only stand once built)
            if has("l3-firestation") { c.append(.fireStation) }
            if has("l3-hospital") { c.append(.hospital) }
        }
        // tier 5
        for k in 0..<BuddyLine.chatterCount { c.append(.chatter(k)) }
        let soon = i.nextBedtime.map { $0 > i.now && $0.timeIntervalSince(i.now) <= bedtimeLead } ?? false
        if !soon { c.append(.tonight) }
        return c
    }

    /// Fisher–Yates with our own generator (the standard library's `shuffled(using:)` may change between releases).
    private static func shuffled(_ a: [BuddyLine], _ rng: inout SeededGenerator) -> [BuddyLine] {
        var a = a
        guard a.count > 1 else { return a }
        for k in stride(from: a.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(k + 1))
            a.swapAt(k, j)
        }
        return a
    }
}
