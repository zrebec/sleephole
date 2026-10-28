import Foundation

/// Mystery boxes 📦 (owner 2026-10-25/26, plan §10 REL 11b) – bought with coins only, never with money. This file holds
/// the RECORD of a purchase and everything derived from the records. The price rules, the odds and the draw are step
/// 11b3; nothing here is ever stored as a counter: "boxes this month", the joker held, the collectibles owned and the
/// coins a box moved are all recomputed from the dated purchases (the owner's rule: "it must not get mixed up").

/// What a collection holds (plan 11b: 30 postcards, 12 decorations, 6 cat accessories, 4 night skies).
public enum CollectibleKind: String, Codable, CaseIterable, Sendable {
    case postcard, decoration, accessory, sky
}

/// What came out of a box.
public enum BoxPrize: Equatable, Sendable {
    /// A coin prize – the amount is the box's `payout`.
    case coins
    /// A lucky night ×2 (the ledger rule is 11b3).
    case luckyNight
    /// A collectible; a duplicate has still this prize and its coins in `payout`.
    case collectible(CollectibleKind, id: String)
    /// A joker won from the box – bronze or silver, never gold.
    case joker(JokerTier)
    /// A prize this build cannot read (a kind added by a later build, reached here by a sync or a downgrade). The box still
    /// counts for coins and the box counts; only the rules that depend on its prize skip it. The text is kept verbatim.
    case unknown(String)

    /// The stored form: `coins`, `lucky`, `item:<kind>:<id>` (the id may contain colons), `joker:<tier>`.
    public var encoded: String {
        switch self {
        case .coins: "coins"
        case .luckyNight: "lucky"
        case .collectible(let kind, let id): "item:\(kind.rawValue):\(id)"
        case .joker(let tier): "joker:\(tier.rawValue)"
        case .unknown(let raw): raw
        }
    }

    /// Reads a stored prize and never fails: what `init?(encoded:)` cannot read becomes `.unknown` with the text unchanged,
    /// so it round-trips through the backup and the sync file.
    public init(stored: String) {
        self = BoxPrize(encoded: stored) ?? .unknown(stored)
    }

    /// Strict: nil for anything this version cannot read (garbled, a gold joker, an empty id, a kind from a later build).
    public init?(encoded: String) {
        let p = encoded.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        switch (p.first, p.count) {
        case ("coins"?, 1): self = .coins
        case ("lucky"?, 1): self = .luckyNight
        case ("item"?, 3):
            guard let kind = CollectibleKind(rawValue: p[1]), !p[2].isEmpty else { return nil }
            self = .collectible(kind, id: p[2])
        case ("joker"?, 2):
            guard let tier = JokerTier(rawValue: p[1]), tier != .gold else { return nil }
            self = .joker(tier)
        default: return nil
        }
    }
}

/// One box bought with coins – one immutable record.
public struct BoxPurchase: Equatable, Sendable {
    public let id: String
    /// The purchase moment.
    public let at: Date
    /// The complete night this box follows. The key is the MORNING date, so it is the purchase morning's date; the month
    /// the box counts in is the month of this key.
    public let nightKey: NightKey
    public let price: Int
    /// The seed the draw ran with – a replay (a sync, a restore) draws the same box.
    public let seed: UInt64
    /// The odds table the draw used – a later table never re-draws an old box.
    public let tableVersion: Int
    public let prize: BoxPrize
    /// The coins the box paid out: a coin prize, or what a duplicate collectible turned into; 0 otherwise.
    public let payout: Int

    public init(id: String, at: Date, nightKey: NightKey, price: Int, seed: UInt64, tableVersion: Int,
                prize: BoxPrize, payout: Int) {
        self.id = id
        self.at = at
        self.nightKey = nightKey
        self.price = price
        self.seed = seed
        self.tableVersion = tableVersion
        self.prize = prize
        self.payout = payout
    }
}

public enum Boxes {
    /// What all boxes did to the balance: Σ payout − Σ price.
    public static func coinDelta(_ boxes: [BoxPurchase]) -> Int {
        boxes.reduce(0) { $0 + $1.payout - $1.price }
    }

    /// Boxes bought in the calendar month of `key` (by the box's night key).
    public static func count(inMonthOf key: NightKey, boxes: [BoxPurchase]) -> Int {
        boxes.filter { $0.nightKey.year == key.year && $0.nightKey.month == key.month }.count
    }

    /// A box already bought after the night `key` ("one a day").
    public static func bought(on key: NightKey, boxes: [BoxPurchase]) -> Bool {
        boxes.contains { $0.nightKey == key }
    }

    /// The ids of the collectibles of that kind won so far (a duplicate adds nothing).
    public static func owned(_ kind: CollectibleKind, boxes: [BoxPurchase]) -> Set<String> {
        var ids = Set<String>()
        for b in boxes {
            if case .collectible(kind, let id) = b.prize { ids.insert(id) }
        }
        return ids
    }

    /// The same ids in the order they were won (oldest first, a duplicate keeps its first place) – the order the town
    /// decorations are placed in. `boxes` may come in any order: sorted by purchase moment, then id.
    public static func ownedInOrder(_ kind: CollectibleKind, boxes: [BoxPurchase]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for b in boxes.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            if case .collectible(kind, let id) = b.prize, seen.insert(id).inserted { out.append(id) }
        }
        return out
    }

    // MARK: jokers won from boxes

    /// A joker from a box lasts until the end of the NEXT month (a box on 31 Oct → through 30 Nov; 15 Dec 2026 → through
    /// 31 Jan 2027): the last day of the month after the box's own month.
    public static func expiry(of box: BoxPurchase, calendar: Calendar) -> NightKey {
        var year = box.nightKey.year, month = box.nightKey.month + 2
        if month > 12 { month -= 12; year += 1 }
        return NightKey(year: year, month: month, day: 1).adding(days: -1, calendar: calendar)
    }

    /// Is this box's joker usable on the night `key`: after the purchase night, up to and including the expiry.
    public static func isValid(_ box: BoxPurchase, at key: NightKey, calendar: Calendar) -> Bool {
        key > box.nightKey && key <= expiry(of: box, calendar: calendar)
    }

    /// The one notion of "a joker won from a box": the tier of a `.joker` prize that was really kept (not gold, payout 0).
    /// A `.joker` prize with a payout is a converted one (the tier was already held) – nobody holds it.
    public static func wonJoker(_ box: BoxPurchase) -> JokerTier? {
        guard case .joker(let tier) = box.prize, tier != .gold, box.payout == 0 else { return nil }
        return tier
    }

    /// For each tier the box joker that is valid at `key` and not used yet (if several, the one that expires first).
    /// "One of each kind held at a time" is a draw rule (11b3) – this only reports what is held.
    public static func heldJokers(boxes: [BoxPurchase], uses: [JokerUse], at key: NightKey,
                                  calendar: Calendar) -> [JokerTier: BoxPurchase] {
        let usedIds = Set(uses.compactMap(\.boxId))
        var held: [JokerTier: BoxPurchase] = [:]
        for b in boxes {
            guard let tier = wonJoker(b), !usedIds.contains(b.id),
                  isValid(b, at: key, calendar: calendar) else { continue }
            if let current = held[tier], (expiry(of: current, calendar: calendar), current.nightKey, current.id)
                <= (expiry(of: b, calendar: calendar), b.nightKey, b.id) { continue }
            held[tier] = b
        }
        return held
    }
}
