import Foundation
import HealthKit
import SleepCore

/// Apple Health as the sleep source (phase HEALTH, H2). READ-ONLY: the app asks to read sleep analysis and never writes.
struct HealthKitSleepSource: SleepSource {
    private let store = HKHealthStore()
    private static let sleepType = HKCategoryType(.sleepAnalysis)

    var name: String { "healthkit" }
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// NOTE: iOS never tells an app whether READ access was granted (a privacy rule) – a refusal simply looks like "no
    /// samples". So this is false only when Health is unavailable or the request itself throws.
    func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [Self.sleepType])
            return true
        } catch {
            return false
        }
    }

    func samples(from: Date, to: Date) async throws -> [SleepSample] {
        guard isAvailable, from < to else { return [] }
        // no strict options: a sample that merely overlaps the window is returned (the caller clips)
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let query = HKSampleQueryDescriptor(predicates: [.categorySample(type: Self.sleepType, predicate: predicate)],
                                            sortDescriptors: [SortDescriptor(\.startDate)])
        let found = try await query.result(for: store)
        return found.compactMap { sample in
            guard let stage = Self.stage(forValue: sample.value) else { return nil }
            return SleepSample(start: sample.startDate, end: sample.endDate, stage: stage,
                               source: sample.sourceRevision.source.name,
                               isFirstParty: Self.isFirstParty(bundleIdentifier: sample.sourceRevision.source.bundleIdentifier))
        }
    }

    /// Apple's own sleep tracking (a watch or the phone) writes with a `com.apple.` bundle identifier; apps from the App
    /// Store never may. So the prefix tells the system's measurement from a third-party app's, whatever the app is called.
    static func isFirstParty(bundleIdentifier: String) -> Bool {
        bundleIdentifier.hasPrefix("com.apple.")
    }

    /// HealthKit's sleep-analysis value → our stage; unknown (future) values are skipped.
    static func stage(forValue value: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepUnspecified: return .asleep
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        default: return nil
        }
    }
}
