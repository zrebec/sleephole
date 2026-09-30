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
                         finalizedAt: finalizedAt)
    }

    convenience init(backup n: BackupFile.Night) {
        self.init(window: NightWindow(key: NightKey(n.keyString) ?? NightKey(date: n.wake, calendar: .current),
                                      bedtime: n.bedtime, wake: n.wake),
                  buildingId: n.buildingId, isDebug: n.isDebug, setupGrace: n.setupGrace, isNap: n.isNap ?? false)
        id = n.id
        eventsData = (try? JSONEncoder().encode(n.events)) ?? eventsData
        outcomeRaw = n.outcomeRaw
        awaySeconds = n.awaySeconds
        startedAt = n.startedAt
        confirmedAt = n.confirmedAt
        finalizedAt = n.finalizedAt
    }
}

/// Share-sheet payload ("Exportovať zálohu").
struct BackupDocument: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName(BackupFile.fileName)
    }
}
