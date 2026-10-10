import Foundation
import SleepCore

// Where the app learns when the owner really fell asleep (phase HEALTH). The SOURCE is replaceable, like the weather:
// Apple Health later (H2), a stand-in for tests, the simulator and screenshots now.

protocol SleepSource: Sendable {
    /// A short name for diagnostics.
    var name: String { get }
    /// false when this source cannot answer at all (no Health on this device, nothing wired up).
    var isAvailable: Bool { get }
    /// Asks the owner for permission to read; true when sleep data may be read.
    func requestAccess() async -> Bool
    /// Every sleep sample that overlaps the window (any stage, any writer); the caller picks and clips.
    func samples(from: Date, to: Date) async throws -> [SleepSample]
}

/// Tests, the simulator and every build before H2: not available, no samples.
struct NoSleepSource: SleepSource {
    var name: String { "none" }
    var isAvailable: Bool { false }
    func requestAccess() async -> Bool { false }
    func samples(from: Date, to: Date) async throws -> [SleepSample] { [] }
}

/// A plausible staged night for ANY window, from one source named "Simulated" (screenshots, checking the pipeline
/// without Apple Health). Asleep about `fallAsleepMinutes` after `from` (varies per night, see `minutes(for:)`), stages in realistic chunks, one short awake stretch
/// in the middle, the last sample ends five minutes before `to`. Deterministic for a given window.
struct SimulatedSleepSource: SleepSource {
    static let sourceName = "Simulated"
    var fallAsleepMinutes: Double = 18

    var name: String { "simulated" }
    var isAvailable: Bool { true }
    func requestAccess() async -> Bool { true }

    /// `fallAsleepMinutes` plus −15…+75 minutes derived from the window's start, never below 3: every night differs, the same
    /// window always gives the same answer.
    func minutes(for from: Date) -> Double {
        let minuteOfEpoch = Int((from.timeIntervalSince1970 / 60).rounded(.down))
        let offset = ((minuteOfEpoch % 91) + 91) % 91 - 15
        return max(3, fallAsleepMinutes + Double(offset))
    }

    func samples(from: Date, to: Date) async throws -> [SleepSample] {
        let start = from.addingTimeInterval(minutes(for: from) * 60)
        let end = to.addingTimeInterval(-5 * 60)
        guard end.timeIntervalSince(start) > 20 * 60 else { return [] }
        // chunk pattern in minutes: stage, length (repeated until the end)
        let pattern: [(SleepStage, Double)] = [(.core, 40), (.deep, 45), (.core, 30), (.rem, 20), (.core, 50), (.rem, 25),
                                               (.core, 60), (.deep, 20), (.rem, 30)]
        let total = end.timeIntervalSince(start)
        let awakeAt = start.addingTimeInterval(total / 2)
        var out: [SleepSample] = []
        var t = start
        var i = 0
        while t < end {
            let (stage, minutes) = pattern[i % pattern.count]
            var chunkEnd = min(t.addingTimeInterval(minutes * 60), end)
            if t < awakeAt, chunkEnd > awakeAt {            // the awake stretch splits the chunk that covers the middle
                out.append(SleepSample(start: t, end: awakeAt, stage: stage, source: Self.sourceName))
                let awakeEnd = min(awakeAt.addingTimeInterval(8 * 60), end)
                out.append(SleepSample(start: awakeAt, end: awakeEnd, stage: .awake, source: Self.sourceName))
                t = awakeEnd
                if chunkEnd > t { out.append(SleepSample(start: t, end: chunkEnd, stage: stage, source: Self.sourceName)) }
                else { chunkEnd = t }
            } else {
                out.append(SleepSample(start: t, end: chunkEnd, stage: stage, source: Self.sourceName))
            }
            t = chunkEnd
            i += 1
        }
        return out
    }
}
