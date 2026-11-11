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
    /// The calm-hour rule the night started under (`CalmHours.currentRule`, build 8, owner 2026-10-15). nil = an older
    /// night (and every nap): it earns no calm-hour coins, so the balance never jumps. Optional, so the store migrates.
    var calmHoursRule: Int?
    /// The seconds of warning a lock-screen trip got when the night started (`SleepRules.lockScreenTolerance`, build 9,
    /// owner 2026-10-18, B33). nil = an older night (and every nap before build 9j): it keeps 10. Optional, so the store migrates.
    var lockScreenTolerance: Double?
    /// The seconds of warning a trip out of the app got when the night started (`SleepRules.accidentalTolerance`,
    /// build 9j, owner 2026-10-18). nil = stored before: 10. Optional, so the store migrates.
    var accidentalTolerance: Double?
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
    /// The diagnostic track (13ab, owner 2026-11-11): what the phone did around this night, `[DiagEntry]` as JSON. LOCAL
    /// ONLY – never in a backup, never in the sync file, never part of a fingerprint or an event count – and it never
    /// changes what the night counts. Optional with no default, so the store migrates by itself.
    var diagData: Data?

    /// `idPrefix`: "bonus" for a test night that counts for the town (one-shot, owner request) –
    /// a unique id so it never collides with the real night of the same date.
    init(window: NightWindow, buildingId: String, isDebug: Bool, setupGrace: TimeInterval, idPrefix: String? = nil,
         isNap: Bool = false, strictLockScreen: Bool? = nil, calmHoursRule: Int? = nil,
         lockScreenTolerance: Double? = nil, accidentalTolerance: Double? = nil) {
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
        self.calmHoursRule = calmHoursRule
        self.lockScreenTolerance = lockScreenTolerance
        self.accidentalTolerance = accidentalTolerance
    }

    /// What every source said about this night (empty when nothing is stored).
    var sleepSources: [SleepAnalysis.SourceSummary] {
        sleepSourcesData.flatMap { try? JSONDecoder().decode([SleepAnalysis.SourceSummary].self, from: $0) } ?? []
    }

    /// Quick test nights (debug, or the "bonus" ones started from the same window) open confirming shortly before the wake.
    var isTestNight: Bool { isDebug || id.hasPrefix("bonus-") }

    var window: NightWindow {
        NightWindow(key: NightKey(keyString)!, bedtime: bedtime, wake: wake, earlyConfirmOverride: isNap ? NapPlan.confirmLead(forLength: wake.timeIntervalSince(bedtime)) : (isTestNight ? NightWindow.testNightConfirmLead : nil))
    }

    var rules: SleepRules {
        var r = isNap ? NapPlan.rules : SleepRules()
        r.setupGrace = setupGrace
        if pauses == nil { r.awayBudget = nil }
        r.lockScreenCollapses = strictLockScreen ?? true
        if !isNap, strictLockScreen == false { r.startDeadline = SleepRules.gentleStartDeadline }
        r.lockScreenTolerance = lockScreenTolerance ?? 10
        r.accidentalTolerance = accidentalTolerance ?? 10
        return r
    }

    /// The stored events, read leniently (B61): an event kind this build does not know, or a malformed element, is skipped
    /// and the others keep their order. Bytes that are no array at all read as empty (and are never overwritten, see `append`).
    var log: NightLog {
        NightLog(window: window, buildingId: buildingId, events: NightEvent.decodeLossy(eventsData) ?? [])
    }

    /// Stores one event. Returns false when the stored journal is not readable at all (not a JSON array): it is then left
    /// exactly as it is (the bytes may still be of use) and the event is not stored; the caller notes it in the diagnostic
    /// track. The side values (start, confirmation, pauses) are kept either way.
    @discardableResult
    func append(_ kind: NightEventKind, at date: Date) -> Bool {
        var stored = true
        if let events = NightEvent.decodeLossy(eventsData) {
            var l = NightLog(window: window, buildingId: buildingId, events: events)
            l.append(kind, at: date)
            eventsData = (try? JSONEncoder().encode(l.events)) ?? eventsData
        } else {
            stored = false
        }
        if kind == .started { startedAt = startedAt ?? date }
        if kind == .confirmed { confirmedAt = confirmedAt ?? date }
        if kind == .pauseStarted { pauses = (pauses ?? 0) + 1 }
        return stored
    }

    /// The diagnostic track stored with this night (empty when there is none).
    var diagLog: DiagLog { DiagLog.decode(diagData) }

    var outcome: Outcome? { outcomeRaw.flatMap(Outcome.init(rawValue:)) }
    var isFinalized: Bool { finalizedAt != nil }

    var result: NightResult? {
        guard let outcome else { return nil }
        // replayed from the log like the rest of the balance; only nights that started under the rule
        let calm = calmHoursRule != nil && !isNap && outcome.isBuildNight ? CalmHours.count(log: log, rules: rules) : nil
        return NightResult(key: window.key, outcome: outcome, buildingId: buildingId, awaySeconds: awaySeconds,
                           startedAt: startedAt, confirmedAt: confirmedAt, pauses: pauses, bedtime: bedtime,
                           fellAsleepAt: fellAsleepAt, asleepSeconds: asleepSeconds,
                           calmHours: calm?.calm, calmHoursTotal: calm?.total,
                           sleepEndedAt: sleepEndedAt, isTestNight: isTestNight ? true : nil)
    }
}
