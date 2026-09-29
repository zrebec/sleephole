import Foundation
import Observation

/// Persistent log of the F2 detection spike (Documents/probe-log.json). Survives app kills.
@Observable
@MainActor
final class ProbeLog {
    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        let at: Date
        let text: String
    }

    private(set) var entries: [Entry] = []
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("probe-log.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func add(_ text: String, at date: Date = Date()) {
        entries.append(Entry(at: date, text: text))
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }

    static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM. HH:mm:ss.SSS"
        return f
    }()

    /// Plain text for sharing (AirDrop / Messages → paste to the agent).
    var exportText: String {
        entries.map { "\(Self.timeFormat.string(from: $0.at))  \($0.text)" }.joined(separator: "\n")
    }
}
