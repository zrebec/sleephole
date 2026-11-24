import Foundation

/// What the log says about a phone call and a trip out of the app RIGHT NOW – the rule-side state the warnings follow
/// (13ae, B55). It never changes what a night counts: `NightEvaluator` stays the only judge; these helpers read the
/// same events in the same order so a notification promises what the evaluator will decide.
public enum TripState {
    /// A `.callStarted` without a later `.callEnded` is on at `date`. `.appLaunched` resets it (a relaunch never sees the
    /// call end). However old the call is, it stays open: the evaluator subtracts an unclosed call up to the wake time, so
    /// the warnings promise exactly that. Call BEFORE the event that is being stored.
    public static func callIsOpen(_ log: NightLog, at date: Date) -> Bool {
        var since: Date?
        for e in log.sortedEvents {
            switch e.kind {
            case .callStarted: since = since ?? e.at
            case .callEnded, .appLaunched: since = nil
            default: break
            }
        }
        return since != nil
    }

    /// The trip that is open at the end of the log, named by the event that began it (`.leftApp`, `.usedLockScreen` or
    /// `.closedByOwner`), or nil. Mirrors `NightEvaluator.awayTrips` (the first event of a trip owns it; a gentle-mode
    /// `.usedLockScreen` is no counted trip, so a later `.leftApp` takes over) but ignores calls and pauses: those are
    /// subtracted by the evaluator, not here.
    public static func openTrip(_ log: NightLog, rules: SleepRules) -> NightEventKind? {
        var trip: NightEventKind?
        for e in log.sortedEvents {
            switch e.kind {
            case .leftApp:
                if trip == nil || (trip == .usedLockScreen && !rules.lockScreenCollapses) { trip = .leftApp }
            case .usedLockScreen:
                if trip == nil { trip = .usedLockScreen }
            case .closedByOwner:
                if trip == nil { trip = .closedByOwner }
            case .returned, .locked, .confirmed, .appLaunched, .restartExcused, .forgiven:
                trip = nil
            default:
                break
            }
        }
        return trip
    }

    /// The moment a trip stamped at `date` counts from: the end of the call that covers `date` (the evaluator subtracts the
    /// call, so the trip begins when it ends), else `date` itself. Only calls that ended in the log count.
    public static func countedFrom(_ log: NightLog, at date: Date) -> Date {
        var since: Date?
        var result = date
        for e in log.sortedEvents {
            switch e.kind {
            case .callStarted: since = since ?? e.at
            case .callEnded:
                if let s = since, s <= result, result < e.at { result = e.at }
                since = nil
            case .appLaunched: since = nil
            default: break
            }
        }
        return result
    }
}
