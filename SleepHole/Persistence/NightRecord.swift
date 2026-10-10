import Foundation
import SleepCore
import SwiftData

/// One night, persisted after EVERY event (the app may be killed at any moment). Plan §8.
@Model
final class NightRecord {
    /// "2026-09-29" for a real night, "debug-<epoch>" for a debug fast night.
    @Attribute(.unique) var id: String
    var keyString: String
    var isDebug: Bool
    /// Afternoon rest (not a night): never builds, never counts for streaks/levels, pays nap coins.
    var isNap: Bool = false
    var bedtime: Date
    var wake: Date
    var buildingId: String
    var eventsData: Data
    /// Rules used for this night (debug nights use a shorter setup grace).
    var setupGrace: Double
    var outcomeRaw: String?
    var awaySeconds: Double = 0
    var startedAt: Date?
    var confirmedAt: Date?
    var finalizedAt: Date?
    /// Night pauses (D17) used. nil = a night from before the pause existed (2026-10-03): it keeps the old rules
    /// (13 s per trip, no budget per night) and gets no "undisturbed night" bonus.
    var pauses: Int?
    /// Strict mode as it was when the night started (owner 2026-10-09, "care instead of enforcement"): true = using
    /// the phone on the lock screen is a trip out of the app, false = gentle (logged, never counted). nil = a night
    /// from before the switch existed: it keeps today's meaning, strict.
    var strictLockScreen: Bool?
    /// What the sleep source (Apple Health, phase HEALTH) said about this night. All optional so the store migrates.
    var fellAsleepAt: Date?
    var sleepEndedAt: Date?
    var asleepSeconds: Double?
    var awakeSeconds: Double?
    var sleepSourceName: String?
    /// When the source was last asked about this night (also set when it found nothing).
    var sleepReadAt: Date?
    /// The JSON of `[SleepAnalysis.SourceSummary]` – what every source said about this night – and the version of the
    /// choice rule the stored values were made with (nil = read before the version existed).
    var sleepSourcesData: Data?
    var sleepRuleVersion: Int?

    /// `idPrefix`: "bonus" for a test night that counts for the town (one-shot, owner request) –
    /// a unique id so it never collides with the real night of the same date.
    init(window: NightWindow, buildingId: String, isDebug: Bool, setupGrace: TimeInterval, idPrefix: String? = nil,
         isNap: Bool = false, strictLockScreen: Bool? = nil) {
        self.keyString = window.key.description
        let stamp = Int(Date().timeIntervalSince1970)
        self.isNap = isNap
        self.id = isNap ? "nap-\(window.key.description)"
            : isDebug ? "debug-\(stamp)" : idPrefix.map { "\($0)-\(stamp)" } ?? window.key.description
        self.isDebug = isDebug
        self.bedtime = window.bedtime
        self.wake = window.wake
        self.buildingId = buildingId
        self.eventsData = (try? JSONEncoder().encode([NightEvent]())) ?? Data()
        self.setupGrace = setupGrace
        self.pauses = 0
        self.strictLockScreen = strictLockScreen
    }

    /// What every source said about this night (empty when nothing is stored).
    var sleepSources: [SleepAnalysis.SourceSummary] {
        sleepSourcesData.flatMap { try? JSONDecoder().decode([SleepAnalysis.SourceSummary].self, from: $0) } ?? []
    }

    var window: NightWindow {
        NightWindow(key: NightKey(keyString)!, bedtime: bedtime, wake: wake, earlyConfirmOverride: isNap ? 0 : nil)
    }

    var rules: SleepRules {
        var r = isNap ? NapPlan.rules : SleepRules()
        r.setupGrace = setupGrace
        if pauses == nil { r.awayBudget = nil }
        r.lockScreenCollapses = strictLockScreen ?? true
        return r
    }

    var log: NightLog {
        let events = (try? JSONDecoder().decode([NightEvent].self, from: eventsData)) ?? []
        return NightLog(window: window, buildingId: buildingId, events: events)
    }

    func append(_ kind: NightEventKind, at date: Date) {
        var l = log
        l.append(kind, at: date)
        eventsData = (try? JSONEncoder().encode(l.events)) ?? eventsData
        if kind == .started { startedAt = startedAt ?? date }
        if kind == .confirmed { confirmedAt = confirmedAt ?? date }
        if kind == .pauseStarted { pauses = (pauses ?? 0) + 1 }
    }

    var outcome: Outcome? { outcomeRaw.flatMap(Outcome.init(rawValue:)) }
    var isFinalized: Bool { finalizedAt != nil }

    var result: NightResult? {
        guard let outcome else { return nil }
        return NightResult(key: window.key, outcome: outcome, buildingId: buildingId, awaySeconds: awaySeconds,
                           startedAt: startedAt, confirmedAt: confirmedAt, pauses: pauses, bedtime: bedtime,
                           fellAsleepAt: fellAsleepAt, asleepSeconds: asleepSeconds)
    }
}
