import Foundation
import SleepCore
import SwiftData

/// Coins spent (owner 2026-09-30: renaming the town; the building shop later). The balance is
/// earned (replayed from nights, naps, achievements) − spent (these rows).
@Model
final class CoinSpend {
    @Attribute(.unique) var id: String = UUID().uuidString
    var at: Date
    var amount: Int
    /// "rename-town", later "shop:<building id>" …
    var reason: String

    init(at: Date, amount: Int, reason: String) {
        self.at = at
        self.amount = amount
        self.reason = reason
    }
}

/// Every change of bedtime / wake (owner 2026-09-30). A change outside the free window resets the 🔥 streak
/// from `breakKey` (tonight's night) – see `SchedulePolicy`.
@Model
final class ScheduleChange {
    @Attribute(.unique) var id: String = UUID().uuidString
    var at: Date
    /// "22:30–6:30"
    var from: String
    var to: String
    var free: Bool
    /// The night that starts a new streak (NightKey string) – only for changes that were not free.
    var breakKey: String?
    /// 1 = made under the change-week rule (build 8, never a `breakKey`); nil = made under the old rule.
    var rule: Int?

    init(at: Date, from: String, to: String, free: Bool, breakKey: String?, rule: Int? = nil) {
        self.rule = rule
        self.at = at
        self.from = from
        self.to = to
        self.free = free
        self.breakKey = breakKey
    }
}

/// A joker 🛡️ the owner switched on (owner 2026-10-02). The automatic bronze ones are not stored – they are
/// replayed from the nights (`Jokers.apply`), like the town and the coins.
@Model
final class JokerRecord {
    @Attribute(.unique) var id: String = UUID().uuidString
    var at: Date
    var tierRaw: String
    /// NightKey string of the first protected night.
    var firstNight: String
    /// The id of the `BoxRecord` whose joker this use spent (build 11); nil = a joker of the month's own slot (an optional
    /// column → a lightweight migration, existing stores open unchanged).
    var boxId: String?

    init(at: Date, tier: JokerTier, firstNight: NightKey, boxId: String? = nil) {
        self.at = at
        self.tierRaw = tier.rawValue
        self.firstNight = firstNight.description
        self.boxId = boxId
    }

    var use: JokerUse? {
        guard let tier = JokerTier(rawValue: tierRaw), let key = NightKey(firstNight) else { return nil }
        return JokerUse(tier: tier, firstNight: key, boxId: boxId)
    }
}

/// A mystery box 📦 bought with coins (build 11, plan §10 REL 11b) – ONE immutable record; nothing about boxes is a
/// counter (boxes this month, jokers held, collectibles owned and the coins a box moved are derived by `Boxes`).
@Model
final class BoxRecord {
    @Attribute(.unique) var id: String = UUID().uuidString
    var at: Date
    /// NightKey string of the complete night this box follows (the purchase morning's date).
    var nightKey: String
    var price: Int
    /// The draw's `UInt64` seed stored losslessly as its bit pattern in an `Int64` (SwiftData has no unsigned column).
    var seedBits: Int64
    var tableVersion: Int
    /// `BoxPrize.encoded`.
    var prizeRaw: String
    var payout: Int

    init(id: String = UUID().uuidString, at: Date, nightKey: NightKey, price: Int, seed: UInt64, tableVersion: Int,
         prize: BoxPrize, payout: Int) {
        self.id = id
        self.at = at
        self.nightKey = nightKey.description
        self.price = price
        self.seedBits = Int64(bitPattern: seed)
        self.tableVersion = tableVersion
        self.prizeRaw = prize.encoded
        self.payout = payout
    }

    convenience init(_ p: BoxPurchase) {
        self.init(id: p.id, at: p.at, nightKey: p.nightKey, price: p.price, seed: p.seed, tableVersion: p.tableVersion,
                  prize: p.prize, payout: p.payout)
    }

    var seed: UInt64 { UInt64(bitPattern: seedBits) }

    /// nil only when the stored night key is unreadable (a corrupt row). An unreadable PRIZE (a later build's kind) is kept as
    /// `.unknown`: the box still counts for coins and the box counts.
    var purchase: BoxPurchase? {
        guard let key = NightKey(nightKey) else { return nil }
        return BoxPurchase(id: id, at: at, nightKey: key, price: price, seed: seed, tableVersion: tableVersion,
                           prize: BoxPrize(stored: prizeRaw), payout: payout)
    }
}
