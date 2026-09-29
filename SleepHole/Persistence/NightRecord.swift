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

    /// `idPrefix`: "bonus" for a test night that counts for the town (one-shot, owner request) –
    /// a unique id so it never collides with the real night of the same date.
    init(window: NightWindow, buildingId: String, isDebug: Bool, setupGrace: TimeInterval, idPrefix: String? = nil) {
        self.keyString = window.key.description
        let stamp = Int(Date().timeIntervalSince1970)
        self.id = isDebug ? "debug-\(stamp)" : idPrefix.map { "\($0)-\(stamp)" } ?? window.key.description
        self.isDebug = isDebug
        self.bedtime = window.bedtime
        self.wake = window.wake
        self.buildingId = buildingId
        self.eventsData = (try? JSONEncoder().encode([NightEvent]())) ?? Data()
        self.setupGrace = setupGrace
    }

    var window: NightWindow { NightWindow(key: NightKey(keyString)!, bedtime: bedtime, wake: wake) }

    var rules: SleepRules {
        var r = SleepRules()
        r.setupGrace = setupGrace
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
    }

    var outcome: Outcome? { outcomeRaw.flatMap(Outcome.init(rawValue:)) }
    var isFinalized: Bool { finalizedAt != nil }

    var result: NightResult? {
        guard let outcome else { return nil }
        return NightResult(key: window.key, outcome: outcome, buildingId: buildingId, awaySeconds: awaySeconds,
                           startedAt: startedAt, confirmedAt: confirmedAt)
    }
}
