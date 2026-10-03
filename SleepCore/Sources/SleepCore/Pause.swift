import Foundation

/// The night pause (owner 2026-10-02, D17): a bathroom trip and ten minutes of reading must not collapse the
/// building – but it must never turn into a habit. A pause is started on purpose with a button on the night
/// screen; the first one of a night is free, every further one costs 50 🪙 more; a complete night without any
/// pause pays a bonus instead.
public enum PausePolicy {
    public static let duration: TimeInterval = 10 * 60
    /// Extra coins for a complete night without a pause ("undisturbed night").
    public static let undisturbedBonus = 30
    public static let priceStep = 50

    /// Price of the `number`-th pause of a night (1 = the first): 0, 50, 100, 150 …
    public static func price(number: Int) -> Int { max(0, number - 1) * priceStep }

    public enum Block: Equatable, Sendable {
        case nap                        // a nap has no pause (30–60 min)
        case collapsed                  // nothing left to protect
        case setup(until: Date)         // during the setup the app may be left anyway
        case running(until: Date)       // a pause is on
        case notEnoughCoins(missing: Int)
    }

    /// The end of the pause that is on at `t`, if any.
    public static func activeUntil(_ log: NightLog, at t: Date) -> Date? {
        log.pauseIntervals.last { $0.0 <= t && t < $0.1 }?.1
    }

    /// Why a pause can't be started at `t` (nil = it can). `coins`: the owner's balance.
    public static func block(_ log: NightLog, rules: SleepRules = SleepRules(), at t: Date, coins: Int,
                             isNap: Bool = false) -> Block? {
        if isNap { return .nap }
        if let collapsed = NightEvaluator.collapsedAt(log, rules: rules), collapsed <= t { return .collapsed }
        if let start = log.startedAt {
            let setupEnds = log.window.setupEnds(start: start, rules: rules)
            if t < setupEnds { return .setup(until: setupEnds) }
        }
        if let until = activeUntil(log, at: t) { return .running(until: until) }
        let price = price(number: log.pauseStarts.count + 1)
        return coins < price ? .notEnoughCoins(missing: price - coins) : nil
    }
}
