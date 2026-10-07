import Foundation

/// A human-readable story of one night, derived from its event log (Štatistiky → tap a calendar day).
public struct NightReport: Equatable, Sendable {
    public struct Trip: Equatable, Sendable {
        public let start: Date
        /// nil = never came back before the end of the night.
        public let end: Date?
        /// The trip started inside a pause (D17) – it is free.
        public var duringPause = false
        /// The owner closed the app during this trip (R4: swiped it away; it ends when the app is opened again).
        public var closedApp = false
        public var duration: TimeInterval? { end.map { $0.timeIntervalSince(start) } }
    }

    public enum ConfirmMethod: String, Sendable { case shake, code }

    public let startedAt: Date?
    public let setupEnds: Date?
    /// First time the phone was locked after the start ("went to sleep").
    public let firstLockAt: Date?
    public let confirmedAt: Date?
    public let confirmMethod: ConfirmMethod?
    public let alarmFiredAt: Date?
    public let alarmStoppedAt: Date?
    /// Trips to other apps that STARTED during the setup time.
    public let setupTrips: [Trip]
    /// Trips to other apps after the setup time.
    public let nightTrips: [Trip]
    /// Phone unlocks while the app sat in the background (Face ID + swipe up) – e.g. to check the time.
    public let screenChecks: [Date]
    public let calls: [Trip]
    /// Cold launches during the night (the app had been killed). Not the ones that merely opened an app the owner
    /// had closed – the trip of that closure tells the story.
    public let relaunches: [Date]
    public let collapsedAt: Date?
    public let abandonedAt: Date?
    /// When each pause (D17) started.
    public let pauses: [Date]

    public init(log: NightLog, rules: SleepRules = SleepRules()) {
        let events = log.sortedEvents
        let start = log.startedAt
        startedAt = start
        setupEnds = start.map { log.window.setupEnds(start: $0, rules: rules) }
        firstLockAt = events.first { $0.kind == .locked && $0.at >= (start ?? .distantPast) }?.at
        confirmedAt = log.confirmedAt
        confirmMethod = log.has(.confirmedByCode) ? .code : log.has(.confirmedByShake) ? .shake : nil
        alarmFiredAt = log.first(.alarmFired)?.at
        alarmStoppedAt = log.first(.alarmStopped)?.at
        abandonedAt = log.first(.abandoned)?.at

        var trips: [Trip] = [], calls: [Trip] = []
        var awaySince: Date?, callSince: Date?
        var closed = false                      // the open trip includes the owner closing the app
        var relaunches: [Date] = []
        for e in events {
            switch e.kind {
            case .leftApp: awaySince = awaySince ?? e.at
            case .closedByOwner:
                awaySince = awaySince ?? e.at
                closed = true
            case .returned, .locked, .confirmed:
                if let s = awaySince { trips.append(Trip(start: s, end: e.at, closedApp: closed)); awaySince = nil }
                closed = false
            case .appLaunched:
                if let s = awaySince {          // reopened after a closure: the trip ends here; any other death: unknown
                    // (opened only after the night was over = never came back during it)
                    trips.append(Trip(start: s, end: closed && e.at <= log.window.wake ? e.at : nil, closedApp: closed))
                    awaySince = nil
                }
                if !closed { relaunches.append(e.at) }
                closed = false
            case .restartExcused:               // a phone restart is no trip (the owner's favour); the relaunch shows it
                awaySince = nil
                closed = false
            case .callStarted: callSince = callSince ?? e.at
            case .callEnded: if let s = callSince { calls.append(Trip(start: s, end: e.at)); callSince = nil }
            default: break
            }
        }
        if let s = awaySince { trips.append(Trip(start: s, end: nil, closedApp: closed)) }
        if let s = callSince { calls.append(Trip(start: s, end: nil)) }
        let setupEnd = setupEnds ?? .distantPast
        let pauseWindows = log.pauseIntervals
        pauses = log.pauseStarts
        setupTrips = trips.filter { $0.start < setupEnd }
        nightTrips = trips.filter { $0.start >= setupEnd }.map { t in
            var t = t
            t.duringPause = pauseWindows.contains { $0.0 <= t.start && t.start < $0.1 }
            return t
        }
        self.calls = calls
        let end = log.confirmedAt ?? .distantFuture
        // unlocking the phone after the alarm to confirm is not a "check" (owner data 2026-10-03)
        let checksEnd = min(end, alarmFiredAt ?? .distantFuture)
        screenChecks = events.filter { $0.kind == .unlocked && $0.at > (start ?? .distantPast) && $0.at < checksEnd }.map(\.at)
        self.relaunches = relaunches
        collapsedAt = NightEvaluator.collapsedAt(log, rules: rules)
    }
}
