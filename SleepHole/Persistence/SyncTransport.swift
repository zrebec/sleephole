import Foundation
import UIKit

/// Phase SYNC, steps S2a / S2b: where the devices' sync files live. The SEAM is replaceable like `WeatherSource`: nothing
/// (the simulator and the tests), a plain folder (Debug builds only – tests and the simulator) and the user's iCloud
/// container (`ICloudSyncTransport`, a real iPhone). Every device writes only ITS OWN file and reads the files of the
/// others, so two devices never write the same file. The engine (`SyncEngine`) decides when to read, merge and write.
protocol SyncTransport: Sendable {
    /// false = nowhere to sync with right now (not signed in to iCloud, tests, …).
    func isAvailable() async -> Bool
    /// Replaces THIS device's file.
    func write(_ data: Data) async throws
    /// The files of all OTHER devices that can be read completely right now.
    func readOthers() async throws -> [Data]
    /// Yields whenever another device's file appeared or changed (never for this device's own file).
    var changes: AsyncStream<Void> { get }
}

/// Tests, the simulator and `servicesEnabled == false`: never available, nothing to read or write.
struct NoSyncTransport: SyncTransport {
    func isAvailable() async -> Bool { false }
    func write(_ data: Data) async throws {}
    func readOthers() async throws -> [Data] { [] }
    var changes: AsyncStream<Void> { AsyncStream { $0.finish() } }
}

#if DEBUG
/// One file `<deviceId>.json` per device in a plain folder – a developer aid for the tests and the simulator (launch
/// arguments `-syncFolder PATH` and `-syncDevice NAME`). The folder is created on demand. `changes` polls the other
/// devices' files every few seconds. Debug builds only: it reads file modification dates, which a shipped build would
/// have to declare in the privacy manifest (`ICloudSyncTransport` needs no dates).
struct FolderSyncTransport: SyncTransport {
    let folder: URL
    let deviceId: String
    /// Seconds between two looks at the folder (`changes`).
    var pollInterval: TimeInterval = 3

    init(folder: URL, deviceId: String, pollInterval: TimeInterval = 3) {
        self.folder = folder
        self.deviceId = SyncDevice.fileSafe(deviceId)
        self.pollInterval = pollInterval
    }

    private var ownName: String { deviceId + ".json" }

    func isAvailable() async -> Bool {
        (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
    }

    func write(_ data: Data) async throws {
        let folder = folder, ownURL = folder.appendingPathComponent(ownName)
        try await Task.detached {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: ownURL, options: .atomic)
        }.value
    }

    func readOthers() async throws -> [Data] {
        let folder = folder, own = ownName
        return try await Task.detached {
            try Self.otherFiles(in: folder, excluding: own).compactMap { try? Data(contentsOf: $0) }
        }.value
    }

    /// Every `*.json` file of the folder except `own`, sorted by name (a missing folder holds none).
    private static func otherFiles(in folder: URL, excluding own: String) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != own }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Name, size and modification time of every other device's file – changes whenever one appears or is replaced.
    private static func signature(of folder: URL, excluding own: String) -> [String] {
        ((try? otherFiles(in: folder, excluding: own)) ?? []).map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let time = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            return "\(url.lastPathComponent)|\(values?.fileSize ?? -1)|\(time)"
        }
    }

    var changes: AsyncStream<Void> {
        let folder = folder, own = ownName, interval = pollInterval
        return AsyncStream { continuation in
            // the baseline is taken when the stream is created, so a file that changes between the engine's first read
            // and the first look is not lost
            let initial = Self.signature(of: folder, excluding: own)
            let task = Task.detached {
                var seen = initial
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    let now = Self.signature(of: folder, excluding: own)
                    if now != seen {
                        seen = now
                        continuation.yield()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif

/// A random id per install, kept in `UserDefaults` under its own key. It is NOT part of `AppSettings` and never goes
/// into a sync file – it only names this device's file.
enum SyncDevice {
    static let key = "sync.deviceId"
    /// The vendor id (`UIDevice.identifierForVendor`) the stored id was made on: it tells a restore of an iPhone backup
    /// onto a NEW phone, which brings `UserDefaults` along (the id would then name two phones' files).
    static let vendorKey = "sync.deviceVendorId"

    /// The id for this install. Made once; made AGAIN when the stored one was made on another device – the vendor id
    /// differs from the one stored with it. A vendor id that is not available (`nil`, early after a reboot) changes
    /// nothing; an id stored without any vendor id (made in that window) adopts the first one that is seen.
    static func id(defaults: UserDefaults = .standard, vendorId: String?) -> String {
        let vendor = vendorId.flatMap { $0.isEmpty ? nil : $0 }
        if let id = defaults.string(forKey: key), !id.isEmpty {
            guard let vendor else { return id }
            switch defaults.string(forKey: vendorKey) {
            case vendor:
                return id
            case nil:
                defaults.set(vendor, forKey: vendorKey)
                return id
            default:
                break                                        // another phone: the id must not travel with the backup
            }
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        if let vendor { defaults.set(vendor, forKey: vendorKey) } else { defaults.removeObject(forKey: vendorKey) }
        return id
    }

    /// This phone's vendor id; nil early after a reboot, before the first unlock.
    @MainActor
    static func currentVendorId() -> String? { UIDevice.current.identifierForVendor?.uuidString }

    /// An id as the stem of a file name: letters, digits, "-" and "_" only, nothing that could leave the folder.
    static func fileSafe(_ id: String) -> String {
        String(id.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? Character($0) : "_"
        })
    }
}

enum SyncTransports {
    /// The transport for this launch. Debug builds: `-syncFolder PATH` (simulator and tests of the app by hand) → a plain
    /// folder, `-syncDevice NAME` names this launch's device (default: the install's id). Otherwise: the hosted unit
    /// tests and the simulator → nothing; a real iPhone → the user's iCloud container.
    @MainActor
    static func forLaunch(args: [String] = DevArgs.list,
                          defaults: UserDefaults = .standard,
                          underTest: Bool = SystemAlarms.isRunningTests,
                          vendorId: String? = SyncDevice.currentVendorId()) -> any SyncTransport {
        #if DEBUG
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        if let path = value("-syncFolder") {
            return FolderSyncTransport(folder: URL(fileURLWithPath: path, isDirectory: true),
                                       deviceId: value("-syncDevice") ?? SyncDevice.id(defaults: defaults, vendorId: vendorId))
        }
        #endif
        if underTest || !usesICloud { return NoSyncTransport() }
        return ICloudSyncTransport(deviceId: SyncDevice.id(defaults: defaults, vendorId: vendorId))
    }

    /// iCloud exists on a real iPhone only: the simulator is never signed in to an account the app may use.
    static var usesICloud: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }
}
