import Foundation
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

    init(at: Date, from: String, to: String, free: Bool, breakKey: String?) {
        self.at = at
        self.from = from
        self.to = to
        self.free = free
        self.breakKey = breakKey
    }
}
