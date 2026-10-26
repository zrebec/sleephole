import Foundation

/// "Another building" (build 11b6, owner 2026-10-26): during the setup of a night the building can be drawn again for
/// coins – 400 🪙 the first time, 800 🪙 the second, then no more that night. Nothing is counted: every draw is a
/// `CoinSpend` row whose reason names the night and the building drawn away from, and the draws made tonight are read
/// back from those reasons.
public enum Reroll {
    /// At most this many draws per night. Change it here only.
    public static let maxPerNight = 2
    /// The first draw costs this; the next ones a multiple of it (`price(drawsMade:)`).
    public static let basePrice = 400

    /// Price of the next draw after `drawsMade` draws tonight; nil once the maximum is reached.
    public static func price(drawsMade: Int) -> Int? {
        guard drawsMade >= 0, drawsMade < maxPerNight else { return nil }
        return basePrice * (drawsMade + 1)
    }

    static let prefix = "reroll-"

    /// The `CoinSpend` reason of a draw on night `nightKey` that replaces building `from`.
    public static func reason(nightKey: String, from: String) -> String { "\(prefix)\(nightKey):\(from)" }

    /// The buildings drawn away from tonight, in the order of `reasons`; reasons of other nights or kinds are ignored.
    /// The number of draws made tonight is its `count`.
    public static func drawnAway(nightKey: String, reasons: [String]) -> [String] {
        let head = "\(prefix)\(nightKey):"
        return reasons.compactMap { $0.hasPrefix(head) ? String($0.dropFirst(head.count)) : nil }
    }
}
