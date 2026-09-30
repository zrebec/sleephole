import Foundation

/// All thresholds of the night rules in one place (plan §5.4, owner rules of 2026-09-29).
public struct SleepRules: Codable, Equatable, Sendable {
    /// "Začať stavbu" is possible until bedtime + 5 min; later the night is missed.
    public var startDeadline: TimeInterval = 5 * 60
    /// Setup time after bedtime: the app may be in the background from the start until
    /// max(start, bedtime) + setupGrace (owner, 2026-09-30: starting at 20:51 for a 21:00 bedtime gives
    /// 9 + 5 = 14 min to set up a podcast, a story, selfies…).
    public var setupGrace: TimeInterval = 5 * 60
    /// After the grace period ANY user-initiated background collapses the building (like SleepTown),
    /// except for this tiny tolerance for an accidental swipe.
    public var accidentalTolerance: TimeInterval = 10
    /// Detecting "left the app" takes ~3 s (lock signals arrive late); the owner gets the full
    /// `accidentalTolerance` AFTER the warning notification (owner, 2026-09-29).
    public var noticeDelay: TimeInterval = 3
    /// The alarm rings at most this long.
    public var alarmDuration: TimeInterval = 2 * 60
    public init() {}
}

public enum NightEvaluator {
    /// Intervals the owner spent OUTSIDE the app with the phone unlocked, clipped to [start, wake],
    /// minus phone calls (system-forced, excused). Plan §5.3.
    public static func awayIntervals(_ log: NightLog) -> [(Date, Date)] {
        guard let start = log.startedAt else { return [] }
        let end = log.window.wake
        var away: [(Date, Date)] = [], calls: [(Date, Date)] = []
        var awaySince: Date?, callSince: Date?
        for e in log.sortedEvents {
            switch e.kind {
            case .leftApp:
                awaySince = awaySince ?? e.at
            case .returned, .locked, .confirmed:
                if let s = awaySince { away.append((s, e.at)); awaySince = nil }
            case .appLaunched:
                awaySince = nil     // the app was killed – unknown what happened → owner's favour
                callSince = nil
            case .callStarted:
                callSince = callSince ?? e.at
            case .callEnded:
                if let s = callSince { calls.append((s, e.at)); callSince = nil }
            default:
                break
            }
        }
        if let s = awaySince { away.append((s, end)) }      // left and never came back
        if let s = callSince { calls.append((s, end)) }
        return away
            .map { (max($0.0, start), min($0.1, end)) }
            .filter { $0.0 < $0.1 }
            .flatMap { subtract(calls, from: $0) }
    }

    public static func awaySeconds(_ log: NightLog) -> TimeInterval {
        awayIntervals(log).reduce(0) { $0 + $1.1.timeIntervalSince($1.0) }
    }

    /// When the building collapsed, or nil. Away time inside the setup grace is free; after it,
    /// staying away longer than the accidental tolerance collapses the building.
    public static func collapsedAt(_ log: NightLog, rules: SleepRules = SleepRules()) -> Date? {
        guard let start = log.startedAt else { return nil }
        let graceEnd = log.window.setupEnds(start: start, rules: rules)
        for (a, b) in awayIntervals(log) {
            let from = max(a, graceEnd)
            let allowed = rules.accidentalTolerance + rules.noticeDelay
            if b.timeIntervalSince(from) > allowed { return from + allowed }
        }
        return nil
    }

    /// Outcome (owner rules of 2026-09-29):
    /// missed – not started by bedtime + 5 min · ruins – collapsed, abandoned or not confirmed within
    /// wake + 60 min · unfinished – confirmed after the alarm stopped (wake + 2…60 min) · complete – otherwise.
    public static func evaluate(_ log: NightLog?, rules: SleepRules = SleepRules()) -> Outcome {
        guard let log, let start = log.startedAt,
              start <= log.window.bedtime + rules.startDeadline else { return .missed }
        if log.has(.abandoned) || collapsedAt(log, rules: rules) != nil { return .ruins }
        guard let confirm = log.confirmedAt, confirm <= log.window.confirmLateUntil else { return .ruins }
        return confirm > log.window.confirmOnTimeUntil ? .unfinished : .complete
    }

    /// `interval` minus all `holes`.
    static func subtract(_ holes: [(Date, Date)], from interval: (Date, Date)) -> [(Date, Date)] {
        var pieces = [interval]
        for h in holes {
            pieces = pieces.flatMap { p -> [(Date, Date)] in
                guard h.0 < p.1, h.1 > p.0 else { return [p] }
                return [(p.0, h.0), (h.1, p.1)].filter { $0.0 < $0.1 }
            }
        }
        return pieces
    }

    public static func result(for log: NightLog?, key: NightKey, rules: SleepRules = SleepRules()) -> NightResult {
        NightResult(key: key, outcome: evaluate(log, rules: rules), buildingId: log?.buildingId,
                    awaySeconds: log.map(awaySeconds) ?? 0,
                    startedAt: log?.startedAt, confirmedAt: log?.confirmedAt)
    }
}

extension NightWindow {
    /// End of the setup time for a night started at `start`: until bedtime + grace, or start + grace
    /// when started after bedtime (never less than the full grace).
    public func setupEnds(start: Date, rules: SleepRules = SleepRules()) -> Date {
        max(start, bedtime) + rules.setupGrace
    }

    /// "Začať stavbu" is enabled in [startOpens, startCloses].
    public func startCloses(_ rules: SleepRules = SleepRules()) -> Date { bedtime + rules.startDeadline }
    public func canStart(at t: Date, rules: SleepRules = SleepRules()) -> Bool {
        t >= startOpens && t <= startCloses(rules)
    }
    /// "Vstal som" (shake or code) is enabled in [confirmOpens, confirmLateUntil].
    public func canConfirm(at t: Date) -> Bool { t >= confirmOpens && t <= confirmLateUntil }
}
