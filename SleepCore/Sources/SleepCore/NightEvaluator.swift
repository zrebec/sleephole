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
    /// All trips out of the app after the setup (outside pauses and calls) share this budget of seconds per
    /// night (2026-10-03: several trips of 6–7 s within a minute used to pass). A single trip is still
    /// limited to `noticeDelay + accidentalTolerance`. A trip that STARTS while some budget is left is always a
    /// full trip with the full warning (the budget never shortens a trip); a trip that starts with the budget
    /// used up collapses the building at once. nil = no budget (nights from before 2026-10-03).
    public var awayBudget: TimeInterval? = 30
    /// Using the phone on the lock screen (`.usedLockScreen`) is a trip out of the app (strict mode). The default
    /// is true so every stored night and every old test keeps its meaning; the app sets it to false for the nights
    /// it starts while Strict mode is off ("care instead of enforcement", owner 2026-10-09): such a lock-screen
    /// trip stays in the journal but is no away time. A `.leftApp` inside it is a normal counted trip from then on.
    public var lockScreenCollapses = true
    public init() {}
}

/// How much of the night's budget of seconds out of the app is left (for the night screen).
public enum AwayBudgetState: Equatable, Sendable { case fine, low, spent }

public enum NightEvaluator {
    /// Intervals the owner spent OUTSIDE the app with the phone unlocked, clipped to [start, wake],
    /// minus phone calls (system-forced, excused) and pauses (D17). Plan §5.3.
    /// Closing the app (`.closedByOwner`, R4) is leaving it until the next `.appLaunched`; a death WITHOUT that
    /// notice and a phone restart (`.restartExcused`) are resolved in the owner's favour.
    /// With `rules.lockScreenCollapses == false` a lock-screen trip is no away time; a `.leftApp` inside it starts
    /// the counted trip at that moment.
    public static func awayIntervals(_ log: NightLog, rules: SleepRules = SleepRules()) -> [(Date, Date)] {
        guard let start = log.startedAt else { return [] }
        let end = log.window.wake
        var away: [(Date, Date)] = [], calls: [(Date, Date)] = []
        var awaySince: Date?, callSince: Date?
        var closed = false              // the open interval is owned by a closure: the relaunch ends it
        for e in log.sortedEvents {
            switch e.kind {
            case .usedLockScreen where !rules.lockScreenCollapses:
                break               // gentle mode: logged, but no away time
            case .leftApp, .usedLockScreen:
                awaySince = awaySince ?? e.at
            case .closedByOwner:
                awaySince = awaySince ?? e.at
                closed = true
            case .returned, .locked, .confirmed:
                if let s = awaySince { away.append((s, e.at)); awaySince = nil }
                closed = false
            case .appLaunched:
                if closed, let s = awaySince {
                    away.append((s, e.at))      // the owner opened the app again
                }
                awaySince = nil     // otherwise the app was killed – unknown what happened → owner's favour
                closed = false
                callSince = nil
            case .restartExcused:
                awaySince = nil     // the phone restarted: the closure was not the owner's doing
                closed = false
            case .forgiven where !log.has(.forgivenessRevoked):
                away.removeAll(); awaySince = nil; closed = false      // calls and pauses are untouched
            case .callStarted:
                callSince = callSince ?? e.at
            case .callEnded:
                if let s = callSince { calls.append((s, e.at)); callSince = nil }
            default:
                break
            }
        }
        if let s = awaySince { away.append((s, end)) }      // left (or closed) and never came back
        if let s = callSince { calls.append((s, end)) }
        return away
            .map { (max($0.0, start), min($0.1, end)) }
            .filter { $0.0 < $0.1 }
            .flatMap { subtract(calls + log.pauseIntervals, from: $0) }
            .sorted { $0.0 < $1.0 }
    }

    public static func awaySeconds(_ log: NightLog, rules: SleepRules = SleepRules()) -> TimeInterval {
        awayIntervals(log, rules: rules).reduce(0) { $0 + $1.1.timeIntervalSince($1.0) }
    }

    /// When the building collapsed, or nil. Away time inside the setup grace is free; after it,
    /// staying away longer than the allowance (a full trip, or nothing once the budget is used up) collapses
    /// the building.
    public static func collapsedAt(_ log: NightLog, rules: SleepRules = SleepRules()) -> Date? {
        guard let start = log.startedAt else { return nil }
        let graceEnd = log.window.setupEnds(start: start, rules: rules)
        var used: TimeInterval = 0                       // seconds away after the setup so far
        for (a, b) in awayIntervals(log, rules: rules) {
            let from = max(a, graceEnd)
            guard b > from else { continue }
            let allowed = allowance(rules, used: used)
            if b.timeIntervalSince(from) > allowed { return from + allowed }
            used += b.timeIntervalSince(from)
        }
        return nil
    }

    /// How long one more trip may last: a full trip (never cut short by the budget) while some budget is left
    /// when it starts, nothing once the budget is used up.
    static func allowance(_ rules: SleepRules, used: TimeInterval) -> TimeInterval {
        let perTrip = rules.accidentalTolerance + rules.noticeDelay
        guard let budget = rules.awayBudget else { return perTrip }
        return used < budget ? perTrip : 0
    }

    /// What the night screen says about the budget at `t`: nil without a budget, `.spent` once it is used up,
    /// `.low` when less than one full trip is left, else `.fine`.
    public static func budgetState(_ log: NightLog, rules: SleepRules = SleepRules(), at t: Date) -> AwayBudgetState? {
        guard let budget = rules.awayBudget else { return nil }
        let left = budget - awayAfterSetup(log, rules: rules, until: t)
        if left <= 0 { return .spent }
        return left < rules.accidentalTolerance + rules.noticeDelay ? .low : .fine
    }

    /// Seconds spent out of the app after the setup, before `t` (outside pauses and calls) – what the night's
    /// budget is charged with.
    public static func awayAfterSetup(_ log: NightLog, rules: SleepRules = SleepRules(), until t: Date) -> TimeInterval {
        guard let start = log.startedAt else { return 0 }
        let graceEnd = log.window.setupEnds(start: start, rules: rules)
        return awayIntervals(log, rules: rules).reduce(0) { sum, i in
            let (from, to) = (max(i.0, graceEnd), min(i.1, t))
            return sum + max(0, to.timeIntervalSince(from))
        }
    }

    /// How long a trip that starts at `t` may last before the building collapses (for the "Come back" warning):
    /// 13 s while budget is left, 0 when it is used up.
    public static func allowance(_ log: NightLog, rules: SleepRules = SleepRules(), at t: Date) -> TimeInterval {
        allowance(rules, used: awayAfterSetup(log, rules: rules, until: t))
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
                    awaySeconds: log.map { awaySeconds($0, rules: rules) } ?? 0,
                    startedAt: log?.startedAt, confirmedAt: log?.confirmedAt,
                    pauses: rules.awayBudget == nil ? nil : log?.pauseStarts.count, bedtime: log?.window.bedtime)
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
