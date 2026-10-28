import Foundation

/// Mystery box rules (step 11b3, owner's answers 2026-10-25/26/27, plan §10 REL 11b): the collectible catalog, the price,
/// what may be bought now, the odds table and the draw. Pure functions of the dated box records – nothing here is a
/// counter. The ids in `BoxCatalog` are PERSISTED in box records forever: never rename one, only add.

/// The collectibles a box can give (ids are persisted – never rename).
public enum BoxCatalog {
    public static func ids(_ kind: CollectibleKind) -> [String] {
        switch kind {
        case .postcard: (1...30).map { String(format: "postcard-%02d", $0) }
        case .decoration: (1...12).map { String(format: "decoration-%02d", $0) }
        case .accessory: ["nightcap", "top-hat", "builder-helmet", "sunglasses", "fish-bowl", "rug"]
        case .sky: (1...4).map { String(format: "sky-%02d", $0) }
        }
    }

    public static func size(_ kind: CollectibleKind) -> Int { ids(kind).count }
}

/// What a roll of the odds table gives (before the rules of "missing first" and "one joker held" are applied).
public enum BoxRoll: Equatable, Sendable {
    /// A multiple of the price paid, in tenths (5 = 0.5×).
    case coins(tenths: Int)
    case luckyNight
    case collectible(CollectibleKind)
    case joker(JokerTier)
}

/// The result of one draw.
public struct BoxDraw: Equatable, Sendable {
    public let roll: BoxRoll
    public let prize: BoxPrize
    public let payout: Int
}

/// What the shop may offer this morning.
public enum BoxOffer: Equatable, Sendable {
    /// One box a day: a box already follows this morning's night.
    case alreadyBoughtToday
    /// Nine boxes this month – none until the 1st of the next month.
    case monthFull
    /// Only a complete real night opens a box.
    case needsCompleteNight
    case notEnoughCoins(price: Int, missing: Int, boxNumber: Int)
    case available(price: Int, boxNumber: Int)
}

public enum BoxRules {
    /// Version of the odds table, stamped on every box (a later table never re-draws an old box).
    public static let tableVersion = 1
    public static let floorPrice = 400
    public static let maxPerMonth = 9
    /// The balance that must stay after a purchase (one silver joker) – except for the town's very first box.
    public static let reserve = JokerTier.silver.price

    /// Share of the balance by the month's box number (1-based): 1–3 → 20 %, 4–6 → 40 %, 7–9 → 60 %; nil after the 9th.
    public static func percent(boxNumber n: Int) -> Int? {
        switch n {
        case 1...3: 20
        case 4...6: 40
        case 7...9: 60
        default: nil
        }
    }

    /// max(400, share of the balance) rounded down to 10; nil after the 9th box. No affordability check.
    public static func price(balance: Int, boxNumber n: Int) -> Int? {
        guard let pct = percent(boxNumber: n) else { return nil }
        return max(floorPrice, max(balance, 0) * pct / 100) / 10 * 10
    }

    /// The balance covers the price and (unless it is the town's very first box) leaves the reserve.
    public static func canAfford(balance: Int, price: Int, firstEver: Bool) -> Bool {
        balance >= price && (firstEver || balance - price >= reserve)
    }

    /// How many more coins are needed: the smallest `d >= 0` for which the box is affordable at `balance + d`.
    /// The price depends on the balance and is rounded down to 10, so affordability is NOT monotone in the balance
    /// (box 7: 2480 ok, 2489 not, 2490 ok) – the search therefore walks upward from the balance instead of solving
    /// for it. Negative balances count as 0. nil after the 9th box.
    public static func coinsMissing(balance: Int, boxNumber n: Int, firstEver: Bool) -> Int? {
        guard percent(boxNumber: n) != nil else { return nil }
        let start = max(balance, 0)
        for d in 0...100_000 {
            let b = start + d
            if let p = price(balance: b, boxNumber: n), canAfford(balance: b, price: p, firstEver: firstEver) { return d }
        }
        return nil
    }

    /// What may be bought on the day `today` (the purchase day's date as a night key – the night that ended this morning
    /// has this key). `todaysNight`: that night's outcome after jokers; nil when no finished REAL night has this key
    /// (naps and test nights never count – the caller passes only real nights). Checked in this order.
    public static func offer(today: NightKey, todaysNight: Outcome?, boxes: [BoxPurchase], balance: Int) -> BoxOffer {
        if Boxes.bought(on: today, boxes: boxes) { return .alreadyBoughtToday }
        let inMonth = Boxes.count(inMonthOf: today, boxes: boxes)
        if inMonth >= maxPerMonth { return .monthFull }
        if todaysNight != .complete { return .needsCompleteNight }
        let number = inMonth + 1
        let bal = max(balance, 0)
        let price = self.price(balance: bal, boxNumber: number)!
        let firstEver = boxes.isEmpty
        if canAfford(balance: bal, price: price, firstEver: firstEver) { return .available(price: price, boxNumber: number) }
        return .notEnoughCoins(price: price, missing: coinsMissing(balance: bal, boxNumber: number, firstEver: firstEver) ?? 0,
                               boxNumber: number)
    }

    // MARK: odds

    public struct Odds: Equatable, Sendable {
        public let roll: BoxRoll
        /// Tenths of a percent (the table sums to 1000).
        public let permille: Int
    }

    /// The odds table, version `tableVersion` ("D" of the owner's simulation); shown to the user before buying.
    public static let odds: [Odds] = [
        Odds(roll: .coins(tenths: 5), permille: 250),
        Odds(roll: .coins(tenths: 10), permille: 100),
        Odds(roll: .coins(tenths: 20), permille: 40),
        Odds(roll: .coins(tenths: 30), permille: 8),
        Odds(roll: .luckyNight, permille: 80),
        Odds(roll: .collectible(.postcard), permille: 250),
        Odds(roll: .collectible(.decoration), permille: 120),
        Odds(roll: .collectible(.accessory), permille: 70),
        Odds(roll: .collectible(.sky), permille: 50),
        Odds(roll: .joker(.bronze), permille: 30),
        Odds(roll: .joker(.silver), permille: 2),
    ]

    /// Which row of the table a number 0..<1000 falls in.
    public static func roll(permille: Int) -> BoxRoll {
        var acc = 0
        for o in odds { acc += o.permille; if permille < acc { return o.roll } }
        return odds[odds.count - 1].roll
    }

    // MARK: the draw

    /// The draw is a pure function of its inputs; the seed is stored with the box so a replay draws the same box.
    /// The generator's raw output is mapped here by hand – the standard library's `random(in:using:)`, `shuffle` and
    /// `randomElement` may change their algorithms, which would re-draw old boxes.
    public static func draw(seed: UInt64, price: Int, nightKey: NightKey, boxes: [BoxPurchase], uses: [JokerUse],
                            calendar: Calendar) -> BoxDraw {
        var g = SeededGenerator(seed: seed)
        let roll = self.roll(permille: Int(g.next() % 1000))
        switch roll {
        case .coins(let tenths):
            return BoxDraw(roll: roll, prize: .coins, payout: price * tenths / 10)
        case .luckyNight:
            return BoxDraw(roll: roll, prize: .luckyNight, payout: 0)
        case .collectible(let kind):
            let all = BoxCatalog.ids(kind)
            let owned = Boxes.owned(kind, boxes: boxes)
            let missing = all.filter { !owned.contains($0) }
            if missing.isEmpty {   // a complete collection: a duplicate, paid back in coins
                let id = all[Int(g.next() % UInt64(all.count))]
                return BoxDraw(roll: roll, prize: .collectible(kind, id: id), payout: price / 4)
            }
            let id = missing[Int(g.next() % UInt64(missing.count))]
            return BoxDraw(roll: roll, prize: .collectible(kind, id: id), payout: 0)
        case .joker(let tier):
            let held = Boxes.heldJokers(boxes: boxes, uses: uses, at: nightKey.adding(days: 1, calendar: calendar),
                                        calendar: calendar)
            return BoxDraw(roll: roll, prize: .joker(tier), payout: held[tier] != nil ? price / 4 : 0)
        }
    }

    /// The record of a purchase with the table version stamped.
    public static func purchase(id: String, at: Date, nightKey: NightKey, price: Int, seed: UInt64,
                                boxes: [BoxPurchase], uses: [JokerUse], calendar: Calendar) -> BoxPurchase {
        let d = draw(seed: seed, price: price, nightKey: nightKey, boxes: boxes, uses: uses, calendar: calendar)
        return BoxPurchase(id: id, at: at, nightKey: nightKey, price: price, seed: seed, tableVersion: tableVersion,
                           prize: d.prize, payout: d.payout)
    }
}
