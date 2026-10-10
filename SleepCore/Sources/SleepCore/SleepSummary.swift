import Foundation

// What Apple Health (or any other source) says about a night's sleep, reduced to one summary (phase HEALTH, H1).
// Pure rules: the sources themselves live in the app (`SleepSource`).

public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case inBed, awake, asleep, core, deep, rem

    /// true for every stage that is real sleep (unspecified, core, deep, REM).
    public var isAsleep: Bool {
        switch self {
        case .asleep, .core, .deep, .rem: return true
        case .inBed, .awake: return false
        }
    }

    /// true for the stages only a watch-like device can tell apart.
    var isStaged: Bool { self == .core || self == .deep || self == .rem }
}

public struct SleepSample: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let stage: SleepStage
    /// The name of whatever wrote the sample (a watch, an app).
    public let source: String
    /// Written by the system's own sleep tracking (the maker of the OS), not by a third-party app.
    public let isFirstParty: Bool

    public init(start: Date, end: Date, stage: SleepStage, source: String, isFirstParty: Bool = false) {
        self.start = start
        self.end = end
        self.stage = stage
        self.source = source
        self.isFirstParty = isFirstParty
    }
}

public struct SleepSummary: Codable, Equatable, Sendable {
    public let fellAsleepAt: Date
    public let wokeAt: Date
    /// All sleep of the chosen source inside the night's window.
    public let asleepSeconds: TimeInterval
    /// Awake time between falling asleep and waking (never negative).
    public let awakeSeconds: TimeInterval
    public let source: String
    /// The source told core / deep / REM apart.
    public let hasStages: Bool

    public init(fellAsleepAt: Date, wokeAt: Date, asleepSeconds: TimeInterval, awakeSeconds: TimeInterval,
                source: String, hasStages: Bool) {
        self.fellAsleepAt = fellAsleepAt
        self.wokeAt = wokeAt
        self.asleepSeconds = asleepSeconds
        self.awakeSeconds = awakeSeconds
        self.source = source
        self.hasStages = hasStages
    }
}

public enum SleepAnalysis {
    /// Sleep intervals this close together (or closer) belong to one run of sleep.
    public static let bridgeGap: TimeInterval = 120
    /// A run must last this long to count as falling asleep: the start of the first run of at least 10 minutes of
    /// sleep (the usual "persistent sleep" definition); a short doze or blip before it does not count.
    public static let minOnsetRun: TimeInterval = 600
    /// Less sleep than this in the window is not a night's sleep.
    public static let minAsleep: TimeInterval = 1800
    /// Without a confirmation the window ends this long after the wake time.
    public static let noConfirmationTail: TimeInterval = 3 * 3600

    /// From the build start to the confirmation of getting up; when nobody confirmed, to the wake time + 3 h.
    public static func window(nightStart: Date, wake: Date, confirmedAt: Date?) -> (from: Date, to: Date) {
        (nightStart, confirmedAt ?? wake.addingTimeInterval(noConfirmationTail))
    }

    /// Version of the choice rule (1 = the source with the most sleep wins, 2 = a source with stages wins from
    /// `preferredShare` of the largest one, 3 = a first-party source comes first, and falling asleep needs a
    /// 10-minute run). Raise it whenever the rule changes: stored nights are then read again.
    public static let ruleVersion = 3
    /// A preferred source (first-party, then with stages) wins when it has at least this share of the largest eligible
    /// source's sleep.
    public static let preferredShare: Double = 2.0 / 3.0

    /// What one source said about the night.
    public struct SourceSummary: Codable, Equatable, Sendable {
        public let name: String
        public let asleepSeconds: TimeInterval
        public let fellAsleepAt: Date
        public let wokeAt: Date
        public let awakeSeconds: TimeInterval
        public let hasStages: Bool
        /// Written by the system's own sleep tracking (stored nights without the key decode as false).
        public let isFirstParty: Bool

        public init(name: String, asleepSeconds: TimeInterval, fellAsleepAt: Date, wokeAt: Date,
                    awakeSeconds: TimeInterval, hasStages: Bool, isFirstParty: Bool = false) {
            self.isFirstParty = isFirstParty
            self.name = name
            self.asleepSeconds = asleepSeconds
            self.fellAsleepAt = fellAsleepAt
            self.wokeAt = wokeAt
            self.awakeSeconds = awakeSeconds
            self.hasStages = hasStages
        }

        private enum CodingKeys: String, CodingKey {
            case name, asleepSeconds, fellAsleepAt, wokeAt, awakeSeconds, hasStages, isFirstParty
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            asleepSeconds = try c.decode(TimeInterval.self, forKey: .asleepSeconds)
            fellAsleepAt = try c.decode(Date.self, forKey: .fellAsleepAt)
            wokeAt = try c.decode(Date.self, forKey: .wokeAt)
            awakeSeconds = try c.decode(TimeInterval.self, forKey: .awakeSeconds)
            hasStages = try c.decode(Bool.self, forKey: .hasStages)
            isFirstParty = try c.decodeIfPresent(Bool.self, forKey: .isFirstParty) ?? false
        }
    }

    /// One entry per source with any asleep time in the window, sorted by name. Sources below `minAsleep` are listed
    /// too (information) but are never chosen.
    public static func sources(samples: [SleepSample], from: Date, to: Date) -> [SourceSummary] {
        guard from < to else { return [] }
        // 1. only sleep, clipped to the window
        var bySource: [String: [(start: Date, end: Date)]] = [:]
        var staged: Set<String> = []
        var firstParty: Set<String> = []
        for s in samples where s.stage.isAsleep {
            let a = max(s.start, from), b = min(s.end, to)
            guard a < b else { continue }
            bySource[s.source, default: []].append((a, b))
            if s.stage.isStaged { staged.insert(s.source) }
            if s.isFirstParty { firstParty.insert(s.source) }
        }
        // 2. per source: merge overlaps, add up, find the runs (gaps up to bridgeGap are bridged)
        return bySource.keys.sorted().map { name in
            var merged: [(start: Date, end: Date)] = []
            for i in bySource[name]!.sorted(by: { $0.start < $1.start }) {
                if let last = merged.last, i.start <= last.end {
                    merged[merged.count - 1].end = max(last.end, i.end)
                } else {
                    merged.append(i)
                }
            }
            let seconds = merged.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            var runs: [(start: Date, end: Date)] = []
            for i in merged {
                if let last = runs.last, i.start.timeIntervalSince(last.end) <= bridgeGap {
                    runs[runs.count - 1].end = max(last.end, i.end)
                } else {
                    runs.append(i)
                }
            }
            let onset = runs.first { $0.end.timeIntervalSince($0.start) >= minOnsetRun } ?? runs[0]
            let woke = runs[runs.count - 1].end
            let asleepInSpan = merged.filter { $0.start >= onset.start }
                .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            let awake = max(0, woke.timeIntervalSince(onset.start) - asleepInSpan)
            return SourceSummary(name: name, asleepSeconds: seconds, fellAsleepAt: onset.start, wokeAt: woke,
                                 awakeSeconds: awake, hasStages: staged.contains(name),
                                 isFirstParty: firstParty.contains(name))
        }
    }

    /// The source we believe, among those with at least `minAsleep`. One way of measuring for the whole series: the
    /// system's own tracking comes first, a third-party app is used only when the system has no usable data that night.
    /// 1. a first-party source with at least `preferredShare` of the largest source's sleep wins (most sleep, then the
    ///    smaller name); 2. otherwise one with stages and that share wins (same order); 3. otherwise the largest
    ///    (tie: stages, then the smaller name).
    public static func chosen(from list: [SourceSummary]) -> SourceSummary? {
        let eligible = list.filter { $0.asleepSeconds >= minAsleep }
        guard let largest = eligible.min(by: { a, b in
            if a.asleepSeconds != b.asleepSeconds { return a.asleepSeconds > b.asleepSeconds }
            if a.hasStages != b.hasStages { return a.hasStages }
            return a.name < b.name
        }) else { return nil }
        let reaching = eligible.filter { $0.asleepSeconds >= preferredShare * largest.asleepSeconds }
        let moreSleep: (SourceSummary, SourceSummary) -> Bool = { a, b in
            if a.asleepSeconds != b.asleepSeconds { return a.asleepSeconds > b.asleepSeconds }
            return a.name < b.name
        }
        return reaching.filter(\.isFirstParty).min(by: moreSleep)
            ?? reaching.filter(\.hasStages).min(by: moreSleep)
            ?? largest
    }

    public static func summary(samples: [SleepSample], from: Date, to: Date) -> SleepSummary? {
        guard let best = chosen(from: sources(samples: samples, from: from, to: to)) else { return nil }
        return SleepSummary(fellAsleepAt: best.fellAsleepAt, wokeAt: best.wokeAt, asleepSeconds: best.asleepSeconds,
                            awakeSeconds: best.awakeSeconds, source: best.name, hasStages: best.hasStages)
    }
}
