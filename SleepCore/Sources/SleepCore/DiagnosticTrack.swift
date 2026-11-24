import Foundation

/// One line of a night's diagnostic track (13ab, owner 2026-11-11): what the phone was doing around the night – sound,
/// calls, alarm, volume, screen, battery, the app's lifecycle. Pure data: it never changes what a night counts, it is
/// never part of a backup or a sync file, and it never holds anything personal (device state only: enums and whole
/// percentages). `k` is a dotted key ("ctx.app", "life", "power", "call"), `v` short `key=value` pairs.
public struct DiagEntry: Codable, Equatable, Sendable {
    public var at: Date
    public var k: String
    public var v: String?
    public init(at: Date, k: String, v: String? = nil) { self.at = at; self.k = k; self.v = v }
}

/// The track of one night / nap: append-only, capped. After `maxEntries` entries one final `diag.cap` entry is written
/// and everything further is dropped.
public struct DiagLog: Equatable, Sendable {
    public static let maxEntries = 800
    public static let maxValueLength = 160
    public static let maxKeyLength = 40
    public static let capKey = "diag.cap"

    public private(set) var entries: [DiagEntry]

    public init(entries: [DiagEntry] = []) { self.entries = entries }

    /// Whether the cap was reached (the final entry is there): nothing more is stored.
    public var isFull: Bool { entries.last?.k == Self.capKey }

    public mutating func append(_ k: String, _ v: String? = nil, at date: Date) {
        guard !isFull else { return }
        if entries.count >= Self.maxEntries {
            entries.append(DiagEntry(at: date, k: Self.capKey, v: "max=\(Self.maxEntries)"))
            return
        }
        entries.append(DiagEntry(at: date, k: String(k.prefix(Self.maxKeyLength)),
                                 v: v.map { String($0.prefix(Self.maxValueLength)) }))
    }

    public mutating func append(contentsOf more: [DiagEntry]) {
        for e in more { append(e.k, e.v, at: e.at) }
    }

    // MARK: retention

    /// How long a finished night keeps its track.
    public static let retentionDays = 30

    /// Whether the track of a night finalized at `finalizedAt` is older than the retention and should be dropped.
    /// A night that is not finalized (nil) is never stale.
    public static func isStale(finalizedAt: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let finalizedAt, let limit = calendar.date(byAdding: .day, value: -retentionDays, to: now) else { return false }
        return finalizedAt < limit
    }

    // MARK: storage

    public func encoded() -> Data? { try? JSONEncoder().encode(entries) }

    /// The readable entries of stored bytes (nil / unreadable bytes give an empty log; a malformed element is skipped).
    public static func decode(_ data: Data?) -> DiagLog {
        guard let data, let list = try? LossyDecoding.elements(DiagEntry.self, from: data) else { return DiagLog() }
        return DiagLog(entries: list)
    }
}
