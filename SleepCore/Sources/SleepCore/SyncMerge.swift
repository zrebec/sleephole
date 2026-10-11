import Foundation

/// The merge rule of phase SYNC (one town on all of a user's devices): every device writes its own file and merges the
/// files of the others, so the same two copies of one night must be ranked the same way on both devices, whichever
/// of them looks at the pair. A merge only ever adds or replaces, it never deletes. Pure functions – the app turns its
/// stored records into these inputs (`SleepHole/Persistence/Sync.swift`).
public enum SyncMerge {
    /// What the choice between two copies of one night looks at.
    public struct NightCopy: Equatable, Sendable {
        /// nil = the copy is not finalized.
        public let outcome: Outcome?
        public let startedAt: Date?
        public let finalizedAt: Date?
        /// How many events the copy's log holds. Event logs only ever grow, so of two copies of the SAME run the one with
        /// more events is the later state of it (see `keepsFirst`).
        public let eventCount: Int
        /// Any stable text of the copy – the tie-break of last resort (two devices must see the same text).
        public let fingerprint: String

        public init(outcome: Outcome?, startedAt: Date?, finalizedAt: Date?, eventCount: Int = 0, fingerprint: String) {
            self.outcome = outcome
            self.startedAt = startedAt
            self.finalizedAt = finalizedAt
            self.eventCount = eventCount
            self.fingerprint = fingerprint
        }
    }

    /// How good an outcome is for the user: complete > unfinished > ruins > missed = excused > not finalized.
    public static func rank(_ outcome: Outcome?) -> Int {
        switch outcome {
        case .complete: 4
        case .unfinished: 3
        case .ruins: 2
        case .missed, .excused: 1
        case nil: 0
        }
    }

    /// True when copy `a` is the one to keep. The criteria, in order:
    /// 1. two copies of the SAME run – the same start – with a different number of events: the one with more events (a
    ///    later correction of a run, such as the developer tool `-revokeForgiveness`, appends an event and may LOWER the
    ///    outcome; the older, "better" copy on another device must not undo it),
    /// 2. the higher rank (two DIFFERENT runs of a night: ambiguity is resolved in the user's favour),
    /// 3. the earlier start, 4. the earlier finalization (a copy with a date beats one without), 5. the smaller
    ///    fingerprint, 6. more events (copies without a start), 7. the smaller outcome name.
    /// For two different copies exactly one of `keepsFirst(a, b)` and `keepsFirst(b, a)` is true, so two devices that
    /// merge each other's copy end up with the SAME copy. Equal copies return true.
    ///
    /// Known limit, accepted: rule 1 before rule 2 is not transitive in ONE case – three copies where two are the same
    /// run, the one with more events has the LOWER rank, and the third (another run) ranks between them. Then the
    /// result of merging all three can depend on the order. It takes two devices running the same night AND a later
    /// correction that lowers it, which only the developer tool does.
    public static func keepsFirst(_ a: NightCopy, _ b: NightCopy) -> Bool {
        if let started = a.startedAt, started == b.startedAt, a.eventCount != b.eventCount {
            return a.eventCount > b.eventCount
        }
        let (ra, rb) = (rank(a.outcome), rank(b.outcome))
        if ra != rb { return ra > rb }
        if a.startedAt != b.startedAt { return earlierWins(a.startedAt, b.startedAt) }
        if a.finalizedAt != b.finalizedAt { return earlierWins(a.finalizedAt, b.finalizedAt) }
        if a.fingerprint != b.fingerprint { return a.fingerprint < b.fingerprint }
        if a.eventCount != b.eventCount { return a.eventCount > b.eventCount }    // only copies without a start get here
        // same rank, same dates, same text: only missed / excused (both rank 1) can still differ
        return (a.outcome?.rawValue ?? "") <= (b.outcome?.rawValue ?? "")
    }

    /// For two different dates (either may be missing): the earlier one wins, a date beats no date.
    private static func earlierWins(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case let (a?, b?): a < b
        case (_?, nil): true
        default: false
        }
    }

    /// The earlier of two dates; a date beats nil.
    public static func earliest(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (a?, b?): min(a, b)
        case (let a?, nil): a
        case (nil, let b?): b
        case (nil, nil): nil
        }
    }

    /// The later of two dates; a date beats nil.
    public static func latest(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (a?, b?): max(a, b)
        case (let a?, nil): a
        case (nil, let b?): b
        case (nil, nil): nil
        }
    }

    /// Last writer wins: the value with the later stamp; a stamp beats no stamp; equal stamps or two missing stamps
    /// keep `local`.
    public static func newer<T>(_ local: (value: T, at: Date?),
                                _ remote: (value: T, at: Date?)) -> (value: T, at: Date?) {
        switch (local.at, remote.at) {
        case let (l?, r?): r > l ? remote : local
        case (nil, _?): remote
        default: local
        }
    }

    /// The stamp of a device's settings at FIRST CONTACT with the sync place (the first read this install completes),
    /// when the user has not changed anything since: **older than any real change** (a real change stamps "now", about
    /// 8·10⁸ seconds after the reference date, so it always wins) and ordered by how established the device is –
    /// `established` is the number of finalized, non-debug nights and naps in the device's store; an empty install gets
    /// the reference date itself, a phone with 46 nights gets 46 seconds later. Between two such stamps the existing
    /// last-writer-wins rule therefore keeps the settings of the more established device, whichever of them looks at
    /// the other's file; a new install can never be "the newest". The ONE place that builds this stamp.
    public static func firstContactStamp(established: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(max(0, established)))
    }

    /// Two times less than one second apart: an entry restored from an old backup has its time cut to whole seconds.
    public static func sameMoment(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 1
    }
}
