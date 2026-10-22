import CoreTransferable
import Foundation
import SleepCore
import SwiftData
import UniformTypeIdentifiers

/// Everything the owner has, as one JSON file (plan §8, F4). Used for export/import and the automatic
/// backup in Documents (visible in Files → On My iPhone → SleepHole).
struct BackupFile: Codable, Equatable {
    static let currentVersion = 1
    var version = BackupFile.currentVersion
    var exportedAt: Date
    var settings: AppSettings
    var onboardingCompletedAt: Date?
    var firstNightBriefingAt: Date?
    var nights: [Night]
    /// UI language (`AppLanguage` raw value). Optional → older backups still load.
    var language: String? = nil
    /// Town name. Optional → older backups still load.
    var townName: String? = nil
    // limits (owner 2026-09-30) – all optional, older backups still load
    var lastRenameAt: Date? = nil
    var lastFreeRenameAt: Date? = nil
    var scheduleCalibrationStart: Date? = nil
    var spends: [Spend]? = nil
    var scheduleChanges: [Change]? = nil
    var jokers: [Joker]? = nil
    // phase SYNC (2026-10-10) – optional, older backups still load
    var townNameChangedAt: Date? = nil
    var schedulePromptMonth: String? = nil
    /// Build 8 (change week, owner 2026-10-15): when the last change week was opened. Optional → older files load.
    var changeWeekStart: Date? = nil

    struct Joker: Codable, Equatable {
        var at: Date
        var tier: String
        var firstNight: String
    }

    struct Spend: Codable, Equatable {
        var at: Date
        var amount: Int
        var reason: String
    }

    struct Change: Codable, Equatable {
        var at: Date
        var from: String
        var to: String
        var free: Bool
        var breakKey: String?
        var rule: Int? = nil        // 1 = made under the change-week rule (build 8); nil = the old rule
    }

    struct Night: Codable, Equatable {
        var id: String
        var keyString: String
        var isDebug: Bool
        var isNap: Bool?
        var bedtime: Date
        var wake: Date
        var buildingId: String
        var events: [NightEvent]
        var setupGrace: Double
        var outcomeRaw: String?
        var awaySeconds: Double
        var startedAt: Date?
        var confirmedAt: Date?
        var finalizedAt: Date?
        var pauses: Int? = nil          // nil in backups from before the pause (2026-10-03) = old rules
        var strictLockScreen: Bool? = nil   // nil = a night from before Strict mode existed (2026-10-09) = strict
        var lockScreenTolerance: Double? = nil   // nil = a night from before build 9 (2026-10-18): a lock-screen trip gets 10 s
        var accidentalTolerance: Double? = nil   // nil = a night from before build 9j: a trip out of the app gets 10 s
        var calmHoursRule: Int? = nil       // nil = a night from before the calm hours (build 8, 2026-10-15): no calm-hour coins
        // what the sleep source said (phase HEALTH) – all optional, older backups still load
        var fellAsleepAt: Date? = nil
        var sleepEndedAt: Date? = nil
        var asleepSeconds: Double? = nil
        var awakeSeconds: Double? = nil
        var sleepSourceName: String? = nil
        var sleepReadAt: Date? = nil
        var sleepSourcesData: Data? = nil
        var sleepRuleVersion: Int? = nil
    }

    static let fileName = "SleepHole-zaloha.json"

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(BackupFile.self, from: data)
    }

    static var autoBackupURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
    }
}

extension NightRecord {
    var backup: BackupFile.Night {
        BackupFile.Night(id: id, keyString: keyString, isDebug: isDebug, isNap: isNap, bedtime: bedtime, wake: wake,
                         buildingId: buildingId, events: log.events, setupGrace: setupGrace, outcomeRaw: outcomeRaw,
                         awaySeconds: awaySeconds, startedAt: startedAt, confirmedAt: confirmedAt,
                         finalizedAt: finalizedAt, pauses: pauses, strictLockScreen: strictLockScreen,
                         lockScreenTolerance: lockScreenTolerance, accidentalTolerance: accidentalTolerance,
                         calmHoursRule: calmHoursRule,
                         fellAsleepAt: fellAsleepAt, sleepEndedAt: sleepEndedAt, asleepSeconds: asleepSeconds,
                         awakeSeconds: awakeSeconds, sleepSourceName: sleepSourceName, sleepReadAt: sleepReadAt,
                         sleepSourcesData: sleepSourcesData, sleepRuleVersion: sleepRuleVersion)
    }

    convenience init(backup n: BackupFile.Night) {
        self.init(window: NightWindow(key: NightKey(n.keyString) ?? NightKey(date: n.wake, calendar: .current),
                                      bedtime: n.bedtime, wake: n.wake),
                  buildingId: n.buildingId, isDebug: n.isDebug, setupGrace: n.setupGrace, isNap: n.isNap ?? false)
        id = n.id
        adoptNight(n)
        fellAsleepAt = n.fellAsleepAt
        sleepEndedAt = n.sleepEndedAt
        asleepSeconds = n.asleepSeconds
        awakeSeconds = n.awakeSeconds
        sleepSourceName = n.sleepSourceName
        sleepReadAt = n.sleepReadAt
        sleepSourcesData = n.sleepSourcesData
        sleepRuleVersion = n.sleepRuleVersion
    }

    /// Everything about the night itself except its sleep values (the Health fields belong to the device that read
    /// them) and its id. `init(backup:)` and the in-place overwrite of a merge (phase SYNC) share it.
    func adoptNight(_ n: BackupFile.Night) {
        if NightKey(n.keyString) != nil { keyString = n.keyString }      // a broken key keeps the one derived from `wake`
        isDebug = n.isDebug
        isNap = n.isNap ?? false
        bedtime = n.bedtime
        wake = n.wake
        buildingId = n.buildingId
        eventsData = (try? JSONEncoder().encode(n.events)) ?? eventsData
        setupGrace = n.setupGrace
        outcomeRaw = n.outcomeRaw
        awaySeconds = n.awaySeconds
        startedAt = n.startedAt
        confirmedAt = n.confirmedAt
        finalizedAt = n.finalizedAt
        pauses = n.pauses
        strictLockScreen = n.strictLockScreen
        calmHoursRule = n.calmHoursRule
        lockScreenTolerance = n.lockScreenTolerance
        accidentalTolerance = n.accidentalTolerance
    }
}

/// Share-sheet payload ("Exportovať zálohu").
/// The data is produced only when the share sheet asks for it (B8): building the item on every render of Settings
/// must not encode the whole backup each time.
struct BackupDocument: Transferable {
    let makeData: @MainActor @Sendable () -> Data
    init(data: Data) { makeData = { data } }
    init(makeData: @escaping @MainActor @Sendable () -> Data) { self.makeData = makeData }
    /// The payload now (what the export hands to the share sheet).
    @MainActor var data: Data { makeData() }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { doc in
            await MainActor.run { doc.makeData() }
        }
        .suggestedFileName(BackupFile.fileName)
    }
}
