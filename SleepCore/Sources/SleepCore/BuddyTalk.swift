import Foundation

/// One sentence of the sleep buddy (owner 2026-10-14, phase TALK). The core decides WHICH sentences apply and in
/// which order; the app turns each case into a localized text.
public enum BuddyLine: Hashable, Sendable {
    // tier 1 – last night (the morning after only)
    case movedIn(buildingId: String, people: Int)
    case newSight(buildingId: String)
    case waiting(buildingId: String)
    case ruined(buildingId: String, repairsTonight: Bool)
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
    // tier 2/4/5 – the real sky (phase and date only, phase 8f)
    case fullMoonTonight, newMoonTonight, longestNight, shortestNight, equinox
    case fullMoonTomorrow, fullMoonSoon(days: Int)
    case moonPhase(MoonQuarter)
    // tier 5 – everyday chatter
    case chatter(Int)
    case tonight

    /// Number of everyday chatter sentences (`chatter(0..<count)`).
    public static let chatterCount = 4

    public var tier: Int {
        switch self {
        case .movedIn, .newSight, .waiting, .ruined, .streakSafe: 1
        case .bedtimeSoon, .fullMoonTonight, .newMoonTonight, .longestNight, .shortestNight, .equinox: 2
        case .week, .streak, .newStreak: 3
        case .size, .nextSize, .firstNeighbours, .parks, .library, .museum, .tallest,
             .noFireStation, .noHospital, .noPolice, .noSchool, .noTownHall, .fireStation, .hospital,
             .fullMoonTomorrow, .fullMoonSoon: 4
        case .chatter, .tonight, .moonPhase: 5
        }
    }

    /// News (owner 2026-10-15): what last night produced (tier 1) and what is about to happen (tier 2). A news line
    /// may open the bubble, once a day.
    public var isNews: Bool { tier <= 2 }

    /// A stable text key of the line (used to remember which news already led today).
    public var newsKey: String { String(describing: self) }
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

/// The six everyday moon phases of the buddy's sky sentence (bands in `BuddySky`).
public enum MoonQuarter: Hashable, Sendable, CaseIterable {
    case waxingCrescent, firstQuarter, waxingGibbous, waningGibbous, lastQuarter, waningCrescent
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
    /// The user's hemisphere (a city's latitude < 0, else the region) – decides which solstice is the longest night.
    public var southernHemisphere: Bool

    public init(now: Date, calendar: Calendar, town: TownSnapshot, lastNight: LastNight?, streak: Int,
                bestStreak: Int, builtNights: Int, unlockedMaxLevel: Int, nextBedtime: Date?,
                southernHemisphere: Bool = false) {
        self.southernHemisphere = southernHemisphere
        self.now = now; self.calendar = calendar; self.town = town; self.lastNight = lastNight
        self.streak = streak; self.bestStreak = bestStreak; self.builtNights = builtNights
        self.unlockedMaxLevel = unlockedMaxLevel; self.nextBedtime = nextBedtime
    }
}

public enum BuddyTalk {
    /// "Bedtime is soon" window.
    public static let bedtimeLead: TimeInterval = 2 * 3600

    /// The sentences that are AVAILABLE now (by the town, the residents, the buildings, the level, the sky), in a
    /// fixed order by tier. The order means nothing: the bubble draws from them at random (`BuddyBag`).
    public static func lines(_ input: BuddyTalkInput) -> [BuddyLine] {
        let today = NightKey(date: input.now, calendar: input.calendar)
        let candidates = candidateLines(input, today: today)
        return (1...5).flatMap { tier in candidates.filter { $0.tier == tier } }
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
            case .ruins:
                // Name the collapsed building and tell the truth about its repair (the same rule as the town's).
                if let idx = i.town.buildings.firstIndex(where: { $0.nightKey == n.key && $0.state == .ruins }) {
                    let b = i.town.buildings[idx]
                    if b.placement.catalogId == b.buildingId {
                        let tonight = today.adding(days: 1, calendar: i.calendar)
                        let helped = TownBuilder.helpedByCompleteNight(in: i.town, before: tonight)
                        c.append(.ruined(buildingId: b.buildingId, repairsTonight: helped == idx))
                    }
                }
            case .excused: c.append(.streakSafe)
            case .missed: break
            }
        }
        // tier 2
        if let b = i.nextBedtime, b > i.now, b.timeIntervalSince(i.now) <= bedtimeLead { c.append(.bedtimeSoon(b)) }
        // the real sky: tiers 2, 4 and 5
        c += BuddySky.lines(day: today, calendar: i.calendar, southernHemisphere: i.southernHemisphere)
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
}

/// The state of the buddy's bubble (owner 2026-10-15): the news of the day first, then a random sentence without
/// repeats – a shuffle bag. A round ends when every available sentence has been heard; the next one starts at once
/// (never with the sentence on screen). The set of available sentences may change at any moment: sentences that
/// disappear are never shown, new ones join the round, and the sentence on screen never changes by itself.
public struct BuddyBag: Sendable {
    /// The sentence on screen.
    public private(set) var current: BuddyLine?
    /// What this round has shown already.
    private var heard: Set<BuddyLine> = []

    public init() {}

    /// A fresh start (Today appears / the app returns): a news line that has not led today leads (tier 1 before
    /// tier 2, random among equals), otherwise a random available sentence. `ledToday` holds the `newsKey`s that led.
    @discardableResult
    public mutating func open<G: RandomNumberGenerator>(available: [BuddyLine], ledToday: Set<String>,
                                                       using g: inout G) -> BuddyLine? {
        heard = []
        let news = available.filter { $0.isNews && !ledToday.contains($0.newsKey) }
        let pool: [BuddyLine]
        if let tier = news.map(\.tier).min() { pool = news.filter { $0.tier == tier } } else { pool = available }
        return show(pool.randomElement(using: &g))
    }

    /// A tap: a random available sentence not yet heard in this round and not the one on screen.
    @discardableResult
    public mutating func next<G: RandomNumberGenerator>(available: [BuddyLine], using g: inout G) -> BuddyLine? {
        let avail = Set(available)
        heard = heard.intersection(avail)      // gone sentences are forgotten, new ones are simply not heard yet
        var pool = available.filter { !heard.contains($0) && $0 != current }
        if pool.isEmpty {                      // the round is over: a new one, never starting with the line on screen
            heard = current.map { [$0] } ?? []
            pool = available.filter { $0 != current }
        }
        guard let pick = pool.randomElement(using: &g) else { return current }   // only one sentence exists
        return show(pick)
    }

    /// Shows a given sentence (the Debug `-buddyLine` aid).
    @discardableResult
    public mutating func force(_ line: BuddyLine) -> BuddyLine? { show(line) }

    private mutating func show(_ line: BuddyLine?) -> BuddyLine? {
        current = line
        if let line { heard.insert(line) }
        return line
    }
}
